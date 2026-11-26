import { DeviceType } from '@prisma/client';

/** Permisos de empleados (se asignan a roles). Ver docs/diseno-sistema.md, sección 5. */
export const PERMISSIONS = [
  'settings.manage',
  'employees.manage',
  'roles.manage',
  'menu.manage',
  'product.toggle_availability',
  'tables.manage',
  'devices.manage',
  'tables.operate',
  'orders.create',
  'orders.approve',
  'orders.cancel',
  'orders.void_after_kitchen',
  'kitchen.operate',
  'bills.discount',
  'payments.take',
  'payments.refund',
  'cash.shift',
  'delivery.dispatch',
  'delivery.own',
  'reports.view',
  'audit.view',
  'customers.manage',
  'inventory.manage',
  'payroll.manage',
] as const;

export type Permission = (typeof PERMISSIONS)[number];

/** Permisos exclusivos de dispositivos (no se asignan a roles). */
export const DEVICE_ONLY_PERMISSIONS = ['table.order', 'table.service_request', 'table.view_bill', 'timeclock.punch'] as const;

export type DevicePermission = (typeof DEVICE_ONLY_PERMISSIONS)[number];
export type AnyPermission = Permission | DevicePermission;

export function isPermission(value: string): value is Permission {
  return (PERMISSIONS as readonly string[]).includes(value);
}

/** Lo que puede hacer un dispositivo por sí solo (sin PIN de empleado). */
export const DEVICE_PERMISSIONS: Record<DeviceType, readonly AnyPermission[]> = {
  EMENU: ['table.order', 'table.service_request', 'table.view_bill'],
  KDS: ['kitchen.operate', 'product.toggle_availability'],
  POS: [],
  WAITER: [],
  CLOCK: ['timeclock.punch'],
};

/** Roles de fábrica. Los permisos se pueden ajustar luego desde el panel. */
export const DEFAULT_ROLES: ReadonlyArray<{ name: string; permissions: readonly Permission[] }> = [
  { name: 'Admin', permissions: PERMISSIONS },
  {
    name: 'Gerente',
    permissions: PERMISSIONS.filter((p) => p !== 'settings.manage' && p !== 'delivery.own'),
  },
  {
    name: 'Cajero',
    permissions: [
      'product.toggle_availability',
      'tables.operate',
      'orders.create',
      'orders.approve',
      'orders.cancel',
      'payments.take',
      'cash.shift',
      'delivery.dispatch',
    ],
  },
  {
    name: 'Mesero',
    permissions: [
      'product.toggle_availability',
      'tables.operate',
      'orders.create',
      'orders.approve',
      'orders.cancel',
    ],
  },
  { name: 'Cocina', permissions: ['product.toggle_availability', 'kitchen.operate'] },
  { name: 'Repartidor', permissions: ['delivery.own'] },
];

export const ADMIN_ROLE_NAME = 'Admin';
