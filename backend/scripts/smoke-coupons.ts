/**
 * Prueba de humo de los cupones: crear y validar, aplicar en la caja (%, monto, mínimo, vencido,
 * pausado, agotado, uno por cliente), recalcular el % en una mesa, cotizar en la web y borrar.
 * Uso:  npm run smoke:coupons   (backend encendido y seed hecho)
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
const rid = () => randomUUID().replace(/-/g, '');
const n = (v: unknown) => Number(v ?? 0);
const near = (a: unknown, b: number) => Math.abs(n(a) - b) < 0.011;
const tag = String(randomInt(1000, 9999));

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
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 400));
  }
}

async function main() {
  console.log(`\nPrueba de cupones → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  if ((await api('GET', '/coupons', undefined, A)).status === 404) {
    console.log('✗ El backend no tiene todavía los cupones. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 2, optionIds }];
  const orders: string[] = [];
  const takeout = async () => {
    const o = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items }, A)).data;
    orders.push(o.id);
    return o;
  };
  const coupon = async (body: Json) => api('POST', '/coupons', { appliesOnline: true, appliesInStore: true, ...body }, A);
  const apply = (billId: string, code: string) => api('POST', `/billing/bills/${billId}/coupon`, { code }, A);

  console.log('Crear');
  const pct = await coupon({ code: `p10-${tag}`, name: '10 % de prueba', type: 'PERCENT', value: 10 });
  check('crea un cupón de 10 % (el código queda en mayúsculas)', pct.status === 201 && pct.data?.code === `P10-${tag}` && pct.data?.state === 'ACTIVE', pct.data);
  check('no repite códigos', (await coupon({ code: `P10-${tag}`, type: 'AMOUNT', value: 1 })).status === 409);
  check('el porcentaje no pasa de 100', (await coupon({ code: `X150-${tag}`, type: 'PERCENT', value: 150 })).status === 400);
  check('el envío gratis no se usa en el local', (await coupon({ code: `ENV-${tag}`, type: 'FREE_DELIVERY', appliesInStore: true })).status === 400);
  const suggested = await api('GET', '/coupons/suggest-code', undefined, A);
  check('sugiere un código', /^[A-Z0-9]{6}$/.test(suggested.data?.code ?? ''), suggested.data);
  const min = (await coupon({ code: `MIN-${tag}`, type: 'AMOUNT', value: 5, minOrderTotal: 10000 })).data;
  const old = (await coupon({ code: `OLD-${tag}`, type: 'AMOUNT', value: 5, startsAt: '2020-01-01T00:00:00Z', endsAt: '2020-02-01T00:00:00Z' })).data;
  const paused = (await coupon({ code: `OFF-${tag}`, type: 'AMOUNT', value: 5, isActive: false })).data;
  const once = (await coupon({ code: `UNO-${tag}`, type: 'AMOUNT', value: 1, maxUses: 1 })).data;
  const perCustomer = (await coupon({ code: `CLI-${tag}`, type: 'AMOUNT', value: 1, maxUsesPerCustomer: 1 })).data;
  const ship = (await coupon({ code: `ENVIO-${tag}`, type: 'FREE_DELIVERY', appliesInStore: false })).data;
  check('lista los cupones con su estado', [old?.state, paused?.state].join() === 'EXPIRED,PAUSED', [old?.state, paused?.state]);

  console.log('\nEn la caja');
  const o1 = await takeout();
  const r1 = await apply(o1.bill.id, ` p10-${tag} `);
  const sub = n(r1.data?.subtotal);
  check('aplica el 10 % a la cuenta', r1.status === 200 && near(r1.data?.coupon?.amount, Math.round(sub * 10) / 100) && near(r1.data?.discountTotal, n(r1.data?.coupon?.amount)), r1.data?.coupon);
  check('un cupón por cuenta', (await apply(o1.bill.id, `MIN-${tag}`)).status === 409);
  const removed = await api('DELETE', `/billing/bills/${o1.bill.id}/coupon`, undefined, A);
  check('se puede quitar', removed.data?.coupon === null && n(removed.data?.discountTotal) === 0, removed.data?.coupon);
  const errors: [string, string, RegExp][] = [
    [`MIN-${tag}`, 'pide el mínimo de compra', /mínimo/],
    [`OLD-${tag}`, 'un cupón vencido no aplica', /venció/],
    [`OFF-${tag}`, 'un cupón pausado no aplica', /activo/],
    [`ENVIO-${tag}`, 'el envío gratis no aplica en la caja', /línea/],
    [`NOEXISTE-${tag}`, 'un código que no existe avisa', /no existe/],
  ];
  for (const [code, name, re] of errors) {
    const r = await apply(o1.bill.id, code);
    check(name, r.status === 400 && re.test(r.data?.message ?? ''), r.data);
  }

  const o2 = await takeout();
  const o3 = await takeout();
  check('cupón de un solo uso: el primero entra', (await apply(o2.bill.id, once.code)).status === 200);
  const soldOut = await apply(o3.bill.id, once.code);
  check('el segundo ya no (agotado)', soldOut.status === 400 && /agotó/.test(soldOut.data?.message ?? ''), soldOut.data);
  await api('POST', `/orders/${o2.id}/cancel`, { reason: 'Prueba de cupones' }, A);
  check('si el pedido se cancela, el cupón vuelve a estar libre', (await apply(o3.bill.id, once.code)).status === 200);

  const noClient = await apply(o1.bill.id, perCustomer.code);
  check('uno por cliente: pide identificar al cliente', noClient.status === 400 && /cliente/i.test(noClient.data?.message ?? ''), noClient.data);
  const phone = `305555${String(randomInt(0, 10_000)).padStart(4, '0')}`;
  const client = (await api('POST', '/customers', { name: 'Prueba Cupón', phone }, A)).data?.customer;
  await api('PATCH', `/billing/bills/${o1.bill.id}/customer`, { customerId: client?.id }, A);
  check('con el cliente identificado, entra', (await apply(o1.bill.id, perCustomer.code)).status === 200);
  const o4 = await takeout();
  await api('PATCH', `/billing/bills/${o4.bill.id}/customer`, { customerId: client?.id }, A);
  const again = await apply(o4.bill.id, perCustomer.code);
  check('el mismo cliente no lo usa dos veces', again.status === 400 && /usaste/.test(again.data?.message ?? ''), again.data);

  console.log('\nEn una mesa (el % se recalcula con cada ronda)');
  const area = (await api('POST', '/tables/areas', { name: `Prueba cupones ${tag}` }, A)).data;
  const table = (await api('POST', '/tables', { label: `C${tag}`, areaId: area.id, seats: 2 }, A)).data;
  const t1 = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId: table.id, items }, A)).data;
  orders.push(t1.id);
  const first = await apply(t1.bill.id, pct.data.code);
  const t2 = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId: table.id, items }, A)).data;
  orders.push(t2.id);
  const bill = (await api('GET', `/billing/bills/${t1.bill.id}`, undefined, A)).data;
  check('otra ronda: el 10 % se recalcula', first.status === 200 && near(bill?.coupon?.amount, Math.round(n(bill?.subtotal) * 10) / 100) && n(bill?.coupon?.amount) > n(first.data?.coupon?.amount), {
    antes: first.data?.coupon?.amount,
    despues: bill?.coupon?.amount,
    subtotal: bill?.subtotal,
  });

  console.log('\nEn la web');
  const onlineMenu = (await api('GET', '/menu?channel=online')).data;
  const webProduct = (onlineMenu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  if (webProduct) {
    const webOptions: string[] = [];
    for (const g of webProduct.modifierGroups ?? []) webOptions.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
    const webItems = [{ productId: webProduct.id, quantity: 2, optionIds: webOptions }];
    const q = await api('POST', '/online/quote', { fulfillmentType: 'PICKUP', items: webItems, couponCode: pct.data.code });
    check('la cotización aplica el cupón', q.status === 200 && n(q.data?.coupon?.amount) > 0 && near(n(q.data?.totals?.discountTotal), n(q.data?.coupon?.amount) + (q.data?.promotions ?? []).reduce((s: number, p: Json) => s + n(p.amount), 0)), q.data?.coupon);
    const bad = await api('POST', '/online/quote', { fulfillmentType: 'PICKUP', items: webItems, couponCode: `OLD-${tag}` });
    check('un cupón inválido no rompe la cotización: explica por qué', bad.status === 200 && /venció/.test(bad.data?.couponError ?? '') && !bad.data?.coupon, bad.data?.couponError);
    const pickupShip = await api('POST', '/online/quote', { fulfillmentType: 'PICKUP', items: webItems, couponCode: ship.code });
    check('envío gratis en Pickup: pide elegir Delivery', /Delivery/.test(pickupShip.data?.couponError ?? ''), pickupShip.data?.couponError);
    const config = (await api('GET', '/online/config')).data;
    if (config?.channels?.delivery && n(config?.delivery?.fee) > 0) {
      const d = await api('POST', '/online/quote', { fulfillmentType: 'DELIVERY', items: webItems, couponCode: ship.code });
      check('envío gratis en Delivery: el envío queda en $0', d.data?.coupon?.freeDelivery === true && n(d.data?.totals?.deliveryFee) === 0, d.data?.totals);
    }
  } else {
    console.log('  ⚠ No hay productos visibles en la web: se omite.');
  }

  console.log('\nBorrar');
  const used = await api('DELETE', `/coupons/${once.id}`, undefined, A);
  check('un cupón usado no se borra (se pausa)', used.status === 409, used.data);
  check('un cupón sin usar se borra', (await api('DELETE', `/coupons/${min.id}`, undefined, A)).status === 204);
  const list = (await api('GET', '/coupons', undefined, A)).data as Json[];
  check('la lista cuenta los usos', list.find((c) => c.id === once.id)?.uses === 1, list.find((c) => c.id === once.id));

  // Limpieza: cancelar pedidos, cerrar la mesa y pausar los cupones de prueba.
  for (const id of orders) await api('POST', `/orders/${id}/cancel`, { reason: 'Prueba de cupones' }, A);
  await api('POST', `/tables/${table.id}/close`, { force: true }, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  for (const c of list.filter((x) => x.code.endsWith(`-${tag}`))) {
    if ((await api('DELETE', `/coupons/${c.id}`, undefined, A)).status === 409) {
      await api('PATCH', `/coupons/${c.id}`, {
        code: c.code,
        name: c.name,
        type: c.type,
        value: c.value === null ? null : n(c.value),
        appliesOnline: c.appliesOnline,
        appliesInStore: c.appliesInStore,
        isActive: false,
      }, A);
    }
  }

  console.log(failures ? `\n❌ ${failures} prueba(s) fallaron\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
