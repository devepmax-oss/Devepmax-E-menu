import { monthIn, pointsForBill, rewardsFor } from './loyalty.rules';

describe('lealtad', () => {
  it('da puntos por dólar consumido, sin impuesto ni propina, y solo si está pagada', () => {
    expect(pointsForBill({ status: 'PAID', subtotal: 42.9, discountTotal: 4.29, refunded: 0 }, 1)).toBe(38);
    expect(pointsForBill({ status: 'PAID', subtotal: 42.9, discountTotal: 0, refunded: 0 }, 2)).toBe(85);
    expect(pointsForBill({ status: 'UNPAID', subtotal: 42.9, discountTotal: 0, refunded: 0 }, 1)).toBe(0);
  });

  it('lo reembolsado no da puntos', () => {
    expect(pointsForBill({ status: 'PAID', subtotal: 50, discountTotal: 0, refunded: 20 }, 1)).toBe(30);
    expect(pointsForBill({ status: 'REFUNDED', subtotal: 50, discountTotal: 0, refunded: 54.13 }, 1)).toBe(0);
  });

  it('entrega un premio por cada meta alcanzada', () => {
    expect(rewardsFor(99, 100)).toEqual({ rewards: 0, cost: 0 });
    expect(rewardsFor(250, 100)).toEqual({ rewards: 2, cost: 200 });
  });

  it('el mes se cuenta en la zona del restaurante', () => {
    // 1 de marzo 02:00 UTC = 28 de febrero en Nueva York
    expect(monthIn('America/New_York', new Date('2027-03-01T02:00:00Z'))).toEqual({ year: 2027, month: 2 });
  });
});
