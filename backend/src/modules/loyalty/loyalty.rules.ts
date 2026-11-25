import { Prisma } from '@prisma/client';

const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);

/**
 * Puntos que corresponden a una cuenta: por cada dólar de lo consumido (sin impuesto, envío ni
 * propina, después de descuentos y cupones) menos lo reembolsado. Solo cuentas pagadas.
 */
export function pointsForBill(
  bill: { status: string; subtotal: Prisma.Decimal.Value; discountTotal: Prisma.Decimal.Value; refunded: Prisma.Decimal.Value },
  pointsPerDollar: number,
): number {
  if (bill.status !== 'PAID' && bill.status !== 'REFUNDED') return 0;
  const eligible = Prisma.Decimal.max(dec(bill.subtotal).minus(bill.discountTotal).minus(bill.refunded), 0);
  return Math.max(0, Math.floor(eligible.times(pointsPerDollar).toNumber() + 1e-9));
}

/** Cuántos premios se pueden entregar con un saldo (y cuántos puntos cuestan). */
export function rewardsFor(balance: number, rewardPoints: number) {
  if (rewardPoints <= 0 || balance < rewardPoints) return { rewards: 0, cost: 0 };
  const rewards = Math.min(10, Math.floor(balance / rewardPoints)); // tope por si alguien ajusta mal los puntos
  return { rewards, cost: rewards * rewardPoints };
}

/** El mes de hoy en la zona del restaurante (1-12) y el año. */
export function monthIn(timezone: string, now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, year: 'numeric', month: 'numeric' }).formatToParts(now);
  return { year: Number(parts.find((p) => p.type === 'year')!.value), month: Number(parts.find((p) => p.type === 'month')!.value) };
}

/** Fin del mes (medianoche del primer día del mes siguiente, hora del restaurante) + 7 días de gracia. */
export function birthdayCouponEnd(year: number, month: number) {
  return new Date(Date.UTC(year, month, 1, 12) + 7 * 86_400_000);
}
