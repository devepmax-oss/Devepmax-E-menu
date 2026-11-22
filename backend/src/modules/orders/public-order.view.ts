import type { OrderView } from './orders.service';

/** Etapa del pedido tal como la ve el cliente en la web o la tablet. */
export type PublicStage = 'awaiting_payment' | 'received' | 'preparing' | 'ready' | 'on_the_way' | 'completed' | 'cancelled';

export function publicStage(status: string): PublicStage {
  switch (status) {
    case 'PENDING_PAYMENT':
      return 'awaiting_payment';
    case 'PENDING_APPROVAL':
    case 'PLACED':
      return 'received';
    case 'ACCEPTED':
    case 'PREPARING':
      return 'preparing';
    case 'READY':
      return 'ready';
    case 'OUT_FOR_DELIVERY':
      return 'on_the_way';
    case 'COMPLETED':
      return 'completed';
    default:
      return 'cancelled';
  }
}

/**
 * Lo que el cliente puede ver de su pedido (seguimiento público por código).
 * Sin teléfono, email, dirección ni datos internos del restaurante.
 */
export function toPublicOrderView(order: OrderView) {
  const firstName = order.customerName?.trim().split(/\s+/)[0] ?? null;
  return {
    number: order.number,
    publicCode: order.publicCode,
    fulfillmentType: order.fulfillmentType,
    status: order.status,
    stage: publicStage(order.status),
    customerFirstName: firstName,
    createdAt: order.createdAt,
    placedAt: order.placedAt,
    estimatedReadyAt: order.estimatedReadyAt,
    readyAt: order.readyAt,
    completedAt: order.completedAt,
    cancelledAt: order.cancelledAt,
    updatedAt: order.updatedAt,
    items: order.items
      .filter((item) => item.status === 'ACTIVE')
      .map((item) => ({
        name: item.name,
        quantity: item.quantity,
        lineTotal: item.lineTotal,
        discount: item.discount,
        modifiers: item.modifiers.map((m) => ({ group: m.group, option: m.option })),
      })),
    promotions: order.promotions.map((p) => ({ name: p.name, amount: p.amount })),
    totals: {
      subtotal: order.bill.subtotal,
      discountTotal: order.bill.discountTotal,
      taxTotal: order.bill.taxTotal,
      deliveryFee: order.bill.deliveryFee,
      tipTotal: order.bill.tipTotal,
      total: order.bill.total,
      amountPaid: order.bill.amountPaid,
      paid: order.bill.status === 'PAID',
    },
  };
}

export type PublicOrderView = ReturnType<typeof toPublicOrderView>;
