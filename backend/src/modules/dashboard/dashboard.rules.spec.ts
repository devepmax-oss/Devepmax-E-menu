import { AlertInput, buildAlerts, change } from './dashboard.rules';

const calm: AlertInput = {
  net: 1000,
  lastWeekSoFar: 900,
  laborCost: 200,
  foodCost: 280,
  lowStock: [],
  lateTickets: 0,
  oldestTicketMinutes: 0,
  orders: 40,
  cancellations: 1,
  manualDiscounts: 1,
  manualDiscountAmount: 10,
  gross: 1050,
  missingOut: 0,
  onlinePaused: false,
};
const ids = (i: Partial<AlertInput>) => buildAlerts({ ...calm, ...i }).map((a) => a.id);

describe('alertas del tablero', () => {
  it('un día normal no da alertas', () => {
    expect(buildAlerts(calm)).toEqual([]);
  });

  it('ventas abajo solo si la semana pasada ya había vendido algo', () => {
    expect(ids({ net: 500, lastWeekSoFar: 900 })).toContain('sales_low');
    expect(ids({ net: 20, lastWeekSoFar: 60 })).not.toContain('sales_low');
  });

  it('personal y food cost altos (solo con ventas suficientes)', () => {
    expect(ids({ laborCost: 400 })).toContain('labor_high');
    expect(ids({ foodCost: 400 })).toContain('food_cost_high');
    expect(ids({ net: 150, laborCost: 100, foodCost: 100, lastWeekSoFar: 0 })).toEqual([]);
    expect(ids({ foodCost: null })).not.toContain('food_cost_high');
  });

  it('cocina atrasada va primero y es roja', () => {
    const alerts = buildAlerts({ ...calm, lateTickets: 2, oldestTicketMinutes: 41, lowStock: ['Pan'] });
    expect(alerts[0]).toMatchObject({ id: 'kitchen_late', level: 'danger' });
    expect(alerts[0].detail).toContain('41 min');
  });

  it('cancelaciones y descuentos fuera de lo normal', () => {
    expect(ids({ cancellations: 5 })).toContain('cancellations');
    expect(ids({ cancellations: 3, orders: 100 })).not.toContain('cancellations');
    expect(ids({ manualDiscounts: 4, manualDiscountAmount: 150 })).toContain('discounts');
  });

  it('ingredientes bajos, jornadas sin salida y web en pausa', () => {
    const a = buildAlerts({ ...calm, lowStock: ['Pan', 'Carne', 'Queso', 'Tomate', 'Lechuga'], missingOut: 1, onlinePaused: true });
    expect(a.find((x) => x.id === 'low_stock')?.detail).toBe('Pan, Carne, Queso, Tomate y 1 más');
    expect(a.map((x) => x.id)).toEqual(expect.arrayContaining(['missing_out', 'online_paused']));
  });

  it('cambio en %', () => {
    expect(change(110, 100)).toBe(10);
    expect(change(50, 200)).toBe(-75);
    expect(change(50, 0)).toBeNull();
  });
});
