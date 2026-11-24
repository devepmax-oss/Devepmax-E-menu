/**
 * Prueba de humo de la tablet de mesa: vincular, ver la mesa, pedir, llamar al mesero,
 * pedir la cuenta y el PIN del personal.
 * Uso:  npm run smoke:emenu   (backend encendido y seed hecho)
 *
 * Crea un área "Prueba automática" con la mesa E1 y una tablet de prueba; al final las elimina.
 */
import { randomUUID } from 'node:crypto';
import { io, Socket } from 'socket.io-client';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const ORIGIN = `http://localhost:${process.env.PORT ?? 3000}`;
const BASE = `${ORIGIN}/api/v1`;
let failures = 0;
type Json = Record<string, any>;

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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

async function main() {
  console.log(`\nPrueba de la tablet de mesa → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;

  // Limpieza de una corrida anterior que se haya cortado.
  for (const d of ((await api('GET', '/devices', undefined, A)).data as Json[]).filter((d) => d.name === 'Tablet de prueba')) {
    await api('DELETE', `/devices/${d.id}`, undefined, A);
  }
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  console.log('Vincular');
  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const table = (await api('POST', '/tables', { label: 'E1', areaId: area.id, seats: 4 }, A)).data;
  const device = await api('POST', '/devices', { name: 'Tablet de prueba', type: 'EMENU', tableId: table.id }, A);
  check('se registra la tablet en la mesa E1', device.status === 201 && device.data?.tableId === table.id, device.data);
  const bad = await api('POST', '/auth/device/pair', { code: '000000' });
  check('un código equivocado no vincula', bad.status === 401);
  const paired = await api('POST', '/auth/device/pair', { code: device.data.pairingCode, appVersion: 'smoke' });
  check('con el código queda vinculada', paired.status === 200 && String(paired.data?.deviceToken).length > 20, paired.data);
  const T = paired.data.deviceToken as string;
  const reuse = await api('POST', '/auth/device/pair', { code: device.data.pairingCode });
  check('el código sirve una sola vez', reuse.status === 401);

  console.log('\nLa mesa');
  const first = await api('GET', '/emenu/table', undefined, T);
  check('la tablet ve su mesa, todavía sin clientes', first.data?.table?.label === 'E1' && first.data?.session === null, first.data);
  const floor = await api('GET', '/tables/floor', undefined, T);
  check('la tablet no puede ver el resto del salón', floor.status === 403, floor.status);
  const menu = (await api('GET', '/menu?channel=dine_in', undefined, T)).data;
  check('la tablet ve el menú de salón', (menu?.categories ?? []).length > 0);

  const tablet = await connect({ token: T });
  const staff = await connect({ token: A });
  check('la tablet se conecta en vivo', tablet !== null);
  const tabletTable = listen(tablet, 'table.updated');
  // Un pedido nuevo llega como order.created (y luego order.updated si cambia).
  const tabletOrders = listen(tablet, 'order.created');
  tablet?.on('order.updated', (d: Json) => tabletOrders.push(d));
  const staffCalls = listen(staff, 'service_request.created');

  console.log('\nLlamar al mesero');
  const call = await api('POST', '/emenu/requests', { type: 'CALL_WAITER' }, T);
  check('al llamar, la mesa se abre y el llamado queda pendiente', call.status === 201 && call.data?.session?.requests?.length === 1, call.data);
  const again = await api('POST', '/emenu/requests', { type: 'CALL_WAITER' }, T);
  check('si insisten, no se repite el llamado', again.data?.session?.requests?.length === 1);
  await sleep(600);
  check('la caja y los meseros reciben el aviso', staffCalls.some((c) => c.table?.label === 'E1' && c.type === 'CALL_WAITER'), staffCalls);
  check('el plano muestra la mesa ocupada', tabletTable.some((t) => t.id === table.id && t.status === 'OCCUPIED'));
  const requestId = call.data.session.requests[0].id as string;
  await api('PATCH', `/tables/requests/${requestId}`, { status: 'DONE' }, A);
  const afterCall = await api('GET', '/emenu/table', undefined, T);
  check('el mesero lo atiende y desaparece de la tablet', afterCall.data?.session?.requests?.length === 0, afterCall.data?.session);

  console.log('\nPedido desde la tablet');
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 2, optionIds, notes: 'Sin cebolla' }];
  const quote = await api('POST', '/orders/quote', { items }, T);
  check('la tablet calcula el total antes de enviar', quote.status === 200 && Number(quote.data?.totals?.total) > 0, quote.data);
  const clientRequestId = randomUUID().replace(/-/g, '');
  const order = await api('POST', '/orders', { clientRequestId, fulfillmentType: 'DINE_IN', items }, T);
  check('se envía el pedido de la mesa', order.status === 201 && order.data?.channel === 'TABLET' && order.data?.table?.label === 'E1', order.data);
  const repeat = await api('POST', '/orders', { clientRequestId, fulfillmentType: 'DINE_IN', items }, T);
  check('si la red falla y reenvía, no se duplica', repeat.data?.id === order.data?.id);
  if (order.data?.status === 'PENDING_APPROVAL') await api('POST', `/orders/${order.data.id}/approve`, undefined, A);
  await sleep(800);
  const withOrder = await api('GET', '/emenu/table', undefined, T);
  const s = withOrder.data?.session;
  check('la tablet ve su pedido y la cuenta', s?.orders?.length === 1 && Number(s?.bill?.total) > 0, s);
  check('el pedido trae la nota y los artículos', s?.orders?.[0]?.items?.[0]?.notes === 'Sin cebolla' && s?.orders?.[0]?.items?.[0]?.quantity === 2);
  check('la tablet recibe su pedido en vivo', tabletOrders.some((o) => o.id === order.data.id), tabletOrders.length);

  console.log('\nPedir la cuenta');
  const bill = await api('POST', '/emenu/requests', { type: 'REQUEST_BILL' }, T);
  check('se pide la cuenta', bill.data?.session?.status === 'BILL_REQUESTED' && bill.data?.session?.requests?.[0]?.type === 'REQUEST_BILL', bill.data?.session);
  const cancel = await api('POST', `/emenu/requests/${bill.data.session.requests[0].id}/cancel`, undefined, T);
  check('se puede retirar el pedido de cuenta', cancel.data?.session?.status === 'OPEN' && cancel.data?.session?.requests?.length === 0, cancel.data?.session);

  console.log('\nMenú del personal');
  const pin = await api('POST', '/auth/device/staff-check', { pin: '9876' }, T);
  check('un PIN equivocado no abre el menú del personal', pin.status === 401 && pin.data?.message === 'PIN incorrecto', pin.data);
  const pinLogin = await api('POST', '/auth/pin', { pin: '9876' }, T);
  check('la tablet no puede iniciar sesión de empleado', pinLogin.status === 403);

  console.log('\nLimpieza');
  for (const t of order.data.tickets) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${order.data.id}/complete`, undefined, A);
  await api('POST', `/tables/${table.id}/close`, { force: true }, A);
  await sleep(500);
  const closed = await api('GET', '/emenu/table', undefined, T);
  check('al cerrar la mesa, la tablet vuelve a la bienvenida', closed.data?.session === null, closed.data);
  await api('POST', `/devices/${device.data.id}/revoke`, undefined, A);
  const revoked = await api('GET', '/emenu/table', undefined, T);
  check('una tablet desvinculada deja de funcionar', revoked.status === 401);
  await api('DELETE', `/devices/${device.data.id}`, undefined, A);
  await api('DELETE', `/tables/${table.id}`, undefined, A);
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se eliminan la tablet, la mesa y el área de prueba', gone.status === 200, gone.data);
  tablet?.close();
  staff?.close();
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
