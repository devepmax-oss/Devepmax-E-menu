/**
 * Prueba de humo de la lealtad: puntos al pagar, ajuste por reembolso y por cambio de cliente,
 * premio en cupón personal (y que solo ese cliente lo use), ajuste manual y regalo de cumpleaños.
 * Uso:  npm run smoke:loyalty   (backend encendido y seed hecho)
 *
 * Activa la lealtad para la prueba y al final deja los ajustes como estaban.
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
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

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
  console.log(`\nPrueba de lealtad → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const before = (await api('GET', '/settings', undefined, A)).data;
  if (before?.loyaltyEnabled === undefined) {
    console.log('✗ El backend no tiene todavía la lealtad. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  const restore = {
    loyaltyEnabled: before.loyaltyEnabled,
    loyaltyPointsPerDollar: before.loyaltyPointsPerDollar,
    loyaltyRewardPoints: before.loyaltyRewardPoints,
    loyaltyRewardAmount: n(before.loyaltyRewardAmount),
    birthdayRewardEnabled: before.birthdayRewardEnabled,
    birthdayRewardAmount: n(before.birthdayRewardAmount),
  };
  await api('PATCH', '/settings', { loyaltyEnabled: true, loyaltyPointsPerDollar: 1, loyaltyRewardPoints: 100000, loyaltyRewardAmount: 5, birthdayRewardEnabled: true, birthdayRewardAmount: 10 }, A);
  let openedShift = false;
  if (!(await api('GET', '/cash/shift', undefined, A)).data?.shift) {
    await api('POST', '/cash/shift/open', { openingCash: 100 }, A);
    openedShift = true;
  }

  try {
    const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
    const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
    const optionIds: string[] = [];
    for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
    const order = async (quantity = 3) => (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items: [{ productId: product.id, quantity, optionIds }] }, A)).data;
    const phone = `305555${String(randomInt(0, 10_000)).padStart(4, '0')}`;
    const client = (await api('POST', '/customers', { name: 'Prueba Lealtad', phone }, A)).data?.customer;
    const loyalty = async () => {
      await wait(700); // los puntos se calculan justo después de cada cambio
      return (await api('GET', `/customers/${client.id}/loyalty`, undefined, A)).data;
    };

    console.log('Ganar puntos');
    const o1 = await order();
    await api('PATCH', `/billing/bills/${o1.bill.id}/customer`, { customerId: client.id }, A);
    const unpaid = await loyalty();
    check('sin pagar todavía no hay puntos', unpaid?.points === 0, unpaid?.points);
    const bill = (await api('GET', `/billing/bills/${o1.bill.id}`, undefined, A)).data;
    const paid = (await api('POST', `/billing/bills/${o1.bill.id}/payments`, { clientRequestId: rid(), method: 'CASH', amount: n(bill.due), cashTendered: n(bill.due) }, A)).data;
    const expected = Math.floor(n(paid.subtotal) - n(paid.discountTotal));
    const l1 = await loyalty();
    check(`al pagar gana 1 punto por dólar (${expected})`, l1?.points === expected, { puntos: l1?.points, esperado: expected });
    check('el movimiento queda en su historial', l1?.history?.[0]?.type === 'EARN' && l1.history[0].points === expected, l1?.history?.[0]);

    console.log('\nReembolsos y cambio de cliente');
    const cash = paid.payments.find((p: Json) => p.method === 'CASH');
    await api('POST', `/billing/payments/${cash.id}/refunds`, { clientRequestId: rid(), amount: 2, reason: 'Prueba de lealtad' }, A);
    const l2 = await loyalty();
    check('un reembolso de $2 quita 2 puntos', l2?.points === Math.floor(n(paid.subtotal) - n(paid.discountTotal) - 2), { puntos: l2?.points });
    await api('PATCH', `/billing/bills/${o1.bill.id}/customer`, { customerId: null }, A);
    const l3 = await loyalty();
    check('si se quita el cliente de la cuenta, pierde esos puntos', l3?.points === 0, l3?.points);
    await api('PATCH', `/billing/bills/${o1.bill.id}/customer`, { customerId: client.id }, A);
    const l4 = await loyalty();
    check('y si se vuelve a poner, los recupera', l4?.points === l2?.points, l4?.points);

    console.log('\nPremio');
    await api('PATCH', '/settings', { loyaltyRewardPoints: 100 }, A);
    const adjust = await api('POST', `/customers/${client.id}/loyalty/adjust`, { points: 100, reason: 'Prueba de premio' }, A);
    const prize = adjust.data?.rewards?.find((r: Json) => r.code.startsWith('PREMIO-'));
    check('al llegar a 100 puntos recibe un cupón de premio', adjust.status === 200 && !!prize && n(prize.value) === 5, adjust.data?.rewards);
    check('y se le descuentan los puntos del premio', adjust.data?.points === n(l4?.points) + 100 - 100 * (adjust.data?.rewards?.filter((r: Json) => r.code.startsWith('PREMIO-')).length ?? 1), adjust.data?.points);
    const other = await order(1);
    const stranger = await api('POST', `/billing/bills/${other.bill.id}/coupon`, { code: prize?.code }, A);
    check('otro cliente no puede usar su premio', stranger.status === 400 && /personal/.test(stranger.data?.message ?? ''), stranger.data);
    await api('PATCH', `/billing/bills/${other.bill.id}/customer`, { customerId: client.id }, A);
    const used = await api('POST', `/billing/bills/${other.bill.id}/coupon`, { code: prize?.code }, A);
    check('él sí lo usa en la caja', used.status === 200 && n(used.data?.coupon?.amount) > 0, used.data?.coupon);
    const tooMuch = await api('POST', `/customers/${client.id}/loyalty/adjust`, { points: -100000, reason: 'Prueba' }, A);
    check('no se pueden quitar más puntos de los que tiene', tooMuch.status === 400, tooMuch.data);
    await api('POST', `/orders/${other.id}/cancel`, { reason: 'Prueba de lealtad' }, A);

    console.log('\nCumpleaños');
    const month = Number(new Intl.DateTimeFormat('en-US', { timeZone: before.timezone ?? 'America/New_York', month: 'numeric' }).format(new Date()));
    await api('PATCH', `/customers/${client.id}`, { birthMonth: month, birthDay: 1 }, A);
    const run = await api('POST', '/customers/loyalty/birthdays', undefined, A);
    const l5 = await loyalty();
    const gifts = (l5?.rewards ?? []).filter((r: Json) => r.code.startsWith('CUMPLE-'));
    check('en el mes de su cumpleaños recibe su regalo', run.status === 200 && gifts.length === 1 && n(gifts[0].value) === 10, l5?.rewards);
    await api('POST', '/customers/loyalty/birthdays', undefined, A);
    const l6 = await loyalty();
    check('solo una vez al año', (l6?.rewards ?? []).filter((r: Json) => r.code.startsWith('CUMPLE-')).length === 1);
    const badDate = await api('PATCH', `/customers/${client.id}`, { birthMonth: 2, birthDay: 30 }, A);
    check('una fecha que no existe avisa', badDate.status === 400, badDate.data);

    await api('DELETE', `/customers/${client.id}`, undefined, A);
  } finally {
    await api('PATCH', '/settings', restore, A);
    if (openedShift) {
      const shift = (await api('GET', '/cash/shift', undefined, A)).data?.shift;
      if (shift) await api('POST', '/cash/shift/close', { countedCash: n(shift.expectedCash) }, A);
    }
  }

  console.log(failures ? `\n❌ ${failures} prueba(s) fallaron\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
