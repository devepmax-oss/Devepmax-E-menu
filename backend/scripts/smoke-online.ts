/**
 * Prueba de humo de los pedidos online (la web) contra el backend que está corriendo.
 * Uso:  npm run smoke:online   (con el backend encendido y el seed hecho)
 *
 * Sin claves de Stripe prueba "pagar al recoger". Con STRIPE_SECRET_KEY de PRUEBA (sk_test_)
 * en .env también prueba el pago con tarjeta usando la tarjeta de prueba de Stripe.
 * Crea pedidos reales en la base de DESARROLLO y al final los cancela. No usar en producción.
 */
import { randomUUID } from 'node:crypto';
import { io } from 'socket.io-client';
import Stripe from 'stripe';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const ORIGIN = `http://localhost:${process.env.PORT ?? 3000}`;
const BASE = `${ORIGIN}/api/v1`;
let failures = 0;
let staffToken = '';
const created: string[] = [];

type Json = Record<string, any>;

async function api(method: string, path: string, body?: unknown, token = ''): Promise<{ status: number; data: any }> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
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

const requestId = () => randomUUID().replace(/-/g, '');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function main(): Promise<void> {
  console.log(`\nPrueba de pedidos online → ${BASE}\n`);
  const login = await api('POST', '/auth/login', {
    email: process.env.SEED_ADMIN_EMAIL,
    password: process.env.SEED_ADMIN_PASSWORD,
  });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  staffToken = login.data.accessToken;

  // Producto disponible en la web
  const menu = (await api('GET', '/menu?channel=online')).data;
  const product = (menu?.categories ?? []).flatMap((c: Json) => c.products).find((p: Json) => p.isAvailable !== false);
  if (!product) {
    console.log('✗ No hay productos visibles en la web. Revisa "Visible en la web" en el menú.');
    process.exit(1);
  }
  const optionIds: string[] = [];
  for (const link of product.modifierGroups ?? []) {
    const group = link.modifierGroup ?? link;
    optionIds.push(...(group.options ?? []).slice(0, group.minSelect ?? 0).map((o: Json) => o.id));
  }
  const items = [{ productId: product.id, quantity: 2, optionIds }];
  console.log(`Producto de prueba: "${product.name}"\n`);

  console.log('Configuración pública');
  const config = await api('GET', '/online/config');
  check('la web obtiene marca, horario y canales sin iniciar sesión', config.status === 200 && !!config.data?.name, config.data);
  check('indica si el pago con tarjeta está disponible', typeof config.data?.payments?.card === 'boolean');
  const cardEnabled = config.data?.payments?.card === true;
  if (!config.data?.isOpenNow) {
    console.log('\n  ⚠ El restaurante figura CERRADO ahora según el horario de Ajustes; los pedidos se rechazarán.');
  }

  console.log('\nCotización');
  const quote = await api('POST', '/online/quote', { fulfillmentType: 'PICKUP', items, tipAmount: 2 });
  check('cotiza el carrito con precios del servidor', quote.status === 200 && Number(quote.data?.totals?.total) > 0, quote.data);
  check('suma la propina al total', Number(quote.data?.totals?.tipTotal) === 2);

  console.log('\nValidaciones');
  const noAddress = await api('POST', '/online/orders', {
    clientRequestId: requestId(), fulfillmentType: 'DELIVERY', paymentMethod: 'card',
    customer: { name: 'Prueba web', phone: '305 555 0100' }, items,
  });
  check('delivery sin dirección se rechaza', noAddress.status === 400 || noAddress.status === 503, noAddress.data);
  const deliveryCash = await api('POST', '/online/orders', {
    clientRequestId: requestId(), fulfillmentType: 'DELIVERY', paymentMethod: 'pay_at_pickup',
    customer: { name: 'Prueba web', phone: '305 555 0100' },
    deliveryAddress: { street: '123 Main St', city: 'Miami', state: 'FL', zipCode: '33101' }, items,
  });
  check('delivery pagando al recoger se rechaza', deliveryCash.status === 400 || deliveryCash.status === 503, deliveryCash.data);
  const badPhone = await api('POST', '/online/orders', {
    clientRequestId: requestId(), fulfillmentType: 'PICKUP', paymentMethod: 'pay_at_pickup',
    customer: { name: 'Prueba web', phone: 'abc' }, items,
  });
  check('un teléfono inválido se rechaza', badPhone.status === 400, badPhone.data);

  console.log('\nPedido pagando al recoger');
  const pickupBody = {
    clientRequestId: requestId(), fulfillmentType: 'PICKUP', paymentMethod: 'pay_at_pickup',
    customer: { name: 'Prueba Web Smoke', phone: '305 555 0100', email: 'prueba@example.com' }, items, tipAmount: 2,
  };
  const pickup = await api('POST', '/online/orders', pickupBody);
  check('el pedido se crea', pickup.status === 201, pickup.data);
  const code: string = pickup.data?.order?.publicCode;
  if (pickup.status !== 201) return summary();
  check(`va directo a cocina (${pickup.data.order.stage})`, pickup.data.order.stage === 'received');
  check('no pide cobro con tarjeta', pickup.data.payment === null);
  const again = await api('POST', '/online/orders', pickupBody);
  check('reenviar el mismo pedido no lo duplica', again.data?.order?.publicCode === code, again.data);

  const publicView = await api('GET', `/online/orders/${code}`);
  check('el cliente ve su pedido con el código', publicView.status === 200 && publicView.data?.number === pickup.data.order.number);
  const raw = JSON.stringify(publicView.data);
  check('la vista pública no expone teléfono ni email', !raw.includes('555') && !raw.includes('prueba@example.com'));
  const unknown = await api('GET', '/online/orders/ZZZZZZZZ');
  check('un código inexistente da 404', unknown.status === 404);

  const staffOrders = (await api('GET', '/orders?scope=active', undefined, staffToken)).data as Json[];
  const staffOrder = staffOrders.find((o) => o.publicCode === code);
  check('aparece en la pantalla de Órdenes como canal Web', staffOrder?.channel === 'ONLINE', staffOrder);
  if (staffOrder) created.push(staffOrder.id);

  console.log('\nSeguimiento en vivo');
  const tracker = io(ORIGIN, { auth: { track: code }, transports: ['websocket'], reconnection: false });
  const updates: Json[] = [];
  tracker.on('order.public', (data: Json) => updates.push(data));
  const ready = await new Promise<boolean>((resolve) => {
    tracker.on('ready', () => resolve(true));
    tracker.on('connect_error', () => resolve(false));
    setTimeout(() => resolve(false), 4000);
  });
  check('el cliente se conecta sin cuenta, solo con su código', ready);
  const ticketId = staffOrder?.tickets?.[0]?.id;
  if (ticketId) {
    await api('PATCH', `/kitchen/tickets/${ticketId}`, { status: 'ACCEPTED' }, staffToken);
    await sleep(800);
    const last = updates[updates.length - 1];
    check('recibe al instante que la cocina empezó', last?.stage === 'preparing', last);
    check('el aviso en vivo tampoco expone datos privados', !JSON.stringify(updates).includes('555'));
  }
  const snoop = io(ORIGIN, { auth: { track: code }, transports: ['websocket'], reconnection: false });
  const snoopGotStaffData = await new Promise<boolean>((resolve) => {
    snoop.on('order.updated', () => resolve(true));
    setTimeout(() => resolve(false), 1500);
  });
  check('quien sigue un pedido no recibe datos de caja', !snoopGotStaffData);
  tracker.close();
  snoop.close();

  if (cardEnabled) {
    console.log('\nPago con tarjeta (modo prueba de Stripe)');
    const key = process.env.STRIPE_SECRET_KEY ?? '';
    if (!key.startsWith('sk_test_')) {
      console.log('  ⚠ STRIPE_SECRET_KEY no es de prueba (sk_test_): se omite el cobro de prueba.');
    } else {
      const card = await api('POST', '/online/orders', {
        clientRequestId: requestId(), fulfillmentType: 'PICKUP', paymentMethod: 'card',
        customer: { name: 'Prueba Tarjeta', phone: '305 555 0101' }, items,
      });
      check('el pedido con tarjeta se crea', card.status === 201, card.data);
      const cardCode: string = card.data?.order?.publicCode;
      check('queda esperando el pago (no va a cocina todavía)', card.data?.order?.stage === 'awaiting_payment');
      check('devuelve el cobro para el navegador', !!card.data?.payment?.clientSecret);
      const pending = (await api('GET', '/orders?scope=active', undefined, staffToken)).data as Json[];
      const pendingOrder = pending.find((o) => o.publicCode === cardCode);
      if (pendingOrder) created.push(pendingOrder.id);
      check('sin pagar no tiene tickets de cocina', (pendingOrder?.tickets?.length ?? 0) === 0);

      // Lo que haría el navegador con la tarjeta de prueba 4242 4242 4242 4242.
      const stripe = new Stripe(key);
      const intentId = String(card.data.payment.clientSecret).split('_secret_')[0];
      await stripe.paymentIntents.confirm(intentId, { payment_method: 'pm_card_visa', return_url: 'https://example.com' });
      const confirmed = await api('POST', `/online/orders/${cardCode}/confirm-payment`);
      check(`al confirmar el pago pasa a cocina (${confirmed.data?.stage})`, confirmed.data?.stage === 'received', confirmed.data);
      check('la cuenta queda pagada', confirmed.data?.totals?.paid === true, confirmed.data?.totals);
      const twice = await api('POST', `/online/orders/${cardCode}/confirm-payment`);
      check('confirmar dos veces no cobra ni duplica nada', twice.data?.totals?.amountPaid === confirmed.data?.totals?.amountPaid);
    }
  } else {
    console.log('\n(Pago con tarjeta: se probará cuando agregues las claves de prueba de Stripe en .env)');
  }

  // Limpieza: cancelar los pedidos de prueba que no tienen pagos.
  for (const id of created) {
    await api('POST', `/orders/${id}/cancel`, { reason: 'Prueba automática online' }, staffToken);
  }
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
