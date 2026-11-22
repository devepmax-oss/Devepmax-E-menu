import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { TicketStatus } from '@prisma/client';
import { Actor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { canMoveTicket } from './order.rules';
import { OrdersService } from './orders.service';
import { TICKET_INCLUDE, toTicketView } from './ticket.view';

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
    // publishUpdate difunde la orden y todos sus tickets (incluido este).
    await this.orders.publishUpdate(ticketView.orderId);
    return toTicketView(ticketView);
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
