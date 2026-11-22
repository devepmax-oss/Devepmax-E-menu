export interface OpeningWindow {
  /** 0 = domingo … 6 = sábado */
  dayOfWeek: number;
  /** HH:MM */
  opensAt: string;
  /** HH:MM; si es menor que opensAt, cierra después de medianoche. */
  closesAt: string;
}

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

const toMinutes = (time: string) => {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
};

/** Día de la semana y minuto del día en la zona horaria del restaurante. */
export function localDayAndMinute(timezone: string, now: Date): { day: number; minute: number } {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '0';
  return { day: WEEKDAYS[get('weekday')] ?? 0, minute: Number(get('hour')) * 60 + Number(get('minute')) };
}

/**
 * ¿Está abierto ahora? Sin horario configurado se considera abierto siempre.
 * Un turno que cruza la medianoche (18:00 a 02:00) cuenta para la madrugada del día siguiente.
 */
export function isOpenAt(hours: OpeningWindow[], timezone: string, now = new Date()): boolean {
  if (hours.length === 0) return true;
  const { day, minute } = localDayAndMinute(timezone, now);
  return hours.some((w) => {
    const open = toMinutes(w.opensAt);
    const close = toMinutes(w.closesAt);
    if (close > open) return w.dayOfWeek === day && minute >= open && minute < close;
    return (w.dayOfWeek === day && minute >= open) || ((w.dayOfWeek + 1) % 7 === day && minute < close);
  });
}
