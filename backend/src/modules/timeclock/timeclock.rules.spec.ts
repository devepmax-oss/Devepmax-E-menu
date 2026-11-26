import {
  addDays,
  allowedActions,
  lateMinutes,
  localDay,
  localTime,
  shiftSpan,
  validateEntry,
  weekStart,
  workedMinutes,
  zonedToUtc,
} from './timeclock.rules';

const at = (iso: string) => new Date(iso);
const TZ = 'America/New_York';

describe('reloj checador', () => {
  it('solo permite los botones que tienen sentido', () => {
    expect(allowedActions('OUT')).toEqual(['IN']);
    expect(allowedActions('IN')).toEqual(['BREAK_START', 'OUT']);
    expect(allowedActions('BREAK')).toEqual(['BREAK_END', 'OUT']);
  });

  it('descansos sin pagar se restan', () => {
    const r = workedMinutes(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), [
      { start: at('2026-11-20T17:00:00Z'), end: at('2026-11-20T17:30:00Z') },
    ], 0);
    expect(r).toEqual({ totalMinutes: 480, breakMinutes: 30, unpaidBreakMinutes: 30, workedMinutes: 450 });
  });

  it('descansos cortos pagados no se restan; los largos sí', () => {
    const breaks = [
      { start: at('2026-11-20T16:00:00Z'), end: at('2026-11-20T16:15:00Z') },
      { start: at('2026-11-20T18:00:00Z'), end: at('2026-11-20T18:45:00Z') },
    ];
    const r = workedMinutes(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), breaks, 20);
    expect(r.unpaidBreakMinutes).toBe(45);
    expect(r.workedMinutes).toBe(435);
    expect(workedMinutes(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), breaks, 1440).workedMinutes).toBe(480);
  });

  it('una jornada abierta cuenta hasta ahora', () => {
    const r = workedMinutes(at('2026-11-20T14:00:00Z'), null, [{ start: at('2026-11-20T15:00:00Z'), end: null }], 0, at('2026-11-20T15:30:00Z'));
    expect(r).toEqual({ totalMinutes: 90, breakMinutes: 30, unpaidBreakMinutes: 30, workedMinutes: 60 });
  });

  it('llegar tarde cuenta después de la tolerancia', () => {
    expect(lateMinutes(at('2026-11-20T14:04:00Z'), at('2026-11-20T14:00:00Z'), 5)).toBe(0);
    expect(lateMinutes(at('2026-11-20T14:12:00Z'), at('2026-11-20T14:00:00Z'), 5)).toBe(12);
    expect(lateMinutes(at('2026-11-20T13:50:00Z'), at('2026-11-20T14:00:00Z'), 5)).toBe(0);
  });

  it('revisa las correcciones', () => {
    const now = at('2026-11-21T00:00:00Z');
    expect(validateEntry(at('2026-11-20T14:00:00Z'), at('2026-11-20T13:00:00Z'), [], now)).toMatch(/después/);
    expect(validateEntry(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), [{ start: at('2026-11-20T13:00:00Z'), end: at('2026-11-20T13:30:00Z') }], now)).toMatch(/dentro/);
    expect(validateEntry(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), [{ start: at('2026-11-20T16:00:00Z'), end: null }], now)).toMatch(/abierto/);
    expect(validateEntry(at('2026-11-20T14:00:00Z'), at('2026-11-20T22:00:00Z'), [{ start: at('2026-11-20T16:00:00Z'), end: at('2026-11-20T16:30:00Z') }], now)).toBeNull();
    expect(validateEntry(at('2026-11-20T14:00:00Z'), null, [{ start: at('2026-11-20T16:00:00Z'), end: null }], now)).toBeNull();
  });
});

describe('horarios en la zona del restaurante', () => {
  it('convierte la hora local a UTC con y sin horario de verano', () => {
    expect(zonedToUtc('2026-07-10', '09:00', TZ).toISOString()).toBe('2026-07-10T13:00:00.000Z');
    expect(zonedToUtc('2026-12-10', '09:00', TZ).toISOString()).toBe('2026-12-10T14:00:00.000Z');
    expect(zonedToUtc('2026-11-01', '12:00', TZ).toISOString()).toBe('2026-11-01T17:00:00.000Z');
  });

  it('día y hora locales de un instante', () => {
    expect(localDay(at('2026-11-21T03:30:00Z'), TZ)).toBe('2026-11-20');
    expect(localTime(at('2026-11-21T03:30:00Z'), TZ)).toBe('22:30');
  });

  it('semanas que empiezan en lunes', () => {
    expect(weekStart('2026-11-25')).toBe('2026-11-23');
    expect(weekStart('2026-11-29')).toBe('2026-11-23');
    expect(weekStart('2026-11-23')).toBe('2026-11-23');
    expect(addDays('2026-11-30', 2)).toBe('2026-12-02');
  });

  it('un turno de noche termina al día siguiente', () => {
    const s = shiftSpan('2026-11-20', '18:00', '02:00', TZ);
    expect(s.start.toISOString()).toBe('2026-11-20T23:00:00.000Z');
    expect(s.end.toISOString()).toBe('2026-11-21T07:00:00.000Z');
  });
});
