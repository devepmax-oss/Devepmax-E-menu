/**
 * Prueba de humo de la pantalla de cocina (KDS): vincular, ver solo su estación, recibir
 * pedidos en vivo, Empezar / Listo / Deshacer, agotar un producto y enterarse de cancelaciones.
 * Uso:  npm run smoke:kds   (backend encendido y seed hecho)
 *
 * Crea "Cocina de prueba" (pantalla de cocina) y dos pedidos para llevar; al final los cierra
 * y elimina la pantalla.
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
const rid = () => randomUUID().replace(/-/g, '');
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

async function main() {
  console.log(`\nPrueba de la pantalla de cocina → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  for (const d of ((await api('GET', '/devices', undefined, A)).data as Json[]).filter((d) => d.name === 'Cocina de prueba')) {
    await api('DELETE', `/devices/${d.id}`, undefined, A);
  }

  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 2, optionIds, notes: 'Sin cebolla' }];
  const newOrder = async (name: string) =>
    (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', customerName: name, notes: 'Bolsa aparte', items }, A)).data;

  console.log('Vincular');
  const first = await newOrder('Prueba cocina 1');
  const stationId = first?.tickets?.[0]?.station?.id as string;
  check('el pedido genera su ticket de cocina', !!stationId, first?.tickets);
  const device = await api('POST', '/devices', { name: 'Cocina de prueba', type: 'KDS', stationId }, A);
  check('se registra la pantalla de cocina con su estación', device.status === 201 && device.data?.stationId === stationId, device.data);
  const paired = await api('POST', '/auth/device/pair', { code: device.data.pairingCode, appVersion: 'smoke' });
  check('se vincula con el código', paired.status === 200 && paired.data?.device?.type === 'KDS', paired.data);
  const K = paired.data.deviceToken as string;
  const me = (await api('GET', '/auth/me', undefined, K)).data;
  const stations = (await api('GET', '/menu/stations', undefined, K)).data as Json[];
  check('sabe cuál es su estación y cómo se llama', me?.stationId === stationId && stations.some((s) => s.id === stationId), { me, stations });

  console.log('\nTickets');
  const list = (await api('GET', '/kitchen/tickets', undefined, K)).data as Json[];
  const mine = list.find((t) => t.order?.id === first.id) ?? {};
  check('ve el ticket del pedido con platos, opciones y notas', !!mine && mine.items?.[0]?.quantity === 2 && mine.items?.[0]?.notes === 'Sin cebolla' && mine.order?.notes === 'Bolsa aparte', mine);
  check('solo ve tickets de su estación', list.every((t) => t.station?.id === stationId), list.map((t) => t.station?.name));
  const other = stations.find((s) => s.id !== stationId);
  if (other) {
    const peek = await api('GET', `/kitchen/tickets?stationId=${other.id}`, undefined, K);
    check('no puede ver otra estación', peek.status === 403, peek.status);
  }

  const kds = await connect({ token: K });
  check('se conecta en vivo', kds !== null);
  const created = listen(kds, 'ticket.created');
  const updated = listen(kds, 'ticket.updated');
  const second = await newOrder('Prueba cocina 2');
  await sleep(800);
  check('un pedido nuevo llega al instante', created.some((t) => t.order?.id === second.id), created.length);

  console.log('\nEmpezar, Listo y Deshacer');
  const start = await api('PATCH', `/kitchen/tickets/${mine.id}`, { status: 'PREPARING' }, K);
  check('Empezar', start.status === 200 && start.data?.status === 'PREPARING', start.data);
  check('la caja ve la orden en preparación', (await api('GET', `/orders/${first.id}`, undefined, A)).data?.status === 'PREPARING');
  const done = await api('PATCH', `/kitchen/tickets/${mine.id}`, { status: 'READY' }, K);
  check('Listo', done.data?.status === 'READY', done.data);
  const firstOrder = (await api('GET', `/orders/${first.id}`, undefined, A)).data;
  check('si era el único ticket, la orden queda lista para entregar', firstOrder?.status === 'READY' || firstOrder?.tickets?.length > 1, firstOrder?.status);
  const undo = await api('PATCH', `/kitchen/tickets/${mine.id}`, { status: 'PREPARING' }, K);
  check('Deshacer (vuelve a preparación)', undo.data?.status === 'PREPARING', undo.data);
  await api('PATCH', `/kitchen/tickets/${mine.id}`, { status: 'READY' }, K);
  const skip = (await api('GET', '/kitchen/tickets', undefined, K)).data.find((t: Json) => t.order?.id === second.id);
  const direct = await api('PATCH', `/kitchen/tickets/${skip.id}`, { status: 'READY' }, K);
  check('un ticket nuevo se puede marcar Listo directo', direct.data?.status === 'READY', direct.data);
  await api('PATCH', `/kitchen/tickets/${skip.id}`, { status: 'PREPARING' }, K);

  console.log('\nAgotados');
  const off = await api('PATCH', `/menu/products/${product.id}/availability`, { isAvailable: false }, K);
  check('la cocina marca un producto agotado', off.status === 200, off.data);
  const offMenu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const seen = (offMenu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.id === product.id);
  check('deja de ofrecerse en el menú', seen?.isAvailable === false, seen);
  await api('PATCH', `/menu/products/${product.id}/availability`, { isAvailable: true }, K);

  console.log('\nLímites y cancelaciones');
  const order = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items }, K);
  check('la pantalla de cocina no puede crear pedidos', order.status === 403, order.status);
  const bills = await api('GET', '/billing/bills', undefined, K);
  check('ni ver la caja', bills.status === 403, bills.status);
  await api('POST', `/orders/${second.id}/cancel`, { reason: 'Prueba automática' }, A);
  await sleep(800);
  check('si cancelan un pedido, la cocina se entera al instante', updated.some((t) => t.order?.id === second.id && t.status === 'CANCELLED'), updated.map((t) => t.status));

  console.log('\nLimpieza');
  await api('POST', `/orders/${first.id}/complete`, undefined, A);
  await api('POST', `/devices/${device.data.id}/revoke`, undefined, A);
  const revoked = await api('GET', '/kitchen/tickets', undefined, K);
  check('una pantalla desvinculada deja de funcionar', revoked.status === 401, revoked.status);
  const gone = await api('DELETE', `/devices/${device.data.id}`, undefined, A);
  check('se elimina la pantalla de prueba', gone.status === 200 || gone.status === 204, gone.status);
  kds?.close();
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
