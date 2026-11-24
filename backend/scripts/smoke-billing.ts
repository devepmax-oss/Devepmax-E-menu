/**
 * Prueba de humo de la caja: turno, cuentas, descuentos, dividir, pagos parciales,
 * efectivo con cambio, propina y mesa liberada al pagar.
 * Uso:  npm run smoke:billing   (backend encendido y seed hecho)
 *
 * Usa un área "Prueba automática" con la mesa C1 y al final la quita. Si ya hay una caja
 * abierta, la usa y la deja abierta; si no, abre una y la cierra al terminar.
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
  console.log(`\nPrueba de la caja → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;

  // Limpieza de una corrida anterior.
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  console.log('Mesa con pedido');
  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const table = (await api('POST', '/tables', { label: 'C1', areaId: area.id, seats: 4 }, A)).data;
  await api('POST', `/tables/${table.id}/open`, { guestCount: 2 }, A);
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const products = (menu?.categories ?? []).flatMap((c: Json) => c.products).filter((p: Json) => p.isAvailable !== false);
  const line = (p: Json, quantity: number) => ({
    productId: p.id,
    quantity,
    optionIds: (p.modifierGroups ?? []).flatMap((g: Json) => (g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id)),
  });
  const order = await api('POST', '/orders', {
    clientRequestId: rid(),
    fulfillmentType: 'DINE_IN',
    tableId: table.id,
    items: [line(products[0], 2), line(products[1] ?? products[0], 1)],
  }, A);
  check('se hace un pedido en la mesa C1', order.status === 201, order.data);
  if (order.status !== 201) return summary();

  let bills = (await api('GET', `/billing/bills?tableId=${table.id}`, undefined, A)).data as Json[];
  check('la caja ve la cuenta de la mesa', bills.length === 1 && bills[0].label === 'Mesa C1' && n(bills[0].due) === n(bills[0].total), bills);
  const open = (await api('GET', '/billing/bills', undefined, A)).data as Json[];
  check('aparece entre las cuentas por cobrar', open.some((b) => b.id === bills[0].id));
  const billId = bills[0].id as string;
  const total = n(bills[0].total);

  console.log('\nCaja');
  let shift = (await api('GET', '/cash/shift', undefined, A)).data.shift as Json | null;
  const openedHere = !shift;
  if (openedHere) {
    const cashNoShift = await api('POST', `/billing/bills/${billId}/payments`, { clientRequestId: rid(), method: 'CASH', amount: 1 }, A);
    check('sin caja abierta no se cobra en efectivo', cashNoShift.status === 409, cashNoShift.data);
    shift = (await api('POST', '/cash/shift/open', { openingCash: 100 }, A)).data;
    check('se abre la caja con $100', n(shift?.openingCash) === 100, shift);
  } else {
    console.log('  (ya había una caja abierta: se usa y se deja abierta)');
  }
  const cashBefore = n(shift?.expectedCash);

  console.log('\nDescuentos');
  const disc = await api('POST', `/billing/bills/${billId}/discounts`, { type: 'PERCENT', value: 10, reason: 'Cliente frecuente' }, A);
  check('10% de descuento baja el total', disc.status === 201 && n(disc.data?.total) < total && disc.data?.discounts?.length === 1, disc.data);
  const removed = await api('DELETE', `/billing/discounts/${disc.data.discounts[0].id}`, {}, A);
  check('se puede quitar el descuento', n(removed.data?.total) === total, removed.data);

  console.log('\nDividir');
  const items = disc.data.items as Json[];
  const split = await api('POST', `/billing/bills/${billId}/split`, { itemIds: [items[items.length - 1].id] }, A);
  check('se pasa un artículo a otra cuenta', split.status === 201 && split.data?.items?.length === 1, split.data);
  bills = (await api('GET', `/billing/bills?tableId=${table.id}`, undefined, A)).data;
  check('la mesa queda con dos cuentas que suman lo mismo', bills.length === 2 && Math.abs(bills.reduce((s, b) => s + n(b.total), 0) - total) < 0.02, bills.map((b) => b.total));
  const merged = await api('POST', `/billing/bills/${split.data.id}/merge`, { targetBillId: billId }, A);
  check('se pueden volver a juntar', n(merged.data?.total) === total, merged.data);
  const again = await api('POST', `/billing/bills/${billId}/split`, { itemIds: [items[items.length - 1].id] }, A);
  const billB = again.data.id as string;
  const billA = (await api('GET', `/billing/bills/${billId}`, undefined, A)).data;

  console.log('\nCobrar');
  const half = Math.round((n(billA.due) / 2) * 100) / 100;
  const cardReq = { clientRequestId: rid(), method: 'CARD_TERMINAL', amount: half, reference: '4242' };
  const card = await api('POST', `/billing/bills/${billId}/payments`, cardReq, A);
  check('se cobra una parte con tarjeta', card.status === 201 && card.data?.status === 'PARTIALLY_PAID', card.data);
  const twice = await api('POST', `/billing/bills/${billId}/payments`, cardReq, A);
  check('si se reenvía el mismo cobro, no se cobra dos veces', n(twice.data?.amountPaid) === half, twice.data?.amountPaid);
  const tooMuch = await api('POST', `/billing/bills/${billId}/payments`, { clientRequestId: rid(), method: 'OTHER', amount: n(billA.due) + 50 }, A);
  check('no se cobra más de lo que se debe', tooMuch.status === 400);
  const splitPaid = await api('POST', `/billing/bills/${billId}/split`, { itemIds: [billA.items[0].id] }, A);
  check('una cuenta con pagos ya no se divide', splitPaid.status === 409);

  // La comida sale antes de cobrar el resto, para que la mesa se libere sola.
  for (const t of order.data.tickets) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${order.data.id}/complete`, undefined, A);

  const rest = n(card.data.due);
  const cash = await api('POST', `/billing/bills/${billId}/payments`, {
    clientRequestId: rid(),
    method: 'CASH',
    amount: rest,
    tip: 2,
    cashTendered: Math.ceil(rest + 2) + 20,
  }, A);
  const lastCash = (cash.data?.payments as Json[] | undefined)?.at(-1);
  check('se cobra el resto en efectivo con propina', cash.data?.status === 'PAID' && n(cash.data?.tipTotal) === 2, cash.data);
  check('calcula el cambio', Math.abs(n(lastCash?.changeGiven) - (Math.ceil(rest + 2) + 20 - (rest + 2))) < 0.01, lastCash);
  let tableNow = (await api('GET', `/tables/${table.id}`, undefined, A)).data;
  check('con otra cuenta pendiente, la mesa sigue ocupada', tableNow.status === 'OCCUPIED', tableNow.status);

  const due = n((await api('GET', `/billing/bills/${billB}`, undefined, A)).data.due);
  const last = await api('POST', `/billing/bills/${billB}/payments`, { clientRequestId: rid(), method: 'OTHER', amount: due, reference: 'Zelle' }, A);
  check('se cobra la segunda cuenta', last.data?.status === 'PAID', last.data);
  tableNow = (await api('GET', `/tables/${table.id}`, undefined, A)).data;
  check('todo pagado: la mesa se libera (por limpiar)', tableNow.status === 'CLEANING' && tableNow.session === null, tableNow);
  const stillOpen = (await api('GET', '/billing/bills', undefined, A)).data as Json[];
  check('ya no aparece entre las cuentas por cobrar', !stillOpen.some((b) => b.id === billId || b.id === billB));

  console.log('\nCierre de caja');
  const now = (await api('GET', '/cash/shift', undefined, A)).data.shift;
  check('el efectivo esperado sube con lo cobrado en efectivo', Math.abs(n(now.expectedCash) - (cashBefore + rest + 2)) < 0.01, now);
  check('el turno separa ventas por forma de pago', ['CASH', 'CARD_TERMINAL'].every((m) => now.sales.some((s: Json) => s.method === m)), now.sales);
  const out = await api('POST', '/cash/shift/movements', { type: 'PAY_OUT', amount: 5, reason: 'Hielo' }, A);
  check('una salida de efectivo baja lo esperado', Math.abs(n(out.data?.expectedCash) - (n(now.expectedCash) - 5)) < 0.01, out.data);
  if (openedHere) {
    const closed = await api('POST', '/cash/shift/close', { countedCash: n(out.data.expectedCash) }, A);
    check('al cerrar, cuadra exacto', closed.data?.closedAt && n(closed.data?.difference) === 0, closed.data);
  } else {
    await api('POST', '/cash/shift/movements', { type: 'PAY_IN', amount: 5, reason: 'Devolución de la prueba' }, A);
  }

  console.log('\nLimpieza');
  await api('PATCH', `/tables/${table.id}/status`, { status: 'AVAILABLE' }, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se quita la mesa y el área de prueba', gone.status === 200, gone.data);
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
