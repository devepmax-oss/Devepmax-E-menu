import type { OrderView } from './orders.service';

/** Etapa del pedido tal como la ve el cliente en la web o la tablet. */
export type PublicStage = 'scheduled' | 'awaiting_payment' | 'received' | 'preparing' | 'ready' | 'on_the_way' | 'completed' | 'cancelled';

export function publicStage(status: string): PublicStage {
  switch (status) {
    case 'SCHEDULED':
      return 'scheduled';
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
/** Coordenadas aproximadas (~100 m) para no publicar la ubicación exacta. */
const approx = (n: unknown) => (typeof n === 'number' && Number.isFinite(n) ? Math.round(n * 1000) / 1000 : null);

export function toPublicOrderView(order: OrderView) {
  const firstName = order.customerName?.trim().split(/\s+/)[0] ?? null;
  const stage = publicStage(order.status);
  const d = order.delivery;
  const onTheWay = stage === 'on_the_way';
  const showDriver = !!d && (stage === 'preparing' || stage === 'ready' || onTheWay);
  const address = (order.deliveryAddress ?? null) as { lat?: unknown; lng?: unknown } | null;
  const destLat = approx(address?.lat);
  const destLng = approx(address?.lng);
  return {
    number: order.number,
    publicCode: order.publicCode,
    fulfillmentType: order.fulfillmentType,
    status: order.status,
    stage,
    customerFirstName: firstName,
    createdAt: order.createdAt,
    placedAt: order.placedAt,
    /** Pedido programado: la hora que pidió el cliente. */
    scheduledFor: order.scheduledFor,
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
    /** Repartidor: nombre y vehículo; el teléfono solo mientras va en camino. */
    driver: showDriver
      ? {
          firstName: d.driver.name.trim().split(/\s+/)[0],
          vehicle: [d.driver.vehicleType, d.driver.vehicleColor].filter(Boolean).join(' · ') || null,
          phone: onTheWay ? d.driver.phone : null,
        }
      : null,
    driverLocation:
      onTheWay && d && d.driver.lastLat !== null && d.driver.lastLng !== null
        ? { lat: d.driver.lastLat, lng: d.driver.lastLng, at: d.driver.lastSeenAt }
        : null,
    destination: destLat !== null && destLng !== null ? { lat: destLat, lng: destLng } : null,
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
