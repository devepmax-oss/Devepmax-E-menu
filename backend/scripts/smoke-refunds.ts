/**
 * Prueba de humo de órdenes manuales, recibos y reembolsos.
 * Uso:  npm run smoke:refunds   (backend encendido, claves sk_test_ en .env)
 *
 * Hace una orden de mostrador pagada en efectivo y una de mesa pagada con tarjeta de prueba;
 * revisa el recibo digital y reembolsa parte y luego todo. Si la caja estaba cerrada, la abre
 * para la prueba y la cierra al final. Elimina la mesa y el área de prueba.
 */
import { randomUUID } from 'node:crypto';
import Stripe from 'stripe';
import { signTablePay } from '../src/common/pay-token';

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

async function main() {
  console.log(`\nPrueba de órdenes manuales, recibos y reembolsos → ${BASE}\n`);
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
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  let openedShift = false;
  if (!(await api('GET', '/cash/shift', undefined, A)).data?.shift) {
    await api('POST', '/cash/shift/open', { openingCash: 100 }, A);
    openedShift = true;
  }
  const shiftBefore = (await api('GET', '/cash/shift', undefined, A)).data.shift;

  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 2, optionIds, notes: 'Bien dorado' }];
  const finish = async (order: Json) => {
    for (const t of order.tickets ?? []) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
    await api('POST', `/orders/${order.id}/complete`, undefined, A);
  };

  console.log('Orden de mostrador (comer aquí, sin mesa)');
  const counter = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', customerName: 'Ana', items }, A);
  check('la caja crea una orden de mostrador sin elegir mesa', counter.status === 201 && counter.data?.channel === 'POS' && counter.data?.table === null, counter.data);
  const takeout = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', customerName: 'Luis', customerPhone: '3055551234', items }, A);
  check('y una para llevar', takeout.status === 201 && takeout.data?.fulfillmentType === 'TAKEOUT', takeout.data);
  await api('POST', `/orders/${takeout.data.id}/cancel`, { reason: 'Prueba automática' }, A);
  const counterBill = (await api('GET', `/billing/bills/${counter.data.bill.id}`, undefined, A)).data;
  check('su cuenta aparece como mostrador', counterBill?.kind === 'COUNTER', counterBill?.kind);
  console.log('\nCuenta antes de pagar');
  const check0 = await api('GET', `/billing/bills/${counterBill.id}/check`, undefined, A);
  check('se puede imprimir la cuenta antes de pagar', check0.status === 200 && near(check0.data?.total, n(counterBill.total)) && Array.isArray(check0.data?.tips), check0.data);
  check('en mostrador la cuenta no trae QR de pago de mesa', check0.data?.payUrl === null, check0.data?.payUrl);
  const early = await api('GET', `/billing/bills/${counterBill.id}/receipt`, undefined, A);
  check('sin cobrar no hay recibo', early.status === 409, early.data);
  const earlySend = await api('POST', `/billing/bills/${counterBill.id}/receipt`, { email: 'cliente@example.com' }, A);
  check('ni se puede enviar un recibo', earlySend.status === 409, earlySend.data);
  const cashPaid = await api('POST', `/billing/bills/${counterBill.id}/payments`, { clientRequestId: rid(), method: 'CASH', amount: n(counterBill.due), cashTendered: Math.ceil(n(counterBill.due)) + 20 }, A);
  check('se cobra en efectivo', cashPaid.data?.status === 'PAID', cashPaid.data);
  const cashPayment = cashPaid.data.payments.find((p: Json) => p.method === 'CASH');

  console.log('\nRecibo digital');
  const receipt = await api('GET', `/billing/bills/${counterBill.id}/receipt`, undefined, A);
  const token = String(receipt.data?.url ?? '').split('/recibo/')[1] ?? '';
  check('la caja obtiene el recibo y su enlace', receipt.status === 200 && token.length > 20 && near(receipt.data?.total, n(counterBill.total)), receipt.data);
  const pub = await api('GET', `/receipts/${token}`);
  check('el cliente abre el recibo sin iniciar sesión', pub.status === 200 && near(pub.data?.total, n(counterBill.total)) && pub.data?.items?.[0]?.quantity === 2, pub.data);
  check('el recibo muestra el pago y el cambio', pub.data?.payments?.[0]?.method === 'Efectivo' && n(pub.data?.payments?.[0]?.changeGiven) > 0, pub.data?.payments);
  check('el recibo no trae datos del personal', !JSON.stringify(pub.data).includes('employee'));
  const fake = await api('GET', `/receipts/${token.split('.')[0]}.AAAAAAAAAAAAAAAAAAAAAA`);
  check('un enlace alterado no abre ningún recibo', fake.status === 404, fake.status);
  const config = (await api('GET', '/billing/receipts/config', undefined, A)).data;
  check('la caja sabe si hay email y SMS configurados', typeof config?.email === 'boolean' && typeof config?.sms === 'boolean', config);
  const empty = await api('POST', `/billing/bills/${counterBill.id}/receipt`, {}, A);
  check('enviar sin email ni teléfono avisa', empty.status === 400, empty.data);

  console.log('\nReembolso en efectivo');
  const tooMuch = await api('POST', `/billing/payments/${cashPayment.id}/refunds`, { clientRequestId: rid(), amount: n(cashPayment.amount) + 5, reason: 'Prueba' }, A);
  check('no deja devolver más de lo cobrado', tooMuch.status === 400, tooMuch.data);
  const reqId = rid();
  const partial = await api('POST', `/billing/payments/${cashPayment.id}/refunds`, { clientRequestId: reqId, amount: 1, reason: 'Llegó frío' }, A);
  check('devuelve $1 en efectivo', partial.status === 201 && near(partial.data?.refundedTotal, 1) && partial.data?.status === 'PAID', partial.data);
  const again = await api('POST', `/billing/payments/${cashPayment.id}/refunds`, { clientRequestId: reqId, amount: 1, reason: 'Llegó frío' }, A);
  check('un doble toque no devuelve dos veces', near(again.data?.refundedTotal, 1), again.data?.refundedTotal);
  const shiftAfter = (await api('GET', '/cash/shift', undefined, A)).data.shift;
  check('la caja espera $1 menos de efectivo y lo muestra como reembolso', near(n(shiftBefore.expectedCash) + n(counterBill.total) - 1, n(shiftAfter.expectedCash)) && n(shiftAfter.totalRefunds) >= 1, shiftAfter);
  const rest = await api('POST', `/billing/payments/${cashPayment.id}/refunds`, { clientRequestId: rid(), reason: 'Cliente se fue' }, A);
  check('sin monto devuelve el resto y la cuenta queda reembolsada', rest.data?.status === 'REFUNDED' && near(rest.data?.refundedTotal, n(cashPayment.amount)), rest.data);
  const done = await api('POST', `/billing/payments/${cashPayment.id}/refunds`, { clientRequestId: rid(), reason: 'Otra vez' }, A);
  check('ya no se puede reembolsar más', done.status === 409, done.data);
  await finish(counter.data);

  console.log('\nOrden de mesa, pagada con tarjeta, y reembolso a la tarjeta');
  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const table = (await api('POST', '/tables', { label: 'R1', areaId: area.id, seats: 2 }, A)).data;
  const tableOrder = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId: table.id, items }, A);
  check('la caja le pone una orden a una mesa sin tablet', tableOrder.status === 201 && tableOrder.data?.table?.label === 'R1', tableOrder.data);
  const tableBill = (await api('GET', `/billing/bills?tableId=${table.id}`, undefined, A)).data?.[0];
  const tableCheck = (await api('GET', `/billing/bills/${tableBill.id}/check`, undefined, A)).data;
  check('la cuenta de una mesa trae el QR para pagar con el celular', String(tableCheck?.payUrl).includes('/cuenta/'), tableCheck?.payUrl);
  const payToken = signTablePay(tableBill.session.id, process.env.JWT_ACCESS_SECRET ?? '');
  const intent = (await api('POST', `/pay/${payToken}/intent`, { clientRequestId: rid(), billId: tableBill.id, amount: n(tableBill.due), tip: 3 })).data;
  const piId = String(intent?.clientSecret ?? '').split('_secret_')[0];
  await stripe.paymentIntents.confirm(piId, { payment_method: 'pm_card_visa', return_url: 'https://example.com' });
  await api('POST', `/pay/${payToken}/confirm`, { paymentIntentId: piId });
  await finish(tableOrder.data);
  const paidTable = (await api('GET', `/billing/bills/${tableBill.id}`, undefined, A)).data;
  check('la mesa quedó pagada con tarjeta', paidTable?.status === 'PAID', paidTable?.status);
  const card = paidTable.payments.find((p: Json) => p.status === 'SUCCEEDED');
  const cardRefund = await api('POST', `/billing/payments/${card.id}/refunds`, { clientRequestId: rid(), amount: 2, reason: 'Error en la propina' }, A);
  check('devuelve $2 a la tarjeta', cardRefund.status === 201 && near(cardRefund.data?.refundedTotal, 2), cardRefund.data);
  const refunds = await stripe.refunds.list({ payment_intent: piId });
  check('Stripe tiene el reembolso', refunds.data.length === 1 && refunds.data[0].amount === 200, refunds.data.map((r) => r.amount));
  const paidToday = (await api('GET', '/billing/bills?scope=paid', undefined, A)).data as Json[];
  check('las dos cuentas aparecen en "Pagadas hoy"', paidToday.some((b) => b.id === counterBill.id) && paidToday.some((b) => b.id === tableBill.id), paidToday.length);

  console.log('\nLimpieza');
  await api('POST', `/tables/${table.id}/close`, { force: true }, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se eliminan la mesa y el área de prueba', gone.status === 200, gone.data);
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
