import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Employee, Prisma, Role } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { generateEmployeePin, hashPassword, hashPin } from '../../common/crypto';
import { ADMIN_ROLE_NAME } from '../../common/permissions';
import { ImageService } from '../../storage/image.service';
import { loadEnv } from '../../config/env';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { AuthService } from '../auth/auth.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { CreateEmployeeDto, EmployeeHistoryQueryDto, SaveRoleDto, UpdateEmployeeDto } from './dto/employee.dto';

type EmployeeWithRole = Employee & { role: Role };

const PIN_ATTEMPTS = 20;

/** Acciones de entrada que cuentan como "último acceso". */
const LOGIN_ACTIONS = ['auth.login', 'auth.pin_login', 'auth.staff_pin'];

const toDay = (date: Date | null) => (date ? date.toISOString().slice(0, 10) : null);
const fromDay = (day: string) => new Date(`${day}T00:00:00.000Z`);
/** Texto limpio; vacío o null quita el dato; undefined no lo toca. */
const clean = (value: string | null | undefined) =>
  value === undefined ? undefined : value === null || !value.trim() ? null : value.trim();

export function toEmployeeView(employee: EmployeeWithRole) {
  return {
    id: employee.id,
    name: employee.name,
    email: employee.email,
    phone: employee.phone,
    isActive: employee.isActive,
    hasPassword: !!employee.passwordHash,
    hasPin: !!employee.pinHash,
    role: { id: employee.role.id, name: employee.role.name },
    jobTitle: employee.jobTitle,
    photoUrl: employee.photoUrl,
    hireDate: toDay(employee.hireDate),
    address: employee.address,
    emergencyName: employee.emergencyName,
    emergencyPhone: employee.emergencyPhone,
    notes: employee.notes,
    terminatedAt: employee.terminatedAt,
    terminationReason: employee.terminationReason,
    createdAt: employee.createdAt,
    updatedAt: employee.updatedAt,
  };
}

function profileData(dto: CreateEmployeeDto | UpdateEmployeeDto) {
  return {
    jobTitle: clean(dto.jobTitle),
    hireDate: dto.hireDate === undefined ? undefined : dto.hireDate ? fromDay(dto.hireDate) : null,
    address: clean(dto.address),
    emergencyName: clean(dto.emergencyName),
    emergencyPhone: clean(dto.emergencyPhone),
    notes: clean(dto.notes),
  };
}

function uniqueTarget(error: unknown): string {
  return String((error as Prisma.PrismaClientKnownRequestError).meta?.target ?? '');
}

@Injectable()
export class EmployeesService {
  private readonly env = loadEnv();

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly auth: AuthService,
    private readonly events: DomainEventsService,
    private readonly images: ImageService,
  ) {}

  async list() {
    const employees = await this.prisma.employee.findMany({
      include: { role: true },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
    });
    return employees.map(toEmployeeView);
  }

  /** Ficha con datos de acceso: sesiones abiertas y último ingreso. */
  async detail(id: string) {
    const employee = await this.prisma.employee.findUnique({ where: { id }, include: { role: true } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    const [activeSessions, lastLogin] = await Promise.all([
      this.prisma.authSession.count({
        where: { subject: `employee:${id}`, revokedAt: null, expiresAt: { gt: new Date() } },
      }),
      this.prisma.auditLog.findFirst({
        where: { entityType: 'employee', entityId: id, action: { in: LOGIN_ACTIONS } },
        orderBy: { createdAt: 'desc' },
        select: { createdAt: true },
      }),
    ]);
    return { ...toEmployeeView(employee), access: { activeSessions, lastLoginAt: lastLogin?.createdAt ?? null } };
  }

  async setPhoto(actor: EmployeeActor, id: string, file: { buffer: Buffer; mimetype: string; size: number }) {
    const current = await this.editable(actor, id);
    const photoUrl = await this.images.save('staff', file);
    const employee = await this.prisma.employee.update({ where: { id }, data: { photoUrl }, include: { role: true } });
    await this.images.remove(current.photoUrl);
    await this.audit.log(actor, 'employee.photo', 'employee', id);
    return toEmployeeView(employee);
  }

  async removePhoto(actor: EmployeeActor, id: string) {
    const current = await this.editable(actor, id);
    const employee = await this.prisma.employee.update({
      where: { id },
      data: { photoUrl: null },
      include: { role: true },
    });
    await this.images.remove(current.photoUrl);
    await this.audit.log(actor, 'employee.photo_removed', 'employee', id);
    return toEmployeeView(employee);
  }

  /** Cierra todas sus sesiones (panel, app de repartidor) y desconecta sus pantallas. */
  async logoutAll(actor: EmployeeActor, id: string) {
    await this.editable(actor, id);
    if (id === actor.id) throw new BadRequestException('Para salir tú, usa "Cerrar sesión"');
    const closed = await this.prisma.authSession.count({
      where: { subject: `employee:${id}`, revokedAt: null, expiresAt: { gt: new Date() } },
    });
    await this.auth.revokeAllSessions(`employee:${id}`);
    this.events.emit('employee.changed', { employeeId: id });
    await this.audit.log(actor, 'employee.logout_all', 'employee', id, { sessions: closed });
    return { closed };
  }

  /**
   * Historial del empleado: cambios a su ficha y sus accesos ("about"), y lo que hizo
   * en el sistema ("actions"). Paginado por cursor, lo más reciente primero.
   */
  async history(id: string, query: EmployeeHistoryQueryDto) {
    const exists = await this.prisma.employee.findUnique({ where: { id }, select: { id: true } });
    if (!exists) throw new NotFoundException('Empleado no encontrado');
    const about: Prisma.AuditLogWhereInput = { entityType: 'employee', entityId: id };
    const actions: Prisma.AuditLogWhereInput = { actor: `employee:${id}` };
    const scope = query.scope ?? 'all';
    const where = scope === 'about' ? about : scope === 'actions' ? actions : { OR: [about, actions] };
    const take = query.take ?? 50;

    const rows = await this.prisma.auditLog.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      ...(query.cursor ? { skip: 1, cursor: { id: query.cursor } } : {}),
    });
    const page = rows.slice(0, take);
    const names = await this.actorNames(page.map((row) => row.actor));
    return {
      items: page.map((row) => ({
        id: row.id,
        at: row.createdAt,
        action: row.action,
        entityType: row.entityType,
        entityId: row.entityId,
        about: row.entityType === 'employee' && row.entityId === id,
        byThisEmployee: row.actor === `employee:${id}`,
        actorName: names.get(row.actor) ?? null,
        data: row.data,
      })),
      nextCursor: rows.length > take ? page[page.length - 1].id : null,
    };
  }

  // ───────── Roles ─────────

  async listRoles() {
    const roles = await this.prisma.role.findMany({
      orderBy: [{ isSystem: 'desc' }, { name: 'asc' }],
      include: { _count: { select: { employees: true } } },
    });
    return roles.map(({ _count, ...role }) => ({ ...role, employeeCount: _count.employees }));
  }

  async createRole(actor: EmployeeActor, dto: SaveRoleDto) {
    this.assertCanGrant(actor, dto.permissions);
    try {
      const role = await this.prisma.role.create({
        data: { name: dto.name.trim(), description: clean(dto.description) ?? null, permissions: dto.permissions },
      });
      await this.audit.log(actor, 'role.create', 'role', role.id, { name: role.name, permissions: role.permissions });
      return { ...role, employeeCount: 0 };
    } catch (error) {
      throw this.roleNameError(error);
    }
  }

  async updateRole(actor: EmployeeActor, id: string, dto: SaveRoleDto) {
    const role = await this.findRole(id);
    if (role.name === ADMIN_ROLE_NAME) {
      throw new BadRequestException('El rol Admin siempre tiene todos los permisos y no se edita');
    }
    if (role.id === actor.roleId) throw new BadRequestException('No puedes editar tu propio rol');
    this.assertCanHandleRole(actor, role);
    this.assertCanGrant(actor, dto.permissions);
    const name = dto.name.trim();
    if (role.isSystem && name !== role.name) {
      throw new BadRequestException('Los roles de fábrica no se renombran; crea uno nuevo si necesitas otro nombre');
    }

    let updated: Role;
    try {
      updated = await this.prisma.role.update({
        where: { id },
        data: { name, description: clean(dto.description), permissions: dto.permissions },
      });
    } catch (error) {
      throw this.roleNameError(error);
    }

    const added = dto.permissions.filter((p) => !role.permissions.includes(p));
    const removed = role.permissions.filter((p) => !dto.permissions.includes(p));
    if (added.length || removed.length) {
      // Las pantallas abiertas de quienes tienen este rol se reconectan con los permisos nuevos.
      const members = await this.prisma.employee.findMany({ where: { roleId: id }, select: { id: true } });
      for (const member of members) this.events.emit('employee.changed', { employeeId: member.id });
    }
    await this.audit.log(actor, 'role.update', 'role', id, { name: updated.name, added, removed });
    const employeeCount = await this.prisma.employee.count({ where: { roleId: id } });
    return { ...updated, employeeCount };
  }

  async deleteRole(actor: EmployeeActor, id: string) {
    const role = await this.findRole(id);
    if (role.isSystem) throw new BadRequestException('Los roles de fábrica no se borran');
    this.assertCanHandleRole(actor, role);
    const count = await this.prisma.employee.count({ where: { roleId: id } });
    if (count > 0) {
      throw new ConflictException(
        `Este rol tiene ${count} ${count === 1 ? 'empleado' : 'empleados'} (activos o de baja). Cámbialos de rol primero.`,
      );
    }
    await this.prisma.role.delete({ where: { id } });
    await this.audit.log(actor, 'role.delete', 'role', id, { name: role.name });
    return { ok: true };
  }

  async create(actor: EmployeeActor, dto: CreateEmployeeDto) {
    const role = await this.findRole(dto.roleId);
    this.assertCanHandleRole(actor, role);
    const passwordHash = dto.password ? await hashPassword(dto.password) : undefined;

    const { result: employee, pin } = await this.withFreshPin(!!dto.generatePin, (pinHash) =>
      this.prisma.employee.create({
        data: {
          name: dto.name.trim(),
          email: dto.email?.trim().toLowerCase(),
          phone: dto.phone?.trim(),
          ...profileData(dto),
          roleId: role.id,
          passwordHash,
          pinHash,
        },
        include: { role: true },
      }),
    );

    await this.audit.log(actor, 'employee.create', 'employee', employee.id, {
      name: employee.name,
      role: role.name,
      pinGenerated: !!pin,
    });
    return { ...toEmployeeView(employee), generatedPin: pin };
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateEmployeeDto) {
    const current = await this.prisma.employee.findUnique({ where: { id }, include: { role: true } });
    if (!current) throw new NotFoundException('Empleado no encontrado');
    this.assertCanHandleRole(actor, current.role);

    if (id === actor.id && (dto.isActive === false || (dto.roleId && dto.roleId !== current.roleId))) {
      throw new BadRequestException('No puedes desactivarte ni cambiar tu propio rol');
    }
    if (dto.regeneratePin && dto.removePin) {
      throw new BadRequestException('Elige generar un PIN nuevo o quitarlo, no ambos');
    }

    let roleId: string | undefined;
    if (dto.roleId && dto.roleId !== current.roleId) {
      const newRole = await this.findRole(dto.roleId);
      this.assertCanHandleRole(actor, newRole);
      roleId = newRole.id;
    }

    const data: Prisma.EmployeeUncheckedUpdateInput = {
      name: dto.name?.trim(),
      email: dto.email === null ? null : dto.email?.trim().toLowerCase(),
      phone: dto.phone === null ? null : dto.phone?.trim(),
      roleId,
      isActive: dto.isActive,
      ...profileData(dto),
    };
    if (dto.isActive === false && current.isActive) {
      data.terminatedAt = new Date();
      data.terminationReason = clean(dto.terminationReason) ?? null;
    } else if (dto.isActive === true && !current.isActive) {
      data.terminatedAt = null;
      data.terminationReason = null;
    } else if (dto.terminationReason !== undefined && !current.isActive) {
      data.terminationReason = clean(dto.terminationReason) ?? null;
    }
    if (dto.password) data.passwordHash = await hashPassword(dto.password);
    if (dto.removePin) data.pinHash = null;

    const { result: employee, pin } = await this.withFreshPin(!!dto.regeneratePin, (pinHash) =>
      this.prisma.employee.update({
        where: { id },
        data: pinHash ? { ...data, pinHash } : data,
        include: { role: true },
      }),
    );

    if (dto.isActive === false || dto.password || roleId) {
      await this.auth.revokeAllSessions(`employee:${id}`);
      // Sus pantallas abiertas se reconectan con los permisos nuevos (o quedan fuera).
      this.events.emit('employee.changed', { employeeId: id });
    }
    const action =
      dto.isActive === false && current.isActive
        ? 'employee.terminate'
        : dto.isActive === true && !current.isActive
          ? 'employee.reactivate'
          : 'employee.update';
    await this.audit.log(actor, action, 'employee', id, {
      fields: Object.keys(dto).filter((k) => k !== 'password'),
      ...(action === 'employee.terminate' ? { reason: data.terminationReason ?? null } : {}),
      passwordChanged: !!dto.password,
      pinGenerated: !!pin,
      pinRemoved: !!dto.removePin,
    });
    return { ...toEmployeeView(employee), generatedPin: pin };
  }

  /**
   * Ejecuta la escritura con un PIN nuevo (si se pidió). Si el PIN generado coincide con
   * el de otro empleado, se genera otro en silencio: nunca se revela que un PIN existe.
   */
  private async withFreshPin<T>(
    wantPin: boolean,
    write: (pinHash: string | undefined) => Promise<T>,
  ): Promise<{ result: T; pin: string | null }> {
    for (let attempt = 0; attempt < (wantPin ? PIN_ATTEMPTS : 1); attempt++) {
      const pin = wantPin ? generateEmployeePin() : null;
      try {
        const result = await write(pin ? hashPin(pin, this.env.pinPepper) : undefined);
        return { result, pin };
      } catch (error) {
        if (isUniqueViolation(error) && uniqueTarget(error).includes('pinHash')) continue;
        throw this.translateUniqueError(error);
      }
    }
    throw new ConflictException('No se pudo generar un PIN. Inténtalo de nuevo.');
  }

  /** Empleado que el actor puede editar (no tiene más permisos que él). */
  private async editable(actor: EmployeeActor, id: string): Promise<EmployeeWithRole> {
    const employee = await this.prisma.employee.findUnique({ where: { id }, include: { role: true } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    this.assertCanHandleRole(actor, employee.role);
    return employee;
  }

  /** Nombres legibles de quién hizo cada acción (empleado o dispositivo). */
  private async actorNames(refs: string[]): Promise<Map<string, string>> {
    const ids = (kind: string) => [
      ...new Set(refs.filter((r) => r.startsWith(`${kind}:`)).map((r) => r.slice(kind.length + 1))),
    ];
    const [employees, devices] = await Promise.all([
      this.prisma.employee.findMany({ where: { id: { in: ids('employee') } }, select: { id: true, name: true } }),
      this.prisma.device.findMany({ where: { id: { in: ids('device') } }, select: { id: true, name: true } }),
    ]);
    const names = new Map<string, string>([['system', 'Sistema']]);
    for (const e of employees) names.set(`employee:${e.id}`, e.name);
    for (const d of devices) names.set(`device:${d.id}`, d.name);
    return names;
  }

  /** Nadie da permisos que él mismo no tiene. */
  private assertCanGrant(actor: EmployeeActor, permissions: string[]): void {
    const extra = permissions.filter((permission) => !actor.permissions.has(permission));
    if (extra.length) {
      throw new ForbiddenException('No puedes dar permisos que tú no tienes');
    }
  }

  private roleNameError(error: unknown): unknown {
    return isUniqueViolation(error) ? new ConflictException('Ya existe un rol con ese nombre') : error;
  }

  private async findRole(roleId: string): Promise<Role> {
    const role = await this.prisma.role.findUnique({ where: { id: roleId } });
    if (!role) throw new BadRequestException('Rol no encontrado');
    return role;
  }

  /** Evita escalar privilegios: nadie asigna ni edita un rol con permisos que él no tiene. */
  private assertCanHandleRole(actor: EmployeeActor, role: Role): void {
    const exceeds = role.permissions.some((permission) => !actor.permissions.has(permission));
    if (exceeds) {
      throw new ForbiddenException('No puedes asignar ni editar un rol con más permisos que el tuyo');
    }
  }

  private translateUniqueError(error: unknown): unknown {
    if (isUniqueViolation(error)) {
      if (uniqueTarget(error).includes('email')) return new ConflictException('Ese email ya está registrado');
      return new ConflictException('Dato duplicado');
    }
    return error;
  }
}
