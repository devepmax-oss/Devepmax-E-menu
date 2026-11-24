import { DeviceActor, EmployeeActor } from '../common/auth/actor';
import { DomainEvent, DomainEventName } from './domain-events.service';
import { normalizeTrackCode, publicOrderRoom, Rooms, roomsForActor, roomsForEvent, secondsUntilExpiry } from './rooms';

function employee(permissions: string[], deviceId: string | null = null): EmployeeActor {
  return {
    kind: 'employee',
    id: 'e1',
    name: 'Ana',
    roleId: 'r1',
    roleName: 'Rol',
    permissions: new Set(permissions),
    deviceId,
  };
}

function device(type: DeviceActor['type'], extra: Partial<DeviceActor> = {}): DeviceActor {
  return {
    kind: 'device',
    id: 'd1',
    name: 'Equipo',
    type,
    tableId: null,
    stationId: null,
    permissions: new Set(),
    ...extra,
  };
}

function event(name: DomainEventName, payload: unknown): DomainEvent {
  return { name, payload, at: new Date().toISOString() };
}

describe('roomsForActor', () => {
  it('un cajero entra a pos, no a cocina ni admin', () => {
    const rooms = roomsForActor(employee(['orders.create', 'payments.take']));
    expect(rooms).toEqual(expect.arrayContaining([Rooms.menu, Rooms.pos, Rooms.employee('e1')]));
    expect(rooms).not.toContain(Rooms.kitchen);
    expect(rooms).not.toContain(Rooms.admin);
  });

  it('cocina entra a todas las estaciones; un mesero a waiters', () => {
    expect(roomsForActor(employee(['kitchen.operate']))).toContain(Rooms.kitchen);
    expect(roomsForActor(employee(['tables.operate']))).toContain(Rooms.waiters);
  });

  it('admin entra a admin', () => {
    expect(roomsForActor(employee(['settings.manage']))).toContain(Rooms.admin);
    expect(roomsForActor(employee(['reports.view']))).toContain(Rooms.admin);
  });

  it('un empleado que entró con PIN cae si revocan ese dispositivo', () => {
    expect(roomsForActor(employee(['orders.create'], 'pos1'))).toContain(Rooms.device('pos1'));
  });

  it('una pantalla de cocina solo entra a su estación', () => {
    const rooms = roomsForActor(device('KDS', { stationId: 's1' }));
    expect(rooms).toContain(Rooms.station('s1'));
    expect(rooms).not.toContain(Rooms.kitchen);
    expect(rooms).not.toContain(Rooms.pos);
  });

  it('una tablet de mesa solo entra a su mesa', () => {
    const rooms = roomsForActor(device('EMENU', { tableId: 't7' }));
    expect(rooms).toEqual(expect.arrayContaining([Rooms.menu, Rooms.table('t7'), Rooms.device('d1')]));
    expect(rooms).not.toContain(Rooms.pos);
    expect(rooms).not.toContain(Rooms.waiters);
  });

  it('una pantalla de cocina sin estación no recibe tickets', () => {
    expect(roomsForActor(device('KDS')).some((r) => r.startsWith('kitchen'))).toBe(false);
  });
});

describe('roomsForEvent', () => {
  it('una orden de mesa va a caja, meseros, admin y su mesa', () => {
    const rooms = roomsForEvent(
      event('order.created', { publicCode: 'ABC', fulfillmentType: 'DINE_IN', table: { id: 't7' } }),
    );
    expect(rooms).toEqual(expect.arrayContaining([Rooms.pos, Rooms.waiters, Rooms.admin, Rooms.table('t7')]));
  });

  it('la orden completa nunca va a la room del cliente que sigue su pedido', () => {
    const rooms = roomsForEvent(event('order.updated', { publicCode: 'ABC', channel: 'ONLINE', fulfillmentType: 'PICKUP' }));
    expect(rooms).not.toContain(Rooms.order('ABC'));
  });

  it('una orden para llevar no va a los meseros ni a ninguna mesa', () => {
    const rooms = roomsForEvent(event('order.updated', { publicCode: 'X', fulfillmentType: 'TAKEOUT', table: null }));
    expect(rooms).not.toContain(Rooms.waiters);
    expect(rooms.some((r) => r.startsWith('table:'))).toBe(false);
  });

  it('un ticket va solo a cocina general y a su estación', () => {
    const rooms = roomsForEvent(event('ticket.created', { station: { id: 's1' } }));
    expect(rooms.sort()).toEqual([Rooms.kitchen, Rooms.station('s1')].sort());
  });

  it('la cuenta va a caja y a su mesa, nunca a cocina', () => {
    const rooms = roomsForEvent(event('bill.updated', { tableId: 't7' }));
    expect(rooms).toEqual(expect.arrayContaining([Rooms.pos, Rooms.table('t7')]));
    expect(rooms.some((r) => r.startsWith('kitchen'))).toBe(false);
  });

  it('agotado va a todos', () => {
    expect(roomsForEvent(event('product.availability', { id: 'p1', isAvailable: false }))).toEqual([Rooms.menu]);
  });

  it('los eventos internos no se difunden', () => {
    expect(roomsForEvent(event('device.changed', { deviceId: 'd1' }))).toEqual([]);
    expect(roomsForEvent(event('employee.changed', { employeeId: 'e1' }))).toEqual([]);
  });
});

describe('secondsUntilExpiry', () => {
  const jwt = (payload: object) =>
    `x.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.y`;

  it('lee el vencimiento del token', () => {
    const now = 1_700_000_000_000;
    expect(secondsUntilExpiry(jwt({ exp: now / 1000 + 900 }), now)).toBe(900);
  });

  it('los tokens de dispositivo (sin exp) no vencen', () => {
    expect(secondsUntilExpiry('dev_abc123')).toBeUndefined();
    expect(secondsUntilExpiry(jwt({ sub: 'x' }))).toBeUndefined();
  });
});

describe('seguimiento público', () => {
  it('solo los pedidos web tienen room de seguimiento', () => {
    expect(publicOrderRoom(event('order.updated', { publicCode: 'ABC', channel: 'ONLINE' }))).toBe(Rooms.order('ABC'));
    expect(publicOrderRoom(event('order.updated', { publicCode: 'ABC', channel: 'POS' }))).toBeUndefined();
    expect(publicOrderRoom(event('ticket.updated', { publicCode: 'ABC', channel: 'ONLINE' }))).toBeUndefined();
  });

  it('acepta solo códigos con formato válido', () => {
    expect(normalizeTrackCode(' abcd2345 ')).toBe('ABCD2345');
    expect(normalizeTrackCode('ab')).toBeUndefined();
    expect(normalizeTrackCode('ABC$1234')).toBeUndefined();
    expect(normalizeTrackCode(42)).toBeUndefined();
  });
});

describe('repartidores', () => {
  it('las entregas van solo al repartidor asignado', () => {
    expect(roomsForEvent(event('delivery.updated', { driverEmployeeId: 'e9' }))).toEqual([Rooms.employee('e9')]);
    expect(roomsForEvent(event('delivery.removed', {}))).toEqual([]);
  });

  it('la ubicación va al seguimiento del pedido y al personal', () => {
    expect(roomsForEvent(event('driver.location', { publicCode: 'ABC' }))).toEqual([Rooms.order('ABC'), Rooms.pos, Rooms.admin]);
  });
});

describe('salón', () => {
  it('el estado de una mesa va a caja, meseros, admin y a su tablet', () => {
    expect(roomsForEvent(event('table.updated', { id: 't3' }))).toEqual([Rooms.pos, Rooms.waiters, Rooms.admin, Rooms.table('t3')]);
  });

  it('un llamado de la tablet avisa al personal y a esa misma tablet', () => {
    const payload = { id: 'r1', type: 'CALL_WAITER', table: { id: 't3', label: '3' } };
    const expected = [Rooms.pos, Rooms.waiters, Rooms.admin, Rooms.table('t3')];
    expect(roomsForEvent(event('service_request.created', payload))).toEqual(expected);
    expect(roomsForEvent(event('service_request.updated', payload))).toEqual(expected);
  });
});
