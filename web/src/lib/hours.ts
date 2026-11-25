import { pick, type Lang } from './i18n';
import type { OpeningWindow } from './types';

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const DAY_NAMES = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const DAY_NAMES_EN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const toMinutes = (t: string) => {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
};

function localNow(timezone: string, now: Date) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '0';
  return { day: WEEKDAYS[get('weekday')] ?? 0, minute: Number(get('hour')) * 60 + Number(get('minute')) };
}

/** "10:30" → "10:30 a. m." (o "10:30 AM" en inglés) */
export function prettyTime(hhmm: string, lang: Lang = 'es') {
  const [h, m] = hhmm.split(':').map(Number);
  const suffix = lang === 'en' ? (h < 12 ? 'AM' : 'PM') : h < 12 ? 'a. m.' : 'p. m.';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${suffix}`;
}

/** Texto corto de horario: "Abierto · cierra 10 p. m." o "Cerrado · abre mañana 11 a. m." */
export function hoursLabel(hours: OpeningWindow[], timezone: string, isOpenNow: boolean, now = new Date(), lang: Lang = 'es'): string {
  const open = pick(lang, 'Abierto', 'Open');
  const closed = pick(lang, 'Cerrado', 'Closed');
  if (!hours.length) return isOpenNow ? open : closed;
  const { day, minute } = localNow(timezone, now);
  if (isOpenNow) {
    const current = hours.find((w) => {
      const o = toMinutes(w.opensAt);
      const c = toMinutes(w.closesAt);
      if (c > o) return w.dayOfWeek === day && minute >= o && minute < c;
      return (w.dayOfWeek === day && minute >= o) || ((w.dayOfWeek + 1) % 7 === day && minute < c);
    });
    return current ? pick(lang, `Abierto · cierra ${prettyTime(current.closesAt, lang)}`, `Open · closes ${prettyTime(current.closesAt, lang)}`) : open;
  }
  for (let offset = 0; offset < 7; offset++) {
    const d = (day + offset) % 7;
    const next = hours
      .filter((w) => w.dayOfWeek === d && (offset > 0 || toMinutes(w.opensAt) > minute))
      .sort((a, b) => toMinutes(a.opensAt) - toMinutes(b.opensAt))[0];
    if (next) {
      const when =
        offset === 0 ? pick(lang, 'hoy', 'today') : offset === 1 ? pick(lang, 'mañana', 'tomorrow') : pick(lang, `el ${DAY_NAMES[d]}`, `on ${DAY_NAMES_EN[d]}`);
      return pick(lang, `Cerrado · abre ${when} ${prettyTime(next.opensAt, lang)}`, `Closed · opens ${when} ${prettyTime(next.opensAt, lang)}`);
    }
  }
  return closed;
}

/** Horario de la semana agrupado por día, para el pie de página. */
export function weekSchedule(hours: OpeningWindow[], lang: Lang = 'es') {
  return (lang === 'en' ? DAY_NAMES_EN : DAY_NAMES).map((name, d) => ({
    name,
    windows: hours.filter((w) => w.dayOfWeek === d).map((w) => `${prettyTime(w.opensAt, lang)} – ${prettyTime(w.closesAt, lang)}`),
  }));
}
