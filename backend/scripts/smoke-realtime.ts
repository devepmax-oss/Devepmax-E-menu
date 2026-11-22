/**
 * Prueba de humo del tiempo real (Socket.IO) contra el backend que está corriendo.
 * Uso:  npm run smoke:realtime   (con el backend encendido y el seed hecho)
 *
 * Crea una orden real y una pantalla de cocina "[PRUEBA]" en la base de DESARROLLO;
 * al final cancela la orden y borra la pantalla. No usar en producción.
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
const WAIT_MS = 4000;
let token = '';
let failures = 0;

type Json = Record<string, any>;

async function api(method: string, path: string, body?: unknown, auth = token): Promise<{ status: number; data: any }> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(auth ? { Authorization: `Bearer ${auth}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : null };
}

function check(name: string, ok: boolean, detail?: unknown): void {
  if (ok) {
    console.log(`  ✓ ${name}`);
  } else {
    failures++;
    console.log(`  ✗ ${name}`);
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 400));
  }
}

/** Guarda todo lo que llega a un socket para poder esperar eventos concretos. */
class Listener {
  readonly received: { name: string; data: any }[] = [];
  private waiters: { match: (name: string, data: any) => boolean; resolve: (d: any) => void }[] = [];

  constructor(readonly socket: Socket) {
    socket.onAny((name: string, data: any) => {
      this.received.push({ name, data });
      this.waiters = this.waiters.filter((w) => {
        if (!w.match(name, data)) return true;
        w.resolve(data);
        return false;
      });
    });
  }

  /** Espera un evento que cumpla la condición (también si ya llegó). Devuelve null si no llega a tiempo. */
  wait(name: string, where: (data: any) => boolean = () => true, ms = WAIT_MS): Promise<any | null> {
    const already = this.received.find((e) => e.name === name && where(e.data));
    if (already) return Promise.resolve(already.data);
    return new Promise((resolve) => {
      const waiter = { match: (n: string, d: any) => n === name && where(d), resolve };
      this.waiters.push(waiter);
      setTimeout(() => {
        this.waiters = this.waiters.filter((w) => w !== waiter);
        resolve(null);
      }, ms);
    });
  }

  has(name: string, where: (data: any) => boolean = () => true): boolean {
    return this.received.some((e) => e.name === name && where(e.data));
  }
}

function connect(auth?: string): Socket {
  return io(ORIGIN, {
    auth: auth ? { token: auth } : {},
    transports: ['websocket'],
    reconnection: false,
    timeout: WAIT_MS,
  });
}

/** Resultado de conectarse: 'ok' con el evento ready, o el mensaje de error del servidor. */
function connectAndWait(auth?: string): Promise<{ socket: Socket; listener: Listener; ready: any; error?: string }> {
  return new Promise((resolve) => {
    const socket = connect(auth);
    const listener = new Listener(socket);
    const done = (ready: any, error?: string) => resolve({ socket, listener, ready, error });
    socket.on('connect_error', (err) => done(null, err.message));
    listener.wait('ready').then((ready) => done(ready, ready ? undefined : 'sin respuesta'));
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function main(): Promise<void> {
  console.log(`\nPrueba de tiempo real → ${ORIGIN}\n`);

  const login = await api('POST', '/auth/login', {
    email: process.env.SEED_ADMIN_EMAIL,
    password: process.env.SEED_ADMIN_PASSWORD,
  });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend y son correctos SEED_ADMIN_* en .env?');
    process.exit(1);
  }
  token = login.data.accessToken;

  // Producto disponible con sus opciones obligatorias
  const menu = (await api('GET', '/menu/admin')).data;
  const product = menu.categories
    .filter((c: Json) => c.isActive)
    .flatMap((c: Json) => c.products)
    .find((p: Json) => p.isActive && p.isAvailable && p.visibleDineIn && p.stationId);
  if (!product) {
    console.log('✗ No hay un producto activo, disponible y con estación de cocina. Revisa el menú en la app.');
    process.exit(1);
  }
  const optionIds: string[] = [];
  for (const link of product.modifierGroups) {
    const group = link.modifierGroup;
    if (!group.isActive) continue;
    optionIds.push(...group.options.filter((o: Json) => o.isAvailable).slice(0, group.minSelect).map((o: Json) => o.id));
  }
  console.log(`Producto de prueba: "${product.name}"\n`);

  // 1. Seguridad de la conexión
  console.log('Conexión segura');
  const anonymous = await connectAndWait();
  check('sin token, el servidor rechaza la conexión', !!anonymous.error && !anonymous.ready, anonymous.error);
  anonymous.socket.close();
  const forged = await connectAndWait('token-falso');
  check('con un token falso, también la rechaza', !!forged.error && !forged.ready, forged.error);
  forged.socket.close();

  const admin = await connectAndWait(token);
  check('con el token del administrador se conecta', !!admin.ready, admin.error);
  if (!admin.ready) return summary();
  const adminRooms: string[] = admin.ready.rooms ?? [];
  check(
    `el servidor le asigna sus salas (${adminRooms.join(', ')})`,
    ['pos', 'admin', 'kitchen', 'menu'].every((r) => adminRooms.includes(r)),
  );

  // 2. Pantalla de cocina de la estación del producto
  console.log('\nPantalla de cocina');
  const created = await api('POST', '/devices', { name: '[PRUEBA] Cocina tiempo real', type: 'KDS', stationId: product.stationId });
  check('se crea la pantalla de cocina de prueba', created.status === 201, created.data);
  const deviceId: string | undefined = created.data?.id;
  const paired = await api('POST', '/auth/device/pair', { code: created.data?.pairingCode }, '');
  check('la pantalla se vincula con su código', !!paired.data?.deviceToken, paired.data);
  const kds = await connectAndWait(paired.data?.deviceToken);
  const kdsRooms: string[] = kds.ready?.rooms ?? [];
  check('la pantalla se conecta', !!kds.ready, kds.error);
  check(
    'solo entra a su estación (no a caja ni a otras cocinas)',
    kdsRooms.includes(`kitchen:${product.stationId}`) && !kdsRooms.includes('pos') && !kdsRooms.includes('kitchen'),
    kdsRooms,
  );

  // 3. Orden nueva: llega sola a caja y a cocina
  console.log('\nOrden nueva, sin recargar');
  const order = await api('POST', '/orders', {
    clientRequestId: randomUUID().replace(/-/g, ''),
    fulfillmentType: 'TAKEOUT',
    customerName: 'Prueba tiempo real',
    items: [{ productId: product.id, quantity: 1, optionIds }],
  });
  check('la orden se crea', order.status === 201, order.data);
  const orderId: string = order.data?.id;
  const ticketId: string | undefined = order.data?.tickets?.find((t: Json) => t.station.id === product.stationId)?.id;

  const posEvent = await admin.listener.wait('order.created', (o) => o.id === orderId);
  check(`caja recibe la orden #${order.data?.number} al instante`, !!posEvent);
  check('trae el total calculado y su versión (updatedAt)', !!posEvent?.bill?.total && !!posEvent?.updatedAt, posEvent);
  const kdsTicket = await kds.listener.wait('ticket.created', (t) => t.id === ticketId);
  check('cocina recibe el ticket con los productos', !!kdsTicket && kdsTicket.items?.length > 0, kdsTicket);
  check('el ticket muestra el número de orden', kdsTicket?.order?.number === order.data?.number);
  check('la pantalla de cocina no recibe datos de caja', !kds.listener.has('order.created') && !kds.listener.has('bill.updated'));

  // 4. Cocina cambia el estado: lo ven caja y cocina
  console.log('\nCambio de estado en cocina');
  const before = posEvent?.updatedAt;
  const accepted = await api('PATCH', `/kitchen/tickets/${ticketId}`, { status: 'ACCEPTED' }, paired.data?.deviceToken);
  check('la pantalla acepta su ticket', accepted.status === 200, accepted.data);
  const ticketUpdate = await kds.listener.wait('ticket.updated', (t) => t.id === ticketId && t.status === 'ACCEPTED');
  check('cocina ve el ticket en ACCEPTED', !!ticketUpdate);
  const orderUpdate = await admin.listener.wait('order.updated', (o) => o.id === orderId && o.status === 'ACCEPTED');
  check('caja ve la orden en ACCEPTED', !!orderUpdate);
  check(
    'la versión (updatedAt) avanza, para descartar eventos viejos',
    !!orderUpdate && new Date(orderUpdate.updatedAt).getTime() >= new Date(before).getTime(),
    { before, after: orderUpdate?.updatedAt },
  );

  // 5. Agotado
  console.log('\nAgotado');
  await api('PATCH', `/menu/products/${product.id}/availability`, { isAvailable: false });
  const soldOut = await kds.listener.wait('product.availability', (p) => p.id === product.id && p.isAvailable === false);
  check('todas las pantallas se enteran de que se agotó', !!soldOut);
  await api('PATCH', `/menu/products/${product.id}/availability`, { isAvailable: true });
  const back = await admin.listener.wait('product.availability', (p) => p.id === product.id && p.isAvailable === true);
  check('y de que volvió a estar disponible', !!back);

  // 6. Cancelación
  console.log('\nCancelación');
  await api('POST', `/orders/${orderId}/cancel`, { reason: 'Prueba de tiempo real' });
  const cancelled = await kds.listener.wait('ticket.updated', (t) => t.id === ticketId && t.status === 'CANCELLED');
  check('cocina recibe el ticket cancelado (lo quita de la pantalla)', !!cancelled);

  // 7. Reconexión
  console.log('\nReconexión');
  admin.socket.close();
  await sleep(300);
  const again = await connectAndWait(token);
  check('al reconectarse recibe "ready" otra vez (señal para pedir la lista completa)', !!again.ready, again.error);
  const list = await api('GET', '/orders?scope=today');
  check('la lista completa trae la orden con su estado actual', list.data?.some?.((o: Json) => o.id === orderId && o.status === 'CANCELLED'));
  again.socket.close();

  // 8. Revocar la pantalla la desconecta al instante
  console.log('\nRevocar dispositivo');
  const disconnected = new Promise<boolean>((resolve) => {
    kds.socket.on('disconnect', () => resolve(true));
    setTimeout(() => resolve(false), WAIT_MS);
  });
  await api('POST', `/devices/${deviceId}/revoke`);
  check('la pantalla revocada queda desconectada', await disconnected);
  const retry = await connectAndWait(paired.data?.deviceToken);
  check('y ya no puede volver a conectarse', !!retry.error && !retry.ready, retry.error);
  retry.socket.close();

  // Limpieza
  const removed = await api('DELETE', `/devices/${deviceId}`);
  check('se borra la pantalla de prueba', removed.status === 204, removed.data);

  summary();
}

function summary(): void {
  console.log(failures === 0 ? '\n✅ Todo correcto\n' : `\n❌ ${failures} comprobación(es) fallaron\n`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
