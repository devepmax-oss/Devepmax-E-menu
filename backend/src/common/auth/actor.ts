import { DeviceType } from '@prisma/client';

export interface EmployeeActor {
  kind: 'employee';
  id: string;
  name: string;
  roleId: string;
  roleName: string;
  permissions: ReadonlySet<string>;
  /** Dispositivo desde el que entró con PIN (null si entró con contraseña). */
  deviceId: string | null;
}

export interface DeviceActor {
  kind: 'device';
  id: string;
  name: string;
  type: DeviceType;
  tableId: string | null;
  stationId: string | null;
  permissions: ReadonlySet<string>;
}

export type Actor = EmployeeActor | DeviceActor;
export type ActorKind = Actor['kind'];

/** Referencia estable para auditoría y sesiones: "employee:<id>", "device:<id>". */
export function actorRef(actor: Actor): string {
  return `${actor.kind}:${actor.id}`;
}
