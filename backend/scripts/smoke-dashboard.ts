/**
 * Prueba de humo del tablero del dueño: ventas de hoy que suben con una orden y bajan al
 * cancelarla, órdenes en cocina, platos del día, ventas por hora, alertas (web en pausa,
 * ingrediente bajo el mínimo) y permisos.
 * Uso:  npm run smoke:dashboard   (backend encendido y seed hecho)
 *
 * Hace una orden para llevar a nombre de "Prueba tablero NNNN" (se cancela), un ingrediente
 * de prueba (se borra) y un empleado de prueba (queda de baja). Deja los ajustes como estaban.
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
const n = (v: unknown) => Number(v ?? 0);
const near = (a: number, b: number) => Math.abs(a - b) < 0.02;

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
  console.log(`\nPrueba del tablero del dueño → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const first = await api('GET', '/dashboard/today', undefined, A);
  if (first.status === 404) {
    console.log('✗ El backend no tiene todavía el tablero. Detenlo (Ctrl+C) y vuelve a correr "npm run start:dev".');
    process.exit(1);
  }
  const settings = (await api('GET', '/settings', undefined, A)).data as Json;
  const inventory = (await api('GET', '/inventory/summary', undefined, A)).data as Json;
  const restore = { onlineOrderingPaused: settings.onlineOrderingPaused, inventoryEnabled: inventory?.enabled ?? false, autoSoldOut: inventory?.autoSoldOut ?? true };
  let orderId = '';
  let itemId = '';
  let employeeId = '';

  try {
    console.log('El día de hoy');
    const d0 = first.data as Json;
    check('responde con ventas, personal, lo de ahora, horas y alertas',
      first.status === 200 && typeof d0.sales?.net === 'number' && typeof d0.labor?.working === 'number' && typeof d0.now?.kitchen === 'number' && Array.isArray(d0.hourly) && Array.isArray(d0.alerts), Object.keys(d0 ?? {}));
    check('compara contra el mismo día de la semana pasada', d0.compareDate === new Date(Date.parse(`${d0.businessDate}T00:00:00Z`) - 7 * 86_400_000).toISOString().slice(0, 10), [d0.businessDate, d0.compareDate]);
    const hourlySum = (d0.hourly as Json[]).reduce((a, h) => a + n(h.today), 0);
    // Por hora va lo de cada orden; los descuentos a toda la cuenta solo restan del total.
    check('las ventas por hora cubren las del día', hourlySum + 0.02 >= n(d0.sales.net), { hourlySum, net: d0.sales.net });

    const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
    const product = (menu?.categories ?? []).flatMap((c: Json) => c.products ?? []).find((p: Json) => p.isAvailable !== false) as Json | undefined;
    const optionIds = (product?.modifierGroups ?? []).flatMap((g: Json) => (g.options ?? []).slice(0, g.minSelect ?? 0).map((o: Json) => o.id));
    const order = await api('POST', '/orders', {
      clientRequestId: rid(),
      fulfillmentType: 'TAKEOUT',
      customerName: `Prueba tablero ${tag}`,
      items: [{ productId: product?.id, quantity: 2, optionIds }],
    }, A);
    orderId = order.data?.id;
    const orderNet = ((order.data?.items ?? []) as Json[]).reduce((a, i) => a + n(i.lineTotal) - n(i.discount), 0);
    check('se hace una orden para llevar', order.status === 201 && orderNet > 0, order.data);
    const d1 = (await api('GET', '/dashboard/today', undefined, A)).data as Json;
    check('las ventas de hoy suben lo de la orden', near(n(d1.sales.net) - n(d0.sales.net), orderNet), { antes: d0.sales.net, despues: d1.sales.net, orden: orderNet });
    check('una orden más y una más en cocina', d1.sales.orders === d0.sales.orders + 1 && d1.now.kitchen === d0.now.kitchen + 1, { orders: [d0.sales.orders, d1.sales.orders], kitchen: [d0.now.kitchen, d1.now.kitchen] });
    check('el plato aparece entre los del día', (d1.topProducts as Json[]).some((p) => p.name === product?.name), d1.topProducts);
    check('el ticket promedio sale de las ventas entre las cuentas', near(n(d1.sales.averageTicket), d1.sales.bills ? n(d1.sales.net) / d1.sales.bills : 0), d1.sales);

    const cancel = await api('POST', `/orders/${orderId}/cancel`, { reason: 'Prueba del tablero' }, A);
    const d2 = (await api('GET', '/dashboard/today', undefined, A)).data as Json;
    check('al cancelarla, las ventas vuelven y cuenta como cancelada', cancel.status === 200 && near(n(d2.sales.net), n(d0.sales.net)) && d2.sales.cancellations === d0.sales.cancellations + 1, { net: [d0.sales.net, d2.sales.net], canceladas: d2.sales.cancellations });
    orderId = '';

    console.log('\nAlertas');
    await api('PATCH', '/settings', { onlineOrderingPaused: true }, A);
    const paused = (await api('GET', '/dashboard/today', undefined, A)).data as Json;
    const pausedAlert = (paused.alerts as Json[]).find((a) => a.id === 'online_paused');
    check('web en pausa → aviso con enlace a Ajustes', pausedAlert?.action === '/settings', paused.alerts);
    await api('PATCH', '/settings', { onlineOrderingPaused: restore.onlineOrderingPaused }, A);

    await api('PATCH', '/inventory/settings', { enabled: true, autoSoldOut: restore.autoSoldOut }, A);
    const item = await api('POST', '/inventory/items', { name: `Prueba tablero ${tag}`, unit: 'unit', minLevel: 5 }, A);
    itemId = item.data?.id;
    const low = (await api('GET', '/dashboard/today', undefined, A)).data as Json;
    const lowAlert = (low.alerts as Json[]).find((a) => a.id === 'low_stock');
    check('ingrediente bajo el mínimo → aviso', lowAlert?.action === '/inventory' && (String(lowAlert.detail).includes(`Prueba tablero ${tag}`) || /y \d+ más/.test(String(lowAlert.detail))), lowAlert);
    check('con inventario, muestra el food cost', low.foodCost !== null && typeof low.foodCost?.cost === 'number', low.foodCost);
    check('las alertas rojas van primero', (low.alerts as Json[]).every((a, i, all) => a.level !== 'danger' || all.slice(0, i).every((b) => b.level === 'danger')), (low.alerts as Json[]).map((a) => a.level));

    console.log('\nPermisos');
    const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((r) => r.name === 'Mesero');
    const emp = await api('POST', '/employees', { name: `Prueba tablero ${tag}`, roleId: mesero?.id }, A);
    employeeId = emp.data?.id;
    await api('PATCH', `/employees/${employeeId}`, { email: `prueba.tablero.${tag}@example.com`, password: `Tablero-${tag}-clave` }, A);
    const E = (await api('POST', '/auth/login', { email: `prueba.tablero.${tag}@example.com`, password: `Tablero-${tag}-clave` })).data?.accessToken;
    const denied = await api('GET', '/dashboard/today', undefined, E);
    check('un mesero no ve el tablero', denied.status === 403, denied.data);
  } finally {
    if (orderId) await api('POST', `/orders/${orderId}/cancel`, { reason: 'Limpieza de la prueba' }, A);
    if (itemId) await api('DELETE', `/inventory/items/${itemId}`, undefined, A);
    if (employeeId) await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Empleado de prueba' }, A);
    await api('PATCH', '/inventory/settings', { enabled: restore.inventoryEnabled, autoSoldOut: restore.autoSoldOut }, A);
    await api('PATCH', '/settings', { onlineOrderingPaused: restore.onlineOrderingPaused }, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
