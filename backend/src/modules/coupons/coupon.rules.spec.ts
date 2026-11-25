import { couponSavings, normalizeCode, randomCouponCode } from './coupon.rules';

describe('cupones', () => {
  it('porcentaje sobre lo que queda de la cuenta, con tope', () => {
    expect(couponSavings({ type: 'PERCENT', value: 10, maxDiscount: null }, 45.5).amount.toString()).toBe('4.55');
    expect(couponSavings({ type: 'PERCENT', value: 50, maxDiscount: 10 }, 45).amount.toString()).toBe('10');
  });

  it('un monto fijo nunca pasa del total', () => {
    expect(couponSavings({ type: 'AMOUNT', value: 5, maxDiscount: null }, 30).amount.toString()).toBe('5');
    expect(couponSavings({ type: 'AMOUNT', value: 50, maxDiscount: null }, 12.25).amount.toString()).toBe('12.25');
  });

  it('envío gratis no descuenta productos: quita el envío', () => {
    const r = couponSavings({ type: 'FREE_DELIVERY', value: null, maxDiscount: null }, 40, 4.99);
    expect(r.amount.toString()).toBe('0');
    expect(r.freeDelivery).toBe(true);
    expect(r.saved.toString()).toBe('4.99');
  });

  it('normaliza y genera códigos legibles', () => {
    expect(normalizeCode(' verano 10 ')).toBe('VERANO10');
    expect(normalizeCode('a!')).toBeNull();
    expect(randomCouponCode('GP', 6, () => 0)).toBe('GPAAAAAA');
    expect(randomCouponCode()).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
  });
});
