/** Horas en que se puede programar un pedido web (reglas puras, sin base de datos). */
import { addDays, localDay, zonedToUtc } from '../timeclock/timeclock.rules';
import type { OpeningWindow } from './opening-hours';

/** Se puede programar desde hoy hasta 6 días después (7 días en total). */
export const SCHEDULE_DAYS = 7;
/** Una hora cada 15 minutos. */
export const SLOT_MINUTES = 15;

export interface SlotDay {
  /** Día local AAAA-MM-DD. */
  day: string;
  /** Hora local "HH:MM" y el instante exacto (ISO) que la web manda de vuelta. */
  times: { time: string; at: string }[];
}

const toMinutes = (time: string) => {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
};
const hhmm = (minute: number) => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;

/**
 * Horas disponibles para programar. Cada turno del horario da horas desde que abre más el
 * tiempo de preparación (o de entrega) hasta antes de cerrar; un turno que cruza la medianoche
 * sigue en el día siguiente. Nunca antes de [now] + [leadMinutes]. Sin horario configurado,
 * el restaurante se considera abierto todo el día.
 */
export function scheduleSlots(
  hours: OpeningWindow[],
  timezone: string,
  now: Date,
  leadMinutes: number,
  days = SCHEDULE_DAYS,
  step = SLOT_MINUTES,
): SlotDay[] {
  const today = localDay(now, timezone);
  const lastDay = addDays(today, days - 1);
  const earliest = now.getTime() + leadMinutes * 60_000;
  const windows = hours.length ? hours : [0, 1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, opensAt: '00:00', closesAt: '00:00' }));
  const byDay = new Map<string, Map<string, string>>();

  // Desde ayer: un turno de anoche que cruza la medianoche puede dar horas hoy.
  for (let offset = -1; offset < days; offset++) {
    const date = addDays(today, offset);
    const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
    for (const w of windows.filter((x) => x.dayOfWeek === weekday)) {
      const open = toMinutes(w.opensAt);
      let close = toMinutes(w.closesAt);
      if (close <= open) close += 24 * 60;
      const first = Math.ceil((open + leadMinutes) / step) * step;
      for (let m = first; m < close; m += step) {
        const day = addDays(date, Math.floor(m / (24 * 60)));
        if (day < today || day > lastDay) continue;
        const time = hhmm(m % (24 * 60));
        const at = zonedToUtc(day, time, timezone);
        if (at.getTime() < earliest) continue;
        const list = byDay.get(day) ?? new Map<string, string>();
        list.set(time, at.toISOString());
        byDay.set(day, list);
      }
    }
  }
  return [...byDay.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([day, times]) => ({
      day,
      times: [...times.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([time, at]) => ({ time, at })),
    }));
}

/** ¿Es una de las horas que se ofrecen? (la web manda el instante que recibió). */
export function isOfferedSlot(slots: SlotDay[], at: Date): boolean {
  const iso = at.toISOString();
  return slots.some((d) => d.times.some((t) => t.at === iso));
}
