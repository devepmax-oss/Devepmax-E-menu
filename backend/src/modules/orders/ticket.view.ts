import { Prisma } from '@prisma/client';

/** Fecha más reciente (para la versión de una vista que junta varias tablas). */
export function latest(...dates: Date[]): Date {
  return dates.reduce((max, d) => (d.getTime() > max.getTime() ? d : max));
}

export const TICKET_INCLUDE = {
  station: true,
  items: { where: { status: 'ACTIVE' }, orderBy: { id: 'asc' }, include: { modifiers: true } },
  order: { include: { tableSession: { include: { table: true } } } },
} satisfies Prisma.KitchenTicketInclude;

export type TicketWithRelations = Prisma.KitchenTicketGetPayload<{ include: typeof TICKET_INCLUDE }>;

export function toTicketView(ticket: TicketWithRelations) {
  const { order } = ticket;
  return {
    id: ticket.id,
    status: ticket.status,
    /** Versión para tiempo real: el ticket muestra datos de la orden, así que cuenta el cambio más reciente. */
    updatedAt: latest(ticket.updatedAt, order.updatedAt),
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

export type TicketView = ReturnType<typeof toTicketView>;
