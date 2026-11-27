import { classify, parsePeriod, percent, unitMargin } from './menu.rules';

describe('ingeniería de menú', () => {
  // 4 platos, 100 unidades: la línea de popularidad es 0.7 × 100 / 4 = 17.5.
  // Margen total: 40×6 + 30×2 + 10×9 + 20×1 = 410 → 4.10 por unidad.
  const dishes = [
    { id: 'tacos', quantity: 40, net: 400, cost: 160 }, // margen 6 por unidad, popular
    { id: 'refresco', quantity: 30, net: 90, cost: 30 }, // margen 2, popular
    { id: 'filete', quantity: 10, net: 150, cost: 60 }, // margen 9, poco popular
    { id: 'sopa', quantity: 20, net: 60, cost: 40 }, // margen 1, apenas popular
  ];

  it('pone cada plato en su cuadrante', () => {
    const r = classify(dishes);
    expect(r.popularityLine).toBe(17.5);
    expect(r.marginLine).toBe(4.1);
    expect(r.classes.get('tacos')).toBe('star');
    expect(r.classes.get('refresco')).toBe('plowhorse');
    expect(r.classes.get('filete')).toBe('puzzle');
    expect(r.classes.get('sopa')).toBe('plowhorse');
  });

  it('un plato que se vende poco y deja poco es perro', () => {
    const r = classify([...dishes, { id: 'ensalada', quantity: 2, net: 10, cost: 8 }]);
    expect(r.classes.get('ensalada')).toBe('dog');
  });

  it('un plato sin receta no se clasifica ni mueve las líneas', () => {
    const r = classify([...dishes, { id: 'postre', quantity: 500, net: 2000, cost: null }]);
    expect(r.classes.get('postre')).toBeNull();
    expect(r.popularityLine).toBe(17.5);
  });

  it('un plato sin venta usa su margen a precio de lista y nunca es popular', () => {
    const r = classify([...dishes, { id: 'nuevo', quantity: 0, net: 0, cost: 0, listUnitMargin: 12 }]);
    expect(r.classes.get('nuevo')).toBe('puzzle');
    const cheap = classify([...dishes, { id: 'barato', quantity: 0, net: 0, cost: 0, listUnitMargin: 1 }]);
    expect(cheap.classes.get('barato')).toBe('dog');
  });

  it('sin ventas no hay clasificación', () => {
    const r = classify([{ id: 'a', quantity: 0, net: 0, cost: 0, listUnitMargin: 5 }]);
    expect(r.classes.get('a')).toBeNull();
  });

  it('margen por unidad', () => {
    expect(unitMargin({ id: 'x', quantity: 4, net: 40, cost: 12 })).toBe(7);
    expect(unitMargin({ id: 'x', quantity: 4, net: 40, cost: null })).toBeNull();
  });

  it('porcentajes', () => {
    expect(percent(25, 200)).toBe(12.5);
    expect(percent(5, 0)).toBeNull();
  });
});

describe('período', () => {
  it('acepta un día o un rango', () => {
    expect(parsePeriod(undefined, undefined, '2026-11-27').days).toBe(1);
    expect(parsePeriod('2026-11-01', '2026-11-30', '2026-11-27').days).toBe(30);
  });
  it('rechaza fechas malas, al revés o muy largas', () => {
    expect(() => parsePeriod('2026-02-30', undefined, '2026-11-27')).toThrow('Fecha inválida');
    expect(() => parsePeriod('2026-13-45', undefined, '2026-11-27')).toThrow('Fecha inválida');
    expect(() => parsePeriod('2026-11-10', '2026-11-01', '2026-11-27')).toThrow('anterior');
    expect(() => parsePeriod('2024-01-01', '2026-11-27', '2026-11-27')).toThrow('400');
  });
});
