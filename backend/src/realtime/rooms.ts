import { Actor } from '../common/auth/actor';
import { DomainEvent } from './domain-events.service';

/**
 * Rooms de Socket.IO. El servidor decide a cuáles entra cada socket según quién es
 * (empleado con permisos o dispositivo); el cliente nunca elige.
 */
export const Rooms = {
  /** Todos los sockets autenticados: cambios del menú (agotado). */
  menu: 'menu',
  pos: 'pos',
  waiters: 'waiters',
  admin: 'admin',
  /** Cocina de todas las estaciones (empleados con permiso de cocina). */
  kitchen: 'kitchen',
  station: (stationId: string) => `kitchen:${stationId}`,
  table: (tableId: string) => `table:${tableId}`,
  order: (publicCode: string) => `order:${publicCode}`,
  /** Control: para desconectar un dispositivo o empleado cuando cambian sus permisos. */
  device: (deviceId: string) => `device:${deviceId}`,
  employee: (employeeId: string) => `employee:${employeeId}`,
} as const;

/** Rooms a las que entra un socket al conectarse. */
export function roomsForActor(actor: Actor): string[] {
  const rooms = new Set<string>([Rooms.menu]);

  if (actor.kind === 'device') {
    rooms.add(Rooms.device(actor.id));
    switch (actor.type) {
      case 'KDS':
        if (actor.stationId) rooms.add(Rooms.station(actor.stationId));
        break;
      case 'POS':
        rooms.add(Rooms.pos);
        break;
      case 'WAITER':
        rooms.add(Rooms.waiters);
        break;
      case 'EMENU':
        if (actor.tableId) rooms.add(Rooms.table(actor.tableId));
        break;
    }
    return [...rooms];
  }

  const can = (permission: string) => actor.permissions.has(permission);
  rooms.add(Rooms.employee(actor.id));
  // Si entró con PIN en un dispositivo, también cae cuando ese dispositivo se revoca.
  if (actor.deviceId) rooms.add(Rooms.device(actor.deviceId));
  if (can('orders.create') || can('orders.approve') || can('payments.take')) rooms.add(Rooms.pos);
  if (can('tables.operate')) rooms.add(Rooms.waiters);
  if (can('kitchen.operate')) rooms.add(Rooms.kitchen);
  if (can('reports.view') || can('settings.manage')) rooms.add(Rooms.admin);
  return [...rooms];
}

interface OrderLike {
  publicCode?: string;
  channel?: string;
  fulfillmentType?: string;
  table?: { id: string } | null;
}

interface TicketLike {
  station?: { id: string };
}

interface BillLike {
  tableId?: string | null;
}

/** A qué rooms va cada evento. Los eventos internos no van a ninguna. */
export function roomsForEvent(event: DomainEvent): string[] {
  switch (event.name) {
    case 'order.created':
    case 'order.updated': {
      const order = event.payload as OrderLike;
      const rooms: string[] = [Rooms.pos, Rooms.admin];
      if (order.fulfillmentType === 'DINE_IN') rooms.push(Rooms.waiters);
      if (order.table?.id) rooms.push(Rooms.table(order.table.id));
      return rooms;
    }
    case 'ticket.created':
    case 'ticket.updated': {
      const ticket = event.payload as TicketLike;
      return ticket.station?.id ? [Rooms.kitchen, Rooms.station(ticket.station.id)] : [Rooms.kitchen];
    }
    case 'bill.updated': {
      const bill = event.payload as BillLike;
      return bill.tableId ? [Rooms.pos, Rooms.admin, Rooms.table(bill.tableId)] : [Rooms.pos, Rooms.admin];
    }
    case 'product.availability':
    case 'option.availability':
      return [Rooms.menu];
    case 'delivery.updated':
    case 'delivery.removed': {
      // Solo al repartidor de esa entrega.
      const { driverEmployeeId } = event.payload as { driverEmployeeId?: string };
      return driverEmployeeId ? [Rooms.employee(driverEmployeeId)] : [];
    }
    case 'table.updated': {
      // Caja, meseros, admin y la tablet de esa mesa.
      const { id } = event.payload as { id?: string };
      return id ? [Rooms.pos, Rooms.waiters, Rooms.admin, Rooms.table(id)] : [Rooms.pos, Rooms.waiters, Rooms.admin];
    }
    case 'driver.location': {
      // Quien sigue ese pedido (solo ve la posición) y el personal.
      const { publicCode } = event.payload as { publicCode?: string };
      return publicCode ? [Rooms.order(publicCode), Rooms.pos, Rooms.admin] : [Rooms.pos, Rooms.admin];
    }
    default:
      return [];
  }
}

/**
 * Room del cliente que sigue su pedido web. Solo recibe `order.public` (vista sin datos
 * privados), nunca la orden completa que ve el personal.
 */
export function publicOrderRoom(event: DomainEvent): string | undefined {
  if (event.name !== 'order.created' && event.name !== 'order.updated') return undefined;
  const order = event.payload as OrderLike;
  return order.channel === 'ONLINE' && order.publicCode ? Rooms.order(order.publicCode) : undefined;
}

/** Código de seguimiento válido (mismo alfabeto que los códigos públicos). */
export function normalizeTrackCode(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const code = value.trim().toUpperCase();
  return /^[A-Z0-9]{6,12}$/.test(code) ? code : undefined;
}

/** Segundos de vida que le quedan a un JWT (sin verificarlo: eso ya lo hizo AuthService). */
export function secondsUntilExpiry(token: string, nowMs = Date.now()): number | undefined {
  const part = token.split('.')[1];
  if (!part) return undefined;
  try {
    const payload = JSON.parse(Buffer.from(part, 'base64url').toString('utf8')) as { exp?: unknown };
    return typeof payload.exp === 'number' ? Math.floor(payload.exp - nowMs / 1000) : undefined;
  } catch {
    return undefined;
  }
}
