/**
 * Prueba de humo del lector de tarjetas (Stripe Terminal) con el lector SIMULADO de Stripe.
 * Uso:  npm run smoke:terminal   (backend encendido, claves sk_test_ y dirección del restaurante en Ajustes)
 *
 * Registra (una sola vez) "Lector de prueba", cobra una mesa con propina en el lector, prueba
 * una tarjeta rechazada y una cancelación. Deja el lector de prueba registrado para usarlo en la app.
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
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

/** Consulta el cobro hasta que termine (o 25 s). */
async function waitFor(paymentId: string, A: string) {
  for (let i = 0; i < 25; i++) {
    const s = (await api('GET', `/billing/terminal/${paymentId}`, undefined, A)).data;
    if (s?.status !== 'waiting') return s;
    await sleep(1000);
  }
  return { status: 'timeout' };
}

async function main() {
  console.log(`\nPrueba del lector de tarjetas → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const config = (await api('GET', '/terminal/config', undefined, A)).data;
  if (!config?.testMode) {
    console.log('✗ Esta prueba necesita STRIPE_SECRET_KEY de PRUEBA (sk_test_) en .env.');
    process.exit(1);
  }

  console.log('Lector');
  let readers = await api('GET', '/terminal/readers', undefined, A);
  if (readers.status === 400) {
    console.log(`✗ ${readers.data?.message}`);
    process.exit(1);
  }
  check('se conecta con Stripe Terminal', readers.status === 200, readers.data);
  let reader = (readers.data as Json[]).find((r) => r.simulated);
  if (!reader) {
    const created = await api('POST', '/terminal/readers', { registrationCode: 'simulated-s700', label: 'Lector de prueba' }, A);
    check('se registra el lector de prueba (S700 simulado)', created.status === 201, created.data);
    readers = await api('GET', '/terminal/readers', undefined, A);
    reader = (readers.data as Json[]).find((r) => r.simulated);
  } else {
    console.log('  (el lector de prueba ya estaba registrado)');
  }
  check('el lector aparece en la lista', !!reader, readers.data);
  if (!reader) return summary();

  // Limpieza de una corrida anterior.
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  console.log('\nCuenta');
  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const table = (await api('POST', '/tables', { label: 'T1', areaId: area.id, seats: 2 }, A)).data;
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds = (product?.modifierGroups ?? []).flatMap((g: Json) => (g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const order = await api('POST', '/orders', {
    clientRequestId: rid(),
    fulfillmentType: 'DINE_IN',
    tableId: table.id,
    items: [{ productId: product.id, quantity: 2, optionIds }],
  }, A);
  check('pedido en la mesa T1', order.status === 201, order.data);
  const bill = (await api('GET', `/billing/bills?tableId=${table.id}`, undefined, A)).data[0];
  const due = n(bill.due);
  const half = Math.round((due / 2) * 100) / 100;

  console.log('\nTarjeta rechazada');
  const declinedReq = { clientRequestId: rid(), readerId: reader.id, amount: half };
  const declined = await api('POST', `/billing/bills/${bill.id}/terminal`, declinedReq, A);
  check('el monto llega al lector', declined.status === 201 && declined.data?.status === 'waiting', declined.data);
  await api('POST', `/billing/terminal/${declined.data.paymentId}/simulate`, { declined: true }, A);
  const declinedEnd = await waitFor(declined.data.paymentId, A);
  check('una tarjeta rechazada se informa y no se cobra', declinedEnd.status === 'failed', declinedEnd);

  console.log('\nCancelar');
  const toCancel = await api('POST', `/billing/bills/${bill.id}/terminal`, { clientRequestId: rid(), readerId: reader.id, amount: half }, A);
  const cancelled = await api('POST', `/billing/terminal/${toCancel.data.paymentId}/cancel`, undefined, A);
  check('la caja puede cancelar el cobro en el lector', cancelled.data?.status === 'cancelled', cancelled.data);

  console.log('\nCobro con propina en el lector');
  const firstReq = { clientRequestId: rid(), readerId: reader.id, amount: half, tipOnReader: true };
  const first = await api('POST', `/billing/bills/${bill.id}/terminal`, firstReq, A);
  const repeat = await api('POST', `/billing/bills/${bill.id}/terminal`, firstReq, A);
  check('si se reenvía, es el mismo cobro', repeat.data?.paymentId === first.data?.paymentId, [first.data, repeat.data]);
  await api('POST', `/billing/terminal/${first.data.paymentId}/simulate`, { tip: 3 }, A);
  const firstEnd = await waitFor(first.data.paymentId, A);
  check('el cliente paga con la tarjeta y se aprueba', firstEnd.status === 'succeeded', firstEnd);
  check('la propina elegida en el lector se suma', n(firstEnd.tip) === 3 && n(firstEnd.bill?.tipTotal) === 3, firstEnd);
  const lastPay = (firstEnd.bill?.payments as Json[] | undefined)?.find((p) => p.status === 'SUCCEEDED');
  check('queda anotada la tarjeta (marca y últimos 4)', /••••/.test(String(lastPay?.reference)), lastPay);
  check('la cuenta queda con pago parcial', firstEnd.bill?.status === 'PARTIALLY_PAID', firstEnd.bill?.status);

  for (const t of order.data.tickets) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${order.data.id}/complete`, undefined, A);

  const rest = n(firstEnd.bill.due);
  const second = await api('POST', `/billing/bills/${bill.id}/terminal`, { clientRequestId: rid(), readerId: reader.id, amount: rest, tipOnReader: false }, A);
  await api('POST', `/billing/terminal/${second.data.paymentId}/simulate`, {}, A);
  const secondEnd = await waitFor(second.data.paymentId, A);
  check('se cobra el resto sin propina', secondEnd.status === 'succeeded' && secondEnd.bill?.status === 'PAID', secondEnd);
  const tableNow = (await api('GET', `/tables/${table.id}`, undefined, A)).data;
  check('pagada con tarjeta: la mesa se libera sola', tableNow.status === 'CLEANING', tableNow.status);

  console.log('\nLimpieza');
  await api('PATCH', `/tables/${table.id}/status`, { status: 'AVAILABLE' }, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se quita la mesa de prueba (el lector de prueba se queda para la app)', gone.status === 200, gone.data);
  summary();
}

function summary() {
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
