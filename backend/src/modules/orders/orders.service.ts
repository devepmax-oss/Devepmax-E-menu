import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { OrderChannel, OrderStatus, Prisma } from '@prisma/client';
import { Actor } from '../../common/auth/actor';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { SettingsService } from '../settings/settings.service';
import { CreateOrderDto } from './dto/order.dto';
import {
  businessDateFor,
  computeTotals,
  deriveOrderStatus,
  generatePublicCode,
  kitchenStarted,
} from './order.rules';
import { PricingService } from './pricing.service';

type Tx = Prisma.TransactionClient;

export const ORDER_INCLUDE = {
  items: { orderBy: { id: 'asc' }, include: { modifiers: true } },
  tickets: { orderBy: { createdAt: 'asc' }, include: { station: true } },
  bill: true,
  tableSession: { include: { table: true } },
} satisfies Prisma.OrderInclude;

type OrderWithRelations = Prisma.OrderGetPayload<{ include: typeof ORDER_INCLUDE }>;

const FINISHED: OrderStatus[] = ['COMPLETED', 'CANCELLED'];

export function toOrderView(order: OrderWithRelations) {
  return {
    id: order.id,
    number: order.number,
    publicCode: order.publicCode,
    businessDate: order.businessDate.toISOString().slice(0, 10),
    channel: order.channel,
    fulfillmentType: order.fulfillmentType,
    status: order.status,
    table: order.tableSession ? { id: order.tableSession.table.id, label: order.tableSession.table.label } : null,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    notes: order.notes,
    createdAt: order.createdAt,
    placedAt: order.placedAt,
    readyAt: order.readyAt,
    completedAt: order.completedAt,
    cancelledAt: order.cancelledAt,
    cancelReason: order.cancelReason,
    items: order.items.map((item) => ({
      id: item.id,
      productId: item.productId,
      name: item.nameSnapshot,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      modifiersTotal: item.modifiersTotal,
      lineTotal: item.lineTotal,
      notes: item.notes,
      seat: item.seat,
      status: item.status,
      stationId: item.stationId,
      modifiers: item.modifiers.map((m) => ({
        group: m.groupNameSnapshot,
        option: m.optionNameSnapshot,
        priceAdjustment: m.priceAdjustment,
      })),
    })),
    tickets: order.tickets.map((t) => ({
      id: t.id,
      status: t.status,
      station: { id: t.station.id, name: t.station.name, color: t.station.color },
    })),
    bill: {
      id: order.bill.id,
      status: order.bill.status,
      subtotal: order.bill.subtotal,
      discountTotal: order.bill.discountTotal,
      taxTotal: order.bill.taxTotal,
      deliveryFee: order.bill.deliveryFee,
      tipTotal: order.bill.tipTotal,
      total: order.bill.total,
      amountPaid: order.bill.amountPaid,
    },
  };
}

export type OrderView = ReturnType<typeof toOrderView>;

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pricing: PricingService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly events: DomainEventsService,
  ) {}

  // ───────── Crear ─────────

  async create(actor: Actor, dto: CreateOrderDto): Promise<OrderView> {
    const existing = await this.findByClientRequestId(dto.clientRequestId);
    if (existing) return existing;

    const settings = await this.settings.get();
    const { channel, tableId, fulfillmentType } = await this.resolveOrigin(actor, dto);
    if (fulfillmentType === 'DINE_IN' && !settings.acceptsDineIn) {
      throw new BadRequestException('Los pedidos en mesa están desactivados');
    }

    const lines = await this.pricing.priceLines(this.prisma, 'dine_in', dto.items);
    const status: OrderStatus = channel === 'TABLET' && settings.requireWaiterApproval ? 'PENDING_APPROVAL' : 'PLACED';

    let orderId: string;
    try {
      orderId = await this.withRetry(() =>
        this.prisma.$transaction(async (tx) => {
          const businessDate = businessDateFor(new Date(), settings.timezone);
          const counter = await tx.dailyCounter.upsert({
            where: { businessDate },
            create: { businessDate, lastOrderNumber: 1 },
            update: { lastOrderNumber: { increment: 1 } },
          });
          const billId = await this.resolveBill(tx, tableId);

          const order = await tx.order.create({
            data: {
              businessDate,
              number: counter.lastOrderNumber,
              publicCode: generatePublicCode(),
              clientRequestId: dto.clientRequestId,
              channel,
              fulfillmentType,
              status,
              tableSessionId: tableId ? (await tx.bill.findUniqueOrThrow({ where: { id: billId } })).tableSessionId : null,
              billId,
              deviceId: actor.kind === 'device' ? actor.id : actor.deviceId,
              createdById: actor.kind === 'employee' ? actor.id : null,
              customerName: dto.customerName?.trim() || null,
              customerPhone: dto.customerPhone?.trim() || null,
              notes: dto.notes?.trim() || null,
              items: {
                create: lines.map((line) => ({
                  billId,
                  productId: line.productId,
                  stationId: line.stationId,
                  nameSnapshot: line.nameSnapshot,
                  unitPrice: line.unitPrice,
                  modifiersTotal: line.modifiersTotal,
                  quantity: line.quantity,
                  lineTotal: line.lineTotal,
                  taxRate: line.taxRate,
                  notes: line.notes,
                  seat: line.seat,
                  modifiers: { create: line.modifiers },
                })),
              },
            },
          });

          if (status === 'PLACED') await this.placeInTx(tx, order.id);
          await this.recomputeBill(tx, billId);
          return order.id;
        }),
      );
    } catch (error) {
      // Dos envíos simultáneos con el mismo clientRequestId: se devuelve la orden ya creada.
      if (isUniqueViolation(error) && this.uniqueTarget(error).includes('clientRequestId')) {
        const duplicate = await this.findByClientRequestId(dto.clientRequestId);
        if (duplicate) return duplicate;
      }
      throw error;
    }

    const view = await this.getView(orderId);
    await this.audit.log(actor, 'order.create', 'order', orderId, {
      number: view.number,
      channel,
      total: view.bill.total.toString(),
    });
    this.events.emit('order.created', view);
    if (view.tickets.length) this.events.emit('ticket.created', { orderId, ticketIds: view.tickets.map((t) => t.id) });
    return view;
  }

  // ───────── Consultar ─────────

  async list(scope: 'active' | 'today'): Promise<OrderView[]> {
    const settings = await this.settings.get();
    const where: Prisma.OrderWhereInput =
      scope === 'active'
        ? { status: { notIn: FINISHED } }
        : { businessDate: businessDateFor(new Date(), settings.timezone) };
    const orders = await this.prisma.order.findMany({
      where,
      include: ORDER_INCLUDE,
      orderBy: { createdAt: 'desc' },
      take: 300,
    });
    return orders.map(toOrderView);
  }

  async getView(id: string): Promise<OrderView> {
    const order = await this.prisma.order.findUnique({ where: { id }, include: ORDER_INCLUDE });
    if (!order) throw new NotFoundException('Orden no encontrada');
    return toOrderView(order);
  }

  // ───────── Cambios de estado ─────────

  /** Orden de tablet aprobada por el mesero: pasa a cocina. */
  async approve(actor: Actor, id: string): Promise<OrderView> {
    await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (order.status !== 'PENDING_APPROVAL') throw new ConflictException('La orden no está esperando aprobación');
      await this.placeInTx(tx, id);
    });
    await this.audit.log(actor, 'order.approve', 'order', id);
    return this.publishUpdate(id, true);
  }

  /** Entregada al cliente (mesa o mostrador). */
  async complete(actor: Actor, id: string): Promise<OrderView> {
    await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (order.status !== 'READY') throw new ConflictException('Solo se pueden entregar órdenes que estén listas');
      const now = new Date();
      await tx.kitchenTicket.updateMany({
        where: { orderId: id, status: { in: ['READY'] } },
        data: { status: 'COMPLETED', completedAt: now },
      });
      await tx.order.update({ where: { id }, data: { status: 'COMPLETED', completedAt: now } });
    });
    await this.audit.log(actor, 'order.complete', 'order', id);
    return this.publishUpdate(id);
  }

  /**
   * Cancela la orden. Si la cocina ya empezó, hace falta el permiso orders.void_after_kitchen
   * (gerente). Las órdenes con pagos se resuelven con un reembolso (Fase 4).
   */
  async cancel(actor: Actor, id: string, reason: string): Promise<OrderView> {
    await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id }, include: { tickets: true } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (FINISHED.includes(order.status)) throw new ConflictException('La orden ya está cerrada');

      if (kitchenStarted(order.tickets.map((t) => t.status)) && !actor.permissions.has('orders.void_after_kitchen')) {
        throw new ForbiddenException('La cocina ya empezó: un gerente debe cancelar esta orden');
      }
      const paid = await tx.payment.count({ where: { billId: order.billId, status: 'SUCCEEDED' } });
      if (paid > 0) throw new ConflictException('La cuenta tiene pagos: primero hay que reembolsar');

      const now = new Date();
      const actorRef = `${actor.kind}:${actor.id}`;
      await tx.kitchenTicket.updateMany({ where: { orderId: id }, data: { status: 'CANCELLED' } });
      await tx.orderItem.updateMany({
        where: { orderId: id, status: 'ACTIVE' },
        data: { status: 'VOIDED', voidReason: reason, voidedById: actorRef, voidedAt: now },
      });
      await tx.order.update({
        where: { id },
        data: { status: 'CANCELLED', cancelledAt: now, cancelReason: reason, cancelledById: actorRef },
      });
      await this.recomputeBill(tx, order.billId);
    });
    await this.audit.log(actor, 'order.cancel', 'order', id, { reason });
    return this.publishUpdate(id);
  }

  /** Recalcula el estado de la orden a partir de sus tickets (lo usa cocina). */
  async syncStatusFromTickets(tx: Tx, orderId: string): Promise<void> {
    const order = await tx.order.findUniqueOrThrow({ where: { id: orderId }, include: { tickets: true } });
    const next = deriveOrderStatus(order.status, order.tickets.map((t) => t.status));
    if (next === order.status) return;
    const now = new Date();
    await tx.order.update({
      where: { id: orderId },
      data: {
        status: next,
        acceptedAt: order.acceptedAt ?? (next !== 'PLACED' ? now : undefined),
        readyAt: next === 'READY' ? now : order.readyAt,
      },
    });
  }

  async publishUpdate(id: string, ticketsCreated = false): Promise<OrderView> {
    const view = await this.getView(id);
    this.events.emit('order.updated', view);
    this.events.emit('bill.updated', view.bill);
    if (ticketsCreated) this.events.emit('ticket.created', { orderId: id, ticketIds: view.tickets.map((t) => t.id) });
    return view;
  }

  // ───────── Internos ─────────

  /** Envía la orden a cocina: un ticket por estación. */
  private async placeInTx(tx: Tx, orderId: string): Promise<void> {
    const items = await tx.orderItem.findMany({ where: { orderId, status: 'ACTIVE' } });
    const fallback = await tx.kitchenStation.findFirst({
      where: { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });

    const byStation = new Map<string, string[]>();
    for (const item of items) {
      const stationId = item.stationId ?? fallback?.id;
      if (!stationId) throw new BadRequestException('Configura al menos una estación de cocina');
      byStation.set(stationId, [...(byStation.get(stationId) ?? []), item.id]);
    }
    for (const [stationId, itemIds] of byStation) {
      const ticket = await tx.kitchenTicket.create({ data: { orderId, stationId } });
      await tx.orderItem.updateMany({ where: { id: { in: itemIds } }, data: { ticketId: ticket.id, stationId } });
    }
    await tx.order.update({ where: { id: orderId }, data: { status: 'PLACED', placedAt: new Date() } });
  }

  /** Mesa → sesión abierta y su cuenta pendiente. Mostrador → cuenta nueva. */
  private async resolveBill(tx: Tx, tableId: string | undefined): Promise<string> {
    if (!tableId) return (await tx.bill.create({ data: {} })).id;

    let session = await tx.tableSession.findFirst({
      where: { tableId, status: { in: ['OPEN', 'BILL_REQUESTED'] } },
      orderBy: { openedAt: 'desc' },
    });
    if (!session) {
      session = await tx.tableSession.create({ data: { tableId } });
      await tx.diningTable.update({ where: { id: tableId }, data: { status: 'OCCUPIED' } });
    }
    const bill = await tx.bill.findFirst({
      where: { tableSessionId: session.id, status: { in: ['UNPAID', 'PARTIALLY_PAID'] } },
      orderBy: { createdAt: 'asc' },
    });
    return bill?.id ?? (await tx.bill.create({ data: { tableSessionId: session.id } })).id;
  }

  async recomputeBill(tx: Tx, billId: string): Promise<void> {
    const bill = await tx.bill.findUniqueOrThrow({
      where: { id: billId },
      include: { items: { where: { status: 'ACTIVE' } }, discounts: true, payments: { where: { status: 'SUCCEEDED' } } },
    });
    const totals = computeTotals(bill.items, {
      discountTotal: bill.discounts.reduce((sum, d) => sum.plus(d.amount), new Prisma.Decimal(0)),
      deliveryFee: bill.deliveryFee,
      tipTotal: bill.tipTotal,
    });
    const isEmpty = bill.items.length === 0 && bill.payments.length === 0;
    await tx.bill.update({
      where: { id: billId },
      data: { ...totals, status: isEmpty ? 'VOID' : bill.status },
    });
  }

  private async resolveOrigin(actor: Actor, dto: CreateOrderDto) {
    if (actor.kind === 'device') {
      if (actor.type !== 'EMENU' || !actor.permissions.has('table.order')) {
        throw new ForbiddenException('Este dispositivo no puede crear órdenes');
      }
      if (!actor.tableId) throw new BadRequestException('La tablet no tiene una mesa asignada');
      return { channel: 'TABLET' as OrderChannel, tableId: actor.tableId, fulfillmentType: 'DINE_IN' as const };
    }

    let channel: OrderChannel = 'POS';
    if (actor.deviceId) {
      const device = await this.prisma.device.findUnique({ where: { id: actor.deviceId } });
      if (device?.type === 'WAITER') channel = 'WAITER';
    }
    if (dto.fulfillmentType === 'DINE_IN') {
      if (!dto.tableId) throw new BadRequestException('Elige la mesa');
      const table = await this.prisma.diningTable.findUnique({ where: { id: dto.tableId } });
      if (!table?.isActive) throw new BadRequestException('Mesa no encontrada');
    }
    return {
      channel,
      tableId: dto.fulfillmentType === 'DINE_IN' ? dto.tableId : undefined,
      fulfillmentType: dto.fulfillmentType,
    };
  }

  private async findByClientRequestId(clientRequestId: string): Promise<OrderView | null> {
    const order = await this.prisma.order.findUnique({ where: { clientRequestId }, include: ORDER_INCLUDE });
    return order ? toOrderView(order) : null;
  }

  private uniqueTarget(error: unknown): string {
    return String((error as Prisma.PrismaClientKnownRequestError).meta?.target ?? '');
  }

  /** Reintenta ante choques de concurrencia (número del día o código público repetidos). */
  private async withRetry<T>(run: () => Promise<T>, attempts = 4): Promise<T> {
    for (let attempt = 1; ; attempt++) {
      try {
        return await run();
      } catch (error) {
        const retryable =
          (isUniqueViolation(error) && !this.uniqueTarget(error).includes('clientRequestId')) ||
          (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2034');
        if (!retryable || attempt >= attempts) throw error;
      }
    }
  }
}
