import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { DeliveryAssignmentStatus, Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { ADMIN_ROLE_NAME } from '../../common/permissions';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEvent, DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { ORDER_INCLUDE, OrdersService, OrderView, toOrderView } from '../orders/orders.service';
import { SettingsService } from '../settings/settings.service';
import { DeliveryZoneDto, DriverLocationDto, UpdateDriverMeDto } from './dto/delivery.dto';
import { toDriverDelivery } from './delivery.view';
import { GeocodingService } from './geocoding.service';
import { PushService } from '../notifications/push.service';

const ACTIVE: DeliveryAssignmentStatus[] = ['PENDING', 'ACCEPTED', 'PICKED_UP'];
/** Una orden de delivery se puede asignar mientras no haya salido ni terminado. */
const ASSIGNABLE = ['PLACED', 'ACCEPTED', 'PREPARING', 'READY'];
/** Máximo de entregas en curso por repartidor para recibir una automática. */
const MAX_ACTIVE_PER_DRIVER = 3;
/** Cada cuánto se revisan las ofertas vencidas. */
const SWEEP_MS = 5000;

@Injectable()
export class DeliveryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DeliveryService.name);
  private unsubscribe?: () => void;
  /** Última ubicación aceptada por repartidor (para no saturar con envíos seguidos). */
  private readonly lastFix = new Map<string, number>();
  /** Pedidos que se están asignando ahora (evita asignar dos veces el mismo). */
  private readonly assigning = new Set<string>();
  private sweepTimer?: NodeJS.Timeout;
  private sweeping = false;
  private offerSeconds = 60;
  /** Entregas a las que ya se avisó "listo para recoger" o "cancelado" (no repetir). */
  private readonly notified = new Set<string>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly orders: OrdersService,
    private readonly events: DomainEventsService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly geocoding: GeocodingService,
    private readonly push: PushService,
  ) {}

  onModuleInit() {
    this.unsubscribe = this.events.subscribe((e) => this.onEvent(e));
    this.sweepTimer = setInterval(() => void this.sweep(), SWEEP_MS);
    // Al arrancar: pedidos que quedaron sin repartidor (por ejemplo, tras reiniciar el servidor).
    setTimeout(() => void this.assignWaiting(), 3000);
  }

  onModuleDestroy() {
    this.unsubscribe?.();
    if (this.sweepTimer) clearInterval(this.sweepTimer);
  }

  /** Cada cambio de una orden con repartidor le llega a ese repartidor en vivo. */
  private onEvent(event: DomainEvent) {
    if (event.name !== 'order.created' && event.name !== 'order.updated') return;
    const order = event.payload as OrderView;
    const d = order.delivery;
    if (!d) {
      // Pedido de delivery que entró a cocina sin repartidor: se asigna solo (si está activado).
      if (order.fulfillmentType === 'DELIVERY' && ASSIGNABLE.includes(order.status)) void this.autoAssign(order.id);
      return;
    }
    if (order.status === 'READY' && (d.status === 'ACCEPTED' || d.status === 'PENDING')) {
      this.notifyOnce(`${d.assignmentId}:ready`, d.driver.employeeId, {
        title: `Pedido #${order.number} listo para recoger`,
        body: 'Pasa por el local: ya está empacado.',
        data: { type: 'delivery.ready', assignmentId: d.assignmentId, orderId: order.id, tag: `delivery-${order.id}` },
      });
    }
    if (order.status === 'CANCELLED' && ACTIVE.includes(d.status)) {
      this.notifyOnce(`${d.assignmentId}:cancelled`, d.driver.employeeId, {
        title: `Pedido #${order.number} cancelado`,
        body: 'Ya no tienes que llevarlo.',
        data: { type: 'delivery.cancelled', assignmentId: d.assignmentId, orderId: order.id, tag: `delivery-${order.id}` },
      });
      void this.prisma.deliveryAssignment
        .updateMany({ where: { id: d.assignmentId, status: { in: ACTIVE } }, data: { status: 'CANCELLED', cancelledAt: new Date() } })
        .catch((e) => this.logger.error(`No se pudo cerrar la entrega: ${String(e)}`));
    }
    this.events.emit('delivery.updated', {
      driverEmployeeId: d.driver.employeeId,
      delivery: toDriverDelivery(order, this.offerSeconds),
    });
  }

  // ───────── Repartidor ─────────

  private async profileFor(actor: EmployeeActor) {
    return this.prisma.driverProfile.upsert({ where: { employeeId: actor.id }, create: { employeeId: actor.id }, update: {} });
  }

  async me(actor: EmployeeActor) {
    const profile = await this.profileFor(actor);
    const employee = await this.prisma.employee.findUniqueOrThrow({ where: { id: actor.id }, select: { name: true, phone: true } });
    return {
      id: profile.id,
      name: employee.name,
      phone: employee.phone,
      status: profile.status,
      vehicleType: profile.vehicleType,
      vehicleColor: profile.vehicleColor,
      vehiclePlate: profile.vehiclePlate,
    };
  }

  async updateMe(actor: EmployeeActor, dto: UpdateDriverMeDto) {
    const profile = await this.profileFor(actor);
    if (profile.status === 'SUSPENDED') throw new ForbiddenException('Tu cuenta de repartidor está suspendida');
    await this.prisma.driverProfile.update({
      where: { id: profile.id },
      data: {
        ...(dto.status ? { status: dto.status } : {}),
        ...(dto.vehicleType !== undefined ? { vehicleType: dto.vehicleType.trim() || null } : {}),
        ...(dto.vehicleColor !== undefined ? { vehicleColor: dto.vehicleColor.trim() || null } : {}),
        ...(dto.vehiclePlate !== undefined ? { vehiclePlate: dto.vehiclePlate.trim().toUpperCase() || null } : {}),
      },
    });
    // Se conectó: puede recibir los pedidos que esperan repartidor.
    if (dto.status === 'AVAILABLE') void this.assignWaiting();
    return this.me(actor);
  }

  /** Entregas en curso del repartidor (asignadas, aceptadas o en camino). */
  async myDeliveries(actor: EmployeeActor) {
    const profile = await this.profileFor(actor);
    const orders = await this.prisma.order.findMany({
      where: { deliveryAssignment: { driverId: profile.id, status: { in: ACTIVE } }, status: { notIn: ['COMPLETED', 'CANCELLED'] } },
      include: ORDER_INCLUDE,
      orderBy: { createdAt: 'asc' },
    });
    return orders.map((o) => toDriverDelivery(toOrderView(o), this.offerSeconds));
  }

  private async ownAssignment(actor: EmployeeActor, id: string) {
    const assignment = await this.prisma.deliveryAssignment.findUnique({
      where: { id },
      include: { driver: true, order: { select: { id: true, status: true } } },
    });
    if (!assignment || assignment.driver.employeeId !== actor.id) throw new NotFoundException('Entrega no encontrada');
    if (assignment.order.status === 'CANCELLED') throw new ConflictException('El pedido fue cancelado');
    return assignment;
  }

  async accept(actor: EmployeeActor, id: string) {
    const a = await this.ownAssignment(actor, id);
    if (a.status === 'ACCEPTED' || a.status === 'PICKED_UP') return this.deliveryView(a.orderId);
    if (a.status !== 'PENDING') throw new ConflictException('Esta entrega ya no está disponible');
    await this.prisma.$transaction([
      this.prisma.deliveryAssignment.update({ where: { id }, data: { status: 'ACCEPTED', acceptedAt: new Date() } }),
      this.touch(a.orderId),
    ]);
    await this.audit.log(actor, 'delivery.accept', 'order', a.orderId);
    return this.publish(a.orderId);
  }

  async decline(actor: EmployeeActor, id: string) {
    const a = await this.ownAssignment(actor, id);
    if (a.status === 'PICKED_UP') throw new ConflictException('Ya recogiste este pedido; márcalo como entregado');
    if (!ACTIVE.includes(a.status)) throw new ConflictException('Esta entrega ya no está activa');
    await this.prisma.$transaction([
      this.prisma.deliveryAssignment.update({
        where: { id },
        data: { status: 'CANCELLED', cancelledAt: new Date(), skippedDriverIds: { push: a.driverId } },
      }),
      this.touch(a.orderId),
    ]);
    await this.audit.log(actor, 'delivery.decline', 'order', a.orderId);
    this.events.emit('delivery.removed', { driverEmployeeId: actor.id, assignmentId: id, orderId: a.orderId, reason: 'declined' });
    // publishUpdate dispara la asignación automática al siguiente repartidor.
    await this.orders.publishUpdate(a.orderId);
    return { ok: true };
  }

  /** Lo recogió en el local: la orden pasa a "En camino". */
  async pickedUp(actor: EmployeeActor, id: string) {
    const a = await this.ownAssignment(actor, id);
    if (a.status === 'PICKED_UP') return this.deliveryView(a.orderId);
    if (!ACTIVE.includes(a.status)) throw new ConflictException('Esta entrega ya no está activa');
    if (a.order.status !== 'READY') throw new ConflictException('La cocina todavía no marca este pedido como listo');
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.deliveryAssignment.update({
        where: { id },
        data: { status: 'PICKED_UP', pickedUpAt: now, acceptedAt: a.acceptedAt ?? now },
      }),
      this.prisma.order.update({ where: { id: a.orderId }, data: { status: 'OUT_FOR_DELIVERY' } }),
    ]);
    await this.audit.log(actor, 'delivery.picked_up', 'order', a.orderId);
    return this.publish(a.orderId);
  }

  async delivered(actor: EmployeeActor, id: string) {
    const a = await this.ownAssignment(actor, id);
    if (a.status !== 'PICKED_UP') throw new ConflictException('Primero marca que recogiste el pedido');
    await this.prisma.deliveryAssignment.update({ where: { id }, data: { status: 'DELIVERED', deliveredAt: new Date() } });
    await this.orders.complete(actor, a.orderId);
    await this.audit.log(actor, 'delivery.delivered', 'order', a.orderId);
    void this.assignWaiting();
    return this.deliveryView(a.orderId);
  }

  /** Ubicación del repartidor. Si va en camino, el cliente la ve en el mapa al instante. */
  async location(actor: EmployeeActor, dto: DriverLocationDto) {
    const now = Date.now();
    if (now - (this.lastFix.get(actor.id) ?? 0) < 3000) return { ok: true, throttled: true };
    this.lastFix.set(actor.id, now);
    const profile = await this.profileFor(actor);
    const at = new Date(now);
    await this.prisma.driverProfile.update({ where: { id: profile.id }, data: { lastLat: dto.lat, lastLng: dto.lng, lastSeenAt: at } });
    const enRoute = await this.prisma.deliveryAssignment.findMany({
      where: { driverId: profile.id, status: 'PICKED_UP' },
      select: { orderId: true, order: { select: { publicCode: true } } },
    });
    for (const r of enRoute) {
      this.events.emit('driver.location', { orderId: r.orderId, publicCode: r.order.publicCode, lat: dto.lat, lng: dto.lng, at: at.toISOString() });
    }
    return { ok: true, throttled: false };
  }

  // ───────── Despacho (caja / gerente) ─────────

  /** Repartidores (empleados activos con rol de repartidor) y cuántas entregas llevan. */
  async drivers() {
    const employees = await this.prisma.employee.findMany({
      // El rol Admin tiene todos los permisos, pero no es repartidor.
      where: { isActive: true, role: { permissions: { has: 'delivery.own' }, name: { not: ADMIN_ROLE_NAME } } },
      select: { id: true, name: true, phone: true },
      orderBy: { name: 'asc' },
    });
    const profiles = await Promise.all(
      employees.map((e) => this.prisma.driverProfile.upsert({ where: { employeeId: e.id }, create: { employeeId: e.id }, update: {} })),
    );
    const counts = await this.prisma.deliveryAssignment.groupBy({
      by: ['driverId'],
      where: { status: { in: ACTIVE }, driverId: { in: profiles.map((p) => p.id) } },
      _count: { _all: true },
    });
    const active = new Map(counts.map((c) => [c.driverId, c._count._all]));
    return employees.map((e, i) => ({
      id: profiles[i].id,
      employeeId: e.id,
      name: e.name,
      phone: e.phone,
      status: profiles[i].status,
      lastSeenAt: profiles[i].lastSeenAt,
      activeDeliveries: active.get(profiles[i].id) ?? 0,
    }));
  }

  async assign(actor: EmployeeActor, orderId: string, driverId: string) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, include: { deliveryAssignment: { include: { driver: true } } } });
    if (!order) throw new NotFoundException('Orden no encontrada');
    if (order.fulfillmentType !== 'DELIVERY') throw new BadRequestException('Solo los pedidos de delivery llevan repartidor');
    if (!ASSIGNABLE.includes(order.status)) throw new ConflictException('Este pedido ya no se puede asignar');
    const driver = await this.prisma.driverProfile.findUnique({ where: { id: driverId }, include: { employee: true } });
    if (!driver || !driver.employee.isActive) throw new NotFoundException('Repartidor no encontrado');
    if (driver.status === 'SUSPENDED') throw new ConflictException('Ese repartidor está suspendido');

    const previous = order.deliveryAssignment;
    if (previous?.status === 'PICKED_UP') throw new ConflictException('El repartidor ya salió con este pedido');
    if (previous && previous.driverId === driverId && ACTIVE.includes(previous.status)) return this.orders.getView(orderId);

    await this.prisma.$transaction([
      this.prisma.deliveryAssignment.upsert({
        where: { orderId },
        create: { orderId, driverId, autoAssigned: false },
        update: {
          driverId,
          status: 'PENDING',
          autoAssigned: false,
          createdAt: new Date(),
          acceptedAt: null,
          pickedUpAt: null,
          deliveredAt: null,
          cancelledAt: null,
        },
      }),
      this.touch(orderId),
    ]);
    if (previous && previous.driverId !== driverId && ACTIVE.includes(previous.status)) {
      this.events.emit('delivery.removed', { driverEmployeeId: previous.driver.employeeId, assignmentId: previous.id, orderId });
    }
    await this.audit.log(actor, 'delivery.assign', 'order', orderId, { driverId });
    const view = await this.orders.publishUpdate(orderId);
    this.notifyOffer(view);
    return view;
  }

  async unassign(actor: EmployeeActor, orderId: string) {
    const a = await this.prisma.deliveryAssignment.findUnique({ where: { orderId }, include: { driver: true } });
    if (!a || !ACTIVE.includes(a.status)) return this.orders.getView(orderId);
    if (a.status === 'PICKED_UP') throw new ConflictException('El repartidor ya salió con este pedido');
    await this.prisma.$transaction([
      this.prisma.deliveryAssignment.update({ where: { id: a.id }, data: { status: 'CANCELLED', cancelledAt: new Date() } }),
      this.touch(orderId),
    ]);
    this.events.emit('delivery.removed', { driverEmployeeId: a.driver.employeeId, assignmentId: a.id, orderId });
    await this.audit.log(actor, 'delivery.unassign', 'order', orderId);
    return this.orders.publishUpdate(orderId);
  }

  // ───────── Zona de delivery ─────────

  async zone() {
    const [zone, settings] = await Promise.all([
      this.prisma.deliveryZone.findFirst({ where: { isActive: true }, orderBy: { fee: 'asc' } }),
      this.settings.get(),
    ]);
    const auto = { autoAssign: settings.autoAssignDrivers, offerSeconds: settings.driverOfferSeconds };
    return zone
      ? { fee: zone.fee, minOrder: zone.minOrder, etaMinutes: zone.etaMinutes, configured: true, ...auto }
      : { fee: new Prisma.Decimal(0), minOrder: new Prisma.Decimal(0), etaMinutes: settings.prepTimeMinutes + 20, configured: false, ...auto };
  }

  async saveZone(actor: EmployeeActor, dto: DeliveryZoneDto) {
    const zone = await this.prisma.deliveryZone.findFirst({ where: { isActive: true }, orderBy: { fee: 'asc' } });
    const data = { fee: new Prisma.Decimal(dto.fee), minOrder: new Prisma.Decimal(dto.minOrder), etaMinutes: dto.etaMinutes };
    if (zone) await this.prisma.deliveryZone.update({ where: { id: zone.id }, data });
    else await this.prisma.deliveryZone.create({ data: { name: 'Zona principal', ...data } });
    if (dto.autoAssign !== undefined || dto.offerSeconds !== undefined) {
      await this.settings.update(actor, { autoAssignDrivers: dto.autoAssign, driverOfferSeconds: dto.offerSeconds });
      if (dto.offerSeconds) this.offerSeconds = dto.offerSeconds;
      if (dto.autoAssign) void this.assignWaiting();
    }
    await this.audit.log(actor, 'delivery.zone', 'settings', 'delivery-zone', { ...dto });
    return this.zone();
  }

  // ───────── Mapa ─────────

  /** Ubica la dirección de entrega en el mapa (en segundo plano; si falla no pasa nada). */
  async locateOrder(orderId: string, address: { street: string; city: string; state: string; zipCode: string }) {
    const settings = await this.settings.get();
    const point = await this.geocoding.geocode(address, settings.email);
    if (!point) return;
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, select: { deliveryAddress: true } });
    const current = (order?.deliveryAddress ?? {}) as Prisma.JsonObject;
    await this.prisma.order.update({ where: { id: orderId }, data: { deliveryAddress: { ...current, lat: point.lat, lng: point.lng } } });
    await this.orders.publishUpdate(orderId);
  }

  // ───────── Ayudantes ─────────

  /** Marca la orden como cambiada para que los clientes acepten la nueva versión. */
  private touch(orderId: string) {
    return this.prisma.order.update({ where: { id: orderId }, data: { updatedAt: new Date() } });
  }

  private async publish(orderId: string) {
    return toDriverDelivery(await this.orders.publishUpdate(orderId), this.offerSeconds);
  }

  private async deliveryView(orderId: string) {
    return toDriverDelivery(await this.orders.getView(orderId), this.offerSeconds);
  }

  // ───────── Notificaciones push ─────────

  /** "Nuevo pedido #12": suena aunque la app esté cerrada o el teléfono bloqueado. */
  private notifyOffer(order: OrderView) {
    const d = order.delivery;
    if (!d || d.status !== 'PENDING') return;
    const a = (order.deliveryAddress ?? {}) as { street?: string; city?: string };
    const where = [a.street, a.city].filter(Boolean).join(', ') || 'Entrega a domicilio';
    void this.push.send(`employee:${d.driver.employeeId}`, {
      title: `Nuevo pedido #${order.number}`,
      body: d.autoAssigned ? `${where} · Acepta en ${this.offerSeconds} s` : `${where} · Te lo asignaron`,
      data: { type: 'delivery.offer', assignmentId: d.assignmentId, orderId: order.id, tag: `delivery-${order.id}` },
      urgent: true,
    });
  }

  private notifyOnce(key: string, employeeId: string, message: { title: string; body: string; data: Record<string, string> }) {
    if (this.notified.has(key)) return;
    this.notified.add(key);
    if (this.notified.size > 5000) this.notified.clear();
    void this.push.send(`employee:${employeeId}`, message);
  }

  // ───────── Asignación automática ─────────

  /**
   * Elige repartidor para un pedido de delivery: disponible, con menos entregas en curso y,
   * si empatan, el que lleva más tiempo sin recibir una. Salta a quienes ya lo rechazaron
   * o lo dejaron vencer. Si no hay nadie, el pedido espera y se asigna cuando alguien se conecte.
   */
  async autoAssign(orderId: string): Promise<void> {
    if (this.assigning.has(orderId)) return;
    this.assigning.add(orderId);
    try {
      const settings = await this.settings.get();
      this.offerSeconds = settings.driverOfferSeconds;
      if (!settings.autoAssignDrivers) return;
      const order = await this.prisma.order.findUnique({ where: { id: orderId }, include: { deliveryAssignment: true } });
      if (!order || order.fulfillmentType !== 'DELIVERY' || !ASSIGNABLE.includes(order.status)) return;
      const current = order.deliveryAssignment;
      if (current && ACTIVE.includes(current.status)) return;

      const driverId = await this.pickDriver(current?.skippedDriverIds ?? []);
      if (!driverId) return;
      const now = new Date();
      await this.prisma.$transaction([
        this.prisma.deliveryAssignment.upsert({
          where: { orderId },
          create: { orderId, driverId, autoAssigned: true },
          update: {
            driverId,
            status: 'PENDING',
            autoAssigned: true,
            createdAt: now,
            acceptedAt: null,
            pickedUpAt: null,
            deliveredAt: null,
            cancelledAt: null,
          },
        }),
        this.touch(orderId),
      ]);
      await this.audit.log('system', 'delivery.auto_assign', 'order', orderId, { driverId });
      this.notifyOffer(await this.orders.publishUpdate(orderId));
    } catch (error) {
      this.logger.error(`No se pudo asignar repartidor al pedido ${orderId}: ${String(error)}`);
    } finally {
      this.assigning.delete(orderId);
    }
  }

  private async pickDriver(skipped: string[]): Promise<string | null> {
    const candidates = await this.prisma.driverProfile.findMany({
      where: {
        status: 'AVAILABLE',
        id: { notIn: skipped },
        employee: { isActive: true, role: { permissions: { has: 'delivery.own' }, name: { not: ADMIN_ROLE_NAME } } },
      },
      select: { id: true, assignments: { orderBy: { createdAt: 'desc' }, take: 1, select: { createdAt: true } } },
    });
    if (!candidates.length) return null;
    const counts = await this.prisma.deliveryAssignment.groupBy({
      by: ['driverId'],
      where: { status: { in: ACTIVE }, driverId: { in: candidates.map((c) => c.id) } },
      _count: { _all: true },
    });
    const active = new Map(counts.map((c) => [c.driverId, c._count._all]));
    const ranked = candidates
      .map((c) => ({ id: c.id, active: active.get(c.id) ?? 0, last: c.assignments[0]?.createdAt.getTime() ?? 0 }))
      .filter((c) => c.active < MAX_ACTIVE_PER_DRIVER)
      .sort((a, b) => a.active - b.active || a.last - b.last);
    return ranked[0]?.id ?? null;
  }

  /** Asigna, del más antiguo al más nuevo, los pedidos de delivery que esperan repartidor. */
  async assignWaiting(): Promise<void> {
    try {
      const waiting = await this.prisma.order.findMany({
        where: {
          fulfillmentType: 'DELIVERY',
          status: { in: ['PLACED', 'ACCEPTED', 'PREPARING', 'READY'] },
          OR: [{ deliveryAssignment: null }, { deliveryAssignment: { status: { in: ['CANCELLED', 'DELIVERED'] } } }],
        },
        select: { id: true },
        orderBy: { placedAt: 'asc' },
        take: 20,
      });
      for (const o of waiting) await this.autoAssign(o.id);
    } catch (error) {
      this.logger.error(`No se pudieron asignar los pedidos en espera: ${String(error)}`);
    }
  }

  /**
   * Ofertas automáticas que nadie aceptó a tiempo: pasan al siguiente repartidor, y quien
   * no respondió queda desconectado (así no se le siguen enviando pedidos que no ve).
   */
  private async sweep(): Promise<void> {
    if (this.sweeping) return;
    this.sweeping = true;
    try {
      const settings = await this.settings.get();
      this.offerSeconds = settings.driverOfferSeconds;
      const cutoff = new Date(Date.now() - settings.driverOfferSeconds * 1000);
      const expired = await this.prisma.deliveryAssignment.findMany({
        where: { status: 'PENDING', autoAssigned: true, createdAt: { lt: cutoff } },
        include: { driver: true },
      });
      for (const a of expired) {
        const closed = await this.prisma.deliveryAssignment.updateMany({
          where: { id: a.id, status: 'PENDING' },
          data: { status: 'CANCELLED', cancelledAt: new Date(), skippedDriverIds: { push: a.driverId } },
        });
        if (closed.count === 0) continue; // la aceptó justo a tiempo
        await this.prisma.driverProfile.updateMany({ where: { id: a.driverId, status: 'AVAILABLE' }, data: { status: 'OFFLINE' } });
        await this.touch(a.orderId);
        await this.audit.log('system', 'delivery.offer_expired', 'order', a.orderId, { driverId: a.driverId });
        this.events.emit('delivery.removed', {
          driverEmployeeId: a.driver.employeeId,
          assignmentId: a.id,
          orderId: a.orderId,
          reason: 'expired',
        });
        // Publicar la orden sin repartidor dispara la asignación al siguiente.
        await this.orders.publishUpdate(a.orderId);
      }
    } catch (error) {
      this.logger.error(`Error revisando ofertas vencidas: ${String(error)}`);
    } finally {
      this.sweeping = false;
    }
  }
}
