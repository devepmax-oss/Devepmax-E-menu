/**
 * Prueba de humo de promociones contra el backend que está corriendo.
 * Uso:  npm run smoke:promotions
 * Crea y borra promociones de prueba ("[PRUEBA] …") y órdenes en la base de DESARROLLO.
 */
import { randomUUID } from 'node:crypto';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const BASE = `http://localhost:${process.env.PORT ?? 3000}/api/v1`;
const TAG = '[PRUEBA]';
let token = '';
let failures = 0;
type Json = Record<string, any>;

async function api(method: string, path: string, body?: unknown): Promise<{ status: number; data: any }> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : null };
}

function check(name: string, ok: boolean, detail?: unknown): void {
  if (ok) console.log(`  ✓ ${name}`);
  else {
    failures++;
    console.log(`  ✗ ${name}`);
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 400));
  }
}

const cents = (n: number) => Math.round(n * 100) / 100;
const num = (v: unknown) => Number(v ?? 0);

async function cleanup(): Promise<void> {
  const list = (await api('GET', '/promotions')).data as Json[];
  for (const p of list ?? []) if (String(p.name).startsWith(TAG)) await api('DELETE', `/promotions/${p.id}`);
}

async function main(): Promise<void> {
  console.log(`\nPrueba de promociones → ${BASE}\n`);
  const login = await api('POST', '/auth/login', {
    email: process.env.SEED_ADMIN_EMAIL,
    password: process.env.SEED_ADMIN_PASSWORD,
  });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Backend encendido y SEED_ADMIN_* correctos?', login.data);
    process.exit(1);
  }
  token = login.data.accessToken;
  await cleanup();

  const existing = ((await api('GET', '/promotions')).data as Json[]).filter((p) => p.state === 'ACTIVE');
  if (existing.length) {
    console.log(`Aviso: hay ${existing.length} promoción(es) activa(s) creadas por ti; pueden cambiar los resultados.`);
  }

  const menu = (await api('GET', '/menu/admin')).data;
  const product = menu.categories
    .filter((c: Json) => c.isActive)
    .flatMap((c: Json) => c.products)
    .find((p: Json) => p.isActive && p.isAvailable && p.visibleDineIn);
  if (!product) {
    console.log('✗ No hay productos disponibles en el menú.');
    process.exit(1);
  }
  const optionIds: string[] = [];
  for (const link of product.modifierGroups) {
    const g = link.modifierGroup;
    if (g.isActive) optionIds.push(...g.options.filter((o: Json) => o.isAvailable).slice(0, g.minSelect).map((o: Json) => o.id));
  }
  const line = (quantity: number) => ({ productId: product.id, quantity, optionIds });
  const quote = async (quantity: number) => (await api('POST', '/orders/quote', { items: [line(quantity)] })).data;

  const base = await quote(1);
  const unit = num(base.lines?.[0]?.lineTotal);
  console.log(`Producto: "${product.name}" · precio por unidad con opciones: $${unit}\n`);
  check('sin promociones no hay descuento', num(base.totals?.discountTotal) === 0, base.totals);

  const create = (body: Json) => api('POST', '/promotions', { appliesDineIn: true, appliesOnline: true, ...body });
  const remove = (id: string) => api('DELETE', `/promotions/${id}`);

  console.log('\nDescuento %');
  const pct = await create({ name: `${TAG} 10%`, type: 'PERCENT_OFF', value: 10, categoryIds: [product.categoryId] });
  check('se crea la promoción', pct.status === 201, pct.data);
  let q = await quote(1);
  check(`10 % de $${unit} = $${cents(unit * 0.1)} (${q.totals.discountTotal})`, num(q.totals.discountTotal) === cents(unit * 0.1));
  check('indica qué promoción se aplicó', q.promotions?.[0]?.name === `${TAG} 10%`, q.promotions);
  await remove(pct.data.id);

  console.log('\nDescuento $');
  const amt = await create({ name: `${TAG} $2`, type: 'AMOUNT_OFF', value: 2, productIds: [product.id] });
  q = await quote(2);
  const expectedAmt = cents(2 * Math.min(2, unit));
  check(`$2 por unidad × 2 = $${expectedAmt} (${q.totals.discountTotal})`, num(q.totals.discountTotal) === expectedAmt);
  await remove(amt.data.id);

  console.log('\n2x1');
  const bogo = await create({ name: `${TAG} 2x1`, type: 'BUY_X_GET_Y', buyQuantity: 1, getQuantity: 1, productIds: [product.id] });
  q = await quote(2);
  check(`2 unidades: 1 gratis ($${unit}) (${q.totals.discountTotal})`, num(q.totals.discountTotal) === unit);
  q = await quote(3);
  check(`3 unidades: sigue siendo 1 gratis (${q.totals.discountTotal})`, num(q.totals.discountTotal) === unit);
  q = await quote(1);
  check('1 unidad: sin descuento', num(q.totals.discountTotal) === 0);

  console.log('\nOrden real con 2x1');
  const order = await api('POST', '/orders', {
    clientRequestId: randomUUID().replace(/-/g, ''),
    fulfillmentType: 'TAKEOUT',
    customerName: `${TAG} cliente`,
    items: [line(2)],
  });
  const quote2 = await quote(2);
  check('la orden se crea', order.status === 201, order.data);
  check(`la cuenta guarda el descuento ($${order.data?.bill?.discountTotal})`, num(order.data?.bill?.discountTotal) === unit);
  check(
    `total de la orden = total cotizado ($${order.data?.bill?.total})`,
    num(order.data?.bill?.total) === num(quote2.totals.total),
    { order: order.data?.bill, quote: quote2.totals },
  );
  check(
    'el impuesto se calcula sobre el precio con descuento',
    num(order.data?.bill?.taxTotal) === num(quote2.totals.taxTotal) && num(order.data?.bill?.taxTotal) < num(base.totals.taxTotal) * 2,
  );
  check('la orden muestra la promoción aplicada', order.data?.promotions?.[0]?.name === `${TAG} 2x1`, order.data?.promotions);
  const cancelled = await api('POST', `/orders/${order.data.id}/cancel`, { reason: 'Prueba de promociones' });
  check(`al cancelar, la cuenta queda en $0 (${cancelled.data?.bill?.total})`, num(cancelled.data?.bill?.total) === 0);
  await remove(bogo.data.id);

  console.log('\nCombo');
  const comboPrice = cents(unit * 2 - 5);
  const combo = await create({
    name: `${TAG} combo`,
    type: 'COMBO_PRICE',
    comboPrice,
    comboSlots: [
      { name: 'Primera', quantity: 1, productIds: [product.id], categoryIds: [] },
      { name: 'Segunda', quantity: 1, productIds: [product.id], categoryIds: [] },
    ],
  });
  check('se crea el combo', combo.status === 201, combo.data);
  q = await quote(2);
  check(`combo de 2 a $${comboPrice}: ahorro $5.00 (${q.totals.discountTotal})`, num(q.totals.discountTotal) === 5);
  q = await quote(1);
  check('con 1 unidad no se forma el combo', num(q.totals.discountTotal) === 0);
  await remove(combo.data.id);

  console.log('\nLa mejor promoción gana (no se acumulan)');
  const a = await create({ name: `${TAG} 10% B`, type: 'PERCENT_OFF', value: 10, productIds: [product.id] });
  const b = await create({ name: `${TAG} $2 B`, type: 'AMOUNT_OFF', value: 2, productIds: [product.id] });
  q = await quote(1);
  const best = Math.max(cents(unit * 0.1), Math.min(2, unit));
  check(`se aplica solo la de mayor ahorro ($${best})`, num(q.totals.discountTotal) === best && q.promotions.length === 1, q.promotions);
  await remove(a.data.id);
  await remove(b.data.id);

  console.log('\nVigencia');
  const tomorrow = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
  const future = await create({ name: `${TAG} futura`, type: 'PERCENT_OFF', value: 50, productIds: [product.id], startsAt: tomorrow });
  check(`una promoción que empieza mañana queda "programada" (${future.data?.state})`, future.data?.state === 'SCHEDULED');
  q = await quote(1);
  check('y todavía no se aplica', num(q.totals.discountTotal) === 0);
  await remove(future.data.id);
  const off = await create({ name: `${TAG} apagada`, type: 'PERCENT_OFF', value: 50, productIds: [product.id], isActive: false });
  q = await quote(1);
  check('una promoción desactivada no se aplica', num(q.totals.discountTotal) === 0);
  await remove(off.data.id);

  console.log('\nValidaciones');
  const invalid = await create({ name: `${TAG} sin productos`, type: 'PERCENT_OFF', value: 10 });
  check('rechaza un descuento sin productos ni categorías', invalid.status === 400, invalid.data);
  const badCombo = await create({ name: `${TAG} combo malo`, type: 'COMBO_PRICE', comboPrice: 10, comboSlots: [] });
  check('rechaza un combo sin partes', badCombo.status === 400, badCombo.data);

  await cleanup();
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (error) => {
  console.error('\n✗ Error inesperado:', error);
  await cleanup().catch(() => undefined);
  process.exit(1);
});
