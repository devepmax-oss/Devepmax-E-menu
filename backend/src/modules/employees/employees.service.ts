import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Employee, Prisma, Role } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { hashPassword, hashPin } from '../../common/crypto';
import { loadEnv } from '../../config/env';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { AuthService } from '../auth/auth.service';
import { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto';

type EmployeeWithRole = Employee & { role: Role };

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
    createdAt: employee.createdAt,
    updatedAt: employee.updatedAt,
  };
}

@Injectable()
export class EmployeesService {
  private readonly env = loadEnv();

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly auth: AuthService,
  ) {}

  async list() {
    const employees = await this.prisma.employee.findMany({
      include: { role: true },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
    });
    return employees.map(toEmployeeView);
  }

  listRoles() {
    return this.prisma.role.findMany({ orderBy: { name: 'asc' } });
  }

  async create(actor: EmployeeActor, dto: CreateEmployeeDto) {
    const role = await this.findRole(dto.roleId);
    this.assertCanHandleRole(actor, role);

    try {
      const employee = await this.prisma.employee.create({
        data: {
          name: dto.name.trim(),
          email: dto.email?.trim().toLowerCase(),
          phone: dto.phone?.trim(),
          roleId: role.id,
          passwordHash: dto.password ? await hashPassword(dto.password) : undefined,
          pinHash: dto.pin ? hashPin(dto.pin, this.env.pinPepper) : undefined,
        },
        include: { role: true },
      });
      await this.audit.log(actor, 'employee.create', 'employee', employee.id, {
        name: employee.name,
        role: role.name,
      });
      return toEmployeeView(employee);
    } catch (error) {
      throw this.translateUniqueError(error);
    }
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateEmployeeDto) {
    const current = await this.prisma.employee.findUnique({ where: { id }, include: { role: true } });
    if (!current) throw new NotFoundException('Empleado no encontrado');
    this.assertCanHandleRole(actor, current.role);

    if (id === actor.id && (dto.isActive === false || (dto.roleId && dto.roleId !== current.roleId))) {
      throw new BadRequestException('No puedes desactivarte ni cambiar tu propio rol');
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
    };
    if (dto.password) data.passwordHash = await hashPassword(dto.password);
    if (dto.pin !== undefined) data.pinHash = dto.pin === null ? null : hashPin(dto.pin, this.env.pinPepper);

    try {
      const employee = await this.prisma.employee.update({ where: { id }, data, include: { role: true } });

      if (dto.isActive === false || dto.password || roleId) {
        await this.auth.revokeAllSessions(`employee:${id}`);
      }
      await this.audit.log(actor, 'employee.update', 'employee', id, {
        fields: Object.keys(dto).filter((k) => !['password', 'pin'].includes(k)),
        passwordChanged: !!dto.password,
        pinChanged: dto.pin !== undefined,
      });
      return toEmployeeView(employee);
    } catch (error) {
      throw this.translateUniqueError(error);
    }
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
      const target = String((error as Prisma.PrismaClientKnownRequestError).meta?.target ?? '');
      if (target.includes('pinHash')) return new ConflictException('Ese PIN ya lo usa otro empleado');
      if (target.includes('email')) return new ConflictException('Ese email ya está registrado');
      return new ConflictException('Dato duplicado');
    }
    return error;
  }
}
