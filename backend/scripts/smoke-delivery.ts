/**
 * Prueba de humo del delivery: asignar repartidor, aceptar, recoger, ubicación en vivo y entregar.
 * Uso:  npm run smoke:delivery   (backend encendido, seed hecho y claves de PRUEBA de Stripe en .env)
 *
 * Crea (o reutiliza) el empleado "Repartidor de prueba" y un pedido de delivery real en la base
 * de DESARROLLO. No usar en producción.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { io, Socket } from 'socket.io-client';
import Stripe from 'stripe';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const ORIGIN = `http://localhost:${process.env.PORT ?? 3000}`;
const BASE = `${ORIGIN}/api/v1`;
const DRIVER_EMAIL = 'repartidor.prueba@devepmax.local';
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

function listen(socket: Socket, event: string) {
  const got: Json[] = [];
  socket.on(event, (d: Json) => got.push(d));
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
  console.log(`\nPrueba de delivery → ${BASE}\n`);
  const key = process.env.STRIPE_SECRET_KEY ?? '';
  if (!key.startsWith('sk_test_')) {
    console.log('✗ Esta prueba necesita STRIPE_SECRET_KEY de PRUEBA (sk_test_) en .env: el delivery se paga en línea.');
    process.exit(1);
  }
  const admin = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (admin.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = admin.data.accessToken as string;

  console.log('Repartidor');
  const roles = (await api('GET', '/roles', undefined, A)).data as Json[];
  // El rol Admin también tiene delivery.own (tiene todo): se busca el rol de repartidor de verdad.
  const driverRole =
    roles.find((r) => r.name === 'Repartidor') ??
    roles.find((r) => (r.permissions as string[]).includes('delivery.own') && !(r.permissions as string[]).includes('settings.manage'));
  check('existe el rol de repartidor', !!driverRole);
  if (!driverRole) return summary();
  const password = `Prueba-${randomBytes(6).toString('hex')}`;
  const employees = (await api('GET', '/employees', undefined, A)).data as Json[];
  const existing = employees.find((e) => e.email === DRIVER_EMAIL);
  const saved = existing
    ? await api('PATCH', `/employees/${existing.id}`, { password, isActive: true, roleId: driverRole.id, phone: '305 555 0177' }, A)
    : await api('POST', '/employees', { name: 'Repartidor de prueba', email: DRIVER_EMAIL, phone: '305 555 0177', roleId: driverRole.id, password }, A);
  check('repartidor de prueba listo', saved.status === 200 || saved.status === 201, saved.data);
  const driverLogin = await api('POST', '/auth/login', { email: DRIVER_EMAIL, password });
  check('el repartidor inicia sesión', driverLogin.status === 200, driverLogin.data);
  const D = driverLogin.data?.accessToken as string;
  const me = await api('PATCH', '/delivery/me', { status: 'AVAILABLE', vehicleType: 'Moto', vehicleColor: 'Roja' }, D);
  check('se marca disponible', me.data?.status === 'AVAILABLE', me.data);
  const forbidden = await api('GET', '/orders?scope=active', undefined, D);
  check('el repartidor no ve la caja ni otras órdenes', forbidden.status === 403);

  console.log('\nZona de delivery');
  const zoneBefore = (await api('GET', '/delivery/zone', undefined, A)).data;
  const zone = await api('PUT', '/delivery/zone', { fee: 3.99, minOrder: 0, etaMinutes: 35 }, A);
  check('se guarda la zona (envío, mínimo, tiempo)', zone.status === 200 && Number(zone.data?.fee) === 3.99, zone.data);
  const config = (await api('GET', '/online/config')).data;
  check('la web muestra el nuevo envío', Number(config?.delivery?.fee) === 3.99, config?.delivery);

  console.log('\nPedido de delivery');
  const menu = (await api('GET', '/menu?channel=online')).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  const optionIds: string[] = [];
  for (const g of product?.modifierGroups ?? []) optionIds.push(...(g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
  const created = await api('POST', '/online/orders', {
    clientRequestId: randomUUID().replace(/-/g, ''),
    fulfillmentType: 'DELIVERY',
    paymentMethod: 'card',
    customer: { name: 'Cliente Delivery', phone: '305 555 0199' },
    deliveryAddress: { street: '350 5th Ave', city: 'New York', state: 'NY', zipCode: '10118', instructions: 'Lobby' },
    items: [{ productId: product.id, quantity: 1, optionIds }],
    tipAmount: 3,
  });
  check('se crea el pedido', created.status === 201, created.data);
  if (created.status !== 201) return summary();
  const code: string = created.data.order.publicCode;
  check('incluye el envío de la zona', Number(created.data.order.totals.deliveryFee) === 3.99, created.data.order.totals);
  const intentId = String(created.data.payment.clientSecret).split('_secret_')[0];
  await new Stripe(key).paymentIntents.confirm(intentId, { payment_method: 'pm_card_visa', return_url: 'https://example.com' });
  const paid = await api('POST', `/online/orders/${code}/confirm-payment`);
  check('pagado y en cocina', paid.data?.stage === 'received' && paid.data?.totals?.paid === true, paid.data);
  const staffOrder = ((await api('GET', '/orders?scope=active', undefined, A)).data as Json[]).find((o) => o.publicCode === code)!;

  console.log('\nAsignar y aceptar');
  const driverSocket = await connect({ token: D });
  check('la app del repartidor se conecta en vivo', !!driverSocket);
  const driverEvents = driverSocket ? listen(driverSocket, 'delivery.updated') : [];
  const drivers = (await api('GET', '/delivery/drivers', undefined, A)).data as Json[];
  const driver = drivers.find((d) => d.name === 'Repartidor de prueba');
  check('caja ve al repartidor disponible', driver?.status === 'AVAILABLE', drivers);
  const assigned = await api('POST', `/delivery/orders/${staffOrder.id}/assign`, { driverId: driver?.id }, A);
  check('se asigna el repartidor', assigned.data?.delivery?.driver?.name === 'Repartidor de prueba', assigned.data);
  await sleep(600);
  check('al repartidor le llega la entrega al instante', driverEvents.some((e) => e.delivery?.publicCode === code && e.delivery?.status === 'PENDING'), driverEvents);
  const mine = (await api('GET', '/delivery/me/deliveries', undefined, D)).data as Json[];
  const mineOne = mine.find((m) => m.publicCode === code);
  check('aparece en "mis entregas" con dirección y teléfono', mineOne?.address?.street === '350 5th Ave' && !!mineOne?.customerPhone, mineOne);
  const accepted = await api('POST', `/delivery/assignments/${mineOne?.assignmentId}/accept`, undefined, D);
  check('el repartidor acepta', accepted.data?.status === 'ACCEPTED', accepted.data);
  const early = await api('POST', `/delivery/assignments/${mineOne?.assignmentId}/picked-up`, undefined, D);
  check('no puede salir antes de que la cocina termine', early.status === 409, early.data);

  console.log('\nCocina y salida');
  for (const t of staffOrder.tickets) await api('PATCH', `/kitchen/tickets/${t.id}`, { status: 'READY' }, A);
  const readyView = (await api('GET', `/online/orders/${code}`)).data;
  check('el cliente ve el nombre del repartidor', readyView?.driver?.firstName === 'Repartidor', readyView?.driver);
  check('sin teléfono del repartidor antes de salir', readyView?.driver?.phone === null);
  const tracker = await connect({ track: code });
  const locations = tracker ? listen(tracker, 'driver.location') : [];
  const publicUpdates = tracker ? listen(tracker, 'order.public') : [];
  const picked = await api('POST', `/delivery/assignments/${mineOne?.assignmentId}/picked-up`, undefined, D);
  check('marca "Lo recogí"', picked.data?.status === 'PICKED_UP' && picked.data?.orderStatus === 'OUT_FOR_DELIVERY', picked.data);
  await sleep(600);
  const lastPublic = publicUpdates[publicUpdates.length - 1];
  check('el cliente ve "Va en camino" al instante', lastPublic?.stage === 'on_the_way', lastPublic);
  check('ahora sí puede llamar al repartidor', !!lastPublic?.driver?.phone);

  console.log('\nUbicación en vivo');
  await api('POST', '/delivery/me/location', { lat: 40.7484, lng: -73.9857 }, D);
  await sleep(600);
  check('el mapa del cliente recibe la ubicación', locations.some((l) => l.lat === 40.7484 && l.lng === -73.9857), locations);
  const withLocation = (await api('GET', `/online/orders/${code}`)).data;
  check('al abrir el seguimiento ya trae la última ubicación', withLocation?.driverLocation?.lat === 40.7484);
  check('el seguimiento no expone la dirección exacta', !JSON.stringify(withLocation).includes('5th Ave'));

  console.log('\nEntrega');
  const done = await api('POST', `/delivery/assignments/${mineOne?.assignmentId}/delivered`, undefined, D);
  check('marca "Entregado"', done.data?.status === 'DELIVERED' && done.data?.orderStatus === 'COMPLETED', done.data);
  const finalView = (await api('GET', `/online/orders/${code}`)).data;
  check('el cliente ve el pedido entregado', finalView?.stage === 'completed');
  const after = (await api('GET', '/delivery/me/deliveries', undefined, D)).data as Json[];
  check('sale de las entregas en curso del repartidor', !after.some((m) => m.publicCode === code));

  driverSocket?.close();
  tracker?.close();
  await api('PATCH', '/delivery/me', { status: 'OFFLINE' }, D);
  await api('PUT', '/delivery/zone', { fee: Number(zoneBefore.fee), minOrder: Number(zoneBefore.minOrder), etaMinutes: zoneBefore.etaMinutes }, A);
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
