import type { OpeningWindow } from './types';

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const DAY_NAMES = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];

const toMinutes = (t: string) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};

function localNow(timezone: string, now: Date) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '0';
  return { day: WEEKDAYS[get('weekday')] ?? 0, minute: Number(get('hour')) * 60 + Number(get('minute')) };
}

/** "10:30" → "10:30 a. m." */
export function prettyTime(hhmm: string) {
  const [h, m] = hhmm.split(':').map(Number);
  const suffix = h < 12 ? 'a. m.' : 'p. m.';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${suffix}`;
}

/** Texto corto de horario: "Abierto · cierra 10 p. m." o "Cerrado · abre mañana 11 a. m." */
export function hoursLabel(hours: OpeningWindow[], timezone: string, isOpenNow: boolean, now = new Date()): string {
  if (!hours.length) return isOpenNow ? 'Abierto' : 'Cerrado';
  const { day, minute } = localNow(timezone, now);
  if (isOpenNow) {
    const current = hours.find((w) => {
      const o = toMinutes(w.opensAt);
      const c = toMinutes(w.closesAt);
      if (c > o) return w.dayOfWeek === day && minute >= o && minute < c;
      return (w.dayOfWeek === day && minute >= o) || ((w.dayOfWeek + 1) % 7 === day && minute < c);
    });
    return current ? `Abierto · cierra ${prettyTime(current.closesAt)}` : 'Abierto';
  }
  for (let offset = 0; offset < 7; offset++) {
    const d = (day + offset) % 7;
    const next = hours
      .filter((w) => w.dayOfWeek === d && (offset > 0 || toMinutes(w.opensAt) > minute))
      .sort((a, b) => toMinutes(a.opensAt) - toMinutes(b.opensAt))[0];
    if (next) {
      const when = offset === 0 ? 'hoy' : offset === 1 ? 'mañana' : `el ${DAY_NAMES[d]}`;
      return `Cerrado · abre ${when} ${prettyTime(next.opensAt)}`;
    }
  }
  return 'Cerrado';
}

/** Horario de la semana agrupado por día, para el pie de página. */
export function weekSchedule(hours: OpeningWindow[]) {
  return DAY_NAMES.map((name, d) => ({
    name,
    windows: hours.filter((w) => w.dayOfWeek === d).map((w) => `${prettyTime(w.opensAt)} – ${prettyTime(w.closesAt)}`),
  }));
}
