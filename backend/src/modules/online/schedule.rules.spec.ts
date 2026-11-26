import { isOfferedSlot, scheduleSlots } from './schedule.rules';

const TZ = 'America/New_York';
// Martes 24 nov 2026, 3:00 p. m. en Nueva York (20:00 UTC).
const now = new Date('2026-11-24T20:00:00Z');
const everyDay = (opensAt: string, closesAt: string) => [0, 1, 2, 3, 4, 5, 6].map((dayOfWeek) => ({ dayOfWeek, opensAt, closesAt }));

describe('horas para programar', () => {
  it('7 días, cada 15 min, desde que abre más la preparación hasta antes de cerrar', () => {
    const slots = scheduleSlots(everyDay('11:00', '22:00'), TZ, now, 20);
    expect(slots).toHaveLength(7);
    expect(slots[0].day).toBe('2026-11-24');
    expect(slots[6].day).toBe('2026-11-30');
    const tomorrow = slots[1].times.map((t) => t.time);
    expect(tomorrow[0]).toBe('11:30'); // 11:00 + 20 min → la siguiente de 15 en 15
    expect(tomorrow[tomorrow.length - 1]).toBe('21:45');
  });

  it('hoy no ofrece horas que ya no alcanzan', () => {
    const today = scheduleSlots(everyDay('11:00', '22:00'), TZ, now, 20)[0].times;
    expect(today[0].time).toBe('15:30'); // ahora 3:00 p. m. + 20 min
    expect(today[0].at).toBe('2026-11-24T20:30:00.000Z');
  });

  it('con el restaurante cerrado hoy ofrece desde que abra', () => {
    const closedDay = [{ dayOfWeek: 3, opensAt: '17:00', closesAt: '21:00' }]; // solo miércoles
    const slots = scheduleSlots(closedDay, TZ, now, 30);
    expect(slots.map((s) => s.day)).toEqual(['2026-11-25']);
    expect(slots[0].times[0].time).toBe('17:30');
  });

  it('un turno que cruza la medianoche sigue en el día siguiente', () => {
    const late = [{ dayOfWeek: 5, opensAt: '18:00', closesAt: '02:00' }]; // viernes
    const slots = scheduleSlots(late, TZ, now, 15);
    expect(slots.map((s) => s.day)).toEqual(['2026-11-27', '2026-11-28']);
    expect(slots[1].times.at(-1)?.time).toBe('01:45');
  });

  it('solo acepta horas que se ofrecieron', () => {
    const slots = scheduleSlots(everyDay('11:00', '22:00'), TZ, now, 20);
    expect(isOfferedSlot(slots, new Date(slots[2].times[3].at))).toBe(true);
    expect(isOfferedSlot(slots, new Date('2026-11-26T03:10:00Z'))).toBe(false);
    expect(isOfferedSlot(slots, new Date('2026-12-15T17:00:00Z'))).toBe(false);
  });
});
