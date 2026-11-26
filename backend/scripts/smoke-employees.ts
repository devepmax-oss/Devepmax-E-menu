/**
 * Prueba de humo del módulo de Empleados (bloque 1): ficha completa, foto, roles propios con
 * permisos que aplican al instante, cerrar sesiones, baja y reactivación, e historial.
 * Uso:  npm run smoke:employees   (backend encendido y seed hecho)
 *
 * Crea un rol "Prueba rol NNNN" (se borra al final) y un empleado "Prueba empleados NNNN"
 * que queda dado de baja (los empleados no se borran, para conservar su historial).
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
// PNG de 8x8 px (sirve para probar la subida de la foto)
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC',
  'base64',
);

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
  console.log(`\nPrueba de empleados → ${BASE}\n`);
  const login = await api('POST', '/auth/login', { email: process.env.SEED_ADMIN_EMAIL, password: process.env.SEED_ADMIN_PASSWORD });
  if (login.status !== 200) {
    console.log('✗ No se pudo iniciar sesión. ¿Está encendido el backend?');
    process.exit(1);
  }
  const A = login.data.accessToken as string;
  const adminId = login.data.employee.id as string;
  const probe = await api('GET', '/roles/permissions', undefined, A);
  if (probe.status === 404) {
    console.log('✗ El backend no tiene todavía el módulo nuevo. Detenlo (Ctrl+C), corre "npx prisma migrate dev" y luego "npm run start:dev".');
    process.exit(1);
  }

  const email = `prueba.empleados.${tag}@example.com`;
  const password = `Prueba-${tag}-clave`;
  let roleId = '';
  let employeeId = '';
  let customerId = '';

  try {
    console.log('Roles');
    const roles = await api('GET', '/roles', undefined, A);
    const adminRole = (roles.data as Json[]).find((r) => r.name === 'Admin');
    const mesero = (roles.data as Json[]).find((r) => r.name === 'Mesero');
    check('lista los roles con cuántos empleados tiene cada uno', roles.status === 200 && typeof adminRole?.employeeCount === 'number', roles.data);
    check('el catálogo de permisos incluye los nuevos', (probe.data as string[]).includes('inventory.manage'));

    const role = await api('POST', '/roles', { name: `Prueba rol ${tag}`, description: 'Solo pruebas', permissions: ['orders.create', 'tables.operate'] }, A);
    roleId = role.data?.id;
    check('crea un rol propio', role.status === 201 && role.data?.isSystem === false, role.data);
    const dup = await api('POST', '/roles', { name: `Prueba rol ${tag}`, permissions: [] }, A);
    check('no deja dos roles con el mismo nombre', dup.status === 409, dup.data);
    const bad = await api('POST', '/roles', { name: `Otro ${tag}`, permissions: ['volar.alto'] }, A);
    check('un permiso que no existe avisa', bad.status === 400, bad.data);
    const lockAdmin = await api('PATCH', `/roles/${adminRole?.id}`, { name: 'Admin', permissions: ['orders.create'] }, A);
    check('el rol Admin no se edita', lockAdmin.status === 400, lockAdmin.data);
    const renameSystem = await api('PATCH', `/roles/${mesero?.id}`, { name: 'Mesera', permissions: mesero?.permissions ?? [] }, A);
    check('un rol de fábrica no se renombra', renameSystem.status === 400, renameSystem.data);

    console.log('\nFicha completa');
    const created = await api('POST', '/employees', {
      name: `Prueba empleados ${tag}`,
      email,
      phone: '305 555 0101',
      roleId,
      password,
      generatePin: true,
      jobTitle: 'Hostess',
      hireDate: '2026-03-15',
      address: '100 Main St, Miami, FL',
      emergencyName: 'María Pérez',
      emergencyPhone: '305 555 0199',
      notes: 'Turno de tarde',
    }, A);
    employeeId = created.data?.id;
    check('crea el empleado con su ficha', created.status === 201 && created.data?.jobTitle === 'Hostess' && created.data?.hireDate === '2026-03-15' && created.data?.emergencyName === 'María Pérez', created.data);
    check('el PIN lo genera el sistema (6 dígitos, una sola vez)', /^\d{6}$/.test(created.data?.generatedPin ?? ''));
    const badDate = await api('PATCH', `/employees/${employeeId}`, { hireDate: '15/03/2026' }, A);
    check('una fecha mal escrita avisa', badDate.status === 400, badDate.data);
    const cleared = await api('PATCH', `/employees/${employeeId}`, { address: null, notes: '' }, A);
    check('borrar un dato de la ficha', cleared.status === 200 && cleared.data?.address === null && cleared.data?.notes === null, cleared.data);

    const form = new FormData();
    form.append('file', new Blob([PNG], { type: 'image/png' }), 'foto.png');
    const photoRes = await fetch(`${BASE}/employees/${employeeId}/photo`, { method: 'POST', headers: { Authorization: `Bearer ${A}` }, body: form });
    const photo = (await photoRes.json()) as Json;
    check('sube la foto', photoRes.status === 201 && typeof photo.photoUrl === 'string', photo);
    const noPhoto = await api('DELETE', `/employees/${employeeId}/photo`, undefined, A);
    check('quita la foto', noPhoto.status === 200 && noPhoto.data?.photoUrl === null, noPhoto.data);

    console.log('\nPermisos al instante');
    const emp = await api('POST', '/auth/login', { email, password });
    check('el empleado entra con su contraseña', emp.status === 200, emp.data);
    const E = emp.data?.accessToken as string;
    const R = emp.data?.refreshToken as string;
    const noList = await api('GET', '/employees', undefined, E);
    check('sin el permiso no ve la lista de empleados', noList.status === 403);
    const noCustomers = await api('GET', '/customers', undefined, E);
    check('sin "Clientes" no entra a clientes', noCustomers.status === 403);
    const grant = await api('PATCH', `/roles/${roleId}`, { name: `Prueba rol ${tag}`, permissions: ['orders.create', 'tables.operate', 'customers.manage'] }, A);
    check('se le agrega un permiso al rol', grant.status === 200 && grant.data?.employeeCount === 1, grant.data);
    const yesCustomers = await api('GET', '/customers', undefined, E);
    check('el permiso nuevo aplica sin volver a entrar', yesCustomers.status === 200, yesCustomers.data);
    const revoke = await api('PATCH', `/roles/${roleId}`, { name: `Prueba rol ${tag}`, permissions: ['orders.create', 'tables.operate'] }, A);
    const againNo = await api('GET', '/customers', undefined, E);
    check('al quitarlo, deja de tenerlo al instante', revoke.status === 200 && againNo.status === 403);
    const selfRole = await api('POST', '/roles', { name: `Sube ${tag}`, permissions: ['settings.manage'] }, E);
    check('un empleado sin permiso de roles no crea roles', selfRole.status === 403);

    const customer = await api('POST', '/customers', { name: `Cliente prueba ${tag}`, phone: `305555${tag}` }, E);
    customerId = customer.data?.id;
    check('el empleado hace algo (registra un cliente)', customer.status === 201, customer.data);

    console.log('\nAcceso y sesiones');
    const detail = await api('GET', `/employees/${employeeId}`, undefined, A);
    check('la ficha muestra sesiones abiertas y último acceso', detail.status === 200 && detail.data?.access?.activeSessions >= 1 && !!detail.data?.access?.lastLoginAt, detail.data);
    const selfOut = await api('POST', `/employees/${adminId}/logout-all`, undefined, A);
    check('no te cierras tus propias sesiones desde aquí', selfOut.status === 400);
    const out = await api('POST', `/employees/${employeeId}/logout-all`, undefined, A);
    check('cierra todas sus sesiones', out.status === 201 && out.data?.closed >= 1, out.data);
    const refresh = await api('POST', '/auth/refresh', { refreshToken: R });
    check('su sesión ya no se puede renovar', refresh.status === 401, refresh.data);
    const delWithPeople = await api('DELETE', `/roles/${roleId}`, undefined, A);
    check('un rol con empleados no se borra', delWithPeople.status === 409, delWithPeople.data);

    console.log('\nBaja y reactivación');
    const term = await api('PATCH', `/employees/${employeeId}`, { isActive: false, terminationReason: 'Fin de temporada' }, A);
    check('dar de baja guarda la fecha y el motivo', term.status === 200 && term.data?.isActive === false && !!term.data?.terminatedAt && term.data?.terminationReason === 'Fin de temporada', term.data);
    const blocked = await api('POST', '/auth/login', { email, password });
    check('dado de baja ya no puede entrar', blocked.status === 401, blocked.data);
    const back = await api('PATCH', `/employees/${employeeId}`, { isActive: true }, A);
    check('reactivar borra la baja', back.status === 200 && back.data?.isActive === true && back.data?.terminatedAt === null, back.data);

    console.log('\nHistorial');
    const all = await api('GET', `/employees/${employeeId}/history`, undefined, A);
    const actions = ((all.data?.items ?? []) as Json[]).map((i) => i.action);
    check('incluye alta, foto, acceso, cierre de sesiones, baja y reactivación',
      ['employee.create', 'employee.photo', 'auth.login', 'employee.logout_all', 'employee.terminate', 'employee.reactivate'].every((a) => actions.includes(a)), actions);
    const createdBy = ((all.data?.items ?? []) as Json[]).find((i) => i.action === 'employee.create');
    check('dice quién hizo cada cambio', !!createdBy?.actorName && createdBy?.about === true, createdBy);
    const did = await api('GET', `/employees/${employeeId}/history?scope=actions`, undefined, A);
    const didActions = ((did.data?.items ?? []) as Json[]).map((i) => i.action);
    check('"Lo que hizo" muestra sus acciones', didActions.includes('customer.create') && !didActions.includes('employee.create'), didActions);
    const page = await api('GET', `/employees/${employeeId}/history?take=2`, undefined, A);
    const next = await api('GET', `/employees/${employeeId}/history?take=2&cursor=${page.data?.nextCursor}`, undefined, A);
    check('se puede ver por páginas', page.data?.items?.length === 2 && !!page.data?.nextCursor && next.data?.items?.[0]?.id !== page.data?.items?.[0]?.id, page.data);
  } finally {
    if (customerId) await api('DELETE', `/customers/${customerId}`, undefined, A);
    if (employeeId) {
      const mesero = ((await api('GET', '/roles', undefined, A)).data as Json[]).find((r) => r.name === 'Mesero');
      await api('PATCH', `/employees/${employeeId}`, { roleId: mesero?.id, isActive: false, terminationReason: 'Empleado de prueba' }, A);
    }
    if (roleId) {
      const del = await api('DELETE', `/roles/${roleId}`, undefined, A);
      check('borra el rol de prueba al final', del.status === 200, del.data);
    }
  }

  console.log(failures ? `\n❌ ${failures} fallas\n` : '\n✅ Todo correcto\n');
  process.exit(failures ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
