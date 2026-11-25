/**
 * Prueba de humo de las cuentas de cliente: entrar con código, perfil, direcciones, historial
 * (incluye un pedido web hecho antes de tener cuenta) y Clientes para el personal (buscar,
 * alta rápida, notas, ligar un cliente a una cuenta de la caja).
 * Uso:  npm run smoke:customers   (backend encendido y seed hecho; sin Twilio/Resend en desarrollo)
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
const phone = () => `305555${String(randomInt(0, 10_000)).padStart(4, '0')}`;

async function api(method: string, path: string, body?: unknown, opts: { staff?: string; customer?: string } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(opts.staff ? { Authorization: `Bearer ${opts.staff}` } : {}),
      ...(opts.customer ? { 'x-customer-token': opts.customer } : {}),
    },
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

function summary() {
  console.log(failures ? `\n❌ ${failures} prueba(s) fallaron\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

async function main() {
  console.log(`\nPrueba de cuentas de cliente → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const config = (await api('GET', '/online/config')).data;
  const open = !!config?.isOpenNow && config?.channels?.pickup && config?.payments?.payAtPickup && !config?.channels?.onlineOrderingPaused;
  const menu = (await api('GET', '/menu?channel=online')).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = product ? [{ productId: product.id, quantity: 1, optionIds }] : [];
  const P = phone();

  if (open && product) {
    const guest = await api('POST', '/online/orders', {
      clientRequestId: rid(), fulfillmentType: 'PICKUP', paymentMethod: 'pay_at_pickup',
      customer: { name: 'Prueba Cliente', phone: `(${P.slice(0, 3)}) ${P.slice(3, 6)}-${P.slice(6)}` }, items,
    });
    check('pedido web antes de tener cuenta', guest.status === 201, guest.data);
  } else {
    console.log('  ⚠ El restaurante está cerrado (o sin Pickup / pagar al recoger): se omiten los pedidos web.\n');
  }

  console.log('Entrar con código');
  const bad = await api('POST', '/customer-auth/request', { target: 'hola' });
  if (bad.status === 404) {
    console.log('  ✗ El backend no tiene todavía las cuentas de cliente. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  check('un dato inválido avisa', bad.status === 400, bad.data);
  const req = await api('POST', '/customer-auth/request', { target: P });
  check('pide el código por SMS', req.status === 200 && req.data?.channel === 'sms', req.data);
  check('no muestra el teléfono completo', !JSON.stringify(req.data?.sentTo ?? '').includes(P.slice(0, 6)), req.data?.sentTo);
  const code = req.data?.devCode as string | undefined;
  if (req.status !== 200) return summary();
  if (!code) {
    console.log('  ⚠ Twilio está configurado: el código llegó por SMS y esta prueba no puede leerlo. Corre la prueba sin claves de Twilio.');
    return summary();
  }
  const wrong = await api('POST', '/customer-auth/verify', { target: P, code: code === '000000' ? '111111' : '000000' });
  check('un código equivocado no entra', wrong.status === 400, wrong.data);
  const ok = await api('POST', '/customer-auth/verify', { target: P, code });
  check('el código correcto entra', ok.status === 200 && typeof ok.data?.token === 'string', ok.data);
  const T = ok.data?.token as string;
  check('cuenta nueva: pide el nombre', ok.data?.customer?.needsName === true || ok.data?.customer?.name === 'Prueba Cliente', ok.data?.customer);
  check('guarda el teléfono como +1…', ok.data?.customer?.phone === `+1${P}`, ok.data?.customer?.phone);
  const reuse = await api('POST', '/customer-auth/verify', { target: P, code });
  check('el mismo código no sirve dos veces', reuse.status === 400);

  console.log('\nMi cuenta');
  check('sin sesión no se ve la cuenta', (await api('GET', '/me')).status === 401);
  check('una sesión de cliente no sirve en el panel', (await api('GET', '/customers', undefined, { staff: T })).status === 401);
  const named = await api('PATCH', '/me', { name: 'Prueba Cliente', lang: 'en' }, { customer: T });
  check('guarda el nombre y el idioma', named.data?.name === 'Prueba Cliente' && named.data?.lang === 'en' && named.data?.needsName === false, named.data);
  const address = { label: 'Casa', street: '123 Main St', city: 'Miami', state: 'fl', zipCode: '33101' };
  const a1 = await api('POST', '/me/addresses', address, { customer: T });
  check('guarda una dirección', a1.data?.addresses?.length === 1 && a1.data.addresses[0].state === 'FL', a1.data);
  const a2 = await api('POST', '/me/addresses', { ...address, street: '123 main st' }, { customer: T });
  check('la misma dirección no se repite', a2.data?.addresses?.length === 1, a2.data?.addresses);
  const a3 = await api('POST', '/me/addresses', { ...address, label: 'Trabajo', street: '9 Ocean Dr' }, { customer: T });
  const work = a3.data?.addresses?.find((x: Json) => x.label === 'Trabajo');
  const edited = await api('PATCH', `/me/addresses/${work?.id}`, { ...address, label: 'Oficina', street: '9 Ocean Dr' }, { customer: T });
  check('edita una dirección', edited.data?.addresses?.some((x: Json) => x.label === 'Oficina'), edited.data?.addresses);
  const removed = await api('DELETE', `/me/addresses/${work?.id}`, undefined, { customer: T });
  check('borra una dirección', removed.data?.addresses?.length === 1, removed.data?.addresses);

  if (open && product) {
    console.log('\nHistorial');
    const mine = await api('POST', '/online/orders', {
      clientRequestId: rid(), fulfillmentType: 'PICKUP', paymentMethod: 'pay_at_pickup',
      customer: { name: 'Prueba Cliente', phone: P }, items,
    }, { customer: T });
    check('pide con su cuenta', mine.status === 201, mine.data);
    const history = (await api('GET', '/me/orders', undefined, { customer: T })).data as Json[];
    check('el historial trae los dos pedidos (el de antes y el nuevo)', Array.isArray(history) && history.length === 2, history?.length);
    check('cada pedido trae lo que llevó para repetirlo', history?.[0]?.items?.[0]?.productId === product.id && Array.isArray(history[0].items[0].options));
    check('y el código de seguimiento', typeof history?.[0]?.trackingCode === 'string');
  }

  console.log('\nClientes (personal)');
  const list = await api('GET', `/customers?q=${P.slice(-4)}`, undefined, { staff: A });
  const row = (list.data?.customers as Json[] | undefined)?.find((c) => c.phone === `+1${P}`);
  check('lo encuentra por teléfono', list.status === 200 && !!row, list.data);
  check('con sus visitas', row?.visits === (open && product ? 2 : 0), row);
  const notes = await api('PATCH', `/customers/${row?.id}`, { notes: 'Prefiere mesa junto a la ventana' }, { staff: A });
  check('guarda una nota del personal', notes.data?.notes === 'Prefiere mesa junto a la ventana', notes.data);
  const me = (await api('GET', '/me', undefined, { customer: T })).data;
  check('el cliente no ve las notas del personal', me && !('notes' in me) && !JSON.stringify(me).includes('ventana'), me);
  const found = await api('GET', `/customers/lookup?phone=${P}`, undefined, { staff: A });
  check('la caja lo busca por teléfono', found.data?.customer?.id === row?.id, found.data);
  const Q = phone();
  const none = await api('GET', `/customers/lookup?phone=${Q}`, undefined, { staff: A });
  check('un teléfono sin cliente no da error', none.status === 200 && none.data?.customer === null, none.data);
  const quick = await api('POST', '/customers', { name: 'Prueba Caja', phone: Q }, { staff: A });
  check('alta rápida en la caja', quick.status === 201 && quick.data?.existing === false, quick.data);
  const twice = await api('POST', '/customers', { name: 'Otro nombre', phone: Q }, { staff: A });
  check('el mismo teléfono usa el mismo cliente', twice.data?.existing === true && twice.data?.customer?.id === quick.data?.customer?.id, twice.data);

  console.log('\nCliente en una cuenta de la caja');
  const dineMenu = (await api('GET', '/menu?channel=dine_in', undefined, { staff: A })).data;
  const p2 = (dineMenu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const opts2: string[] = [];
  for (const g of p2?.modifierGroups ?? []) opts2.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const order = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items: [{ productId: p2.id, quantity: 1, optionIds: opts2 }] }, { staff: A })).data;
  const attached = await api('PATCH', `/billing/bills/${order.bill.id}/customer`, { customerId: quick.data?.customer?.id }, { staff: A });
  check('liga el cliente a la cuenta', attached.data?.customer?.id === quick.data?.customer?.id, attached.data?.customer);
  const detail = (await api('GET', `/customers/${quick.data?.customer?.id}`, undefined, { staff: A })).data;
  check('la cuenta aparece en su historial', detail?.history?.some((h: Json) => h.id === order.bill.id), detail?.history);
  const detached = await api('PATCH', `/billing/bills/${order.bill.id}/customer`, { customerId: null }, { staff: A });
  check('y se puede quitar', detached.data?.customer === null, detached.data?.customer);
  await api('POST', `/orders/${order.id}/cancel`, { reason: 'Prueba de clientes' }, { staff: A });

  console.log('\nAdministrar clientes');
  await api('PATCH', `/customers/${row?.id}`, { marketingOptIn: true }, { staff: A });
  const optIn = (await api('GET', `/customers?filter=optIn&q=${P.slice(-4)}`, undefined, { staff: A })).data;
  check('filtra a quienes aceptan promociones', optIn?.customers?.some((c: Json) => c.id === row?.id) && !optIn.customers.some((c: Json) => c.id === quick.data?.customer?.id), optIn);
  const bySpent = await api('GET', '/customers?sort=spent', undefined, { staff: A });
  check('ordena por lo que más gastan', bySpent.status === 200 && Array.isArray(bySpent.data?.customers), bySpent.data);
  const taken = await api('PATCH', `/customers/${quick.data?.customer?.id}`, { phone: P }, { staff: A });
  check('no deja repetir el teléfono de otro cliente', taken.status === 409, taken.data);
  const mail = `prueba${Q}@example.com`;
  const edited2 = await api('PATCH', `/customers/${quick.data?.customer?.id}`, { name: 'Prueba Caja Editado', email: mail }, { staff: A });
  check('edita nombre y email', edited2.data?.name === 'Prueba Caja Editado' && edited2.data?.email === mail, edited2.data);
  const link = await api('POST', '/customers/export-link', { filter: 'all' }, { staff: A });
  const file = link.data?.url ? await fetch(link.data.url) : null;
  const bytes = file ? Buffer.from(await file.arrayBuffer()) : Buffer.alloc(0);
  check('exporta la lista a Excel', file?.status === 200 && bytes.subarray(0, 2).toString() === 'PK', { status: file?.status });
  const fake = await fetch(`${BASE}/customers/export/abc.def`);
  check('un enlace alterado no descarga nada', fake.status === 401, fake.status);
  const merged = await api('POST', `/customers/${row?.id}/merge`, { fromId: quick.data?.customer?.id }, { staff: A });
  check('junta dos fichas de la misma persona', merged.status === 200 && merged.data?.email === mail && merged.data?.phone === `+1${P}`, merged.data);
  check('la ficha duplicada desaparece', (await api('GET', `/customers/${quick.data?.customer?.id}`, undefined, { staff: A })).status === 404);
  check('el cliente sigue con su sesión', (await api('GET', '/me', undefined, { customer: T })).data?.email === mail);
  const R = await api('POST', '/customers', { name: 'Prueba Borrar', phone: phone() }, { staff: A });
  const del = await api('DELETE', `/customers/${R.data?.customer?.id}`, undefined, { staff: A });
  check('borra un cliente', del.status === 204 && (await api('GET', `/customers/${R.data?.customer?.id}`, undefined, { staff: A })).status === 404, del.status);

  console.log('\nSalir');
  await api('POST', '/customer-auth/logout', undefined, { customer: T });
  check('al salir, la sesión deja de servir', (await api('GET', '/me', undefined, { customer: T })).status === 401);

  summary();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
