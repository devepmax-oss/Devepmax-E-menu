import { Decimal } from '@prisma/client/runtime/library';

/** Mismos valores que el enum PromotionType de Prisma (el motor no depende de la base de datos). */
export type PromotionType = 'PERCENT_OFF' | 'AMOUNT_OFF' | 'BUY_X_GET_Y' | 'COMBO_PRICE';

/** Línea de una orden tal como la ve el motor de promociones. */
export interface EngineLine {
  index: number;
  productId: string;
  categoryId: string;
  /** Precio de UNA unidad con sus modificadores. */
  unitAmount: Decimal.Value;
  quantity: number;
}

export interface EnginePromotion {
  id: string;
  name: string;
  type: PromotionType;
  value: Decimal.Value | null;
  buyQuantity: number | null;
  getQuantity: number | null;
  comboPrice: Decimal.Value | null;
  priority: number;
  targets: { productId: string | null; categoryId: string | null }[];
  slots: { quantity: number; productIds: string[]; categoryIds: string[] }[];
}

export interface Allocation {
  promotionId: string;
  name: string;
  amount: Decimal;
  /** Descuento por línea (índice de la línea → monto). */
  perLine: Map<number, Decimal>;
}

interface Unit {
  line: number;
  productId: string;
  categoryId: string;
  price: Decimal;
  used: boolean;
}

interface Evaluation {
  savings: Decimal;
  shares: { unit: Unit; amount: Decimal }[];
}

const ZERO = new Decimal(0);
const MIN_SAVING = new Decimal('0.005');

function matchesTargets(unit: Unit, targets: EnginePromotion['targets']): boolean {
  return targets.some((t) => t.productId === unit.productId || t.categoryId === unit.categoryId);
}

function matchesSlot(unit: Unit, slot: EnginePromotion['slots'][number]): boolean {
  return slot.productIds.includes(unit.productId) || slot.categoryIds.includes(unit.categoryId);
}

function byPriceDesc(a: Unit, b: Unit): number {
  return b.price.comparedTo(a.price);
}

function sum(values: Decimal[]): Decimal {
  return values.reduce((acc, v) => acc.plus(v), ZERO);
}

function evaluate(promotion: EnginePromotion, free: Unit[]): Evaluation | null {
  const value = new Decimal(promotion.value ?? 0);
  switch (promotion.type) {
    case 'PERCENT_OFF': {
      const shares = free
        .filter((u) => matchesTargets(u, promotion.targets))
        .map((unit) => ({ unit, amount: unit.price.times(value).div(100) }));
      return { savings: sum(shares.map((s) => s.amount)), shares };
    }
    case 'AMOUNT_OFF': {
      const shares = free
        .filter((u) => matchesTargets(u, promotion.targets))
        .map((unit) => ({ unit, amount: Decimal.min(value, unit.price) }));
      return { savings: sum(shares.map((s) => s.amount)), shares };
    }
    case 'BUY_X_GET_Y': {
      const buy = promotion.buyQuantity ?? 0;
      const get = promotion.getQuantity ?? 0;
      if (buy < 1 || get < 1) return null;
      // De mayor a menor precio: en cada grupo de X+Y, los Y más baratos salen gratis.
      const eligible = free.filter((u) => matchesTargets(u, promotion.targets)).sort(byPriceDesc);
      const size = buy + get;
      const shares: Evaluation['shares'] = [];
      for (let start = 0; start + size <= eligible.length; start += size) {
        const group = eligible.slice(start, start + size);
        group.forEach((unit, i) => shares.push({ unit, amount: i >= buy ? unit.price : ZERO }));
      }
      return { savings: sum(shares.map((s) => s.amount)), shares };
    }
    case 'COMBO_PRICE': {
      if (promotion.comboPrice === null || promotion.slots.length === 0) return null;
      const comboPrice = new Decimal(promotion.comboPrice);
      const taken = new Set<Unit>();
      const shares: Evaluation['shares'] = [];
      for (;;) {
        const combo: Unit[] = [];
        for (const slot of promotion.slots) {
          const candidates = free.filter((u) => !taken.has(u) && !combo.includes(u) && matchesSlot(u, slot)).sort(byPriceDesc);
          if (candidates.length < slot.quantity) break;
          combo.push(...candidates.slice(0, slot.quantity));
        }
        const complete = combo.length === promotion.slots.reduce((n, s) => n + s.quantity, 0);
        if (!complete) break;
        const regular = sum(combo.map((u) => u.price));
        const saving = regular.minus(comboPrice);
        if (saving.lte(0)) break;
        // El ahorro se reparte en proporción al precio de cada producto del combo.
        for (const unit of combo) {
          taken.add(unit);
          shares.push({ unit, amount: saving.times(unit.price).div(regular) });
        }
      }
      return { savings: sum(shares.map((s) => s.amount)), shares };
    }
    default:
      return null;
  }
}

/** Reparte un monto ya redondeado entre líneas, ajustando los centavos en la línea mayor. */
function allocatePerLine(shares: Evaluation['shares'], amount: Decimal): Map<number, Decimal> {
  const raw = new Map<number, Decimal>();
  for (const { unit, amount: share } of shares) raw.set(unit.line, (raw.get(unit.line) ?? ZERO).plus(share));
  const perLine = new Map<number, Decimal>();
  for (const [line, value] of raw) {
    const rounded = value.toDecimalPlaces(2, Decimal.ROUND_HALF_UP);
    if (rounded.gt(0)) perLine.set(line, rounded);
  }
  const diff = amount.minus(sum([...perLine.values()]));
  if (!diff.isZero() && perLine.size > 0) {
    const [largest] = [...perLine.entries()].sort((a, b) => b[1].comparedTo(a[1]));
    perLine.set(largest[0], largest[1].plus(diff));
  }
  return perLine;
}

/**
 * Aplica las promociones a una orden buscando el mayor ahorro para el cliente:
 * en cada paso elige la promoción que más ahorra con las unidades libres y la aplica.
 * Cada unidad recibe como máximo una promoción.
 */
export function applyPromotions(lines: EngineLine[], promotions: EnginePromotion[]): Allocation[] {
  const units: Unit[] = lines.flatMap((line) =>
    Array.from({ length: line.quantity }, () => ({
      line: line.index,
      productId: line.productId,
      categoryId: line.categoryId,
      price: new Decimal(line.unitAmount),
      used: false,
    })),
  );

  const pending = [...promotions];
  const result: Allocation[] = [];
  for (;;) {
    const free = units.filter((u) => !u.used);
    let best: { promotion: EnginePromotion; evaluation: Evaluation } | null = null;
    for (const promotion of pending) {
      const evaluation = evaluate(promotion, free);
      if (!evaluation || evaluation.savings.lt(MIN_SAVING)) continue;
      const better =
        !best ||
        evaluation.savings.gt(best.evaluation.savings) ||
        (evaluation.savings.eq(best.evaluation.savings) && promotion.priority > best.promotion.priority);
      if (better) best = { promotion, evaluation };
    }
    if (!best) break;

    const amount = best.evaluation.savings.toDecimalPlaces(2, Decimal.ROUND_HALF_UP);
    for (const { unit } of best.evaluation.shares) unit.used = true;
    result.push({
      promotionId: best.promotion.id,
      name: best.promotion.name,
      amount,
      perLine: allocatePerLine(best.evaluation.shares, amount),
    });
    pending.splice(pending.indexOf(best.promotion), 1);
  }
  return result;
}
