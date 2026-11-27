/**
 * Prueba de humo del análisis de menú y promociones: platos con su costo (del inventario o de
 * la receta), margen y cuadrante, platos sin venta, sin receta, y el costo de una promoción
 * y de un cupón. Más permisos y fechas inválidas.
 * Uso:  npm run smoke:menu   (backend encendido y seed hecho)
 *
 * Crea una categoría "Prueba análisis NNNN" con 4 platos (quedan inactivos), 2 ingredientes,
 * una promoción y un cupón (se borran o pausan) y una orden para llevar (se cancela).
 */
import { randomInt, randomUUID } from 'node:crypto';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const BASE = `http://localhost:${process.env.PORT ?? 3000}/api/v1`;
let failures = 0;
type Json = Record<string, any>;
const tag = String(randomInt(1000, 9999));
const rid = () => randomUUID().replace(/-/g, '');
const n = (v: unknown) => Number(v ?? 0);
const near = (a: unknown, b: number) => Math.abs(n(a) - b) < 0.02;

async function api(method: string, path: string, body?: unknown, token = '') {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, data: text ? JSON.parse(text) : null } as { status: number; data: any };
}

function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`  ✓ ${name}`);
  else {
    failures++;
    console.log(`  ✗ ${name}`);
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 500));
  }
}

async function main() {
  console.log(`\nPrueba del análisis de menú y promociones → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const first = await api('GET', '/dashboard/menu', undefined, A);
  if (first.status === 404) {
    console.log('✗ El backend no tiene todavía el análisis de menú. Detenlo (Ctrl+C) y vuelve a correr "npm run start:dev".');
    process.exit(1);
  }
  const today = first.data?.from as string;
  const inv = (await api('GET', '/inventory/summary', undefined, A)).data as Json;
  const restore = { enabled: inv?.enabled ?? false, autoSoldOut: inv?.autoSoldOut ?? true };
  const products: string[] = [];
  let categoryId = '';
  const items: Json[] = [];
  let orderId = '';
  let promoId = '';
  let coupon: Json | null = null;
  let employeeId = '';
  const name = (s: string) => `${s} ${tag}`;

  try {
    console.log('Preparación');
    await api('PATCH', '/inventory/settings', { enabled: true, autoSoldOut: false }, A);
    const cat = (await api('POST', '/menu/categories', { name: `Prueba análisis ${tag}`, visibleOnline: false }, A)).data as Json;
    categoryId = cat?.id ?? '';
    const make = async (label: string, price: number) => {
      const p = (await api('POST', '/menu/products', { categoryId: cat.id, name: name(label), price, visibleOnline: false }, A)).data as Json;
      products.push(p.id);
      return p;
    };
    const tacos = await make('Tacos', 10); // costo 2 → margen 8
    const sopa = await make('Sopa', 8); // costo 6 → margen 2
    const filete = await make('Filete', 20); // sin venta, costo 5
    const postre = await make('Postre', 6); // sin receta
    const cheap = (await api('POST', '/inventory/items', { name: name('Insumo barato'), unit: 'unit' }, A)).data as Json;
    const pricey = (await api('POST', '/inventory/items', { name: name('Insumo caro'), unit: 'unit' }, A)).data as Json;
    items.push(cheap, pricey);
    await api('POST', '/inventory/receipts', { lines: [{ itemId: cheap.id, quantity: 100, unitCost: 1 }, { itemId: pricey.id, quantity: 100, unitCost: 3 }] }, A);
    await api('PUT', `/inventory/recipes/${tacos.id}`, { lines: [{ itemId: cheap.id, quantity: 2 }] }, A);
    await api('PUT', `/inventory/recipes/${sopa.id}`, { lines: [{ itemId: pricey.id, quantity: 2 }] }, A);
    await api('PUT', `/inventory/recipes/${filete.id}`, { lines: [{ itemId: cheap.id, quantity: 2 }, { itemId: pricey.id, quantity: 1 }] }, A);
    const promo = await api('POST', '/promotions', { name: name('Martes de tacos'), type: 'PERCENT_OFF', value: 10, productIds: [tacos.id], appliesDineIn: true, appliesOnline: true }, A);
    promoId = promo.data?.id;
    check('se prepara el menú de prueba (4 platos, recetas, promoción)', !!cat?.id && products.length === 4 && promo.status === 201, promo.data);

    const before = (await api('GET', `/dashboard/menu?from=${today}&to=${today}`, undefined, A)).data as Json;
    const unsold0 = (before.unsold as Json[]).map((u) => u.name);
    check('antes de vender, los 4 aparecen sin venta', [tacos, sopa, filete, postre].every((p) => unsold0.includes(p.name)), unsold0.filter((x) => x.endsWith(tag)));

    console.log('\nPlatos');
    const order = await api('POST', '/orders', {
      clientRequestId: rid(),
      fulfillmentType: 'TAKEOUT',
      customerName: name('Prueba análisis'),
      items: [
        { productId: tacos.id, quantity: 3 },
        { productId: sopa.id, quantity: 1 },
      ],
    }, A);
    orderId = order.data?.id;
    check('se hace una orden: 3 tacos y 1 sopa', order.status === 201, order.data);
    coupon = (await api('POST', '/coupons', { code: `MENU-${tag}`, name: 'Prueba análisis', type: 'AMOUNT', value: 1, appliesOnline: true, appliesInStore: true }, A)).data;
    const applied = await api('POST', `/billing/bills/${order.data?.billId ?? order.data?.bill?.id}/coupon`, { code: `MENU-${tag}` }, A);
    check('se aplica un cupón de $1 a la cuenta', applied.status === 200, applied.data);

    const r = (await api('GET', `/dashboard/menu?from=${today}&to=${today}`, undefined, A)).data as Json;
    const dish = (p: Json) => (r.dishes as Json[]).find((d) => d.productId === p.id);
    const t = dish(tacos);
    const s = dish(sopa);
    check('tacos: 3 vendidos, $27 netos con el 10 %', t?.quantity === 3 && near(t?.net, 27), t);
    check('tacos: costo $6 tomado del inventario', near(t?.cost, 6) && t?.costSource === 'inventory', t);
    check('tacos: margen $21 y food cost 22.2 %', near(t?.margin, 21) && near(t?.foodCostPct, 22.2), t);
    check('sopa: $8 netos, costo $6, margen $2', s?.quantity === 1 && near(s?.net, 8) && near(s?.cost, 6) && near(s?.margin, 2), s);
    check('cada plato vendido tiene cuadrante', ['star', 'plowhorse', 'puzzle', 'dog'].includes(t?.class) && ['star', 'plowhorse', 'puzzle', 'dog'].includes(s?.class), [t?.class, s?.class]);
    check('tacos dejan más por unidad que sopa', n(t?.unitMargin) > n(s?.unitMargin), [t?.unitMargin, s?.unitMargin]);
    const unsold = r.unsold as Json[];
    const f = unsold.find((u) => u.productId === filete.id);
    check('filete sigue sin venta, con su margen de lista $15', !!f && near(f.unitMargin, 15), f);
    check('postre sin venta y sin receta (sin margen)', unsold.some((u) => u.productId === postre.id && u.unitMargin === null));
    check('los vendidos ya no están en "sin venta"', !unsold.some((u) => u.productId === tacos.id || u.productId === sopa.id));
    check('el resumen suma las ventas de la orden', n(r.summary.net) - n(before.summary.net) > 34.9 && r.summary.orders === before.summary.orders + 1, [before.summary, r.summary]);

    console.log('\nPromociones y cupones');
    const p = (r.promotions.promotions as Json[]).find((x) => x.id === promoId);
    check('la promoción: 1 orden, 3 unidades, $3 de descuento', p?.orders === 1 && p?.units === 3 && near(p?.discount, 3), p);
    check('ventas de las órdenes con la promoción: $35', near(p?.sales, 35), p);
    const c = (r.promotions.coupons as Json[]).find((x) => x.code === `MENU-${tag}`);
    check('el cupón: 1 uso, $1 de descuento', c?.uses === 1 && near(c?.discount, 1), c);
    check('el total de descuentos subió $4', near(n(r.promotions.totalDiscount) - n(before.promotions.totalDiscount), 4), [before.promotions.totalDiscount, r.promotions.totalDiscount]);

    console.log('\nCancelaciones, fechas y permisos');
    await api('POST', `/orders/${orderId}/cancel`, { reason: 'Prueba del análisis' }, A);
    orderId = '';
    const after = (await api('GET', `/dashboard/menu?from=${today}&to=${today}`, undefined, A)).data as Json;
    check('al cancelar, los platos vuelven a "sin venta"', (after.unsold as Json[]).some((u) => u.productId === tacos.id) && !(after.dishes as Json[]).some((d) => d.productId === tacos.id));
    check('una fecha inválida avisa', (await api('GET', '/dashboard/menu?from=2026-02-30', undefined, A)).status === 400);
    check('más de 400 días avisa', (await api('GET', '/dashboard/menu?from=2024-01-01&to=2026-11-27', undefined, A)).status === 400);
    const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((x) => x.name === 'Mesero');
    const emp = await api('POST', '/employees', { name: name('Prueba análisis'), roleId: mesero?.id }, A);
    employeeId = emp.data?.id;
    await api('PATCH', `/employees/${employeeId}`, { email: `prueba.analisis.${tag}@example.com`, password: `Analisis-${tag}-clave` }, A);
    const E = (await api('POST', '/auth/login', { email: `prueba.analisis.${tag}@example.com`, password: `Analisis-${tag}-clave` })).data?.accessToken;
    check('un mesero no ve el análisis', (await api('GET', '/dashboard/menu', undefined, E)).status === 403);
  } finally {
    if (orderId) await api('POST', `/orders/${orderId}/cancel`, { reason: 'Limpieza de la prueba' }, A);
    if (promoId) await api('DELETE', `/promotions/${promoId}`, undefined, A);
    if (coupon?.id && (await api('DELETE', `/coupons/${coupon.id}`, undefined, A)).status === 409) {
      await api('PATCH', `/coupons/${coupon.id}`, { code: coupon.code, name: coupon.name, type: coupon.type, value: n(coupon.value), appliesOnline: true, appliesInStore: true, isActive: false }, A);
    }
    for (const id of products) await api('PATCH', `/menu/products/${id}`, { isActive: false }, A);
    if (categoryId) await api('PATCH', `/menu/categories/${categoryId}`, { isActive: false }, A);
    for (const it of items) if ((await api('DELETE', `/inventory/items/${it.id}`, undefined, A)).status === 409) {
      await api('PATCH', `/inventory/items/${it.id}`, { name: it.name, unit: it.unit, isActive: false }, A);
    }
    if (employeeId) await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Empleado de prueba' }, A);
    await api('PATCH', '/inventory/settings', restore, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
