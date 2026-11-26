import { RULE_PRESETS, dayPayCents, isRuleValid, rateOn, splitWeek, tipOwner } from './payroll.rules';

const H = 60;
const week = (hours: number[]) => hours.map((h, i) => ({ day: `2026-11-${String(23 + i).padStart(2, '0')}`, minutes: h * H }));
const totals = (s: ReturnType<typeof splitWeek>) =>
  s.reduce((t, d) => ({ regular: t.regular + d.regular, overtime: t.overtime + d.overtime, double: t.double + d.double }), {
    regular: 0,
    overtime: 0,
    double: 0,
  });

describe('horas extra', () => {
  it('federal: lo que pasa de 40 h en la semana es extra', () => {
    expect(totals(splitWeek(week([9, 9, 9, 9, 9]), RULE_PRESETS.federal))).toEqual({ regular: 40 * H, overtime: 5 * H, double: 0 });
    expect(totals(splitWeek(week([8, 8, 8, 8]), RULE_PRESETS.federal))).toEqual({ regular: 32 * H, overtime: 0, double: 0 });
  });

  it('federal: las horas extra caen en los últimos días de la semana', () => {
    const s = splitWeek(week([10, 10, 10, 10, 5]), RULE_PRESETS.federal);
    expect(s[3]).toMatchObject({ regular: 10 * H, overtime: 0 });
    expect(s[4]).toMatchObject({ regular: 0, overtime: 5 * H });
  });

  it('california: extra después de 8 h al día y doble después de 12 h', () => {
    const s = splitWeek(week([13]), RULE_PRESETS.california);
    expect(s[0]).toEqual({ day: '2026-11-23', regular: 8 * H, overtime: 4 * H, double: 1 * H });
  });

  it('california: no cuenta dos veces lo diario y lo semanal', () => {
    // 5 días de 9 h: 1 h extra diaria cada día (5 h); normales 40 h → nada más por la semana.
    expect(totals(splitWeek(week([9, 9, 9, 9, 9]), RULE_PRESETS.california))).toEqual({ regular: 40 * H, overtime: 5 * H, double: 0 });
    // 6 días de 8 h: 48 h normales por día → 8 h pasan a extra por la semana.
    expect(totals(splitWeek(week([8, 8, 8, 8, 8, 8]), RULE_PRESETS.california))).toEqual({ regular: 40 * H, overtime: 8 * H, double: 0 });
  });

  it('sin horas extra todo es normal', () => {
    expect(totals(splitWeek(week([12, 12, 12, 12]), RULE_PRESETS.none))).toEqual({ regular: 48 * H, overtime: 0, double: 0 });
  });

  it('valida reglas raras', () => {
    expect(isRuleValid(RULE_PRESETS.california)).toBe(true);
    expect(isRuleValid({ ...RULE_PRESETS.california, doubleDailyHours: 6 })).toBe(false);
    expect(isRuleValid({ ...RULE_PRESETS.federal, overtimeMultiplier: 0.5 })).toBe(false);
  });
});

describe('pago', () => {
  it('normal, extra a 1.5x y doble a 2x', () => {
    const p = dayPayCents({ day: 'x', regular: 8 * H, overtime: 2 * H, double: 1 * H }, 15, RULE_PRESETS.california);
    expect(Math.round(p.regular)).toBe(12000);
    expect(Math.round(p.overtime)).toBe(4500);
    expect(Math.round(p.double)).toBe(3000);
  });

  it('usa la tarifa vigente de cada día', () => {
    const rates = [
      { effectiveFrom: '2026-01-01', hourlyRate: 12 },
      { effectiveFrom: '2026-11-25', hourlyRate: 14 },
    ];
    expect(rateOn(rates, '2026-11-24')).toBe(12);
    expect(rateOn(rates, '2026-11-25')).toBe(14);
    expect(rateOn(rates, '2025-12-31')).toBeNull();
  });
});

describe('propinas', () => {
  const base = { isDelivery: false, driverEmployeeId: null, waiterId: null, cashierId: null, orderCreatorId: null };
  it('delivery al repartidor, mesa al mesero, si no a quien cobró', () => {
    expect(tipOwner({ ...base, isDelivery: true, driverEmployeeId: 'd', waiterId: 'w', cashierId: 'c' })).toBe('d');
    expect(tipOwner({ ...base, waiterId: 'w', cashierId: 'c' })).toBe('w');
    expect(tipOwner({ ...base, cashierId: 'c', orderCreatorId: 'o' })).toBe('c');
    expect(tipOwner({ ...base, orderCreatorId: 'o' })).toBe('o');
    expect(tipOwner(base)).toBeNull();
  });
});
