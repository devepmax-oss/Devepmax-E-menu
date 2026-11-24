import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, ServiceRequestType } from '@prisma/client';
import { DeviceActor, EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { ORDER_INCLUDE, toOrderView } from '../orders/orders.service';
import { TablesService } from './tables.service';

const OPEN_SESSION = { status: { in: ['OPEN', 'BILL_REQUESTED'] } } satisfies Prisma.TableSessionWhereInput;
const OPEN_REQUEST = { status: { in: ['OPEN', 'ACKNOWLEDGED'] } } satisfies Prisma.ServiceRequestWhereInput;
const LIVE_BILL = ['UNPAID', 'PARTIALLY_PAID', 'PAID'];

type RequestWithTable = Prisma.ServiceRequestGetPayload<{ include: { tableSession: { include: { table: true } } } }>;

/** Lo que se difunde de un llamado: qué pide y en qué mesa. */
function toRequestEvent(r: RequestWithTable) {
  return {
    id: r.id,
    type: r.type,
    status: r.status,
    createdAt: r.createdAt,
    table: { id: r.tableSession.table.id, label: r.tableSession.table.label },
  };
}

/**
 * La tablet de la mesa: ve su mesa, sus pedidos y la cuenta, y llama al mesero o pide la cuenta.
 * El personal atiende los llamados desde la caja o el panel.
 */
@Injectable()
export class EmenuService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEventsService,
    private readonly tables: TablesService,
    private readonly audit: AuditService,
  ) {}

  private tableIdOf(device: DeviceActor): string | null {
    if (device.type !== 'EMENU') throw new ForbiddenException('Solo para tablets de mesa');
    return device.tableId;
  }

  /** Mesa, visita en curso, pedidos (sin datos del personal) y cuenta. */
  async table(device: DeviceActor) {
    const tableId = this.tableIdOf(device);
    if (!tableId) return { table: null, session: null };
    const table = await this.prisma.diningTable.findUnique({ where: { id: tableId }, include: { area: true } });
    if (!table?.isActive) return { table: null, session: null };

    const tableInfo = { id: table.id, label: table.label, area: table.area.name, seats: table.seats, status: table.status };
    const session = await this.prisma.tableSession.findFirst({
      where: { tableId, ...OPEN_SESSION },
      orderBy: { openedAt: 'desc' },
      include: { serviceRequests: { where: OPEN_REQUEST, orderBy: { createdAt: 'asc' } } },
    });
    if (!session) return { table: tableInfo, session: null };

    const orders = (
      await this.prisma.order.findMany({ where: { tableSessionId: session.id }, include: ORDER_INCLUDE, orderBy: { createdAt: 'asc' } })
    ).map(toOrderView);

    // Todas las órdenes de la visita comparten la cuenta de la mesa; se suma cada cuenta una vez.
    const bills = new Map(orders.filter((o) => LIVE_BILL.includes(o.bill.status)).map((o) => [o.bill.id, o.bill]));
    const sum = (pick: (b: (typeof orders)[number]['bill']) => Prisma.Decimal) =>
      [...bills.values()].reduce((acc, b) => acc.plus(pick(b)), new Prisma.Decimal(0));
    const total = sum((b) => b.total);
    const paid = sum((b) => b.amountPaid);

    return {
      table: tableInfo,
      session: {
        id: session.id,
        status: session.status,
        guestCount: session.guestCount,
        openedAt: session.openedAt,
        requests: session.serviceRequests.map((r) => ({ id: r.id, type: r.type, status: r.status, createdAt: r.createdAt })),
        orders: orders
          .filter((o) => o.status !== 'PENDING_PAYMENT')
          .map((o) => ({
            id: o.id,
            number: o.number,
            status: o.status,
            createdAt: o.createdAt,
            readyAt: o.readyAt,
            items: o.items
              .filter((i) => i.status === 'ACTIVE')
              .map((i) => ({
                id: i.id,
                name: i.name,
                quantity: i.quantity,
                lineTotal: i.lineTotal,
                discount: i.discount,
                notes: i.notes,
                modifiers: i.modifiers.map((m) => m.option),
              })),
          })),
        bill: {
          subtotal: sum((b) => b.subtotal),
          discountTotal: sum((b) => b.discountTotal),
          taxTotal: sum((b) => b.taxTotal),
          tipTotal: sum((b) => b.tipTotal),
          total,
          paid,
          due: Prisma.Decimal.max(total.minus(paid), 0),
        },
      },
    };
  }

  /** "Llamar al mesero" o "Pedir la cuenta". Si ya hay uno igual sin atender, no se repite. */
  async createRequest(device: DeviceActor, type: ServiceRequestType) {
    const tableId = this.tableIdOf(device);
    if (!tableId) throw new BadRequestException('La tablet no tiene una mesa asignada');
    const table = await this.prisma.diningTable.findUnique({ where: { id: tableId } });
    if (!table?.isActive) throw new BadRequestException('La tablet no tiene una mesa asignada');

    let session = await this.prisma.tableSession.findFirst({ where: { tableId, ...OPEN_SESSION }, orderBy: { openedAt: 'desc' } });
    if (!session) {
      if (type === 'REQUEST_BILL') throw new BadRequestException('Todavía no hay nada en la cuenta de esta mesa');
      // Llamaron al mesero al sentarse: la mesa queda ocupada.
      [session] = await this.prisma.$transaction([
        this.prisma.tableSession.create({ data: { tableId } }),
        this.prisma.diningTable.update({ where: { id: tableId }, data: { status: 'OCCUPIED' } }),
      ]);
    }

    const existing = await this.prisma.serviceRequest.findFirst({ where: { tableSessionId: session.id, type, ...OPEN_REQUEST } });
    if (!existing) {
      const created = await this.prisma.serviceRequest.create({
        data: { tableSessionId: session.id, type },
        include: { tableSession: { include: { table: true } } },
      });
      if (type === 'REQUEST_BILL') {
        await this.prisma.tableSession.update({ where: { id: session.id }, data: { status: 'BILL_REQUESTED' } });
      }
      await this.audit.log(device, 'table.request', 'table', tableId, { label: table.label, type });
      this.events.emit('service_request.created', toRequestEvent(created));
    }
    this.tables.notify(tableId);
    return this.table(device);
  }

  /** El cliente se arrepintió del llamado. */
  async cancelRequest(device: DeviceActor, id: string) {
    const tableId = this.tableIdOf(device);
    const request = await this.findRequest(id);
    if (!tableId || request.tableSession.tableId !== tableId) throw new NotFoundException('Llamado no encontrado');
    if (request.status !== 'DONE') await this.finish(request, 'DONE', null);
    return this.table(device);
  }

  /** El personal lo vio (ACKNOWLEDGED) o ya lo atendió (DONE). */
  async resolveRequest(actor: EmployeeActor, id: string, status: 'ACKNOWLEDGED' | 'DONE') {
    const request = await this.findRequest(id);
    if (request.status !== 'DONE') {
      await this.finish(request, status, actor.id);
      await this.audit.log(actor, 'table.request_resolved', 'table', request.tableSession.tableId, { type: request.type, status });
    }
    return { ok: true };
  }

  private async findRequest(id: string) {
    const request = await this.prisma.serviceRequest.findUnique({ where: { id }, include: { tableSession: { include: { table: true } } } });
    if (!request) throw new NotFoundException('Llamado no encontrado');
    return request;
  }

  private async finish(request: RequestWithTable, status: 'ACKNOWLEDGED' | 'DONE', employeeId: string | null) {
    const updated = await this.prisma.serviceRequest.update({
      where: { id: request.id },
      data: { status, ...(status === 'DONE' ? { resolvedAt: new Date(), resolvedById: employeeId } : {}) },
      include: { tableSession: { include: { table: true } } },
    });
    // Si se retira el pedido de cuenta sin cobrar, la mesa sigue abierta normal.
    if (status === 'DONE' && request.type === 'REQUEST_BILL' && employeeId === null && request.tableSession.status === 'BILL_REQUESTED') {
      await this.prisma.tableSession.update({ where: { id: request.tableSessionId }, data: { status: 'OPEN' } });
    }
    this.events.emit('service_request.updated', toRequestEvent(updated));
    this.tables.notify(request.tableSession.tableId);
  }
}
