import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { FulfillmentType, OrderChannel, OrderStatus, Prisma } from '@prisma/client';
import { Actor } from '../../common/auth/actor';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { Allocation } from '../promotions/promotion.engine';
import { PromotionsService } from '../promotions/promotions.service';
import { SettingsService } from '../settings/settings.service';
import { CreateOrderDto, OrderLineDto, QuoteOrderDto } from './dto/order.dto';
import {
  businessDateFor,
  computeTotals,
  deriveOrderStatus,
  generatePublicCode,
  kitchenStarted,
} from './order.rules';
import { PricedLine, PricingService } from './pricing.service';
import { TICKET_INCLUDE, latest, toTicketView } from './ticket.view';

type Tx = Prisma.TransactionClient;

/** Datos para crear una orden desde cualquier canal. */
export interface NewOrder {
  clientRequestId: string;
  channel: OrderChannel;
  fulfillmentType: FulfillmentType;
  /** PLACED (a cocina), PENDING_APPROVAL (espera al mesero) o PENDING_PAYMENT (web, espera el pago). */
  status: OrderStatus;
  tableId?: string;
  deviceId?: string | null;
  createdById?: string | null;
  customerName?: string | null;
  customerPhone?: string | null;
  customerEmail?: string | null;
  /** Cliente con cuenta (web con sesión). Si no viene, se usa el cliente identificado en la cuenta. */
  customerId?: string | null;
  deliveryAddress?: Prisma.InputJsonValue;
  deliveryInstructions?: string | null;
  notes?: string | null;
  items: OrderLineDto[];
  pricingChannel: 'dine_in' | 'online';
  deliveryFee?: Prisma.Decimal;
  tipTotal?: Prisma.Decimal;
}

export const ORDER_INCLUDE = {
  items: { orderBy: { id: 'asc' }, include: { modifiers: true, discounts: true } },
  tickets: { orderBy: { createdAt: 'asc' }, include: { station: true } },
  bill: true,
  tableSession: { include: { table: true } },
  deliveryAssignment: { include: { driver: { include: { employee: { select: { id: true, name: true, phone: true } } } } } },
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
    /** Versión para tiempo real: el cambio más reciente entre la orden, su cuenta y sus tickets. */
    updatedAt: latest(order.updatedAt, order.bill.updatedAt, ...order.tickets.map((t) => t.updatedAt)),
    table: order.tableSession ? { id: order.tableSession.table.id, label: order.tableSession.table.label } : null,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    customerEmail: order.customerEmail,
    deliveryAddress: order.deliveryAddress,
    deliveryInstructions: order.deliveryInstructions,
    notes: order.notes,
    createdAt: order.createdAt,
    placedAt: order.placedAt,
    readyAt: order.readyAt,
    estimatedReadyAt: order.estimatedReadyAt,
    completedAt: order.completedAt,
    cancelledAt: order.cancelledAt,
    cancelReason: order.cancelReason,
    promotions: summarizePromotions(order.items.filter((i) => i.status === 'ACTIVE').flatMap((i) => i.discounts)),
    items: order.items.map((item) => ({
      id: item.id,
      productId: item.productId,
      name: item.nameSnapshot,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      modifiersTotal: item.modifiersTotal,
      lineTotal: item.lineTotal,
      discount: item.discounts.reduce((sum, d) => sum.plus(d.amount), new Prisma.Decimal(0)),
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
    delivery: toDeliveryInfo(order.deliveryAssignment),
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
      updatedAt: order.bill.updatedAt,
    },
  };
}

export type OrderView = ReturnType<typeof toOrderView>;

type AssignmentWithDriver = NonNullable<OrderWithRelations['deliveryAssignment']>;

/** Repartidor asignado (null si no hay o si la asignación se canceló). */
function toDeliveryInfo(a: AssignmentWithDriver | null) {
  if (!a || a.status === 'CANCELLED') return null;
  const d = a.driver;
  return {
    assignmentId: a.id,
    status: a.status,
    autoAssigned: a.autoAssigned,
    assignedAt: a.createdAt,
    acceptedAt: a.acceptedAt,
    pickedUpAt: a.pickedUpAt,
    deliveredAt: a.deliveredAt,
    driver: {
      id: d.id,
      employeeId: d.employee.id,
      name: d.employee.name,
      phone: d.employee.phone,
      vehicleType: d.vehicleType,
      vehicleColor: d.vehicleColor,
      vehiclePlate: d.vehiclePlate,
      lastLat: d.lastLat,
      lastLng: d.lastLng,
      lastSeenAt: d.lastSeenAt,
    },
  };
}

/** Promociones aplicadas, agrupadas (nombre y ahorro total). */
function summarizePromotions(discounts: { promotionId: string | null; reason: string; amount: Prisma.Decimal }[]) {
  const byKey = new Map<string, { promotionId: string | null; name: string; amount: Prisma.Decimal }>();
  for (const d of discounts) {
    const key = d.promotionId ?? `manual:${d.reason}`;
    const current = byKey.get(key);
    byKey.set(key, {
      promotionId: d.promotionId,
      name: d.reason,
      amount: (current?.amount ?? new Prisma.Decimal(0)).plus(d.amount),
    });
  }
  return [...byKey.values()];
}

/** Descuento por línea según las asignaciones del motor de promociones. */
function discountsByLine(allocations: Allocation[]): Map<number, Prisma.Decimal> {
  const result = new Map<number, Prisma.Decimal>();
  for (const allocation of allocations) {
    for (const [line, amount] of allocation.perLine) {
      result.set(line, (result.get(line) ?? new Prisma.Decimal(0)).plus(amount));
    }
  }
  return result;
}

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pricing: PricingService,
    private readonly promotions: PromotionsService,
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
    const status: OrderStatus = channel === 'TABLET' && settings.requireWaiterApproval ? 'PENDING_APPROVAL' : 'PLACED';

    return this.createOrder(
      {
        clientRequestId: dto.clientRequestId,
        channel,
        fulfillmentType,
        status,
        tableId,
        deviceId: actor.kind === 'device' ? actor.id : actor.deviceId,
        createdById: actor.kind === 'employee' ? actor.id : null,
        customerName: dto.customerName,
        customerPhone: dto.customerPhone,
        notes: dto.notes,
        items: dto.items,
        pricingChannel: 'dine_in',
      },
      actor,
    );
  }

  /**
   * Crea una orden de cualquier canal (caja, tablet, mesero o web) dentro de una transacción:
   * número del día, cuenta, líneas con promociones, envío a cocina si corresponde y totales.
   * Idempotente por clientRequestId.
   */
  async createOrder(input: NewOrder, auditActor: Actor | 'system'): Promise<OrderView> {
    const existing = await this.findByClientRequestId(input.clientRequestId);
    if (existing) return existing;

    const settings = await this.settings.get();
    const lines = await this.pricing.priceLines(this.prisma, input.pricingChannel, input.items);
    const allocations = await this.promotions.applyToLines(input.pricingChannel, lines);

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
          const billId = await this.resolveBill(tx, input.tableId, input.createdById);
          const billRow = await tx.bill.findUniqueOrThrow({ where: { id: billId }, select: { tableSessionId: true, customerId: true } });
          const customerId = input.customerId ?? billRow.customerId ?? null;
          if (customerId && !billRow.customerId) {
            await tx.bill.update({ where: { id: billId }, data: { customerId } });
          }
          if (input.deliveryFee || input.tipTotal) {
            await tx.bill.update({
              where: { id: billId },
              data: { deliveryFee: input.deliveryFee ?? 0, tipTotal: input.tipTotal ?? 0 },
            });
          }

          const order = await tx.order.create({
            data: {
              businessDate,
              number: counter.lastOrderNumber,
              publicCode: generatePublicCode(),
              clientRequestId: input.clientRequestId,
              channel: input.channel,
              fulfillmentType: input.fulfillmentType,
              status: input.status,
              tableSessionId: input.tableId ? billRow.tableSessionId : null,
              billId,
              customerId,
              deviceId: input.deviceId ?? null,
              createdById: input.createdById ?? null,
              customerName: input.customerName?.trim() || null,
              customerPhone: input.customerPhone?.trim() || null,
              customerEmail: input.customerEmail?.trim() || null,
              deliveryAddress: input.deliveryAddress ?? undefined,
              deliveryInstructions: input.deliveryInstructions?.trim() || null,
              notes: input.notes?.trim() || null,
            },
          });

          await this.createItems(tx, order.id, billId, lines, allocations);
          if (input.status === 'PLACED') await this.placeInTx(tx, order.id, settings.prepTimeMinutes);
          await this.recomputeBill(tx, billId);
          return order.id;
        }),
      );
    } catch (error) {
      // Dos envíos simultáneos con el mismo clientRequestId: se devuelve la orden ya creada.
      if (isUniqueViolation(error) && this.uniqueTarget(error).includes('clientRequestId')) {
        const duplicate = await this.findByClientRequestId(input.clientRequestId);
        if (duplicate) return duplicate;
      }
      throw error;
    }

    const view = await this.getView(orderId);
    await this.audit.log(auditActor, 'order.create', 'order', orderId, {
      number: view.number,
      channel: input.channel,
      total: view.bill.total.toString(),
    });
    this.events.emit('order.created', view);
    this.emitBill(view);
    await this.emitTickets(orderId, 'ticket.created');
    return view;
  }

  /**
   * Orden online pagada: pasa a cocina. Si ya estaba en cocina (pago confirmado dos veces,
   * por el webhook y por la web) no hace nada.
   */
  async placeAfterPayment(orderId: string): Promise<OrderView> {
    const settings = await this.settings.get();
    const placed = await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id: orderId } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (order.status !== 'PENDING_PAYMENT') return false;
      await this.placeInTx(tx, orderId, settings.prepTimeMinutes);
      return true;
    });
    if (!placed) return this.getView(orderId);
    await this.audit.log('system', 'order.paid_online', 'order', orderId);
    return this.publishUpdate(orderId, true);
  }

  /**
   * Cotiza sin crear la orden: precios, promociones y totales tal como quedarían.
   * Lo usan el carrito de la tablet, el POS y la web.
   */
  async quote(dto: QuoteOrderDto, channel: 'dine_in' | 'online' = 'dine_in') {
    const lines = await this.pricing.priceLines(this.prisma, channel, dto.items);
    const allocations = await this.promotions.applyToLines(channel, lines);
    const perLine = discountsByLine(allocations);
    const totals = computeTotals(
      lines.map((line, i) => ({ lineTotal: line.lineTotal, taxRate: line.taxRate, discount: perLine.get(i) })),
    );
    return {
      lines: lines.map((line, i) => ({
        productId: line.productId,
        name: line.nameSnapshot,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        modifiersTotal: line.modifiersTotal,
        lineTotal: line.lineTotal,
        discount: perLine.get(i) ?? new Prisma.Decimal(0),
        modifiers: line.modifiers.map((m) => ({ group: m.groupNameSnapshot, option: m.optionNameSnapshot, priceAdjustment: m.priceAdjustment })),
      })),
      promotions: allocations.map((a) => ({ promotionId: a.promotionId, name: a.name, amount: a.amount })),
      totals,
    };
  }

  // ───────── Consultar ─────────

  async list(scope: 'active' | 'today'): Promise<OrderView[]> {
    const settings = await this.settings.get();
    const where: Prisma.OrderWhereInput =
      scope === 'active'
        ? {
            status: { notIn: FINISHED },
            // Un pedido web que no se pagó en 30 min se considera abandonado y no estorba en la pantalla.
            // Si el pago llega después, pasa a cocina y vuelve a aparecer.
            NOT: { status: 'PENDING_PAYMENT', createdAt: { lt: new Date(Date.now() - 30 * 60_000) } },
          }
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

  async findByPublicCode(publicCode: string): Promise<OrderView | null> {
    const order = await this.prisma.order.findUnique({ where: { publicCode }, include: ORDER_INCLUDE });
    return order ? toOrderView(order) : null;
  }

  // ───────── Cambios de estado ─────────

  /** Orden de tablet aprobada por el mesero: pasa a cocina. */
  async approve(actor: Actor, id: string): Promise<OrderView> {
    const settings = await this.settings.get();
    await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (order.status !== 'PENDING_APPROVAL') throw new ConflictException('La orden no está esperando aprobación');
      await this.placeInTx(tx, id, settings.prepTimeMinutes);
    });
    await this.audit.log(actor, 'order.approve', 'order', id);
    return this.publishUpdate(id, true);
  }

  /** Entregada al cliente (mesa o mostrador). */
  async complete(actor: Actor, id: string): Promise<OrderView> {
    await this.prisma.$transaction(async (tx) => {
      const order = await tx.order.findUnique({ where: { id } });
      if (!order) throw new NotFoundException('Orden no encontrada');
      if (order.status !== 'READY' && order.status !== 'OUT_FOR_DELIVERY') {
        throw new ConflictException('Solo se pueden entregar órdenes que estén listas');
      }
      const now = new Date();
      await tx.kitchenTicket.updateMany({
        where: { orderId: id, status: { in: ['READY'] } },
        data: { status: 'COMPLETED', completedAt: now },
      });
      await tx.order.update({ where: { id }, data: { status: 'COMPLETED', completedAt: now } });
      // Si lo entrega el local (sin pasar por la app del repartidor), la asignación queda cerrada.
      await tx.deliveryAssignment.updateMany({
        where: { orderId: id, status: { in: ['PENDING', 'ACCEPTED', 'PICKED_UP'] } },
        data: { status: 'DELIVERED', deliveredAt: now },
      });
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

  /**
   * Difunde en tiempo real el estado actual de la orden, su cuenta y todos sus tickets.
   * Se llama después de cada cambio (ya confirmado en la base de datos).
   */
  async publishUpdate(id: string, ticketsCreated = false): Promise<OrderView> {
    const view = await this.getView(id);
    this.events.emit('order.updated', view);
    this.emitBill(view);
    await this.emitTickets(id, ticketsCreated ? 'ticket.created' : 'ticket.updated');
    return view;
  }

  private emitBill(view: OrderView): void {
    this.events.emit('bill.updated', { ...view.bill, orderId: view.id, tableId: view.table?.id ?? null });
  }

  /** Cada pantalla de cocina recibe el ticket completo de su estación (no tiene que pedirlo aparte). */
  private async emitTickets(orderId: string, name: 'ticket.created' | 'ticket.updated'): Promise<void> {
    const tickets = await this.prisma.kitchenTicket.findMany({ where: { orderId }, include: TICKET_INCLUDE });
    for (const ticket of tickets) this.events.emit(name, toTicketView(ticket));
  }

  // ───────── Internos ─────────

  /** Crea las líneas, sus modificadores y los descuentos de promociones. */
  private async createItems(tx: Tx, orderId: string, billId: string, lines: PricedLine[], allocations: Allocation[]) {
    const itemIds: string[] = [];
    for (const line of lines) {
      const item = await tx.orderItem.create({
        data: {
          orderId,
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
        },
      });
      itemIds.push(item.id);
    }
    for (const allocation of allocations) {
      for (const [line, amount] of allocation.perLine) {
        await tx.discount.create({
          data: {
            billId,
            orderItemId: itemIds[line],
            type: 'AMOUNT',
            value: amount,
            amount,
            reason: allocation.name,
            promotionId: allocation.promotionId,
          },
        });
      }
    }
  }

  /** Envía la orden a cocina: un ticket por estación. */
  private async placeInTx(tx: Tx, orderId: string, prepMinutes = 20): Promise<void> {
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
    const now = new Date();
    await tx.order.update({
      where: { id: orderId },
      data: { status: 'PLACED', placedAt: now, estimatedReadyAt: new Date(now.getTime() + prepMinutes * 60_000) },
    });
  }

  /**
   * Mesa → sesión abierta y su cuenta pendiente. Mostrador → cuenta nueva.
   * Si la mesa no tiene mesero, la atiende el empleado que tomó el primer pedido.
   */
  private async resolveBill(tx: Tx, tableId: string | undefined, employeeId?: string | null): Promise<string> {
    if (!tableId) return (await tx.bill.create({ data: {} })).id;

    let session = await tx.tableSession.findFirst({
      where: { tableId, status: { in: ['OPEN', 'BILL_REQUESTED'] } },
      orderBy: { openedAt: 'desc' },
    });
    if (!session) {
      session = await tx.tableSession.create({ data: { tableId, waiterId: employeeId ?? null } });
      await tx.diningTable.update({ where: { id: tableId }, data: { status: 'OCCUPIED' } });
    } else if (!session.waiterId && employeeId) {
      session = await tx.tableSession.update({ where: { id: session.id }, data: { waiterId: employeeId } });
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
    const activeIds = new Set(bill.items.map((i) => i.id));
    const perItem = new Map<string, Prisma.Decimal>();
    let billDiscount = new Prisma.Decimal(0);
    for (const d of bill.discounts) {
      if (!d.orderItemId) billDiscount = billDiscount.plus(d.amount);
      // Los descuentos de líneas anuladas dejan de contar.
      else if (activeIds.has(d.orderItemId)) {
        perItem.set(d.orderItemId, (perItem.get(d.orderItemId) ?? new Prisma.Decimal(0)).plus(d.amount));
      }
    }
    const totals = computeTotals(
      bill.items.map((i) => ({ lineTotal: i.lineTotal, taxRate: i.taxRate, discount: perItem.get(i.id) })),
      { billDiscount, deliveryFee: bill.deliveryFee, tipTotal: bill.tipTotal },
    );
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
    // Comer aquí sin mesa = mostrador (barra). Con mesa, la orden se suma a la cuenta de la mesa.
    if (dto.fulfillmentType === 'DINE_IN' && dto.tableId) {
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
