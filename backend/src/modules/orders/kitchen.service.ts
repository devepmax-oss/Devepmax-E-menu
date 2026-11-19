import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, TicketStatus } from '@prisma/client';
import { Actor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { canMoveTicket } from './order.rules';
import { OrdersService } from './orders.service';

const TICKET_INCLUDE = {
  station: true,
  items: { where: { status: 'ACTIVE' }, orderBy: { id: 'asc' }, include: { modifiers: true } },
  order: { include: { tableSession: { include: { table: true } } } },
} satisfies Prisma.KitchenTicketInclude;

type TicketWithRelations = Prisma.KitchenTicketGetPayload<{ include: typeof TICKET_INCLUDE }>;

export function toTicketView(ticket: TicketWithRelations) {
  const { order } = ticket;
  return {
    id: ticket.id,
    status: ticket.status,
    createdAt: ticket.createdAt,
    acceptedAt: ticket.acceptedAt,
    startedAt: ticket.startedAt,
    readyAt: ticket.readyAt,
    station: { id: ticket.station.id, name: ticket.station.name, color: ticket.station.color },
    order: {
      id: order.id,
      number: order.number,
      channel: order.channel,
      fulfillmentType: order.fulfillmentType,
      status: order.status,
      table: order.tableSession?.table.label ?? null,
      customerName: order.customerName,
      notes: order.notes,
      scheduledFor: order.scheduledFor,
    },
    items: ticket.items.map((item) => ({
      id: item.id,
      name: item.nameSnapshot,
      quantity: item.quantity,
      notes: item.notes,
      seat: item.seat,
      modifiers: item.modifiers.map((m) => ({ group: m.groupNameSnapshot, option: m.optionNameSnapshot })),
    })),
  };
}

const ACTIVE_TICKETS: TicketStatus[] = ['NEW', 'ACCEPTED', 'PREPARING', 'READY'];

const TIMESTAMP_FOR: Partial<Record<TicketStatus, 'acceptedAt' | 'startedAt' | 'readyAt' | 'completedAt'>> = {
  ACCEPTED: 'acceptedAt',
  PREPARING: 'startedAt',
  READY: 'readyAt',
  COMPLETED: 'completedAt',
};

@Injectable()
export class KitchenService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly orders: OrdersService,
    private readonly audit: AuditService,
    private readonly events: DomainEventsService,
  ) {}

  /** Tickets en curso. Una pantalla de cocina solo ve los de su estación. */
  async list(actor: Actor, stationId?: string) {
    const station = this.stationScope(actor, stationId);
    const tickets = await this.prisma.kitchenTicket.findMany({
      where: { status: { in: ACTIVE_TICKETS }, ...(station ? { stationId: station } : {}) },
      include: TICKET_INCLUDE,
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
    return tickets.map(toTicketView);
  }

  async updateStatus(actor: Actor, id: string, status: TicketStatus) {
    const ticketView = await this.prisma.$transaction(async (tx) => {
      const ticket = await tx.kitchenTicket.findUnique({ where: { id } });
      if (!ticket) throw new NotFoundException('Ticket no encontrado');
      this.stationScope(actor, ticket.stationId);
      if (ticket.status === 'CANCELLED') throw new ConflictException('La orden fue cancelada');
      if (ticket.status === status) throw new BadRequestException('El ticket ya está en ese estado');
      if (!canMoveTicket(ticket.status, status)) throw new BadRequestException('Cambio de estado no permitido');

      const stamp = TIMESTAMP_FOR[status];
      await tx.kitchenTicket.update({
        where: { id },
        data: { status, ...(stamp && !ticket[stamp] ? { [stamp]: new Date() } : {}) },
      });
      await this.orders.syncStatusFromTickets(tx, ticket.orderId);
      return tx.kitchenTicket.findUniqueOrThrow({ where: { id }, include: TICKET_INCLUDE });
    });

    await this.audit.log(actor, 'ticket.status', 'ticket', id, { status });
    const view = toTicketView(ticketView);
    this.events.emit('ticket.updated', view);
    await this.orders.publishUpdate(view.order.id);
    return view;
  }

  /** Dispositivos de cocina: solo su estación. Empleados: la que pidan (o todas). */
  private stationScope(actor: Actor, requested?: string): string | undefined {
    if (actor.kind === 'device') {
      if (!actor.stationId) throw new ForbiddenException('Esta pantalla no tiene una estación asignada');
      if (requested && requested !== actor.stationId) throw new ForbiddenException('Este ticket es de otra estación');
      return actor.stationId;
    }
    return requested;
  }
}
