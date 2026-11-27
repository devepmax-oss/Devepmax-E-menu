/** Reglas de los tiempos de cocina: estadísticas de minutos y cuándo un ticket va tarde. */

export interface TimeStats {
  count: number;
  /** Minutos con un decimal. */
  average: number | null;
  median: number | null;
  /** 9 de cada 10 tickets salen en este tiempo o menos. */
  p90: number | null;
  max: number | null;
}

const one = (v: number) => Math.round(v * 10) / 10;

/** Promedio, mediana, percentil 90 (rango más cercano) y máximo de una lista de minutos. */
export function stats(values: number[]): TimeStats {
  const v = values.filter((x) => Number.isFinite(x) && x >= 0).sort((a, b) => a - b);
  if (!v.length) return { count: 0, average: null, median: null, p90: null, max: null };
  const at = (p: number) => v[Math.min(v.length - 1, Math.max(0, Math.ceil(p * v.length) - 1))];
  const mid = v.length % 2 ? v[(v.length - 1) / 2] : (v[v.length / 2 - 1] + v[v.length / 2]) / 2;
  return {
    count: v.length,
    average: one(v.reduce((a, x) => a + x, 0) / v.length),
    median: one(mid),
    p90: one(at(0.9)),
    max: one(v[v.length - 1]),
  };
}

export const minutesBetween = (from: Date, to: Date) => (to.getTime() - from.getTime()) / 60_000;

/** Tiempos de un ticket: espera (hasta que empiezan), preparación y total (hasta Listo). */
export function ticketTimes(t: { createdAt: Date; startedAt: Date | null; readyAt: Date | null }) {
  if (!t.readyAt) return null;
  const total = minutesBetween(t.createdAt, t.readyAt);
  if (total < 0) return null;
  const started = t.startedAt && t.startedAt >= t.createdAt && t.startedAt <= t.readyAt ? t.startedAt : null;
  return {
    total,
    wait: started ? minutesBetween(t.createdAt, started) : null,
    prep: started ? minutesBetween(started, t.readyAt) : null,
  };
}

/** Un ticket va tarde si tardó más que la meta (el tiempo de preparación del restaurante). */
export const isLate = (totalMinutes: number, targetMinutes: number) => totalMinutes > targetMinutes;

export function latePercent(totals: number[], target: number) {
  if (!totals.length) return null;
  return one((totals.filter((x) => isLate(x, target)).length / totals.length) * 100);
}
