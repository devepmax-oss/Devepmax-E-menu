/**
 * Prueba de humo del cierre del día: hace una venta con descuento, propina y un reembolso, y
 * cancela otra orden; revisa que el reporte de hoy lo refleje.
 * Uso:  npm run smoke:report   (backend encendido y seed hecho)
 *
 * Si la caja estaba cerrada, la abre para la prueba y la cierra al final.
 */
import { randomUUID } from 'node:crypto';

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

async function api(method: string, path: string, body?: unknown, token = ''): Promise<{ status: number; data: any }> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, data: text ? JSON.parse(text) : null };
}

function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`  ✓ ${name}`);
  else {
    failures++;
    console.log(`  ✗ ${name}`);
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 400));
  }
}

const method = (r: Json, m: string) => (r.payments as Json[]).find((p) => p.method === m) ?? { count: 0, amount: 0, tips: 0, refunded: 0 };

async function main() {
  console.log(`\nPrueba del cierre del día → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  let openedShift = false;
  if (!(await api('GET', '/cash/shift', undefined, A)).data?.shift) {
    await api('POST', '/cash/shift/open', { openingCash: 100 }, A);
    openedShift = true;
  }

  console.log('Antes');
  const before = await api('GET', '/reports/day', undefined, A);
  check('el reporte de hoy abre', before.status === 200 && typeof before.data?.summary?.orders === 'number', before.data);
  const b = before.data;
  const bad = await api('GET', '/reports/day?date=24-11-2026', undefined, A);
  check('una fecha mal escrita avisa', bad.status === 400, bad.status);
  const old = await api('GET', '/reports/day?date=2001-01-01', undefined, A);
  check('un día sin ventas sale en cero', old.data?.summary?.orders === 0 && n(old.data?.summary?.collected) === 0, old.data?.summary);

  console.log('\nVentas del día');
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 3, optionIds }];

  const sale = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', customerName: 'Reporte', items }, A)).data;
  const discounted = (await api('POST', `/billing/bills/${sale.bill.id}/discounts`, { type: 'AMOUNT', value: 1, reason: 'Prueba de reporte' }, A)).data;
  const tip = 2.5;
  const paid = (await api('POST', `/billing/bills/${sale.bill.id}/payments`, { clientRequestId: rid(), method: 'CASH', amount: n(discounted.due), tip, cashTendered: n(discounted.due) + tip + 10 }, A)).data;
  const cash = paid.payments.find((p: Json) => p.method === 'CASH');
  await api('POST', `/billing/payments/${cash.id}/refunds`, { clientRequestId: rid(), amount: 1, reason: 'Reembolso de reporte' }, A);
  const dropped = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items }, A)).data;
  await api('POST', `/orders/${dropped.id}/cancel`, { reason: 'Cancelada para el reporte' }, A);
  for (const t of sale.tickets ?? []) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${sale.id}/complete`, undefined, A);

  const after = (await api('GET', '/reports/day', undefined, A)).data;
  const s0 = b.summary, s1 = after.summary;
  check('cuenta la orden vendida y la cancelada aparte', s1.orders === s0.orders + 1 && s1.cancelledOrders === s0.cancelledOrders + 1, { s0, s1 });
  check('ventas netas = subtotal − descuentos', near(n(s1.netSales) - n(s0.netSales), n(paid.subtotal) - n(paid.discountTotal)), { s0: s0.netSales, s1: s1.netSales });
  check('suma el descuento y el impuesto', near(n(s1.discounts) - n(s0.discounts), 1) && near(n(s1.tax) - n(s0.tax), n(paid.taxTotal)));
  check('suma la propina', near(n(s1.tips) - n(s0.tips), tip));
  check('lo cobrado incluye la propina', near(n(s1.collected) - n(s0.collected), n(cash.amount)));
  check('resta el reembolso', near(n(s1.refunded) - n(s0.refunded), 1) && near(n(s1.netCollected) - n(s0.netCollected), n(cash.amount) - 1));
  const m0 = method(b, 'CASH'), m1 = method(after, 'CASH');
  check('efectivo: un cobro más, con su propina y su reembolso', m1.count === m0.count + 1 && near(n(m1.tips) - n(m0.tips), tip) && near(n(m1.refunded) - n(m0.refunded), 1), { m0, m1 });
  const p0 = (b.products as Json[]).find((p) => p.name === product.name)?.quantity ?? 0;
  const p1 = (after.products as Json[]).find((p) => p.name === product.name)?.quantity ?? 0;
  check('el producto suma 3 vendidos (la cancelada no cuenta)', p1 === p0 + 3, { p0, p1 });
  check('la caja aparece en "quién cobró"', (after.cashiers as Json[]).some((c) => c.name && n(c.amount) > 0));
  check('el descuento manual aparece con quién lo hizo', (after.discounts as Json[]).some((d) => d.reason === 'Prueba de reporte' && d.appliedBy !== '—'));
  check('el reembolso aparece con su motivo', (after.refunds as Json[]).some((r) => r.reason === 'Reembolso de reporte' && r.method === 'CASH'));
  check('la cancelación aparece con su motivo', (after.cancellations as Json[]).some((c) => c.number === dropped.number && c.reason === 'Cancelada para el reporte'));
  check('para llevar suma una orden', (after.fulfillment as Json[]).find((f) => f.type === 'TAKEOUT')?.orders === ((b.fulfillment as Json[]).find((f) => f.type === 'TAKEOUT')?.orders ?? 0) + 1);
  check('la venta aparece en su hora', (after.hours as Json[]).reduce((a, h) => a + h.orders, 0) === s1.orders);
  check('trae el turno de caja de hoy', (after.shifts as Json[]).length >= 1, after.shifts?.length);

  if (openedShift) {
    const s = (await api('GET', '/cash/shift', undefined, A)).data.shift;
    await api('POST', '/cash/shift/close', { countedCash: n(s.expectedCash), notes: 'Prueba automática' }, A);
  }
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
