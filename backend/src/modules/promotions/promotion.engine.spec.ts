import { applyPromotions, EngineLine, EnginePromotion } from './promotion.engine';

const burger = (index: number, quantity = 1, price = '14.50'): EngineLine => ({
  index,
  productId: 'burger',
  categoryId: 'burgers',
  unitAmount: price,
  quantity,
});
const drink = (index: number, quantity = 1): EngineLine => ({
  index,
  productId: 'soda',
  categoryId: 'drinks',
  unitAmount: '3.00',
  quantity,
});

function promo(partial: Partial<EnginePromotion> & Pick<EnginePromotion, 'type'>): EnginePromotion {
  return {
    id: partial.type,
    name: partial.type,
    value: null,
    buyQuantity: null,
    getQuantity: null,
    comboPrice: null,
    priority: 0,
    targets: [{ productId: null, categoryId: 'burgers' }],
    slots: [],
    ...partial,
  };
}

const total = (lines: EngineLine[], promotions: EnginePromotion[]) =>
  applyPromotions(lines, promotions)
    .reduce((s, a) => s + Number(a.amount), 0)
    .toFixed(2);

describe('motor de promociones', () => {
  it('descuento porcentual sobre la categoría', () => {
    expect(total([burger(0, 2), drink(1)], [promo({ type: 'PERCENT_OFF', value: 10 })])).toBe('2.90');
  });

  it('descuento fijo por unidad, nunca mayor que el precio', () => {
    expect(total([burger(0, 2)], [promo({ type: 'AMOUNT_OFF', value: 2 })])).toBe('4.00');
    expect(total([burger(0, 1, '1.50')], [promo({ type: 'AMOUNT_OFF', value: 2 })])).toBe('1.50');
  });

  it('2x1: sale gratis el más barato de cada par', () => {
    const lines = [burger(0, 1, '14.50'), burger(1, 1, '12.00')];
    expect(total(lines, [promo({ type: 'BUY_X_GET_Y', buyQuantity: 1, getQuantity: 1 })])).toBe('12.00');
  });

  it('2x1 con 3 unidades: solo una sale gratis', () => {
    expect(total([burger(0, 3)], [promo({ type: 'BUY_X_GET_Y', buyQuantity: 1, getQuantity: 1 })])).toBe('14.50');
  });

  it('combo a precio fijo', () => {
    const combo = promo({
      type: 'COMBO_PRICE',
      comboPrice: 15,
      targets: [],
      slots: [
        { quantity: 1, productIds: [], categoryIds: ['burgers'] },
        { quantity: 1, productIds: ['soda'], categoryIds: [] },
      ],
    });
    expect(total([burger(0), drink(1)], [combo])).toBe('2.50');
    expect(total([burger(0, 2), drink(1, 2)], [combo])).toBe('5.00');
    expect(total([burger(0)], [combo])).toBe('0.00');
  });

  it('elige la promoción que más ahorra y no acumula sobre la misma unidad', () => {
    const lines = [burger(0)];
    const result = applyPromotions(lines, [
      promo({ type: 'PERCENT_OFF', value: 10 }),
      promo({ type: 'AMOUNT_OFF', value: 2 }),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0].promotionId).toBe('AMOUNT_OFF');
  });

  it('reparte el descuento por línea y cuadra los centavos', () => {
    const [allocation] = applyPromotions([burger(0), burger(1, 1, '9.99')], [promo({ type: 'PERCENT_OFF', value: 15 })]);
    const perLine = [...allocation.perLine.values()].reduce((s, v) => s.plus(v), allocation.amount.minus(allocation.amount));
    expect(perLine.toString()).toBe(allocation.amount.toString());
  });
});
