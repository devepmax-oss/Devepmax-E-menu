/**
 * Prueba de humo de los tiempos de cocina: un ticket que pasa por Empezar y Listo cuenta en
 * el total, en su estación y en su plato; uno sin Listo queda como "sin marcar"; fechas
 * inválidas y permisos.
 * Uso:  npm run smoke:kitchen-times   (backend encendido y seed hecho)
 *
 * Hace dos órdenes para llevar a nombre de "Prueba tiempos NNNN" (se cancelan o se completan).
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
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 500));
  }
}

async function main() {
  console.log(`\nPrueba de los tiempos de cocina → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const first = await api('GET', '/dashboard/kitchen', undefined, A);
  if (first.status === 404) {
    console.log('✗ El backend no tiene todavía los tiempos de cocina. Detenlo (Ctrl+C) y vuelve a correr "npm run start:dev".');
    process.exit(1);
  }
  const today = first.data?.from as string;
  const get = async () => (await api('GET', `/dashboard/kitchen?from=${today}&to=${today}`, undefined, A)).data as Json;
  const orders: string[] = [];
  let employeeId = '';

  try {
    console.log('Hoy');
    const k0 = await get();
    const settings = (await api('GET', '/settings', undefined, A)).data as Json;
    check('responde con resumen, estaciones, platos, horas y los más lentos',
      typeof k0.summary?.tickets === 'number' && Array.isArray(k0.stations) && Array.isArray(k0.dishes) && Array.isArray(k0.hours) && Array.isArray(k0.slowest), Object.keys(k0 ?? {}));
    check('la meta es el tiempo de preparación de Ajustes', k0.targetMinutes === settings.prepTimeMinutes, [k0.targetMinutes, settings.prepTimeMinutes]);

    const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
    const product = (menu?.categories ?? []).flatMap((c: Json) => c.products ?? []).find((p: Json) => p.isAvailable !== false) as Json | undefined;
    const optionIds = (product?.modifierGroups ?? []).flatMap((g: Json) => (g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
    const order = async () => {
      const r = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', customerName: `Prueba tiempos ${tag}`, items: [{ productId: product?.id, quantity: 2, optionIds }] }, A);
      if (r.data?.id) orders.push(r.data.id);
      return r;
    };

    console.log('\nUn ticket que llega a Listo');
    const o1 = await order();
    const ticket = (o1.data?.tickets ?? [])[0] as Json | undefined;
    check('se hace una orden con su ticket de cocina', o1.status === 201 && !!ticket?.id, o1.data);
    const started = await api('PATCH', `/kitchen/tickets/${ticket?.id}`, { status: 'PREPARING' }, A);
    const ready = await api('PATCH', `/kitchen/tickets/${ticket?.id}`, { status: 'READY' }, A);
    check('la cocina lo empieza y lo marca Listo', started.status === 200 && ready.status === 200, [started.data, ready.data]);
    const k1 = await get();
    check('cuenta un ticket más con tiempo', k1.summary.count === k0.summary.count + 1 && k1.summary.tickets === k0.summary.tickets + 1, [k0.summary, k1.summary]);
    check('tiene espera y preparación', k1.summary.wait.count === k0.summary.wait.count + 1 && k1.summary.prep.count === k0.summary.prep.count + 1);
    const station = (k1.stations as Json[]).find((x) => x.id === ticket?.station?.id);
    const before = (k0.stations as Json[]).find((x) => x.id === ticket?.station?.id);
    check('suma en su estación', !!station && station.count === (before?.count ?? 0) + 1, station);
    const dish = (k1.dishes as Json[]).find((d) => d.productId === product?.id);
    const dish0 = (k0.dishes as Json[]).find((d) => d.productId === product?.id);
    check('suma en su plato (2 unidades)', !!dish && dish.units === (dish0?.units ?? 0) + 2 && dish.count === (dish0?.count ?? 0) + 1, dish);
    check('aparece en las horas del día', (k1.hours as Json[]).reduce((a, h) => a + h.count, 0) === k1.summary.count);

    console.log('\nUn ticket sin Listo');
    const o2 = await order();
    check('se hace otra orden', o2.status === 201, o2.data);
    const k2 = await get();
    check('cuenta como ticket sin marcar Listo, sin tiempo', k2.summary.notMarked === k1.summary.notMarked + 1 && k2.summary.count === k1.summary.count, k2.summary);

    console.log('\nFechas y permisos');
    check('una fecha inválida avisa', (await api('GET', '/dashboard/kitchen?from=2026-13-01', undefined, A)).status === 400);
    const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((x) => x.name === 'Mesero');
    const emp = await api('POST', '/employees', { name: `Prueba tiempos ${tag}`, roleId: mesero?.id }, A);
    employeeId = emp.data?.id;
    await api('PATCH', `/employees/${employeeId}`, { email: `prueba.tiempos.${tag}@example.com`, password: `Tiempos-${tag}-clave` }, A);
    const E = (await api('POST', '/auth/login', { email: `prueba.tiempos.${tag}@example.com`, password: `Tiempos-${tag}-clave` })).data?.accessToken;
    check('un mesero no ve los tiempos', (await api('GET', '/dashboard/kitchen', undefined, E)).status === 403);
  } finally {
    for (const id of orders) {
      const c = await api('POST', `/orders/${id}/cancel`, { reason: 'Prueba de tiempos de cocina' }, A);
      if (c.status !== 200) await api('POST', `/orders/${id}/complete`, {}, A);
    }
    if (employeeId) await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Empleado de prueba' }, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
