/**
 * Demostración en vivo: crea pedidos de ejemplo y los avanza en cocina, poco a poco,
 * para ver la pantalla de Órdenes actualizarse sola.
 * Uso:  npm run demo:orders   (con el backend encendido). Ctrl + C para detenerlo.
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
const NAMES = ['Luis', 'María', 'Carlos', 'Ana', 'José', 'Rosa', 'Pedro', 'Carmen'];
const KINDS = ['TAKEOUT', 'PICKUP'] as const;
const NEXT: Record<string, string> = { NEW: 'ACCEPTED', ACCEPTED: 'PREPARING', PREPARING: 'READY' };
const TOTAL_ORDERS = 6;
const TICK_MS = 5000;

type Json = Record<string, any>;
let token = '';

async function api(method: string, path: string, body?: unknown): Promise<{ status: number; data: any }> {
  let response: Response;
  try {
    response = await fetch(`${BASE}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    console.log(`\n✗ El backend no responde (${method} ${path}).`);
    console.log('  Mira la ventana del backend: el error que lo detuvo aparece allí, en rojo. Cópialo y pégalo.\n');
    process.exit(1);
  }
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : null };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const pick = <T>(list: readonly T[]): T => list[Math.floor(Math.random() * list.length)];

function lineFor(product: Json): Json {
  const optionIds: string[] = [];
  for (const link of product.modifierGroups ?? []) {
    const group = link.modifierGroup;
    if (!group?.isActive) continue;
    optionIds.push(...group.options.filter((o: Json) => o.isAvailable).slice(0, group.minSelect).map((o: Json) => o.id));
  }
  return { productId: product.id, quantity: 1 + Math.floor(Math.random() * 2), optionIds };
}

async function main(): Promise<void> {
  const login = await api('POST', '/auth/login', {
    email: process.env.SEED_ADMIN_EMAIL,
    password: process.env.SEED_ADMIN_PASSWORD,
  });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend y son correctos SEED_ADMIN_* en .env?');
    process.exit(1);
  }
  token = login.data.accessToken;

  const menu = (await api('GET', '/menu/admin')).data;
  const products: Json[] = menu.categories
    .filter((c: Json) => c.isActive)
    .flatMap((c: Json) => c.products)
    .filter((p: Json) => p.isActive && p.isAvailable);
  if (!products.length) {
    console.log('✗ No hay productos activos y disponibles. Crea alguno en la app.');
    process.exit(1);
  }

  console.log(`\nDemostración en vivo → abre la pantalla "Órdenes" en la app.`);
  console.log(`Cada ${TICK_MS / 1000} s llega un pedido o la cocina avanza uno. Ctrl + C para detener.\n`);

  const tickets: { id: string; status: string; order: number }[] = [];
  let created = 0;

  for (let tick = 0; tick < 40; tick++) {
    if (created < TOTAL_ORDERS && (tick % 2 === 0 || tickets.every((t) => t.status === 'READY'))) {
      const name = pick(NAMES);
      const kind = pick(KINDS);
      const lines = [lineFor(pick(products))];
      if (Math.random() > 0.5) lines.push(lineFor(pick(products)));
      const res = await api('POST', '/orders', {
        clientRequestId: randomUUID().replace(/-/g, ''),
        fulfillmentType: kind,
        customerName: name,
        items: lines,
      });
      if (res.status !== 201) {
        console.log('  ✗ No se pudo crear el pedido:', JSON.stringify(res.data).slice(0, 200));
      } else {
        created++;
        console.log(`  + Pedido #${res.data.number} · ${kind === 'PICKUP' ? 'Pickup' : 'Para llevar'} · ${name} · $${res.data.bill.total}`);
        for (const t of res.data.tickets) tickets.push({ id: t.id, status: t.status, order: res.data.number });
      }
    } else {
      const movable = tickets.filter((t) => NEXT[t.status]);
      if (!movable.length) {
        if (created >= TOTAL_ORDERS) break;
        await sleep(TICK_MS);
        continue;
      }
      const ticket = movable[0];
      const next = NEXT[ticket.status];
      const res = await api('PATCH', `/kitchen/tickets/${ticket.id}`, { status: next });
      if (res.status === 200) {
        ticket.status = next;
        const label: Record<string, string> = { ACCEPTED: 'aceptado', PREPARING: 'en preparación', READY: 'LISTO' };
        console.log(`  → Pedido #${ticket.order}: cocina ${label[next]}`);
      } else {
        // Cancelado desde la app o cambiado por otra persona: se deja de mover.
        ticket.status = 'DONE';
      }
    }
    await sleep(TICK_MS);
  }

  console.log('\n✅ Demostración terminada. Entrega o cancela los pedidos desde la app.\n');
}

main().catch((error) => {
  console.error('\n✗ Error inesperado:', error);
  process.exit(1);
});
