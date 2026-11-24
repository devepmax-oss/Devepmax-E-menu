import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { BillStatus, OrderStatus, Prisma, SessionStatus } from '@prisma/client';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { EmployeeActor } from '../../common/auth/actor';
import { hashPin } from '../../common/crypto';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { isUniqueViolation } from '../../prisma/errors';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { OrdersService } from '../orders/orders.service';
import { TablesService } from '../tables/tables.service';
import { DiscountDto, PaymentDto } from './dto/billing.dto';

type Tx = Prisma.TransactionClient;
const D = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const ZERO = D(0);
const OPEN_BILL: BillStatus[] = ['UNPAID', 'PARTIALLY_PAID'];
const OPEN_SESSION: SessionStatus[] = ['OPEN', 'BILL_REQUESTED'];
const FINISHED_ORDER: OrderStatus[] = ['COMPLETED', 'CANCELLED'];

const BILL_INCLUDE = {
  items: {
    where: { status: 'ACTIVE' },
    orderBy: { id: 'asc' },
    include: { modifiers: true, discounts: true, order: { select: { id: true, number: true } } },
  },
  discounts: true,
  payments: { orderBy: { createdAt: 'asc' } },
  orders: {
    orderBy: { createdAt: 'asc' },
    select: {
      id: true,
      number: true,
      status: true,
      channel: true,
      fulfillmentType: true,
      customerName: true,
      customerPhone: true,
      createdAt: true,
    },
  },
  tableSession: {
    include: {
      table: true,
      serviceRequests: { where: { type: 'REQUEST_BILL', status: { in: ['OPEN', 'ACKNOWLEDGED'] } } },
    },
  },
} satisfies Prisma.BillInclude;

type BillWithAll = Prisma.BillGetPayload<{ include: typeof BILL_INCLUDE }>;

const sum = (values: Prisma.Decimal[]) => values.reduce((a, b) => a.plus(b), ZERO);

/** Qué es la cuenta: mesa, mostrador / para llevar, pickup o delivery. */
function kindOf(bill: BillWithAll) {
  if (bill.tableSessionId) return 'TABLE';
  const types = bill.orders.map((o) => o.fulfillmentType);
  if (types.includes('DELIVERY')) return 'DELIVERY';
  if (types.includes('PICKUP')) return 'PICKUP';
  return 'COUNTER';
}

/** La cuenta como la ve la caja. */
export function toBillView(bill: BillWithAll, names: Map<string, string>) {
  const session = bill.tableSession;
  const succeeded = bill.payments.filter((p) => p.status === 'SUCCEEDED');
  const firstOrder = bill.orders.find((o) => o.status !== 'CANCELLED') ?? bill.orders[0];
  const kind = kindOf(bill);
  return {
    id: bill.id,
    status: bill.status,
    kind,
    label: session
      ? `Mesa ${session.table.label}`
      : `#${firstOrder?.number ?? '—'}${firstOrder?.customerName ? ` · ${firstOrder.customerName}` : ''}`,
    table: session ? { id: session.table.id, label: session.table.label } : null,
    session: session
      ? { id: session.id, status: session.status, guestCount: session.guestCount, openedAt: session.openedAt }
      : null,
    billRequested: (session?.serviceRequests.length ?? 0) > 0,
    openedAt: bill.createdAt,
    orders: bill.orders,
    items: bill.items.map((i) => ({
      id: i.id,
      orderId: i.order.id,
      orderNumber: i.order.number,
      name: i.nameSnapshot,
      quantity: i.quantity,
      unitPrice: i.unitPrice,
      modifiersTotal: i.modifiersTotal,
      lineTotal: i.lineTotal,
      discount: sum(i.discounts.map((d) => d.amount)),
      modifiers: i.modifiers.map((m) => m.optionNameSnapshot),
      notes: i.notes,
      seat: i.seat,
    })),
    discounts: bill.discounts
      .filter((d) => d.appliedById !== null)
      .map((d) => ({
        id: d.id,
        type: d.type,
        value: d.value,
        amount: d.amount,
        reason: d.reason,
        itemId: d.orderItemId,
        itemName: bill.items.find((i) => i.id === d.orderItemId)?.nameSnapshot ?? null,
        appliedBy: d.appliedById ? names.get(d.appliedById) ?? null : null,
        authorizedBy: d.authorizedById ? names.get(d.authorizedById) ?? null : null,
      })),
    payments: bill.payments.map((p) => ({
      id: p.id,
      method: p.method,
      status: p.status,
      amount: p.amount,
      tipAmount: p.tipAmount,
      cashTendered: p.cashTendered,
      changeGiven: p.changeGiven,
      reference: p.reference,
      createdAt: p.createdAt,
      employee: p.employeeId ? names.get(p.employeeId) ?? null : null,
    })),
    subtotal: bill.subtotal,
    discountTotal: bill.discountTotal,
    taxTotal: bill.taxTotal,
    deliveryFee: bill.deliveryFee,
    tipTotal: bill.tipTotal,
    total: bill.total,
    amountPaid: sum(succeeded.map((p) => p.amount)),
    due: Prisma.Decimal.max(bill.total.minus(bill.amountPaid), 0),
  };
}

export type BillView = ReturnType<typeof toBillView>;

/**
 * Cobro en caja: cuentas abiertas, pagos (efectivo, tarjeta, otro), propinas, descuentos con
 * PIN de gerente y dividir o juntar cuentas de una mesa. Al quedar todo pagado, la mesa se libera.
 */
@Injectable()
export class BillingService {
  private readonly logger = new Logger(BillingService.name);
  private readonly env = loadEnv();
  private readonly pinLimiter = new AttemptLimiter(5, 5 * 60_000);

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEventsService,
    private readonly audit: AuditService,
    private readonly orders: OrdersService,
    private readonly tables: TablesService,
  ) {}

  // ───────── Consultar ─────────

  /** Cuentas por cobrar (o las de una mesa). */
  async list(tableId?: string): Promise<BillView[]> {
    const where: Prisma.BillWhereInput = tableId
      ? { tableSession: { tableId, status: { in: OPEN_SESSION } }, status: { not: 'VOID' } }
      : {
          status: { in: OPEN_BILL },
          items: { some: { status: 'ACTIVE' } },
          // Los pedidos web sin pagar todavía no son una cuenta para la caja.
          orders: { some: { status: { notIn: ['PENDING_PAYMENT', 'CANCELLED'] } } },
        };
    const bills = await this.prisma.bill.findMany({ where, include: BILL_INCLUDE, orderBy: { createdAt: 'asc' } });
    return this.views(bills);
  }

  async view(id: string): Promise<BillView> {
    const bill = await this.prisma.bill.findUnique({ where: { id }, include: BILL_INCLUDE });
    if (!bill) throw new NotFoundException('Cuenta no encontrada');
    return (await this.views([bill]))[0];
  }

  private async views(bills: BillWithAll[]): Promise<BillView[]> {
    const ids = new Set<string>();
    for (const b of bills) {
      b.payments.forEach((p) => p.employeeId && ids.add(p.employeeId));
      b.discounts.forEach((d) => {
        if (d.appliedById) ids.add(d.appliedById);
        if (d.authorizedById) ids.add(d.authorizedById);
      });
    }
    const employees = ids.size
      ? await this.prisma.employee.findMany({ where: { id: { in: [...ids] } }, select: { id: true, name: true } })
      : [];
    const names = new Map(employees.map((e) => [e.id, e.name]));
    return bills.map((b) => toBillView(b, names));
  }

  // ───────── Cobrar ─────────

  async pay(actor: EmployeeActor, billId: string, dto: PaymentDto): Promise<BillView> {
    const existing = await this.prisma.payment.findUnique({ where: { clientRequestId: dto.clientRequestId } });
    if (existing) return this.view(existing.billId); // reintento: ya se registró

    const amount = D(dto.amount).toDecimalPlaces(2);
    const tip = D(dto.tip ?? 0).toDecimalPlaces(2);
    const charged = amount.plus(tip);

    let change: Prisma.Decimal | null = null;
    try {
      await this.prisma.$transaction(async (tx) => {
        const bill = await tx.bill.findUnique({ where: { id: billId } });
        if (!bill) throw new NotFoundException('Cuenta no encontrada');
        if (!OPEN_BILL.includes(bill.status)) throw new ConflictException('Esta cuenta ya está pagada o anulada');
        const due = bill.total.minus(bill.amountPaid);
        if (amount.gt(due.plus(0.001))) {
          throw new BadRequestException(`La cuenta tiene $${due.toFixed(2)} por cobrar: el monto es mayor`);
        }

        const shift = await tx.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
        let tendered: Prisma.Decimal | null = null;
        if (dto.method === 'CASH') {
          if (!shift) throw new ConflictException('Abre la caja para cobrar en efectivo');
          tendered = D(dto.cashTendered ?? charged.toNumber()).toDecimalPlaces(2);
          if (tendered.lt(charged)) throw new BadRequestException('El efectivo recibido no alcanza');
          change = tendered.minus(charged);
        }

        await tx.payment.create({
          data: {
            billId,
            method: dto.method,
            status: 'SUCCEEDED',
            amount: charged,
            tipAmount: tip,
            cashTendered: tendered,
            changeGiven: change,
            employeeId: actor.id,
            cashShiftId: shift?.id ?? null,
            clientRequestId: dto.clientRequestId,
            reference: dto.reference?.trim() || null,
          },
        });
        if (tip.gt(0)) await tx.bill.update({ where: { id: billId }, data: { tipTotal: { increment: tip } } });
        await this.settle(tx, billId);
      });
    } catch (error) {
      // Dos envíos simultáneos del mismo cobro: cuenta como uno.
      if (isUniqueViolation(error)) return this.view(billId);
      throw error;
    }

    await this.audit.log(actor, 'payment.take', 'bill', billId, {
      method: dto.method,
      amount: charged.toString(),
      tip: tip.toString(),
      change: (change as Prisma.Decimal | null)?.toString() ?? null,
    });
    return this.afterChange(actor, billId);
  }

  // ───────── Descuentos ─────────

  async addDiscount(actor: EmployeeActor, billId: string, dto: DiscountDto): Promise<BillView> {
    const authorizedById = await this.authorize(actor, dto.managerPin);
    await this.prisma.$transaction(async (tx) => {
      const bill = await tx.bill.findUnique({ where: { id: billId }, include: { items: { where: { status: 'ACTIVE' }, include: { discounts: true } } } });
      if (!bill) throw new NotFoundException('Cuenta no encontrada');
      if (!OPEN_BILL.includes(bill.status)) throw new ConflictException('Esta cuenta ya está pagada o anulada');

      let base: Prisma.Decimal;
      if (dto.itemId) {
        const item = bill.items.find((i) => i.id === dto.itemId);
        if (!item) throw new BadRequestException('Ese artículo no está en la cuenta');
        base = item.lineTotal.minus(sum(item.discounts.map((d) => d.amount)));
      } else {
        base = bill.subtotal.minus(bill.discountTotal);
      }
      if (base.lte(0)) throw new BadRequestException('No queda nada a qué descontarle');
      const value = D(dto.value);
      if (dto.type === 'PERCENT' && value.gt(100)) throw new BadRequestException('El porcentaje va de 1 a 100');
      const amount = Prisma.Decimal.min(dto.type === 'PERCENT' ? base.times(value).div(100) : value, base).toDecimalPlaces(2);

      await tx.discount.create({
        data: {
          billId,
          orderItemId: dto.itemId ?? null,
          type: dto.type,
          value,
          amount,
          reason: dto.reason.trim(),
          appliedById: actor.id,
          authorizedById,
        },
      });
      await this.settle(tx, billId);
      const after = await tx.bill.findUniqueOrThrow({ where: { id: billId } });
      if (after.total.lt(after.amountPaid)) {
        throw new ConflictException('El descuento deja la cuenta por debajo de lo ya cobrado');
      }
    });
    await this.audit.log(actor, 'bill.discount', 'bill', billId, {
      type: dto.type,
      value: dto.value,
      itemId: dto.itemId ?? null,
      reason: dto.reason,
      authorizedById,
    });
    return this.afterChange(actor, billId);
  }

  async removeDiscount(actor: EmployeeActor, discountId: string, managerPin?: string): Promise<BillView> {
    const discount = await this.prisma.discount.findUnique({ where: { id: discountId }, include: { bill: true } });
    if (!discount || discount.appliedById === null) throw new NotFoundException('Descuento no encontrado');
    if (!OPEN_BILL.includes(discount.bill.status)) throw new ConflictException('Esta cuenta ya está pagada o anulada');
    const authorizedById = await this.authorize(actor, managerPin);
    await this.prisma.$transaction(async (tx) => {
      await tx.discount.delete({ where: { id: discountId } });
      await this.settle(tx, discount.billId);
    });
    await this.audit.log(actor, 'bill.discount_removed', 'bill', discount.billId, {
      amount: discount.amount.toString(),
      reason: discount.reason,
      authorizedById,
    });
    return this.afterChange(actor, discount.billId);
  }

  /** Quien aplica necesita el permiso de descuentos, o el PIN de un gerente que lo tenga. */
  private async authorize(actor: EmployeeActor, managerPin?: string): Promise<string | null> {
    if (actor.permissions.has('bills.discount')) return null;
    if (!managerPin) throw new ForbiddenException('Hace falta el PIN de un gerente');
    const key = `discount:${actor.id}`;
    this.pinLimiter.assertAllowed(key);
    const manager = await this.prisma.employee.findUnique({
      where: { pinHash: hashPin(managerPin, this.env.pinPepper) },
      include: { role: true },
    });
    if (!manager?.isActive || !manager.role.permissions.includes('bills.discount')) {
      this.pinLimiter.fail(key);
      throw new UnauthorizedException('PIN de gerente incorrecto');
    }
    this.pinLimiter.reset(key);
    return manager.id;
  }

  // ───────── Dividir y juntar ─────────

  /** Pasa los artículos elegidos a una cuenta nueva de la misma mesa. */
  async split(actor: EmployeeActor, billId: string, itemIds: string[]): Promise<BillView> {
    const newBillId = await this.prisma.$transaction(async (tx) => {
      const bill = await tx.bill.findUnique({
        where: { id: billId },
        include: { items: { where: { status: 'ACTIVE' } }, payments: { where: { status: 'SUCCEEDED' } } },
      });
      if (!bill) throw new NotFoundException('Cuenta no encontrada');
      if (!bill.tableSessionId) throw new BadRequestException('Solo se dividen cuentas de mesa; aquí usa "pagar una parte"');
      if (!OPEN_BILL.includes(bill.status)) throw new ConflictException('Esta cuenta ya está pagada o anulada');
      if (bill.payments.length > 0) throw new ConflictException('Esta cuenta ya tiene pagos: cobra el resto con "pagar una parte"');
      const ids = new Set(itemIds);
      const moving = bill.items.filter((i) => ids.has(i.id));
      if (moving.length !== ids.size) throw new BadRequestException('Algún artículo no está en esta cuenta');
      if (moving.length === bill.items.length) throw new BadRequestException('Deja al menos un artículo en la cuenta original');

      const created = await tx.bill.create({ data: { tableSessionId: bill.tableSessionId } });
      await tx.orderItem.updateMany({ where: { id: { in: [...ids] } }, data: { billId: created.id } });
      await tx.discount.updateMany({ where: { orderItemId: { in: [...ids] } }, data: { billId: created.id } });
      await this.settle(tx, billId);
      await this.settle(tx, created.id);
      return created.id;
    });
    await this.audit.log(actor, 'bill.split', 'bill', billId, { newBillId, items: itemIds.length });
    await this.afterChange(actor, billId);
    return this.afterChange(actor, newBillId);
  }

  /** Junta una cuenta (sin pagos) con otra de la misma mesa. */
  async merge(actor: EmployeeActor, billId: string, targetBillId: string): Promise<BillView> {
    if (billId === targetBillId) throw new BadRequestException('Elige otra cuenta');
    await this.prisma.$transaction(async (tx) => {
      const [source, target] = await Promise.all([
        tx.bill.findUnique({ where: { id: billId }, include: { payments: { where: { status: 'SUCCEEDED' } } } }),
        tx.bill.findUnique({ where: { id: targetBillId } }),
      ]);
      if (!source || !target) throw new NotFoundException('Cuenta no encontrada');
      if (!source.tableSessionId || source.tableSessionId !== target.tableSessionId) {
        throw new BadRequestException('Solo se juntan cuentas de la misma mesa');
      }
      if (source.payments.length > 0) throw new ConflictException('Esa cuenta ya tiene pagos');
      if (!OPEN_BILL.includes(target.status)) throw new ConflictException('La otra cuenta ya está pagada');
      await tx.orderItem.updateMany({ where: { billId }, data: { billId: targetBillId } });
      await tx.discount.updateMany({ where: { billId }, data: { billId: targetBillId } });
      await tx.order.updateMany({ where: { billId }, data: { billId: targetBillId } });
      await this.settle(tx, billId); // queda vacía → anulada
      await this.settle(tx, targetBillId);
    });
    await this.audit.log(actor, 'bill.merge', 'bill', targetBillId, { from: billId });
    await this.afterChange(actor, billId);
    return this.afterChange(actor, targetBillId);
  }

  // ───────── Internos ─────────

  /** Totales al día y estado según lo cobrado. */
  async settle(tx: Tx, billId: string): Promise<void> {
    await this.orders.recomputeBill(tx, billId);
    const bill = await tx.bill.findUniqueOrThrow({ where: { id: billId }, include: { payments: { where: { status: 'SUCCEEDED' } } } });
    if (bill.status === 'VOID' || bill.status === 'REFUNDED') return;
    const paid = sum(bill.payments.map((p) => p.amount));
    const status: BillStatus = paid.gte(bill.total) && bill.total.gt(0) ? 'PAID' : paid.gt(0) ? 'PARTIALLY_PAID' : 'UNPAID';
    await tx.bill.update({
      where: { id: billId },
      data: { amountPaid: paid, status, closedAt: status === 'PAID' ? bill.closedAt ?? new Date() : null },
    });
  }

  /** Avisa en vivo y, si la mesa quedó pagada y sin pedidos en cocina, la libera. */
  async afterChange(actor: EmployeeActor | 'system', billId: string): Promise<BillView> {
    const view = await this.view(billId);
    this.events.emit('bill.updated', {
      id: view.id,
      status: view.status,
      subtotal: view.subtotal,
      discountTotal: view.discountTotal,
      taxTotal: view.taxTotal,
      tipTotal: view.tipTotal,
      total: view.total,
      amountPaid: view.amountPaid,
      tableId: view.table?.id ?? null,
    });
    for (const order of view.orders) {
      await this.orders.publishUpdate(order.id).catch((e) => this.logger.warn(`No se pudo avisar la orden: ${String(e)}`));
    }
    if (view.status === 'PAID' && view.table && view.session) await this.releaseTable(actor, view.table.id, view.session.id);
    return this.view(billId);
  }

  private async releaseTable(actor: EmployeeActor | 'system', tableId: string, sessionId: string) {
    const [bills, activeOrders] = await Promise.all([
      this.prisma.bill.findMany({ where: { tableSessionId: sessionId, status: { not: 'VOID' } } }),
      this.prisma.order.count({ where: { tableSessionId: sessionId, status: { notIn: FINISHED_ORDER } } }),
    ]);
    if (activeOrders > 0) return; // todavía sale comida: la mesa se cierra después
    if (!bills.every((b) => b.status === 'PAID')) return;
    try {
      await this.tables.close(actor, tableId);
    } catch (error) {
      this.logger.warn(`No se pudo liberar la mesa: ${String(error)}`);
    }
  }
}
