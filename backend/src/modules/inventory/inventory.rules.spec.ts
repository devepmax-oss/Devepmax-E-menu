import { canMake, plateCost, weightedCost } from './inventory.rules';

describe('inventario', () => {
  it('costo promedio ponderado al comprar', () => {
    // 1000 g a $0.010 + 1000 g a $0.014 = $0.012 por g
    expect(weightedCost(1000, 0.01, 1000, 0.014).toString()).toBe('0.012');
    expect(weightedCost(0, 0.01, 500, 0.02).toString()).toBe('0.02');
    expect(weightedCost(-20, 0.01, 500, 0.02).toString()).toBe('0.02');
  });

  it('costo y margen de un plato', () => {
    const r = plateCost(12.5, [
      { quantity: 150, costPerUnit: 0.012 }, // carne
      { quantity: 1, costPerUnit: 0.6 }, // pan
    ]);
    expect(r.cost.toString()).toBe('2.4');
    expect(r.margin.toString()).toBe('10.1');
    expect(r.foodCostPct).toBe(19.2);
  });

  it('sabe si alcanza para hacer uno', () => {
    expect(canMake([{ quantity: 150, onHand: 200 }, { quantity: 1, onHand: 1 }])).toBe(true);
    expect(canMake([{ quantity: 150, onHand: 100 }])).toBe(false);
  });
});
