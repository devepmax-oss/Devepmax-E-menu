/**
 * Prueba de humo de los pedidos programados: horas ofrecidas (7 días, cada 15 min, dentro
 * del horario), pedido para más tarde que espera sin ir a cocina, "enviar a cocina ya",
 * horas inválidas, desactivar la opción y cancelar un programado.
 * Uso:  npm run smoke:scheduled   (backend encendido y seed hecho)
 *
 * Crea dos pedidos web de prueba a nombre de "Prueba programado NNNN" (se cancelan al final)
 * y deja los ajustes como estaban.
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
const tag = String(randomInt(1000, 9999));
const rid = () => randomUUID().replace(/-/g, '');

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
  console.log(`\nPrueba de pedidos programados → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const probe = await api('GET', '/online/slots?fulfillmentType=PICKUP');
  if (probe.status === 404) {
    console.log('✗ El backend no tiene todavía los pedidos programados. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  const before = (await api('GET', '/settings', undefined, A)).data as Json;
  const restore = {
    acceptsPickup: before.acceptsPickup,
    onlineOrderingPaused: before.onlineOrderingPaused,
    scheduledOrdersEnabled: before.scheduledOrdersEnabled ?? true,
  };
  const orderIds: string[] = [];

  try {
    await api('PATCH', '/settings', { acceptsPickup: true, onlineOrderingPaused: false, scheduledOrdersEnabled: true }, A);

    console.log('Horas para programar');
    const config = (await api('GET', '/online/config')).data;
    check('la web sabe que se puede programar (hasta 7 días)', config?.scheduling?.enabled === true && config?.scheduling?.maxDays === 7, config?.scheduling);
    const slots = (await api('GET', '/online/slots?fulfillmentType=PICKUP')).data as Json;
    const days = (slots?.days ?? []) as Json[];
    check('ofrece horas en los próximos 7 días', slots?.enabled === true && days.length > 0 && days.length <= 7, { days: days.map((d) => d.day) });
    const allTimes = days.flatMap((d) => d.times as Json[]);
    check('cada 15 minutos', allTimes.every((t) => /^\d{2}:(00|15|30|45)$/.test(t.time)), allTimes.slice(0, 5));
    check('ninguna hora antes de lo que tarda la cocina', allTimes.every((t) => new Date(t.at).getTime() >= Date.now() + n(config?.prepTimeMinutes) * 60_000 - 60_000));

    // Un día después de hoy, a una hora "normal" (después de las 5 a. m., para no caer en la madrugada).
    const laterDay = days.slice(1).find((d) => (d.times as Json[]).some((t) => t.time >= '05:00')) ?? days[0];
    const slot = (laterDay?.times as Json[] | undefined)?.find((t) => t.time >= '05:00') ?? laterDay?.times?.[0];
    if (!slot) {
      console.log('✗ No hay horas para programar: revisa el horario del restaurante en Ajustes.');
      process.exit(1);
    }

    const menu = (await api('GET', '/menu?channel=online')).data;
    const product = (menu?.categories ?? []).flatMap((c: Json) => c.products ?? []).find((p: Json) => p.isAvailable !== false) as Json | undefined;
    const optionIds = (product?.modifierGroups ?? []).flatMap((g: Json) => (g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
    const order = (scheduledFor?: string, extra: Json = {}) =>
      api('POST', '/online/orders', {
        clientRequestId: rid(),
        fulfillmentType: 'PICKUP',
        paymentMethod: 'pay_at_pickup',
        items: [{ productId: product?.id, quantity: 1, optionIds }],
        customer: { name: `Prueba programado ${tag}`, phone: '305 555 0142' },
        ...(scheduledFor ? { scheduledFor } : {}),
        ...extra,
      });

    console.log('\nPedido programado');
    const bad = await order('2026-01-01T00:07:00.000Z');
    check('una hora que no se ofrece avisa', bad.status === 400, bad.data);
    const made = await order(slot.at);
    check('se programa un pedido para recoger', made.status === 201 && made.data?.order?.stage === 'scheduled', made.data);
    check('el seguimiento muestra la hora programada', made.data?.order?.scheduledFor === slot.at, made.data?.order?.scheduledFor);
    const active = (await api('GET', '/orders?scope=active', undefined, A)).data as Json[];
    const staffView = active.find((o) => o.publicCode === made.data?.order?.publicCode);
    if (staffView) orderIds.push(staffView.id);
    check('el personal lo ve como "Programada", sin tickets de cocina', staffView?.status === 'SCHEDULED' && staffView?.tickets?.length === 0, staffView && { status: staffView.status, tickets: staffView.tickets });
    check('pasa sola a cocina antes de la hora (lo que tarda la cocina)',
      !!staffView?.releaseAt && new Date(slot.at).getTime() - new Date(staffView.releaseAt).getTime() === n(config?.prepTimeMinutes) * 60_000, staffView?.releaseAt);
    check('cuenta en el día en que se entrega', staffView?.businessDate === laterDay.day, { businessDate: staffView?.businessDate, day: laterDay.day });

    const released = await api('POST', `/orders/${staffView?.id}/release`, undefined, A);
    check('"Enviar a cocina ya" lo manda a cocina', released.status === 200 && released.data?.status === 'PLACED' && released.data?.tickets?.length > 0, released.data?.status);
    check('queda listo para la hora que pidió el cliente', new Date(released.data?.estimatedReadyAt).toISOString() === slot.at, released.data?.estimatedReadyAt);
    const twice = await api('POST', `/orders/${staffView?.id}/release`, undefined, A);
    check('no se manda dos veces', twice.status === 409, twice.data);

    console.log('\nCancelar y desactivar');
    const second = await order(slot.at);
    const second2 = ((await api('GET', '/orders?scope=active', undefined, A)).data as Json[]).find((o) => o.publicCode === second.data?.order?.publicCode);
    if (second2) orderIds.push(second2.id);
    const cancel = await api('POST', `/orders/${second2?.id}/cancel`, { reason: 'Prueba de programados' }, A);
    check('un programado se puede cancelar', cancel.status === 200 && cancel.data?.status === 'CANCELLED', cancel.data?.status);

    await api('PATCH', '/settings', { scheduledOrdersEnabled: false }, A);
    const off = await order(slot.at);
    const offSlots = (await api('GET', '/online/slots?fulfillmentType=PICKUP')).data;
    check('desactivados, no se pueden programar', off.status === 400 && offSlots?.enabled === false && offSlots?.days?.length === 0, off.data);
  } finally {
    for (const id of orderIds) await api('POST', `/orders/${id}/cancel`, { reason: 'Limpieza de la prueba' }, A);
    await api('PATCH', '/settings', restore, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

function n(v: unknown) {
  return Number(v ?? 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
