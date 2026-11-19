import {
  businessDateFor,
  canMoveTicket,
  computeTotals,
  deriveOrderStatus,
  generatePublicCode,
  kitchenStarted,
  lineTotal,
  selectionError,
} from './order.rules';

describe('businessDateFor', () => {
  const tz = 'America/New_York';

  it('usa la fecha local del restaurante', () => {
    // 2026-11-19 15:00 en Nueva York = 20:00 UTC
    expect(businessDateFor(new Date('2026-11-19T20:00:00Z'), tz).toISOString()).toBe('2026-11-19T00:00:00.000Z');
  });

  it('antes de las 4 a. m. cuenta para el día anterior', () => {
    // 2026-11-20 01:30 en Nueva York = 06:30 UTC
    expect(businessDateFor(new Date('2026-11-20T06:30:00Z'), tz).toISOString()).toBe('2026-11-19T00:00:00.000Z');
  });
});

describe('estados', () => {
  it('cocina avanza o deshace un paso, pero no salta hacia atrás', () => {
    expect(canMoveTicket('NEW', 'PREPARING')).toBe(true);
    expect(canMoveTicket('READY', 'PREPARING')).toBe(true);
    expect(canMoveTicket('READY', 'NEW')).toBe(false);
    expect(canMoveTicket('NEW', 'CANCELLED')).toBe(false);
  });

  it('la orden está lista solo cuando todas las estaciones terminaron', () => {
    expect(deriveOrderStatus('PLACED', ['READY', 'PREPARING'])).toBe('PREPARING');
    expect(deriveOrderStatus('PREPARING', ['READY', 'READY'])).toBe('READY');
    expect(deriveOrderStatus('PLACED', ['ACCEPTED', 'NEW'])).toBe('ACCEPTED');
    expect(deriveOrderStatus('PLACED', ['NEW', 'CANCELLED'])).toBe('PLACED');
  });

  it('no cambia estados que no dependen de cocina', () => {
    expect(deriveOrderStatus('PENDING_APPROVAL', ['READY'])).toBe('PENDING_APPROVAL');
    expect(deriveOrderStatus('CANCELLED', ['READY'])).toBe('CANCELLED');
  });

  it('detecta si la cocina ya empezó', () => {
    expect(kitchenStarted(['NEW', 'NEW'])).toBe(false);
    expect(kitchenStarted(['NEW', 'ACCEPTED'])).toBe(true);
  });
});

describe('precios', () => {
  it('calcula la línea con modificadores y cantidad', () => {
    expect(lineTotal('14.50', '1.25', 2).toString()).toBe('31.5');
    expect(lineTotal('2.00', '-3.00', 1).toString()).toBe('0');
  });

  it('valida mínimos y máximos de los grupos', () => {
    const groups = [{ id: 'g1', name: 'Término', minSelect: 1, maxSelect: 1 }];
    expect(selectionError('Burger', groups, new Map())).toContain('elige una opción');
    expect(selectionError('Burger', groups, new Map([['g1', 2]]))).toContain('como máximo 1');
    expect(selectionError('Burger', groups, new Map([['g1', 1]]))).toBeNull();
  });

  it('suma impuestos por tasa y redondea al final', () => {
    const totals = computeTotals([
      { lineTotal: '10.00', taxRate: '0.08875' },
      { lineTotal: '5.00', taxRate: '0.08875' },
    ]);
    expect(totals.subtotal.toString()).toBe('15');
    expect(totals.taxTotal.toString()).toBe('1.33'); // 1.33125
    expect(totals.total.toString()).toBe('16.33');
  });

  it('el descuento reduce la base del impuesto', () => {
    const totals = computeTotals([{ lineTotal: '20.00', taxRate: '0.1' }], { discountTotal: '5.00' });
    expect(totals.taxTotal.toString()).toBe('1.5');
    expect(totals.total.toString()).toBe('16.5');
  });

  it('genera códigos públicos legibles', () => {
    expect(generatePublicCode()).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  });
});
