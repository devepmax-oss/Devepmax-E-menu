import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { Prisma, TableStatus } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEvent, DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { AreaDto, BulkTablesDto, CreateTableDto, LayoutDto, UpdateAreaDto, UpdateTableDto } from './dto/tables.dto';

const OPEN_SESSION = { status: { in: ['OPEN', 'BILL_REQUESTED'] } } satisfies Prisma.TableSessionWhereInput;
const FINISHED_ORDER = ['COMPLETED', 'CANCELLED'];

const TABLE_INCLUDE = {
  devices: { where: { isActive: true, type: 'EMENU' }, select: { id: true, name: true, lastSeenAt: true } },
  sessions: {
    where: OPEN_SESSION,
    orderBy: { openedAt: 'desc' },
    take: 1,
    include: {
      orders: { select: { id: true, status: true } },
      bills: { where: { status: { in: ['UNPAID', 'PARTIALLY_PAID', 'PAID'] } }, select: { total: true, amountPaid: true } },
      serviceRequests: { where: { status: { in: ['OPEN', 'ACKNOWLEDGED'] } }, orderBy: { createdAt: 'asc' } },
    },
  },
} satisfies Prisma.DiningTableInclude;

type TableWithSession = Prisma.DiningTableGetPayload<{ include: typeof TABLE_INCLUDE }>;

/** Lo que ven caja y meseros de cada mesa: estado, sesión abierta, cuenta y llamados. */
export function toTableView(t: TableWithSession) {
  const s = t.sessions[0];
  const total = s ? s.bills.reduce((sum, b) => sum.plus(b.total), new Prisma.Decimal(0)) : new Prisma.Decimal(0);
  const paid = s ? s.bills.reduce((sum, b) => sum.plus(b.amountPaid), new Prisma.Decimal(0)) : new Prisma.Decimal(0);
  return {
    id: t.id,
    label: t.label,
    areaId: t.areaId,
    seats: t.seats,
    status: t.status,
    posX: t.posX,
    posY: t.posY,
    isActive: t.isActive,
    tablets: t.devices.map((d) => ({ id: d.id, name: d.name, lastSeenAt: d.lastSeenAt })),
    session: s
      ? {
          id: s.id,
          status: s.status,
          guestCount: s.guestCount,
          openedAt: s.openedAt,
          orderCount: s.orders.filter((o) => o.status !== 'CANCELLED').length,
          activeOrders: s.orders.filter((o) => !FINISHED_ORDER.includes(o.status)).length,
          total,
          paid,
          due: Prisma.Decimal.max(total.minus(paid), 0),
          requests: s.serviceRequests.map((r) => ({ id: r.id, type: r.type, status: r.status, createdAt: r.createdAt })),
        }
      : null,
  };
}

export type TableView = ReturnType<typeof toTableView>;

/** Ordena "2" antes que "10" y luego por texto. */
const byLabel = (a: { label: string }, b: { label: string }) => {
  const na = Number.parseInt(a.label, 10);
  const nb = Number.parseInt(b.label, 10);
  if (!Number.isNaN(na) && !Number.isNaN(nb) && na !== nb) return na - nb;
  return a.label.localeCompare(b.label, 'es', { numeric: true });
};

@Injectable()
export class TablesService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TablesService.name);
  private unsubscribe?: () => void;
  /** Agrupa varios cambios seguidos de la misma mesa en un solo aviso. */
  private readonly pending = new Map<string, NodeJS.Timeout>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEventsService,
    private readonly audit: AuditService,
  ) {}

  onModuleInit() {
    this.unsubscribe = this.events.subscribe((e) => this.onEvent(e));
  }

  onModuleDestroy() {
    this.unsubscribe?.();
    this.pending.forEach((t) => clearTimeout(t));
  }

  /** Un pedido o una cuenta de mesa cambió: el plano se actualiza en vivo. */
  private onEvent(event: DomainEvent) {
    if (event.name === 'order.created' || event.name === 'order.updated') {
      const tableId = (event.payload as { table?: { id: string } | null }).table?.id;
      if (tableId) this.schedule(tableId);
    } else if (event.name === 'bill.updated') {
      const tableId = (event.payload as { tableId?: string | null }).tableId;
      if (tableId) this.schedule(tableId);
    }
  }

  private schedule(tableId: string) {
    clearTimeout(this.pending.get(tableId));
    this.pending.set(
      tableId,
      setTimeout(() => {
        this.pending.delete(tableId);
        void this.publish(tableId).catch((e) => this.logger.error(`No se pudo difundir la mesa: ${String(e)}`));
      }, 250),
    );
  }

  private async publish(tableId: string): Promise<TableView> {
    const view = await this.view(tableId);
    this.events.emit('table.updated', view);
    return view;
  }

  // ───────── Lectura ─────────

  /** Salón completo: áreas con sus mesas. */
  async floor() {
    const [areas, tables] = await Promise.all([
      this.prisma.diningArea.findMany({ orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] }),
      this.prisma.diningTable.findMany({ where: { isActive: true }, include: TABLE_INCLUDE }),
    ]);
    const views = tables.map(toTableView).sort(byLabel);
    return areas.map((a) => ({ id: a.id, name: a.name, sortOrder: a.sortOrder, tables: views.filter((t) => t.areaId === a.id) }));
  }

  async view(id: string): Promise<TableView> {
    const table = await this.prisma.diningTable.findUnique({ where: { id }, include: TABLE_INCLUDE });
    if (!table) throw new NotFoundException('Mesa no encontrada');
    return toTableView(table);
  }

  // ───────── Áreas ─────────

  async createArea(actor: EmployeeActor, dto: AreaDto) {
    const count = await this.prisma.diningArea.count();
    const area = await this.prisma.diningArea.create({ data: { name: dto.name.trim(), sortOrder: dto.sortOrder ?? count } });
    await this.audit.log(actor, 'area.create', 'area', area.id, { name: area.name });
    return area;
  }

  async updateArea(actor: EmployeeActor, id: string, dto: UpdateAreaDto) {
    await this.findArea(id);
    const area = await this.prisma.diningArea.update({
      where: { id },
      data: { ...(dto.name !== undefined ? { name: dto.name.trim() } : {}), ...(dto.sortOrder !== undefined ? { sortOrder: dto.sortOrder } : {}) },
    });
    await this.audit.log(actor, 'area.update', 'area', id, { ...dto });
    return area;
  }

  async deleteArea(actor: EmployeeActor, id: string) {
    await this.findArea(id);
    const tables = await this.prisma.diningTable.count({ where: { areaId: id, isActive: true } });
    if (tables > 0) throw new ConflictException('Primero mueve o elimina las mesas de esta área');
    // Mesas eliminadas que conservan historial: pasan a otra área (siguen ocultas).
    const archived = await this.prisma.diningTable.count({ where: { areaId: id } });
    if (archived > 0) {
      const other = await this.prisma.diningArea.findFirst({ where: { id: { not: id } }, orderBy: { sortOrder: 'asc' } });
      if (!other) throw new ConflictException('Es la única área: cámbiale el nombre en lugar de eliminarla');
      await this.prisma.diningTable.updateMany({ where: { areaId: id }, data: { areaId: other.id } });
    }
    await this.prisma.diningArea.delete({ where: { id } });
    await this.audit.log(actor, 'area.delete', 'area', id);
    return { ok: true };
  }

  // ───────── Mesas ─────────

  async createTable(actor: EmployeeActor, dto: CreateTableDto) {
    await this.findArea(dto.areaId);
    const label = dto.label.trim();
    const slot = dto.posX === undefined || dto.posY === undefined ? await this.freeSlot(dto.areaId) : { posX: dto.posX, posY: dto.posY };
    try {
      const table = await this.prisma.diningTable.create({ data: { label, areaId: dto.areaId, seats: dto.seats, ...slot } });
      await this.audit.log(actor, 'table.create', 'table', table.id, { label });
      return this.publish(table.id);
    } catch (error) {
      if (isUniqueViolation(error)) return this.reviveOrConflict(actor, label, dto);
      throw error;
    }
  }

  /** Una mesa eliminada antes con el mismo nombre vuelve a usarse en lugar de chocar. */
  private async reviveOrConflict(actor: EmployeeActor, label: string, dto: CreateTableDto) {
    const old = await this.prisma.diningTable.findUnique({ where: { label } });
    if (!old || old.isActive) throw new ConflictException(`Ya existe la mesa ${label}`);
    const slot = await this.freeSlot(dto.areaId);
    await this.prisma.diningTable.update({
      where: { id: old.id },
      data: { isActive: true, areaId: dto.areaId, seats: dto.seats, status: 'AVAILABLE', posX: dto.posX ?? slot.posX, posY: dto.posY ?? slot.posY },
    });
    await this.audit.log(actor, 'table.create', 'table', old.id, { label, revived: true });
    return this.publish(old.id);
  }

  async bulkCreate(actor: EmployeeActor, dto: BulkTablesDto) {
    await this.findArea(dto.areaId);
    const created: TableView[] = [];
    const skipped: string[] = [];
    for (let n = dto.from; n < dto.from + dto.count; n++) {
      try {
        created.push(await this.createTable(actor, { label: String(n), areaId: dto.areaId, seats: dto.seats }));
      } catch (error) {
        if (error instanceof ConflictException) skipped.push(String(n));
        else throw error;
      }
    }
    return { created: created.length, skipped };
  }

  async updateTable(actor: EmployeeActor, id: string, dto: UpdateTableDto) {
    const table = await this.findTable(id);
    if (dto.areaId) await this.findArea(dto.areaId);
    if (dto.isActive === false) return this.removeTable(actor, id);
    try {
      await this.prisma.diningTable.update({
        where: { id },
        data: {
          ...(dto.label !== undefined ? { label: dto.label.trim() } : {}),
          ...(dto.areaId !== undefined ? { areaId: dto.areaId } : {}),
          ...(dto.seats !== undefined ? { seats: dto.seats } : {}),
          ...(dto.posX !== undefined ? { posX: dto.posX } : {}),
          ...(dto.posY !== undefined ? { posY: dto.posY } : {}),
        },
      });
    } catch (error) {
      if (isUniqueViolation(error)) throw new ConflictException(`Ya existe la mesa ${dto.label}`);
      throw error;
    }
    await this.audit.log(actor, 'table.update', 'table', id, { from: table.label, ...dto });
    return this.publish(id);
  }

  /** Quitar del plano. Si tuvo pedidos se oculta (se conserva el historial). */
  async removeTable(actor: EmployeeActor, id: string) {
    const table = await this.findTable(id);
    const open = await this.prisma.tableSession.count({ where: { tableId: id, ...OPEN_SESSION } });
    if (open) throw new ConflictException(`La mesa ${table.label} está ocupada: ciérrala primero`);
    const history = await this.prisma.tableSession.count({ where: { tableId: id } });
    await this.prisma.device.updateMany({ where: { tableId: id }, data: { tableId: null } });
    if (history) await this.prisma.diningTable.update({ where: { id }, data: { isActive: false } });
    else await this.prisma.diningTable.delete({ where: { id } });
    await this.audit.log(actor, 'table.delete', 'table', id, { label: table.label });
    this.events.emit('table.updated', { id, removed: true });
    return { ok: true };
  }

  async saveLayout(actor: EmployeeActor, dto: LayoutDto) {
    await this.prisma.$transaction(
      dto.positions.map((p) => this.prisma.diningTable.update({ where: { id: p.id }, data: { posX: p.posX, posY: p.posY } })),
    );
    await this.audit.log(actor, 'table.layout', 'table', 'layout', { count: dto.positions.length });
    for (const p of dto.positions) this.schedule(p.id);
    return { ok: true };
  }

  // ───────── Operación (meseros y caja) ─────────

  /** Sentar clientes: abre la mesa (o actualiza cuántos son). */
  async open(actor: EmployeeActor, id: string, guestCount?: number) {
    const table = await this.findTable(id);
    const session = await this.prisma.tableSession.findFirst({ where: { tableId: id, ...OPEN_SESSION } });
    if (session) {
      if (guestCount !== undefined) await this.prisma.tableSession.update({ where: { id: session.id }, data: { guestCount } });
    } else {
      await this.prisma.$transaction([
        this.prisma.tableSession.create({ data: { tableId: id, guestCount, waiterId: actor.id } }),
        this.prisma.diningTable.update({ where: { id }, data: { status: 'OCCUPIED' } }),
      ]);
      await this.audit.log(actor, 'table.open', 'table', id, { label: table.label, guestCount });
    }
    return this.publish(id);
  }

  /** Los clientes se fueron: la mesa queda "por limpiar". */
  async close(actor: EmployeeActor, id: string, force = false) {
    const table = await this.findTable(id);
    const view = toTableView(await this.prisma.diningTable.findUniqueOrThrow({ where: { id }, include: TABLE_INCLUDE }));
    const s = view.session;
    if (!s) {
      if (table.status === 'OCCUPIED') await this.prisma.diningTable.update({ where: { id }, data: { status: 'CLEANING' } });
      return this.publish(id);
    }
    if (s.activeOrders > 0) {
      throw new ConflictException(`La mesa ${table.label} tiene pedidos en curso: entrégalos o cancélalos antes de cerrarla`);
    }
    if (s.due.gt(0) && !force) {
      throw new ConflictException(`La cuenta de la mesa ${table.label} tiene $${s.due.toFixed(2)} pendientes`);
    }
    const now = new Date();
    await this.prisma.$transaction([
      this.prisma.tableSession.update({ where: { id: s.id }, data: { status: 'CLOSED', closedAt: now } }),
      this.prisma.serviceRequest.updateMany({
        where: { tableSessionId: s.id, status: { in: ['OPEN', 'ACKNOWLEDGED'] } },
        data: { status: 'DONE', resolvedAt: now, resolvedById: actor.id },
      }),
      this.prisma.diningTable.update({ where: { id }, data: { status: 'CLEANING' } }),
    ]);
    await this.audit.log(actor, s.due.gt(0) ? 'table.close_unpaid' : 'table.close', 'table', id, {
      label: table.label,
      total: s.total.toString(),
      due: s.due.toString(),
    });
    return this.publish(id);
  }

  /** Reservar, quitar la reserva o marcar lista después de limpiar. */
  async setStatus(actor: EmployeeActor, id: string, status: Extract<TableStatus, 'AVAILABLE' | 'RESERVED' | 'CLEANING'>) {
    const table = await this.findTable(id);
    const open = await this.prisma.tableSession.count({ where: { tableId: id, ...OPEN_SESSION } });
    if (open) throw new ConflictException(`La mesa ${table.label} tiene clientes: ciérrala primero`);
    await this.prisma.diningTable.update({ where: { id }, data: { status } });
    await this.audit.log(actor, 'table.status', 'table', id, { label: table.label, status });
    return this.publish(id);
  }

  // ───────── Ayudantes ─────────

  private async findArea(id: string) {
    const area = await this.prisma.diningArea.findUnique({ where: { id } });
    if (!area) throw new NotFoundException('Área no encontrada');
    return area;
  }

  private async findTable(id: string) {
    const table = await this.prisma.diningTable.findUnique({ where: { id } });
    if (!table || !table.isActive) throw new NotFoundException('Mesa no encontrada');
    return table;
  }

  /** Primer lugar libre del plano (de izquierda a derecha, de arriba abajo, cada 3 casillas). */
  private async freeSlot(areaId: string): Promise<{ posX: number; posY: number }> {
    const used = await this.prisma.diningTable.findMany({ where: { areaId, isActive: true }, select: { posX: true, posY: true } });
    const taken = new Set(used.map((t) => `${t.posX}:${t.posY}`));
    for (let y = 0; y <= 36; y += 3) {
      for (let x = 0; x <= 21; x += 3) {
        if (!taken.has(`${x}:${y}`)) return { posX: x, posY: y };
      }
    }
    throw new BadRequestException('El plano de esta área está lleno');
  }
}
