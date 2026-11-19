import { ADMIN_ROLE_NAME, DEFAULT_ROLES, DEVICE_PERMISSIONS, PERMISSIONS, isPermission } from './permissions';

describe('permisos', () => {
  it('no tiene permisos duplicados', () => {
    expect(new Set(PERMISSIONS).size).toBe(PERMISSIONS.length);
  });

  it('el rol Admin tiene todos los permisos', () => {
    const admin = DEFAULT_ROLES.find((r) => r.name === ADMIN_ROLE_NAME);
    expect([...(admin?.permissions ?? [])].sort()).toEqual([...PERMISSIONS].sort());
  });

  it('los roles de fábrica solo usan permisos válidos', () => {
    for (const role of DEFAULT_ROLES) {
      for (const permission of role.permissions) expect(isPermission(permission)).toBe(true);
    }
  });

  it('el Gerente no puede cambiar ajustes del restaurante', () => {
    const manager = DEFAULT_ROLES.find((r) => r.name === 'Gerente');
    expect(manager?.permissions).not.toContain('settings.manage');
  });

  it('las tablets de mesa no pueden operar cocina ni cobrar', () => {
    expect(DEVICE_PERMISSIONS.EMENU).not.toContain('kitchen.operate');
    expect(DEVICE_PERMISSIONS.EMENU).not.toContain('payments.take');
  });
});
