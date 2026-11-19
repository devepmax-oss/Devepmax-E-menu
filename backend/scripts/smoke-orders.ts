/**
 * Prueba de humo del motor de órdenes contra el backend que está corriendo.
 * Uso:  npm run smoke:orders   (con el backend encendido y el seed hecho)
 *
 * Crea órdenes reales en la base de datos de DESARROLLO. No usar en producción.
 */
import { randomUUID } from 'node:crypto';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const BASE = `http://localhost:${process.env.PORT ?? 3000}/api/v1`;
let token = '';
let failures = 0;

type Json = Record<string, any>;

async function api(method: string, path: string, body?: unknown): Promise<{ status: number; data: Json | any }> {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
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

function newRequestId(): string {
  return randomUUID().replace(/-/g, '');
}

async function main(): Promise<void> {
  console.log(`\nPrueba del motor de órdenes → ${BASE}\n`);

  // 1. Login
  const login = await api('POST', '/auth/login', {
    email: process.env.SEED_ADMIN_EMAIL,
    password: process.env.SEED_ADMIN_PASSWORD,
  });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend y son correctos SEED_ADMIN_* en .env?');
    console.log('  ', login.data);
    process.exit(1);
  }
  token = login.data.accessToken;
  console.log('Sesión iniciada');

  // 2. Un producto disponible, eligiendo las opciones obligatorias
  const menu = (await api('GET', '/menu/admin')).data;
  const products = menu.categories
    .filter((c: Json) => c.isActive)
    .flatMap((c: Json) => c.products)
    .filter((p: Json) => p.isActive && p.isAvailable && p.visibleDineIn);
  if (!products.length) {
    console.log('✗ No hay productos activos y disponibles en el menú. Crea uno en la app y repite.');
    process.exit(1);
  }
  const product = products[0];
  const optionIds: string[] = [];
  for (const link of product.modifierGroups) {
    const group = link.modifierGroup;
    if (!group.isActive) continue;
    const available = group.options.filter((o: Json) => o.isAvailable);
    optionIds.push(...available.slice(0, group.minSelect).map((o: Json) => o.id));
  }
  const requiredGroup = product.modifierGroups.find((l: Json) => l.modifierGroup.isActive && l.modifierGroup.minSelect > 0);
  console.log(`Producto de prueba: "${product.name}" ($${product.price})\n`);

  // 3. Crear una orden
  console.log('Crear orden');
  const requestId = newRequestId();
  const orderBody = {
    clientRequestId: requestId,
    fulfillmentType: 'TAKEOUT',
    customerName: 'Prueba automática',
    items: [{ productId: product.id, quantity: 2, optionIds, notes: 'Sin cebolla' }],
  };
  const created = await api('POST', '/orders', orderBody);
  check('responde 201', created.status === 201, created.data);
  const order = created.data;
  if (created.status !== 201) return summary();
  check(`número del día asignado (#${order.number})`, order.number > 0);
  check(`estado inicial PLACED (${order.status})`, order.status === 'PLACED');
  check(`total calculado en el servidor ($${order.bill.total})`, Number(order.bill.total) > 0);
  check(`se creó al menos un ticket de cocina (${order.tickets.length})`, order.tickets.length >= 1);
  check('la nota de la línea se guardó', order.items[0]?.notes === 'Sin cebolla');

  // 4. Idempotencia
  console.log('\nNo duplicar órdenes');
  const repeated = await api('POST', '/orders', orderBody);
  check('reenviar la misma orden devuelve la misma (no crea otra)', repeated.data?.id === order.id, repeated.data);

  // 5. Numeración
  console.log('\nNumeración');
  const second = await api('POST', '/orders', { ...orderBody, clientRequestId: newRequestId() });
  check(`la siguiente orden es #${order.number + 1}`, second.data?.number === order.number + 1, second.data);

  // 6. Validaciones
  console.log('\nValidaciones');
  const tampered = await api('POST', '/orders', {
    ...orderBody,
    clientRequestId: newRequestId(),
    items: [{ productId: product.id, quantity: 1, price: 0.01 }],
  });
  check('rechaza que la app intente mandar su propio precio', tampered.status === 400, tampered.data);
  const unknown = await api('POST', '/orders', {
    ...orderBody,
    clientRequestId: newRequestId(),
    items: [{ productId: 'no-existe', quantity: 1 }],
  });
  check('rechaza productos inexistentes', unknown.status === 400, unknown.data);
  if (requiredGroup) {
    const missing = await api('POST', '/orders', {
      ...orderBody,
      clientRequestId: newRequestId(),
      items: [{ productId: product.id, quantity: 1, optionIds: [] }],
    });
    check(`exige elegir "${requiredGroup.modifierGroup.name}"`, missing.status === 400, missing.data);
  }

  // 7. Cocina
  console.log('\nCocina');
  const tickets = (await api('GET', '/kitchen/tickets')).data as Json[];
  const ticketIds: string[] = order.tickets.map((t: Json) => t.id);
  check('los tickets aparecen en la cocina', ticketIds.every((id) => tickets.some((t) => t.id === id)));
  for (const [status, expected] of [
    ['ACCEPTED', 'ACCEPTED'],
    ['PREPARING', 'PREPARING'],
    ['READY', 'READY'],
  ] as const) {
    for (const id of ticketIds) await api('PATCH', `/kitchen/tickets/${id}`, { status });
    const current = (await api('GET', `/orders/${order.id}`)).data;
    check(`tickets en ${status} → orden en ${expected} (${current.status})`, current.status === expected);
  }
  const back = await api('PATCH', `/kitchen/tickets/${ticketIds[0]}`, { status: 'NEW' });
  check('no permite saltar hacia atrás varios pasos', back.status === 400, back.data);

  // 8. Entregar
  console.log('\nEntrega');
  const completed = await api('POST', `/orders/${order.id}/complete`);
  check(`orden entregada (${completed.data?.status})`, completed.data?.status === 'COMPLETED', completed.data);

  // 9. Cancelar
  console.log('\nCancelación');
  const cancelled = await api('POST', `/orders/${second.data.id}/cancel`, { reason: 'Prueba automática' });
  check(`orden cancelada (${cancelled.data?.status})`, cancelled.data?.status === 'CANCELLED', cancelled.data);
  check(`la cuenta quedó en $0 (${cancelled.data?.bill?.total})`, Number(cancelled.data?.bill?.total) === 0);
  const ticketsAfter = (await api('GET', '/kitchen/tickets')).data as Json[];
  check(
    'los tickets cancelados ya no aparecen en cocina',
    !ticketsAfter.some((t) => second.data.tickets.some((st: Json) => st.id === t.id)),
  );

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
