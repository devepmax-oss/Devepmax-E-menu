import { Prisma } from '@prisma/client';

const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);

export const UNITS = ['unit', 'g', 'kg', 'oz', 'lb', 'ml', 'l', 'fl_oz'] as const;
export type Unit = (typeof UNITS)[number];

/** Costo promedio ponderado tras una compra (si no había existencia, vale el costo nuevo). */
export function weightedCost(onHand: Prisma.Decimal.Value, oldCost: Prisma.Decimal.Value, quantity: Prisma.Decimal.Value, unitCost: Prisma.Decimal.Value) {
  const have = Prisma.Decimal.max(dec(onHand), 0);
  const total = have.plus(quantity);
  if (have.lte(0) || total.lte(0)) return dec(unitCost).toDecimalPlaces(4);
  return have.times(oldCost).plus(dec(quantity).times(unitCost)).div(total).toDecimalPlaces(4);
}

/** Costo de un plato con su receta, y su margen con el precio de venta. */
export function plateCost(price: Prisma.Decimal.Value, lines: { quantity: Prisma.Decimal.Value; costPerUnit: Prisma.Decimal.Value }[]) {
  const cost = lines.reduce((s, l) => s.plus(dec(l.quantity).times(l.costPerUnit)), dec(0)).toDecimalPlaces(2);
  const p = dec(price);
  return {
    cost,
    margin: p.minus(cost).toDecimalPlaces(2),
    /** % del precio que se va en ingredientes ("food cost"). */
    foodCostPct: p.gt(0) ? cost.div(p).times(100).toDecimalPlaces(1).toNumber() : null,
  };
}

/** ¿Alcanza la existencia para hacer al menos uno? */
export function canMake(lines: { quantity: Prisma.Decimal.Value; onHand: Prisma.Decimal.Value }[]) {
  return lines.every((l) => dec(l.onHand).gte(l.quantity));
}
