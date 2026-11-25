/**
 * Prueba de humo del modo mesero: quién atiende cada mesa, tomar una mesa, pedidos listos
 * para llevar y presentar la cuenta con el QR de pago (sin poder cobrar).
 * Uso:  npm run smoke:waiter   (backend encendido y seed hecho)
 *
 * Crea (o reutiliza) el empleado "Mesero de prueba" y el área "Prueba automática" con las mesas
 * W1 y W2; al final cierra y elimina las mesas y desactiva al mesero de prueba.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { io, Socket } from 'socket.io-client';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const ORIGIN = `http://localhost:${process.env.PORT ?? 3000}`;
const BASE = `${ORIGIN}/api/v1`;
const WAITER_EMAIL = 'mesero.prueba@devepmax.test';
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
  console.log(`\nPrueba del modo mesero → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const adminId = (login.data.employee?.id ?? (await api('GET', '/auth/me', undefined, login.data.accessToken)).data?.id) as string;

  // Limpieza de una corrida anterior que se haya cortado (incluye pedidos que quedaron abiertos).
  const active = ((await api('GET', '/orders?scope=active', undefined, A)).data ?? []) as Json[];
  for (const area of ((await api('GET', '/tables/floor', undefined, A)).data as Json[]).filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      for (const o of active.filter((o) => o.table?.id === t.id)) await api('POST', `/orders/${o.id}/cancel`, { reason: 'Prueba automática' }, A);
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  console.log('Mesero');
  const roles = (await api('GET', '/roles', undefined, A)).data as Json[];
  const role = roles.find((r) => r.name === 'Mesero');
  check('existe el rol Mesero', !!role);
  const password = `Prueba-${randomBytes(6).toString('hex')}`;
  const existing = ((await api('GET', '/employees', undefined, A)).data as Json[]).find((e) => e.email === WAITER_EMAIL);
  const saved = existing
    ? await api('PATCH', `/employees/${existing.id}`, { password, isActive: true, roleId: role?.id }, A)
    : await api('POST', '/employees', { name: 'Mesero de prueba', email: WAITER_EMAIL, roleId: role?.id, password }, A);
  const waiterId = (saved.data?.id ?? existing?.id) as string;
  const W = (await api('POST', '/auth/login', { email: WAITER_EMAIL, password })).data?.accessToken as string;
  check('el mesero inicia sesión', !!W);

  const area = (await api('POST', '/tables/areas', { name: 'Prueba automática' }, A)).data;
  const w1 = (await api('POST', '/tables', { label: 'W1', areaId: area.id, seats: 4 }, A)).data;
  const w2 = (await api('POST', '/tables', { label: 'W2', areaId: area.id, seats: 2 }, A)).data;
  const table = async (id: string, token = W) => (await api('GET', `/tables/${id}`, undefined, token)).data;

  console.log('\nQuién atiende cada mesa');
  await api('POST', `/tables/${w1.id}/open`, { guestCount: 2 }, W);
  const seated = await table(w1.id);
  check('quien sienta a los clientes atiende la mesa', seated?.session?.waiter?.id === waiterId && seated?.session?.waiter?.name === 'Mesero de prueba', seated?.session);

  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const items = [{ productId: product.id, quantity: 1, optionIds }];
  const w2Order = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId: w2.id, items }, A)).data;
  check('quien toma el primer pedido de una mesa libre la atiende', (await table(w2.id))?.session?.waiter?.id === adminId);
  const claim = await api('PATCH', `/tables/${w2.id}/waiter`, {}, W);
  check('el mesero puede tomar una mesa', claim.status === 200 && claim.data?.session?.waiter?.id === waiterId, claim.data?.session);
  const give = await api('PATCH', `/tables/${w2.id}/waiter`, { waiterId: adminId }, W);
  check('pero no asignársela a otro', give.status === 403, give.status);
  const manager = await api('PATCH', `/tables/${w1.id}/waiter`, { waiterId: adminId }, A);
  check('un gerente sí puede asignarla', manager.data?.session?.waiter?.id === adminId, manager.data?.session);
  const back = await api('PATCH', `/tables/${w1.id}/waiter`, { waiterId }, A);
  check('y devolverla', back.data?.session?.waiter?.id === waiterId, back.data?.session);

  console.log('\nPedidos listos para llevar');
  const socket = await connect({ token: W });
  check('el mesero se conecta en vivo', socket !== null);
  const ready: Json[] = [];
  socket?.on('order.updated', (o: Json) => {
    if (o.status === 'READY') ready.push(o);
  });
  const order = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId: w1.id, items }, W);
  check('el mesero toma el pedido de su mesa', order.status === 201 && order.data?.table?.label === 'W1', order.data);
  for (const t of order.data.tickets ?? []) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await sleep(800);
  check('le llega en vivo que el pedido está listo', ready.some((o) => o.id === order.data.id && o.table?.label === 'W1'), ready.length);
  check('la mesa muestra 1 pedido listo para llevar', (await table(w1.id))?.session?.readyOrders === 1);
  const served = await api('POST', `/orders/${order.data.id}/complete`, undefined, W);
  check('lo marca entregado', served.data?.status === 'COMPLETED', served.data?.status);
  check('y ya no queda nada por llevar', (await table(w1.id))?.session?.readyOrders === 0);

  console.log('\nPresentar la cuenta');
  const checks = await api('GET', `/billing/tables/${w1.id}/check`, undefined, W);
  const c = checks.data?.[0];
  check('el mesero obtiene la cuenta de su mesa', checks.status === 200 && checks.data?.length === 1 && Number(c?.due) > 0, checks.data);
  check('con propinas sugeridas', Array.isArray(c?.tips) && c.tips.length > 0, c?.tips);
  check('y el QR para pagar con el celular (si Stripe está configurado)', c?.payUrl === null || String(c?.payUrl).includes('/cuenta/'), c?.payUrl);
  const bills = await api('GET', '/billing/bills', undefined, W);
  check('pero no puede abrir la caja ni cobrar', bills.status === 403, bills.status);

  console.log('\nLimpieza');
  socket?.close();
  await api('POST', `/orders/${w2Order.id}/cancel`, { reason: 'Prueba automática' }, A);
  for (const t of [w1, w2]) {
    await api('POST', `/tables/${t.id}/close`, { force: true }, A);
    await api('DELETE', `/tables/${t.id}`, undefined, A);
  }
  const gone = await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  check('se eliminan las mesas y el área de prueba', gone.status === 200 || gone.status === 204, gone.status);
  await api('PATCH', `/employees/${waiterId}`, { isActive: false }, A);
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
