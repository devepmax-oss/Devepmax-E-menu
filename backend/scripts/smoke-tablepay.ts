/**
 * Prueba de humo de "pagar desde la mesa con el celular" (QR de la tablet), con tarjetas de
 * prueba de Stripe. Uso:  npm run smoke:tablepay   (backend encendido, claves sk_test_ en .env)
 *
 * Crea un área "Prueba automática" con la mesa Q1 y una tablet; pide desde la tablet, paga la
 * mitad con propina, prueba una tarjeta rechazada, paga el resto y la mesa se libera sola.
 * Al final elimina la tablet, la mesa y el área.
 */
import { randomUUID } from 'node:crypto';
import { io, Socket } from 'socket.io-client';
import Stripe from 'stripe';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const ORIGIN = `http://localhost:${process.env.PORT ?? 3000}`;
const BASE = `${ORIGIN}/api/v1`;
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

function listen(socket: Socket | null, event: string) {
  const got: Json[] = [];
  socket?.on(event, (d: Json) => got.push(d));
  return got;
}

async function connect(auth: Json): Promise<Socket | null> {
  const socket = io(ORIGIN, { auth, transports: ['websocket'], reconnection: false });
  const ok = await new Promise<boolean>((resolve) => {
    socket.on('ready', () => resolve(true));
    socket.on('connect_error', () => resolve(false));
    setTimeout(() => resolve(false), 4000);
  });
  return ok ? socket : null;
}

/** Lo que hace el celular del cliente al tocar "Pagar" (aquí, con una tarjeta de prueba). */
async function payOnPhone(stripe: Stripe, clientSecret: string, card: string) {
  const id = clientSecret.split('_secret_')[0];
  try {
    const intent = await stripe.paymentIntents.confirm(id, { payment_method: card, return_url: 'https://example.com/pagado' });
    return { id, status: intent.status };
  } catch (error) {
    return { id, status: 'declined', message: (error as Error).message };
  }
}

async function main() {
  console.log(`\nPrueba de pagar desde la mesa con el celular → ${BASE}\n`);
  const key = process.env.STRIPE_SECRET_KEY ?? '';
  if (!key.startsWith('sk_test_')) {
    console.log('✗ Esta prueba necesita las claves de prueba de Stripe (sk_test_) en backend/.env');
    process.exit(1);
  }
  const stripe = new Stripe(key);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;

  // Limpieza de una corrida anterior que se haya cortado.
  for (const d of ((await api('GET', '/devices', undefined, A)).data as Json[]).filter((d) => d.name === 'Tablet QR de prueba')) {
    await api('DELETE', `/devices/${d.id}`, undefined, A);
  }
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  console.log('Preparar la mesa');
  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const table = (await api('POST', '/tables', { label: 'Q1', areaId: area.id, seats: 4 }, A)).data;
  const device = (await api('POST', '/devices', { name: 'Tablet QR de prueba', type: 'EMENU', tableId: table.id }, A)).data;
  const T = (await api('POST', '/auth/device/pair', { code: device.pairingCode, appVersion: 'smoke' })).data.deviceToken as string;
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, T)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const order = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', items: [{ productId: product.id, quantity: 3, optionIds }] }, T)).data;
  if (order?.status === 'PENDING_APPROVAL') await api('POST', `/orders/${order.id}/approve`, undefined, A);
  const tablet = await connect({ token: T });
  const tabletBills = listen(tablet, 'bill.updated');

  const mesa = (await api('GET', '/emenu/table', undefined, T)).data;
  const payUrl = mesa?.session?.payUrl as string | null;
  check('la tablet recibe el enlace del QR de pago', typeof payUrl === 'string' && payUrl.includes('/cuenta/'), mesa?.session);
  const token = String(payUrl ?? '').split('/cuenta/')[1] ?? '';

  console.log('\nEl cliente abre la cuenta en su celular');
  const view = await api('GET', `/pay/${token}`);
  const bill = view.data?.bills?.[0];
  check('ve su mesa y la cuenta, lista para pagar', view.status === 200 && view.data?.table === 'Q1' && view.data?.payable === true && n(bill?.due) > 0, view.data);
  check('ve lo que pidió', bill?.items?.[0]?.quantity === 3, bill?.items);
  check('no ve datos del personal', !JSON.stringify(view.data).includes('employee'));
  const fake = await api('GET', `/pay/${token.split('.')[0]}.AAAAAAAAAAAAAAAAAAAAAA`);
  check('un enlace alterado no abre ninguna cuenta', fake.status === 404, fake.status);
  const due = n(bill.due);

  console.log('\nPagar la mitad con propina');
  const tooMuch = await api('POST', `/pay/${token}/intent`, { clientRequestId: rid(), billId: bill.id, amount: due + 5 });
  check('no deja pagar más de lo que se debe', tooMuch.status === 400, tooMuch.data);
  const half = Math.round((due / 2) * 100) / 100;
  const tip = Math.round(half * 0.18 * 100) / 100;
  const req = rid();
  const intent = await api('POST', `/pay/${token}/intent`, { clientRequestId: req, billId: bill.id, amount: half, tip, email: 'cliente@example.com' });
  check('se prepara el pago de su parte', intent.status === 200 && String(intent.data?.clientSecret).includes('_secret_'), intent.data);
  const retry = await api('POST', `/pay/${token}/intent`, { clientRequestId: req, billId: bill.id, amount: half, tip });
  check('si la red falla y reintenta, es el mismo pago', retry.data?.paymentId === intent.data?.paymentId);
  const paid = await payOnPhone(stripe, intent.data.clientSecret, 'pm_card_visa');
  check('paga con la tarjeta de prueba Visa', paid.status === 'succeeded', paid);
  const confirmed = await api('POST', `/pay/${token}/confirm`, { paymentIntentId: paid.id });
  const after = confirmed.data?.view?.bills?.[0];
  check('la cuenta baja a lo que falta', confirmed.data?.status === 'succeeded' && Math.abs(n(after?.due) - (due - half)) < 0.011, confirmed.data);
  check('la propina queda en la cuenta', Math.abs(n(after?.tipTotal) - tip) < 0.011, after);
  const twice = await api('POST', `/pay/${token}/confirm`, { paymentIntentId: paid.id });
  check('confirmar dos veces no lo cuenta doble', Math.abs(n(twice.data?.view?.bills?.[0]?.due) - (due - half)) < 0.011);
  await sleep(600);
  check('la tablet se entera en vivo', tabletBills.some((b) => b.id === bill.id), tabletBills.length);
  const staffBill = (await api('GET', `/billing/bills/${bill.id}`, undefined, A)).data;
  const qr = (staffBill?.payments ?? []).find((p: Json) => p.method === 'CARD_QR' && p.status === 'SUCCEEDED');
  check('la caja lo ve como "QR en la mesa" con la tarjeta', !!qr && String(qr.reference).includes('4242'), staffBill?.payments);

  console.log('\nTarjeta rechazada');
  const second = await api('POST', `/pay/${token}/intent`, { clientRequestId: rid(), billId: bill.id, amount: n(after.due) });
  const declined = await payOnPhone(stripe, second.data.clientSecret, 'pm_card_chargeDeclined');
  check('el banco la rechaza', declined.status === 'declined', declined);
  const stillDue = await api('POST', `/pay/${token}/confirm`, { paymentIntentId: declined.id });
  check('no se cobra nada y sigue debiendo lo mismo', stillDue.data?.status === 'pending' && Math.abs(n(stillDue.data?.view?.bills?.[0]?.due) - n(after.due)) < 0.011, stillDue.data);

  console.log('\nPagar el resto: la mesa se libera sola');
  for (const t of order.tickets ?? []) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${order.id}/complete`, undefined, A);
  const rest = await api('POST', `/pay/${token}/intent`, { clientRequestId: rid(), billId: bill.id, amount: n(after.due) });
  const restPaid = await payOnPhone(stripe, rest.data.clientSecret, 'pm_card_mastercard');
  const final = await api('POST', `/pay/${token}/confirm`, { paymentIntentId: restPaid.id });
  check('la cuenta queda pagada', final.data?.view?.bills?.[0]?.status === 'PAID' && n(final.data?.view?.bills?.[0]?.due) === 0, final.data?.view);
  await sleep(600);
  const free = (await api('GET', '/emenu/table', undefined, T)).data;
  check('la mesa se libera y la tablet vuelve a la bienvenida', free?.session === null, free);
  const reopened = await api('GET', `/pay/${token}`);
  check('si el cliente recarga, ve "pagada" (ya no se puede pagar)', reopened.data?.closed === true && reopened.data?.payable === false, reopened.data);
  const late = await api('POST', `/pay/${token}/intent`, { clientRequestId: rid(), billId: bill.id, amount: 1 });
  check('con la mesa cerrada no se crean pagos nuevos', late.status === 409, late.data);

  console.log('\nLimpieza');
  await api('POST', `/devices/${device.id}/revoke`, undefined, A);
  await api('DELETE', `/devices/${device.id}`, undefined, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se eliminan la tablet, la mesa y el área de prueba', gone.status === 200, gone.data);
  tablet?.close();
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
