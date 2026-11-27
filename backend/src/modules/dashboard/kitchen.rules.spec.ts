import { isLate, latePercent, stats, ticketTimes } from './kitchen.rules';

const at = (min: number) => new Date(Date.UTC(2026, 10, 27, 18, 0) + min * 60_000);

describe('tiempos de cocina', () => {
  it('promedio, mediana, p90 y máximo', () => {
    const s = stats([10, 12, 8, 30, 15, 9, 11, 14, 13, 18]);
    expect(s.count).toBe(10);
    expect(s.average).toBe(14);
    expect(s.median).toBe(12.5);
    expect(s.p90).toBe(18);
    expect(s.max).toBe(30);
  });

  it('una sola medida y lista vacía', () => {
    expect(stats([7])).toEqual({ count: 1, average: 7, median: 7, p90: 7, max: 7 });
    expect(stats([])).toEqual({ count: 0, average: null, median: null, p90: null, max: null });
  });

  it('ignora valores inválidos', () => {
    expect(stats([5, -1, Number.NaN, 15]).count).toBe(2);
  });

  it('separa espera y preparación', () => {
    expect(ticketTimes({ createdAt: at(0), startedAt: at(4), readyAt: at(16) })).toEqual({ total: 16, wait: 4, prep: 12 });
  });

  it('si lo marcaron Listo sin empezar, solo hay total', () => {
    expect(ticketTimes({ createdAt: at(0), startedAt: null, readyAt: at(9) })).toEqual({ total: 9, wait: null, prep: null });
  });

  it('sin Listo no hay tiempos; un inicio fuera de orden no cuenta', () => {
    expect(ticketTimes({ createdAt: at(0), startedAt: at(2), readyAt: null })).toBeNull();
    expect(ticketTimes({ createdAt: at(5), startedAt: at(1), readyAt: at(10) })).toEqual({ total: 5, wait: null, prep: null });
  });

  it('tarde es más que la meta', () => {
    expect(isLate(20, 20)).toBe(false);
    expect(isLate(20.5, 20)).toBe(true);
    expect(latePercent([10, 25, 30, 15], 20)).toBe(50);
    expect(latePercent([], 20)).toBeNull();
  });
});
