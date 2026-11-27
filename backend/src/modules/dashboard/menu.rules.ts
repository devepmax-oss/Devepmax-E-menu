/**
 * Ingeniería de menú (método Kasavana–Smith): cada plato se compara contra la popularidad
 * esperada y contra el margen promedio del menú.
 *
 * - Estrella: se vende mucho y deja buen margen → cuidarlo, que se vea.
 * - Caballo de batalla: se vende mucho, deja poco → revisar precio o receta.
 * - Enigma: deja buen margen, se vende poco → promoverlo, mejor foto o lugar.
 * - Perro: poco de las dos → cambiarlo o quitarlo.
 *
 * Popularidad: un plato es popular si vende al menos el 70 % de lo que le tocaría si todos
 * vendieran igual (0.7 × total / número de platos). Margen: contra el margen por unidad
 * promedio ponderado (margen total / unidades). Solo entran los platos con costo conocido.
 */
export type MenuClass = 'star' | 'plowhorse' | 'puzzle' | 'dog';

export interface DishInput {
  id: string;
  quantity: number;
  /** Ventas netas del plato (después de sus promociones). */
  net: number;
  /** Costo de lo vendido; null = sin receta. */
  cost: number | null;
  /** Para platos sin venta: margen por unidad a precio de lista (precio − costo de receta). */
  listUnitMargin?: number | null;
}

export const POPULARITY_FACTOR = 0.7;
export const MAX_PERIOD_DAYS = 400;

export function unitMargin(d: DishInput): number | null {
  if (d.cost === null) return null;
  if (d.quantity > 0) return (d.net - d.cost) / d.quantity;
  return d.listUnitMargin ?? null;
}

export function classify(dishes: DishInput[]) {
  const known = dishes.filter((d) => unitMargin(d) !== null);
  const totalQty = known.reduce((a, d) => a + d.quantity, 0);
  const totalMargin = known.reduce((a, d) => a + (d.quantity > 0 ? d.net - (d.cost ?? 0) : 0), 0);
  const popularityLine = known.length ? (POPULARITY_FACTOR * totalQty) / known.length : 0;
  const marginLine = totalQty > 0 ? totalMargin / totalQty : 0;
  const classes = new Map<string, MenuClass | null>();
  for (const d of dishes) {
    const m = unitMargin(d);
    if (m === null || totalQty === 0) {
      classes.set(d.id, null);
      continue;
    }
    const popular = d.quantity > 0 && d.quantity >= popularityLine;
    const profitable = m >= marginLine;
    classes.set(d.id, popular ? (profitable ? 'star' : 'plowhorse') : profitable ? 'puzzle' : 'dog');
  }
  return { popularityLine: round(popularityLine, 1), marginLine: round(marginLine, 2), classes };
}

/** Período AAAA-MM-DD (ambos incluidos), hasta 400 días. Lanza Error con un mensaje para el usuario. */
export function parsePeriod(from: string | undefined, to: string | undefined, today: string) {
  const f = from ?? to ?? today;
  const t = to ?? from ?? today;
  for (const d of [f, t]) {
    const date = new Date(`${d}T00:00:00Z`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d) || Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== d) {
      throw new Error('Fecha inválida (usa AAAA-MM-DD)');
    }
  }
  const fd = new Date(`${f}T00:00:00Z`);
  const td = new Date(`${t}T00:00:00Z`);
  if (td < fd) throw new Error('La fecha final es anterior a la inicial');
  const days = Math.round((td.getTime() - fd.getTime()) / 86_400_000) + 1;
  if (days > MAX_PERIOD_DAYS) throw new Error(`El período puede tener hasta ${MAX_PERIOD_DAYS} días`);
  return { from: fd, to: td, days };
}

export function round(v: number, digits = 2) {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
}

export const percent = (part: number, whole: number) => (whole > 0 ? round((part / whole) * 100, 1) : null);
