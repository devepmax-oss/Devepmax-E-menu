/**
 * Prueba de humo del reloj checador y los horarios: tablet de reloj con PIN, entrada,
 * descanso y salida, jornadas corregidas por el gerente (con motivo), descansos pagados o no,
 * tardanzas contra el turno, horario semanal (turnos de noche, copiar semana) y quién trabaja ahora.
 * Uso:  npm run smoke:timeclock   (backend encendido y seed hecho)
 *
 * Crea una tablet "Reloj prueba NNNN" (se borra al final) y un empleado "Prueba reloj NNNN"
 * que queda de baja. Deja los ajustes del reloj como estaban.
 */
import { randomInt } from 'node:crypto';

try {
  process.loadEnvFile();
} catch {
  // variables del sistema
}

const BASE = `http://localhost:${process.env.PORT ?? 3000}/api/v1`;
let failures = 0;
type Json = Record<string, any>;
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

const dayIn = (tz: string, offsetDays: number) => {
  const d = new Date(Date.now() + offsetDays * 86_400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(d);
};

async function main() {
  console.log(`\nPrueba del reloj checador → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const before = await api('GET', '/timeclock/settings', undefined, A);
  if (before.status === 404) {
    console.log('✗ El backend no tiene todavía el reloj checador. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }
  const restore = before.data as Json;
  const tz = ((await api('GET', '/settings', undefined, A)).data?.timezone as string) ?? 'America/New_York';
  const today = dayIn(tz, 0);
  const yesterday = dayIn(tz, -1);
  const tomorrow = dayIn(tz, 1);
  const nextWeek = dayIn(tz, 6);

  let deviceId = '';
  let employeeId = '';
  const entryIds: string[] = [];

  try {
    await api('PATCH', '/timeclock/settings', { paidBreakMinutes: 0, clockGraceMinutes: 5 }, A);

    console.log('Tablet de reloj');
    const device = await api('POST', '/devices', { name: `Reloj prueba ${tag}`, type: 'CLOCK' }, A);
    deviceId = device.data?.id;
    check('se crea una tablet de tipo "Reloj checador"', device.status === 201 && device.data?.type === 'CLOCK', device.data);
    const paired = await api('POST', '/auth/device/pair', { code: device.data?.pairingCode, appVersion: 'smoke' });
    const T = paired.data?.deviceToken as string;
    check('se vincula con su código', paired.status === 200 && !!T, paired.data);

    const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((r) => r.name === 'Mesero');
    const emp = await api('POST', '/employees', { name: `Prueba reloj ${tag}`, roleId: mesero?.id, generatePin: true }, A);
    employeeId = emp.data?.id;
    const pin = emp.data?.generatedPin as string;

    const wrong = await api('POST', '/timeclock/device/lookup', { pin: pin === '000000' ? '111111' : '000000' }, T);
    check('un PIN equivocado no dice nada de nadie', wrong.status === 401 && wrong.data?.message === 'PIN incorrecto', wrong.data);
    const notDevice = await api('POST', '/timeclock/device/lookup', { pin }, A);
    check('solo la tablet de reloj marca con PIN', notDevice.status === 403, notDevice.data);

    console.log('\nEntrada, descanso y salida');
    const look = await api('POST', '/timeclock/device/lookup', { pin }, T);
    check('con el PIN ve su nombre y que está fuera', look.status === 200 && look.data?.state === 'OUT' && look.data?.employee?.name === `Prueba reloj ${tag}` && look.data?.actions?.join() === 'IN', look.data);
    const early = await api('POST', '/timeclock/device/punch', { pin, action: 'BREAK_START' }, T);
    check('no puede iniciar descanso sin entrada', early.status === 409, early.data);
    const inn = await api('POST', '/timeclock/device/punch', { pin, action: 'IN' }, T);
    check('marca la entrada', inn.status === 201 && inn.data?.state === 'IN' && inn.data?.done === 'Entrada marcada', inn.data);
    const twice = await api('POST', '/timeclock/device/punch', { pin, action: 'IN' }, T);
    check('no marca dos entradas', twice.status === 409, twice.data);
    const nowIn = await api('GET', '/timeclock/now', undefined, A);
    check('aparece en "Trabajando ahora"', (nowIn.data?.working as Json[] | undefined)?.some((w) => w.employee.id === employeeId) === true, nowIn.data);
    const br = await api('POST', '/timeclock/device/punch', { pin, action: 'BREAK_START' }, T);
    check('inicia descanso', br.data?.state === 'BREAK' && br.data?.actions?.join() === 'BREAK_END,OUT', br.data);
    const brEnd = await api('POST', '/timeclock/device/punch', { pin, action: 'BREAK_END' }, T);
    check('termina descanso', brEnd.data?.state === 'IN', brEnd.data);
    const out = await api('POST', '/timeclock/device/punch', { pin, action: 'OUT' }, T);
    check('marca la salida', out.data?.state === 'OUT' && out.data?.done === 'Salida marcada', out.data);
    const todayList = await api('GET', `/timeclock/entries?from=${today}&to=${today}&employeeId=${employeeId}`, undefined, A);
    const todayEntry = (todayList.data?.entries as Json[] | undefined)?.[0];
    if (todayEntry) entryIds.push(todayEntry.id);
    check('queda una jornada de hoy con su descanso', todayList.data?.entries?.length === 1 && todayEntry?.breaks?.length === 1 && todayEntry?.open === false, todayList.data);

    console.log('\nCorrecciones del gerente');
    const noReason = await api('POST', '/timeclock/entries', { employeeId, day: yesterday, clockIn: '09:00', clockOut: '17:00', reason: '' }, A);
    check('sin motivo no se agrega', noReason.status === 400, noReason.data);
    const outside = await api('POST', '/timeclock/entries', { employeeId, day: yesterday, clockIn: '09:00', clockOut: '17:00', breaks: [{ start: '08:00', end: '08:30' }], reason: 'Prueba' }, A);
    check('un descanso fuera de la jornada avisa', outside.status === 400, outside.data);
    const manual = await api('POST', '/timeclock/entries', {
      employeeId, day: yesterday, clockIn: '09:00', clockOut: '17:00', breaks: [{ start: '12:00', end: '12:30' }], reason: 'Olvidó marcar',
    }, A);
    const manualId = manual.data?.id as string;
    if (manualId) entryIds.push(manualId);
    check('agrega una jornada de ayer (8 h con 30 min de descanso sin pagar = 7 h 30)', manual.status === 201 && manual.data?.workedMinutes === 450 && manual.data?.source === 'MANUAL', manual.data);
    const overlap = await api('POST', '/timeclock/entries', { employeeId, day: yesterday, clockIn: '16:00', clockOut: '18:00', reason: 'Doble' }, A);
    check('no deja dos jornadas encimadas', overlap.status === 409, overlap.data);

    await api('PATCH', '/timeclock/settings', { paidBreakMinutes: 30 }, A);
    const paid = await api('GET', `/timeclock/entries?from=${yesterday}&to=${yesterday}&employeeId=${employeeId}`, undefined, A);
    check('con descansos pagados de hasta 30 min cuenta 8 h', paid.data?.entries?.[0]?.workedMinutes === 480, paid.data?.entries?.[0]);
    await api('PATCH', '/timeclock/settings', { paidBreakMinutes: 0 }, A);

    console.log('\nHorario');
    const shift = await api('POST', '/schedule/shifts', { employeeId, day: yesterday, start: '09:00', end: '17:00', position: 'Sala' }, A);
    check('programa un turno', shift.status === 201 && shift.data?.minutes === 480 && shift.data?.start === '09:00', shift.data);
    const clash = await api('POST', '/schedule/shifts', { employeeId, day: yesterday, start: '16:00', end: '20:00' }, A);
    check('no deja turnos encimados', clash.status === 409, clash.data);
    const night = await api('POST', '/schedule/shifts', { employeeId, day: tomorrow, start: '18:00', end: '02:00' }, A);
    check('un turno de noche termina al día siguiente (8 h)', night.status === 201 && night.data?.minutes === 480, night.data);

    const late = await api('PUT', `/timeclock/entries/${manualId}`, {
      employeeId, day: yesterday, clockIn: '09:20', clockOut: '18:00', breaks: [{ start: '12:00', end: '12:30' }], reason: 'Llegó 9:20',
    }, A);
    check('corrige la jornada y guarda el motivo', late.status === 200 && late.data?.edited?.reason === 'Llegó 9:20', late.data);
    const lateList = await api('GET', `/timeclock/entries?from=${yesterday}&to=${yesterday}&employeeId=${employeeId}`, undefined, A);
    const lateEntry = lateList.data?.entries?.[0];
    check('cuenta 20 min tarde contra el turno de 9:00', lateEntry?.lateMinutes === 20 && lateEntry?.shift?.start === '09:00', lateEntry);
    check('el total del período suma las horas y la tardanza', lateList.data?.totals?.[0]?.workedMinutes === 490 && lateList.data?.totals?.[0]?.lateCount === 1, lateList.data?.totals);

    const week = await api('GET', `/schedule?week=${yesterday}`, undefined, A);
    check('la semana trae 7 días, el personal y los turnos', week.data?.days?.length === 7 && (week.data?.shifts as Json[]).some((s) => s.id === shift.data?.id) && (week.data?.employees as Json[]).some((e) => e.id === employeeId), week.data?.days);
    const copy = await api('POST', '/schedule/copy-week', { fromWeek: yesterday, toWeek: nextWeek }, A);
    const weekA = week.data?.weekStart;
    const weekB = (await api('GET', `/schedule?week=${nextWeek}`, undefined, A)).data?.weekStart;
    if (weekA === weekB) {
      check('copiar a la misma semana avisa', copy.status === 400, copy.data);
    } else {
      check('copia la semana a la siguiente', copy.status === 201 && copy.data?.copied >= 1, copy.data);
      const again = await api('POST', '/schedule/copy-week', { fromWeek: yesterday, toWeek: nextWeek }, A);
      check('copiar otra vez salta lo que ya está', again.data?.skipped >= 1 && again.data?.copied === 0, again.data);
    }

    console.log('\nEl gerente marca por alguien');
    const mIn = await api('POST', `/timeclock/employees/${employeeId}/punch`, { action: 'IN', reason: 'No hay tablet' }, A);
    check('marca la entrada por el empleado', mIn.status === 201 && mIn.data?.state === 'IN', mIn.data);
    const mOut = await api('POST', `/timeclock/employees/${employeeId}/punch`, { action: 'OUT' }, A);
    check('y la salida', mOut.data?.state === 'OUT', mOut.data);
    const all = await api('GET', `/timeclock/entries?from=${today}&to=${today}&employeeId=${employeeId}`, undefined, A);
    for (const e of (all.data?.entries ?? []) as Json[]) if (!entryIds.includes(e.id)) entryIds.push(e.id);
    check('queda como jornada manual', (all.data?.entries as Json[]).some((e) => e.source === 'MANUAL'), all.data?.entries);

    const del = await api('DELETE', `/timeclock/entries/${manualId}`, { reason: 'Prueba terminada' }, A);
    check('borra una jornada con motivo', del.status === 200, del.data);

    const history = await api('GET', `/employees/${employeeId}/history?scope=about`, undefined, A);
    const actions = ((history.data?.items ?? []) as Json[]).map((i) => i.action);
    check('el historial del empleado guarda marcas y correcciones',
      ['timeclock.in', 'timeclock.out', 'timeclock.entry_create', 'timeclock.entry_update', 'timeclock.entry_delete'].every((a) => actions.includes(a)), actions);
  } finally {
    if (employeeId) {
      for (const w of [yesterday, tomorrow, nextWeek]) {
        const wk = await api('GET', `/schedule?week=${w}`, undefined, A);
        for (const s of (wk.data?.shifts ?? []) as Json[]) if (s.employeeId === employeeId) await api('DELETE', `/schedule/shifts/${s.id}`, undefined, A);
      }
      for (const id of entryIds) await api('DELETE', `/timeclock/entries/${id}`, { reason: 'Limpieza de la prueba' }, A);
      await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Empleado de prueba' }, A);
    }
    if (deviceId) await api('DELETE', `/devices/${deviceId}`, undefined, A);
    await api('PATCH', '/timeclock/settings', { paidBreakMinutes: restore.paidBreakMinutes, clockGraceMinutes: restore.clockGraceMinutes }, A);
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
