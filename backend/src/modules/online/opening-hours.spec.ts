import { isOpenAt, localDayAndMinute } from './opening-hours';

const NY = 'America/New_York';
// Domingo 22 de noviembre de 2026 (Nueva York está en UTC−5 en noviembre).
const at = (hhmm: string, day = 22) => new Date(`2026-11-${day}T${hhmm}:00-05:00`);

describe('localDayAndMinute', () => {
  it('usa la zona horaria del restaurante', () => {
    expect(localDayAndMinute(NY, at('20:30'))).toEqual({ day: 0, minute: 20 * 60 + 30 });
  });
});

describe('isOpenAt', () => {
  it('sin horario configurado, siempre abierto', () => {
    expect(isOpenAt([], NY, at('03:00'))).toBe(true);
  });

  it('abre y cierra el mismo día', () => {
    const hours = [{ dayOfWeek: 0, opensAt: '11:00', closesAt: '22:00' }];
    expect(isOpenAt(hours, NY, at('10:59'))).toBe(false);
    expect(isOpenAt(hours, NY, at('11:00'))).toBe(true);
    expect(isOpenAt(hours, NY, at('21:59'))).toBe(true);
    expect(isOpenAt(hours, NY, at('22:00'))).toBe(false);
  });

  it('un turno que cruza la medianoche sigue abierto de madrugada', () => {
    const saturdayNight = [{ dayOfWeek: 6, opensAt: '18:00', closesAt: '02:00' }];
    expect(isOpenAt(saturdayNight, NY, at('01:30'))).toBe(true); // domingo 1:30
    expect(isOpenAt(saturdayNight, NY, at('02:30'))).toBe(false);
  });

  it('un día sin turno está cerrado', () => {
    const mondayOnly = [{ dayOfWeek: 1, opensAt: '11:00', closesAt: '22:00' }];
    expect(isOpenAt(mondayOnly, NY, at('12:00'))).toBe(false);
  });
});
