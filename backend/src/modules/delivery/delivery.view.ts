import type { OrderView } from '../orders/orders.service';

const ACTIVE = ['PENDING', 'ACCEPTED', 'PICKED_UP'];

/**
 * Lo que ve el repartidor de una entrega: cliente, dirección, productos y estado.
 * Sin datos de caja ni de otros pedidos.
 */
export function toDriverDelivery(order: OrderView) {
  const d = order.delivery!;
  const cancelled = order.status === 'CANCELLED';
  const completed = order.status === 'COMPLETED';
  return {
    assignmentId: d.assignmentId,
    status: cancelled ? 'CANCELLED' : completed ? 'DELIVERED' : d.status,
    active: !cancelled && !completed && ACTIVE.includes(d.status),
    orderId: order.id,
    number: order.number,
    publicCode: order.publicCode,
    orderStatus: order.status,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    address: order.deliveryAddress,
    instructions: order.deliveryInstructions,
    notes: order.notes,
    items: order.items
      .filter((i) => i.status === 'ACTIVE')
      .map((i) => ({ name: i.name, quantity: i.quantity, modifiers: i.modifiers.map((m) => m.option), notes: i.notes })),
    total: order.bill.total,
    tip: order.bill.tipTotal,
    paid: order.bill.status === 'PAID',
    amountDue: Math.max(0, Number(order.bill.total) - Number(order.bill.amountPaid)).toFixed(2),
    estimatedReadyAt: order.estimatedReadyAt,
    readyAt: order.readyAt,
    assignedAt: d.assignedAt,
    acceptedAt: d.acceptedAt,
    pickedUpAt: d.pickedUpAt,
    updatedAt: order.updatedAt,
  };
}

export type DriverDelivery = ReturnType<typeof toDriverDelivery>;
