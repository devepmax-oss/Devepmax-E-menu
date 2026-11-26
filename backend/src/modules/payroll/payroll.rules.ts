/** Reglas puras de la nómina: horas normales, extra y dobles; pago y a quién va cada propina. */

export interface OvertimeRule {
  /** Pasando estas horas en la semana, lo normal se paga como extra (0 = no aplica). */
  weeklyHours: number;
  /** Pasando estas horas en un día, se paga como extra (0 = no aplica). */
  dailyHours: number;
  /** Pasando estas horas en un día, se paga doble (0 = no aplica). */
  doubleDailyHours: number;
  overtimeMultiplier: number;
  doubleMultiplier: number;
}

export interface DaySplit {
  day: string;
  regular: number;
  overtime: number;
  double: number;
}

/** Reglas listas para elegir en la app. */
export const RULE_PRESETS: Record<'federal' | 'california' | 'none', OvertimeRule> = {
  federal: { weeklyHours: 40, dailyHours: 0, doubleDailyHours: 0, overtimeMultiplier: 1.5, doubleMultiplier: 2 },
  california: { weeklyHours: 40, dailyHours: 8, doubleDailyHours: 12, overtimeMultiplier: 1.5, doubleMultiplier: 2 },
  none: { weeklyHours: 0, dailyHours: 0, doubleDailyHours: 0, overtimeMultiplier: 1.5, doubleMultiplier: 2 },
};

/**
 * Reparte los minutos trabajados de UNA semana (días en orden) en normales, extra y dobles.
 * Primero por día (extra después de N h, doble después de M h); luego, lo normal que pase
 * del límite semanal se vuelve extra. Así nunca se cuenta un minuto dos veces.
 */
export function splitWeek(days: { day: string; minutes: number }[], rule: OvertimeRule): DaySplit[] {
  const sorted = [...days].sort((a, b) => a.day.localeCompare(b.day));
  let weekRegular = 0;
  return sorted.map(({ day, minutes }) => {
    let rest = Math.max(0, Math.round(minutes));
    let double = 0;
    if (rule.doubleDailyHours > 0 && rest > rule.doubleDailyHours * 60) {
      double = rest - rule.doubleDailyHours * 60;
      rest = rule.doubleDailyHours * 60;
    }
    let overtime = 0;
    if (rule.dailyHours > 0 && rest > rule.dailyHours * 60) {
      overtime = rest - rule.dailyHours * 60;
      rest = rule.dailyHours * 60;
    }
    let regular = rest;
    if (rule.weeklyHours > 0) {
      const room = Math.max(0, rule.weeklyHours * 60 - weekRegular);
      if (regular > room) {
        overtime += regular - room;
        regular = room;
      }
    }
    weekRegular += regular;
    return { day, regular, overtime, double };
  });
}

/** Pago en centavos de un día con su tarifa (dólares por hora). */
export function dayPayCents(split: DaySplit, hourlyRate: number, rule: OvertimeRule) {
  const perMinute = (hourlyRate * 100) / 60;
  const regular = split.regular * perMinute;
  const overtime = split.overtime * perMinute * rule.overtimeMultiplier;
  const double = split.double * perMinute * rule.doubleMultiplier;
  return { regular, overtime, double };
}

/** Tarifa vigente un día: la más reciente que empezó ese día o antes. */
export function rateOn<T extends { effectiveFrom: string; hourlyRate: number }>(rates: T[], day: string): number | null {
  let best: T | null = null;
  for (const r of rates) {
    if (r.effectiveFrom <= day && (!best || r.effectiveFrom > best.effectiveFrom)) best = r;
  }
  return best ? best.hourlyRate : null;
}

export interface TipSource {
  isDelivery: boolean;
  driverEmployeeId: string | null;
  waiterId: string | null;
  cashierId: string | null;
  orderCreatorId: string | null;
}

/**
 * A quién se le acredita una propina: en delivery al repartidor; si no, al mesero de la mesa;
 * si no hubo mesero, a quien cobró; y si tampoco, a quien tomó el pedido. null = sin asignar
 * (por ejemplo, un pedido web para recoger).
 */
export function tipOwner(s: TipSource): string | null {
  if (s.isDelivery && s.driverEmployeeId) return s.driverEmployeeId;
  return s.waiterId ?? s.cashierId ?? s.orderCreatorId ?? null;
}

export const isRuleValid = (r: OvertimeRule) =>
  r.weeklyHours >= 0 &&
  r.dailyHours >= 0 &&
  r.doubleDailyHours >= 0 &&
  (r.doubleDailyHours === 0 || r.dailyHours === 0 || r.doubleDailyHours > r.dailyHours) &&
  r.overtimeMultiplier >= 1 &&
  r.doubleMultiplier >= r.overtimeMultiplier;
