/**
 * Prueba de humo del inventario: proveedores, ingredientes, receta con costo y margen, entrada
 * de mercancía (costo promedio), descuento al vender y devolución al cancelar, merma, conteo,
 * agotar el plato sin existencia y reactivarlo al reponer.
 * Uso:  npm run smoke:inventory   (backend encendido y seed hecho)
 *
 * Usa una categoría "Prueba inventario" (oculta) y deja los ajustes como estaban.
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
const rid = () => randomUUID().replace(/-/g, '');
const n = (v: unknown) => Number(v ?? 0);
const near = (a: unknown, b: number) => Math.abs(n(a) - b) < 0.011;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
const tag = String(randomInt(1000, 9999));

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
  console.log(`\nPrueba de inventario → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const before = await api('GET', '/inventory/summary', undefined, A);
  if (before.status === 404) {
    console.log('✗ El backend no tiene todavía el inventario. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  if (before.status === 403) {
    console.log('✗ Falta el permiso de inventario. Cierra sesión y vuelve a entrar (o corre la migración).');
    process.exit(1);
  }
  const restore = { enabled: before.data.enabled, autoSoldOut: before.data.autoSoldOut };
  const orders: string[] = [];
  let productId = '';
  const itemIds: string[] = [];

  try {
    await api('PATCH', '/inventory/settings', { enabled: true, autoSoldOut: true }, A);

    // Plato de prueba
    const admin = (await api('GET', '/menu/admin', undefined, A)).data;
    const cats = (Array.isArray(admin) ? admin : (admin?.categories ?? [])) as Json[];
    let cat: Json | undefined = cats.find((c) => c.name === 'Prueba inventario');
    if (!cat) cat = (await api('POST', '/menu/categories', { name: 'Prueba inventario', visibleOnline: false }, A)).data;
    const product = (await api('POST', '/menu/products', { categoryId: cat!.id, name: `Hamburguesa prueba ${tag}`, price: 12.5, visibleOnline: false }, A)).data;
    productId = product.id;

    console.log('Proveedores e ingredientes');
    const supplier = await api('POST', '/inventory/suppliers', { name: `Carnes del Sur ${tag}`, phone: '305 555 0100' }, A);
    check('crea un proveedor', supplier.status === 201 && !!supplier.data?.id, supplier.data);
    const meat = await api('POST', '/inventory/items', { name: `Carne molida ${tag}`, unit: 'g', minLevel: 200, supplierId: supplier.data.id }, A);
    const bun = await api('POST', '/inventory/items', { name: `Pan de hamburguesa ${tag}`, unit: 'unit', minLevel: 2 }, A);
    check('crea ingredientes con su unidad', meat.status === 201 && meat.data?.unit === 'g' && bun.data?.unit === 'unit', [meat.data, bun.data]);
    itemIds.push(meat.data.id, bun.data.id);
    check('una unidad que no existe avisa', (await api('POST', '/inventory/items', { name: 'X', unit: 'taza' }, A)).status === 400);

    console.log('\nReceta, compra y costo');
    const recipe = await api('PUT', `/inventory/recipes/${productId}`, { lines: [{ itemId: meat.data.id, quantity: 150 }, { itemId: bun.data.id, quantity: 1 }] }, A);
    check('guarda la receta del plato', recipe.status === 200 && recipe.data?.lines?.length === 2, recipe.data);
    const receipt = await api('POST', '/inventory/receipts', {
      supplierId: supplier.data.id,
      reference: `F-${tag}`,
      lines: [
        { itemId: meat.data.id, quantity: 1000, unitCost: 0.01 },
        { itemId: bun.data.id, quantity: 10, unitCost: 0.6 },
      ],
    }, A);
    check('registra la compra (total $16)', receipt.status === 201 && near(receipt.data?.total, 16), receipt.data);
    await api('POST', '/inventory/receipts', { lines: [{ itemId: meat.data.id, quantity: 1000, unitCost: 0.014 }] }, A);
    const items1 = (await api('GET', '/inventory/items', undefined, A)).data as Json[];
    const m1 = items1.find((i) => i.id === meat.data.id);
    check('la existencia sube y el costo queda en promedio ($0.012 por g)', n(m1?.onHand) === 2000 && near(n(m1?.costPerUnit) * 1000, 12), m1);
    const plate = ((await api('GET', '/inventory/recipes', undefined, A)).data as Json[]).find((r) => r.productId === productId);
    check('costo del plato $2.40, margen $10.10, food cost 19.2 %', near(plate?.cost, 2.4) && near(plate?.margin, 10.1) && plate?.foodCostPct === 19.2, plate);

    console.log('\nVentas');
    const stock = async () => {
      await wait(700); // el inventario se descuenta justo después de cada cambio de la orden
      const all = (await api('GET', '/inventory/items', undefined, A)).data as Json[];
      return { meat: n(all.find((i) => i.id === meat.data.id)?.onHand), bun: n(all.find((i) => i.id === bun.data.id)?.onHand) };
    };
    const sale = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items: [{ productId, quantity: 2, optionIds: [] }] }, A)).data;
    orders.push(sale.id);
    const s1 = await stock();
    check('vender 2 descuenta 300 g de carne y 2 panes', s1.meat === 1700 && s1.bun === 8, s1);
    await api('POST', `/orders/${sale.id}/cancel`, { reason: 'Prueba de inventario' }, A);
    const s2 = await stock();
    check('al cancelar, todo vuelve', s2.meat === 2000 && s2.bun === 10, s2);

    console.log('\nMermas y conteos');
    const waste = await api('POST', `/inventory/items/${bun.data.id}/waste`, { quantity: 3, reason: 'Se quemaron' }, A);
    check('una merma baja la existencia', n(waste.data?.onHand) === 7, waste.data);
    const counted = await api('POST', `/inventory/items/${meat.data.id}/count`, { onHand: 200, reason: 'Conteo del lunes' }, A);
    check('el conteo físico deja la existencia contada', n(counted.data?.onHand) === 200 && counted.data?.low === true, counted.data);
    const moves = (await api('GET', `/inventory/movements?itemId=${meat.data.id}`, undefined, A)).data as Json[];
    check('el conteo queda como movimiento con la diferencia (−1800 g)', moves.some((m) => m.type === 'COUNT' && n(m.quantity) === -1800), moves.slice(0, 3));
    const summary = (await api('GET', '/inventory/summary', undefined, A)).data;
    check('el resumen suma las mermas de la semana', n(summary?.wasteLast7Days) >= 1.8 && summary?.low >= 1, summary);

    console.log('\nAgotar y reactivar');
    const last = (await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'TAKEOUT', items: [{ productId, quantity: 1, optionIds: [] }] }, A)).data;
    orders.push(last.id);
    await wait(700);
    const out = ((await api('GET', '/inventory/recipes', undefined, A)).data as Json[]).find((r) => r.productId === productId);
    check('sin carne para otra, el plato se agota solo', out?.isAvailable === false && out?.soldOutByStock === true, out);
    await api('POST', '/inventory/receipts', { lines: [{ itemId: meat.data.id, quantity: 1000, unitCost: 0.012 }] }, A);
    const back = ((await api('GET', '/inventory/recipes', undefined, A)).data as Json[]).find((r) => r.productId === productId);
    check('al reponer, vuelve a estar disponible', back?.isAvailable === true && back?.soldOutByStock === false, back);

    console.log('\nBorrar');
    check('un ingrediente con movimientos no se borra', (await api('DELETE', `/inventory/items/${meat.data.id}`, undefined, A)).status === 409);
    const spare = (await api('POST', '/inventory/items', { name: `Sobrante ${tag}`, unit: 'kg' }, A)).data;
    check('uno sin movimientos sí', (await api('DELETE', `/inventory/items/${spare.id}`, undefined, A)).status === 204);
    check('un proveedor con compras no se borra', (await api('DELETE', `/inventory/suppliers/${supplier.data.id}`, undefined, A)).status === 409);
  } finally {
    for (const id of orders) await api('POST', `/orders/${id}/cancel`, { reason: 'Prueba de inventario' }, A);
    if (productId) {
      await api('PUT', `/inventory/recipes/${productId}`, { lines: [] }, A);
      await api('PATCH', `/menu/products/${productId}`, { isActive: false }, A);
    }
    for (const id of itemIds) {
      const it = ((await api('GET', '/inventory/items', undefined, A)).data as Json[]).find((i) => i.id === id);
      if (it) await api('PATCH', `/inventory/items/${id}`, { name: it.name, unit: it.unit, isActive: false }, A);
    }
    await api('PATCH', '/inventory/settings', restore, A);
  }

  console.log(failures ? `\n❌ ${failures} prueba(s) fallaron\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
