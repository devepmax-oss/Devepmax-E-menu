/** Reglas puras del reloj checador y los horarios (sin base de datos). */

export type ClockState = 'OUT' | 'IN' | 'BREAK';
export type ClockAction = 'IN' | 'BREAK_START' | 'BREAK_END' | 'OUT';

/** "Siempre se pagan" los descansos. */
export const ALL_BREAKS_PAID = 1440;
/** Una jornada abierta más de esto probablemente olvidó marcar la salida. */
export const MISSING_OUT_HOURS = 16;

const MINUTE = 60_000;

/** Qué botón se puede usar en cada estado. */
export function allowedActions(state: ClockState): ClockAction[] {
  switch (state) {
    case 'OUT':
      return ['IN'];
    case 'IN':
      return ['BREAK_START', 'OUT'];
    case 'BREAK':
      return ['BREAK_END', 'OUT'];
  }
}

export function invalidActionMessage(state: ClockState, action: ClockAction): string {
  if (action === 'IN') return 'Ya tienes la entrada marcada';
  if (state === 'OUT') return 'Primero marca tu entrada';
  if (action === 'BREAK_START') return 'Ya estás en descanso';
  return 'No estás en descanso';
}

export interface BreakSpan {
  start: Date;
  end: Date | null;
}

/**
 * Minutos de una jornada. Un descanso que dura hasta [paidBreakMinutes] se paga (cuenta
 * como trabajado); uno más largo se descuenta completo. Lo que sigue abierto se cuenta
 * hasta [now].
 */
export function workedMinutes(
  clockIn: Date,
  clockOut: Date | null,
  breaks: BreakSpan[],
  paidBreakMinutes: number,
  now = new Date(),
) {
  const end = clockOut ?? now;
  const total = Math.max(0, (end.getTime() - clockIn.getTime()) / MINUTE);
  let breakMinutes = 0;
  let unpaidBreakMinutes = 0;
  for (const b of breaks) {
    const bEnd = b.end ?? (clockOut && clockOut < now ? clockOut : now);
    const minutes = Math.max(0, (bEnd.getTime() - b.start.getTime()) / MINUTE);
    breakMinutes += minutes;
    const paid = paidBreakMinutes >= ALL_BREAKS_PAID || minutes <= paidBreakMinutes;
    if (!paid) unpaidBreakMinutes += minutes;
  }
  return {
    totalMinutes: Math.round(total),
    breakMinutes: Math.round(breakMinutes),
    unpaidBreakMinutes: Math.round(unpaidBreakMinutes),
    workedMinutes: Math.max(0, Math.round(total - unpaidBreakMinutes)),
  };
}

/** Minutos tarde contra el turno, después de la tolerancia. 0 si llegó a tiempo. */
export function lateMinutes(clockIn: Date, shiftStart: Date, graceMinutes: number): number {
  const late = Math.floor((clockIn.getTime() - shiftStart.getTime()) / MINUTE);
  return late > graceMinutes ? late : 0;
}

/** Revisa que una jornada corregida tenga sentido (salida después de la entrada, descansos dentro). */
export function validateEntry(clockIn: Date, clockOut: Date | null, breaks: BreakSpan[], now = new Date()): string | null {
  if (clockIn.getTime() > now.getTime() + MINUTE) return 'La entrada no puede ser en el futuro';
  if (clockOut && clockOut.getTime() <= clockIn.getTime()) return 'La salida debe ser después de la entrada';
  if (clockOut && clockOut.getTime() - clockIn.getTime() > 24 * 60 * MINUTE) return 'Una jornada no puede pasar de 24 horas';
  if (clockOut && clockOut.getTime() > now.getTime() + MINUTE) return 'La salida no puede ser en el futuro';
  const sorted = [...breaks].sort((a, b) => a.start.getTime() - b.start.getTime());
  let last = clockIn.getTime();
  for (const [i, b] of sorted.entries()) {
    if (b.start.getTime() < last) return 'Los descansos deben quedar dentro de la jornada y sin encimarse';
    if (!b.end && (i < sorted.length - 1 || clockOut)) return 'Solo el último descanso puede seguir abierto, y solo si no hay salida';
    if (b.end && b.end.getTime() <= b.start.getTime()) return 'Un descanso debe terminar después de empezar';
    last = (b.end ?? b.start).getTime();
  }
  if (clockOut && last > clockOut.getTime()) return 'Los descansos deben quedar dentro de la jornada';
  return null;
}

// ───────── Fechas en la zona del restaurante ─────────

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

export const isDay = (value: string) => DAY.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
export const isTime = (value: string) => TIME.test(value);

/** Diferencia (ms) entre la hora local de [timezone] y UTC en ese instante. */
function offsetMs(at: Date, timezone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(at);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUtc - Math.floor(at.getTime() / 1000) * 1000;
}

/** "2026-11-27" + "17:30" en la zona del restaurante → instante UTC (respeta el horario de verano). */
export function zonedToUtc(day: string, time: string, timezone: string): Date {
  const [y, m, d] = day.split('-').map(Number);
  const [hh, mm] = time.split(':').map(Number);
  const wall = Date.UTC(y, m - 1, d, hh, mm);
  let guess = wall - offsetMs(new Date(wall), timezone);
  guess = wall - offsetMs(new Date(guess), timezone);
  return new Date(guess);
}

/** Día local (AAAA-MM-DD) de un instante. */
export function localDay(at: Date, timezone: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(at);
}

/** Hora local (HH:mm) de un instante. */
export function localTime(at: Date, timezone: string): string {
  return new Intl.DateTimeFormat('en-GB', { timeZone: timezone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(at);
}

/** Suma días a un AAAA-MM-DD. */
export function addDays(day: string, days: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** Lunes de la semana de [day]. */
export function weekStart(day: string): string {
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay(); // 0 = domingo
  return addDays(day, -((weekday + 6) % 7));
}

/**
 * Inicio y fin de un turno a partir del día y las horas locales. Si termina a la misma hora
 * o antes de empezar, termina al día siguiente (turno de noche).
 */
export function shiftSpan(day: string, start: string, end: string, timezone: string) {
  const startAt = zonedToUtc(day, start, timezone);
  const endDay = end <= start ? addDays(day, 1) : day;
  return { start: startAt, end: zonedToUtc(endDay, end, timezone) };
}
