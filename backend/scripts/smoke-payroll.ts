/**
 * Prueba de humo de nómina y desempeño: tarifas con fecha, horas extra con la regla federal y
 * la de California, pago con la tarifa de cada día, propinas al mesero de la mesa, Excel y
 * desempeño por empleado.
 * Uso:  npm run smoke:payroll   (backend encendido y seed hecho)
 *
 * Crea un empleado "Prueba nómina NNNN" (queda de baja), jornadas de la semana pasada (se
 * borran) y una mesa "Prueba nómina" con una cuenta pagada de prueba. Deja la regla de horas
 * extra como estaba.
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

async function api(method: string, path: string, body?: unknown, token = '') {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, data } as { status: number; data: any };
}

function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`  ✓ ${name}`);
  else {
    failures++;
    console.log(`  ✗ ${name}`);
    if (detail !== undefined) console.log('    ', JSON.stringify(detail).slice(0, 400));
  }
}

const addDays = (day: string, days: number) => {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};
const mondayOf = (day: string) => addDays(day, -((new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7));

async function main() {
  console.log(`\nPrueba de nómina y desempeño → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const before = await api('GET', '/payroll/settings', undefined, A);
  if (before.status === 404) {
    console.log('✗ El backend no tiene todavía la nómina. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  if (before.status === 403) {
    console.log('✗ Falta el permiso de nómina. Corre "npx prisma migrate dev" y reinicia el backend.');
    process.exit(1);
  }
  const restore = before.data as Json;
  const tz = ((await api('GET', '/settings', undefined, A)).data?.timezone as string) ?? 'America/New_York';
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(new Date());
  const lastMonday = addDays(mondayOf(today), -7);
  const thursday = addDays(lastMonday, 3);

  let employeeId = '';
  const entryIds: string[] = [];
  let tableId = '';
  let areaId = '';

  try {
    console.log('Regla y tarifas');
    const bad = await api('PATCH', '/payroll/settings', { weeklyHours: 40, dailyHours: 8, doubleDailyHours: 6 }, A);
    check('una regla sin sentido avisa (doble antes que extra)', bad.status === 400, bad.data);
    const federal = await api('PATCH', '/payroll/settings', { weeklyHours: 40, dailyHours: 0, doubleDailyHours: 0, overtimeMultiplier: 1.5, doubleMultiplier: 2 }, A);
    check('elige la regla federal (40 h por semana)', federal.status === 200 && federal.data?.preset === 'federal', federal.data);

    const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((r) => r.name === 'Mesero');
    const emp = await api('POST', '/employees', { name: `Prueba nómina ${tag}`, roleId: mesero?.id }, A);
    employeeId = emp.data?.id;
    const r1 = await api('PUT', `/payroll/rates/${employeeId}`, { hourlyRate: 15, effectiveFrom: '2024-01-01' }, A);
    const r2 = await api('PUT', `/payroll/rates/${employeeId}`, { hourlyRate: 20, effectiveFrom: thursday }, A);
    check('guarda la tarifa y un aumento con fecha', r1.status === 200 && r2.status === 200 && r2.data?.hourlyRate === 20, [r1.data, r2.data]);
    const rates = await api('GET', '/payroll/rates', undefined, A);
    const mine = (rates.data as Json[]).find((r) => r.employee.id === employeeId);
    check('la tarifa de hoy es la más reciente y queda el historial', mine?.currentRate === 20 && mine?.history?.length === 2, mine);
    const badRate = await api('PUT', `/payroll/rates/${employeeId}`, { hourlyRate: -3 }, A);
    check('una tarifa negativa avisa', badRate.status === 400, badRate.data);

    console.log('\nNómina de la semana pasada (5 días de 10 h)');
    for (let i = 0; i < 5; i++) {
      const e = await api('POST', '/timeclock/entries', { employeeId, day: addDays(lastMonday, i), clockIn: '09:00', clockOut: '19:00', reason: 'Prueba de nómina' }, A);
      if (e.data?.id) entryIds.push(e.data.id);
    }
    check('se agregan las 5 jornadas', entryIds.length === 5);
    const week1 = await api('GET', `/payroll?week=${lastMonday}`, undefined, A);
    const row1 = (week1.data?.employees as Json[] | undefined)?.find((r) => r.employee.id === employeeId);
    check('federal: 40 h normales y 10 h extra', row1?.regularMinutes === 2400 && row1?.overtimeMinutes === 600 && row1?.doubleMinutes === 0, row1);
    // Lun-Mié 30 h a $15 = $450; jue 10 h a $20 = $200; vie 10 h extra a $20 × 1.5 = $300.
    check('paga cada día con su tarifa: $450 + $200 + $300 = $950', row1?.wages === 950 && row1?.overtimePay === 300, row1);

    const ca = await api('PATCH', '/payroll/settings', { weeklyHours: 40, dailyHours: 8, doubleDailyHours: 12 }, A);
    check('elige la regla de California', ca.data?.preset === 'california', ca.data);
    const week2 = await api('GET', `/payroll?week=${lastMonday}`, undefined, A);
    const row2 = (week2.data?.employees as Json[] | undefined)?.find((r) => r.employee.id === employeeId);
    // Cada día: 8 h normales + 2 h extra. Lun-Mié 3 × (8×15 + 2×22.5) = $495; jue-vie 2 × (8×20 + 2×30) = $440.
    check('california: 8 h normales y 2 h extra cada día = $935', row2?.regularMinutes === 2400 && row2?.overtimeMinutes === 600 && row2?.wages === 935, row2);
    const two = await api('GET', `/payroll?week=${lastMonday}&weeks=2`, undefined, A);
    check('dos semanas: del lunes al domingo siguiente', two.data?.from === lastMonday && two.data?.to === addDays(lastMonday, 13) && two.data?.weeks === 2, { from: two.data?.from, to: two.data?.to });

    console.log('\nPropinas al mesero de la mesa');
    const area = (await api('POST', '/tables/areas', { name: `Prueba nómina ${tag}` }, A)).data;
    areaId = area?.id;
    const table = (await api('POST', '/tables', { label: `N${tag}`, areaId, seats: 2 }, A)).data;
    tableId = table?.id;
    await api('POST', `/tables/${tableId}/open`, { guestCount: 2 }, A);
    const waiter = await api('PATCH', `/tables/${tableId}/waiter`, { waiterId: employeeId }, A);
    check('la mesa queda a cargo del empleado', waiter.status === 200, waiter.data);
    const menu = (await api('GET', '/menu?channel=dine_in', undefined, A)).data;
    const products = (menu?.categories ?? []).flatMap((c: Json) => c.products).filter((p: Json) => p.isAvailable !== false && !(p.modifierGroups ?? []).some((g: Json) => (g.minSelect ?? 0) > 0));
    const order = await api('POST', '/orders', { clientRequestId: rid(), fulfillmentType: 'DINE_IN', tableId, items: [{ productId: products[0]?.id, quantity: 1, optionIds: [] }] }, A);
    const bill = ((await api('GET', `/billing/bills?tableId=${tableId}`, undefined, A)).data as Json[])[0];
    const paid = await api('POST', `/billing/bills/${bill?.id}/payments`, { clientRequestId: rid(), method: 'CARD_TERMINAL', amount: n(bill?.due), tip: 4, reference: 'prueba' }, A);
    check('se cobra la cuenta con $4 de propina', order.status === 201 && paid.status === 201, [order.data, paid.data]);
    const thisWeek = await api('GET', `/payroll?week=${today}`, undefined, A);
    const row3 = (thisWeek.data?.employees as Json[] | undefined)?.find((r) => r.employee.id === employeeId);
    check('la propina con tarjeta se le acredita al mesero', row3?.tips?.card === 4 && row3?.tips?.cash === 0, row3);

    const perf = await api('GET', `/performance?from=${today}&to=${today}`, undefined, A);
    const p = (perf.data?.employees as Json[] | undefined)?.find((r) => r.employee.id === employeeId);
    check('desempeño: 1 cuenta, sus ventas, 1 mesa, 2 comensales y la propina', p?.bills === 1 && p?.netSales > 0 && p?.tables === 1 && p?.guests === 2 && p?.tips === 4, p);
    const perfWeek = await api('GET', `/performance?from=${lastMonday}&to=${addDays(lastMonday, 6)}`, undefined, A);
    const pw = (perfWeek.data?.employees as Json[] | undefined)?.find((r) => r.employee.id === employeeId);
    check('desempeño: las 50 h trabajadas de la semana pasada', pw?.workedMinutes === 3000, pw);
    const tooLong = await api('GET', `/performance?from=2025-01-01&to=${today}`, undefined, A);
    check('un período muy largo avisa', tooLong.status === 400, tooLong.data);

    console.log('\nExcel');
    const link = await api('POST', '/payroll/export-link', { week: lastMonday, weeks: 1 }, A);
    check('da un enlace para descargar', link.status === 200 && typeof link.data?.url === 'string', link.data);
    if (link.data?.url) {
      const file = await fetch(link.data.url);
      const bytes = Buffer.from(await file.arrayBuffer());
      check('el enlace descarga un Excel', file.status === 200 && bytes.subarray(0, 2).toString() === 'PK' && (file.headers.get('content-disposition') ?? '').includes('nomina-'), file.status);
    }
    const forged = await fetch(`${BASE}/payroll/export/abc.def`);
    check('un enlace inventado no descarga nada', forged.status === 401, forged.status);

    console.log('\nPermisos');
    const pin = (await api('PATCH', `/employees/${employeeId}`, { email: `prueba.nomina.${tag}@example.com`, password: `Nomina-${tag}-clave` }, A)).status;
    const emp2 = await api('POST', '/auth/login', { email: `prueba.nomina.${tag}@example.com`, password: `Nomina-${tag}-clave` });
    const denied = await api('GET', `/payroll?week=${today}`, undefined, emp2.data?.accessToken);
    check('un mesero no ve la nómina', pin === 200 && denied.status === 403, denied.data);

    const del = await api('DELETE', `/payroll/rates/${r2.data?.id}`, undefined, A);
    const after = ((await api('GET', '/payroll/rates', undefined, A)).data as Json[]).find((r) => r.employee.id === employeeId);
    check('borrar el aumento deja la tarifa anterior', del.status === 200 && after?.currentRate === 15, after);
  } finally {
    for (const id of entryIds) await api('DELETE', `/timeclock/entries/${id}`, { reason: 'Limpieza de la prueba' }, A);
    if (tableId) {
      await api('POST', `/tables/${tableId}/close`, { force: true }, A);
      await api('DELETE', `/tables/${tableId}`, undefined, A);
    }
    if (areaId) await api('DELETE', `/tables/areas/${areaId}`, undefined, A);
    if (employeeId) await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Empleado de prueba' }, A);
    await api('PATCH', '/payroll/settings', {
      weeklyHours: restore.weeklyHours,
      dailyHours: restore.dailyHours,
      doubleDailyHours: restore.doubleDailyHours,
      overtimeMultiplier: restore.overtimeMultiplier,
      doubleMultiplier: restore.doubleMultiplier,
    }, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
