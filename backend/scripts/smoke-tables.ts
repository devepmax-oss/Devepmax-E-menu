/**
 * Prueba de humo del salón: áreas, mesas, plano, abrir/cerrar mesa y tiempo real.
 * Uso:  npm run smoke:tables   (backend encendido y seed hecho)
 *
 * Crea un área "Prueba automática" con mesas P1–P3, hace un pedido de mesa y al final
 * elimina todo lo que creó (el historial de pedidos se conserva, oculto).
 */
import { randomUUID } from 'node:crypto';
import { io } from 'socket.io-client';

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

async function main() {
  console.log(`\nPrueba del salón → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;

  // Limpieza de una corrida anterior que se haya cortado.
  const before = (await api('GET', '/tables/floor', undefined, A)).data as Json[];
  for (const area of before.filter((a) => a.name === 'Prueba automática')) {
    for (const t of area.tables) {
      await api('POST', `/tables/${t.id}/close`, { force: true }, A);
      await api('DELETE', `/tables/${t.id}`, undefined, A);
    }
    await api('DELETE', `/tables/areas/${area.id}`, undefined, A);
  }

  // El restaurante necesita al menos un área real (la de prueba se borra al final).
  const current = (await api('GET', '/tables/floor', undefined, A)).data as Json[];
  if (!current.some((a) => a.name !== 'Prueba automática')) {
    await api('POST', '/tables/areas', { name: 'Salón' }, A);
    console.log('(Se creó el área "Salón" para tus mesas)\n');
  }

  console.log('Plano');
  const area = await api('POST', '/tables/areas', { name: 'Prueba automática' }, A);
  check('se crea un área', area.status === 201, area.data);
  const t1 = await api('POST', '/tables', { label: 'P1', areaId: area.data.id, seats: 4 }, A);
  const t2 = await api('POST', '/tables', { label: 'P2', areaId: area.data.id, seats: 2 }, A);
  check('se crean mesas con lugar libre en el plano', t1.status === 201 && t2.data?.posX !== null, [t1.data, t2.data]);
  const dup = await api('POST', '/tables', { label: 'P1', areaId: area.data.id, seats: 4 }, A);
  check('no se repite el nombre de una mesa', dup.status === 409, dup.data);
  await api('PUT', '/tables/layout', { positions: [{ id: t1.data.id, posX: 6, posY: 3 }] }, A);
  const floor = (await api('GET', '/tables/floor', undefined, A)).data as Json[];
  const mine = floor.find((a) => a.id === area.data.id);
  const p1 = mine?.tables.find((t: Json) => t.label === 'P1');
  check('el plano guarda la posición', p1?.posX === 6 && p1?.posY === 3, p1);
  check('las mesas empiezan libres', p1?.status === 'AVAILABLE' && p1?.session === null);

  console.log('\nOperación');
  const socket = io(ORIGIN, { auth: { token: A }, transports: ['websocket'], reconnection: false });
  const updates: Json[] = [];
  socket.on('table.updated', (d: Json) => updates.push(d));
  await new Promise<void>((resolve) => {
    socket.on('ready', () => resolve());
    setTimeout(resolve, 3000);
  });
  const reserved = await api('PATCH', `/tables/${t2.data.id}/status`, { status: 'RESERVED' }, A);
  check('se puede reservar una mesa', reserved.data?.status === 'RESERVED', reserved.data);
  const opened = await api('POST', `/tables/${t1.data.id}/open`, { guestCount: 3 }, A);
  check('al sentar clientes la mesa queda ocupada', opened.data?.status === 'OCCUPIED' && opened.data?.session?.guestCount === 3, opened.data);
  await sleep(500);
  check('caja y meseros lo ven al instante', updates.some((u) => u.id === t1.data.id && u.status === 'OCCUPIED'), updates);

  const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const order = await api('POST', '/orders', {
    clientRequestId: randomUUID().replace(/-/g, ''),
    fulfillmentType: 'DINE_IN',
    tableId: t1.data.id,
    items: [{ productId: product.id, quantity: 1, optionIds }],
  }, A);
  check('se hace un pedido en la mesa', order.status === 201, order.data);
  await sleep(800);
  const withOrder = (await api('GET', `/tables/${t1.data.id}`, undefined, A)).data;
  check('la mesa muestra el pedido y la cuenta', withOrder?.session?.orderCount === 1 && Number(withOrder?.session?.total) > 0, withOrder?.session);
  check('el aviso en vivo trae la cuenta', updates.some((u) => u.id === t1.data.id && Number(u.session?.total) > 0));

  const busy = await api('POST', `/tables/${t1.data.id}/close`, {}, A);
  check('no se cierra con pedidos en cocina', busy.status === 409, busy.data);
  for (const t of order.data.tickets) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  await api('POST', `/orders/${order.data.id}/complete`, undefined, A);
  const unpaid = await api('POST', `/tables/${t1.data.id}/close`, {}, A);
  check('avisa si la cuenta tiene saldo', unpaid.status === 409 && /pendientes/.test(unpaid.data?.message), unpaid.data);
  const closed = await api('POST', `/tables/${t1.data.id}/close`, { force: true }, A);
  check('se puede cerrar igual (queda por limpiar)', closed.data?.status === 'CLEANING' && closed.data?.session === null, closed.data);
  const ready = await api('PATCH', `/tables/${t1.data.id}/status`, { status: 'AVAILABLE' }, A);
  check('al limpiarla queda libre', ready.data?.status === 'AVAILABLE', ready.data);

  console.log('\nLimpieza');
  const delBusy = await api('DELETE', `/tables/areas/${area.data.id}`, undefined, A);
  check('no se borra un área con mesas', delBusy.status === 409);
  for (const t of [t1.data, t2.data]) await api('DELETE', `/tables/${t.id}`, undefined, A);
  const delArea = await api('DELETE', `/tables/areas/${area.data.id}`, undefined, A);
  check('se eliminan las mesas y el área de prueba', delArea.status === 200, delArea.data);
  socket.close();
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
