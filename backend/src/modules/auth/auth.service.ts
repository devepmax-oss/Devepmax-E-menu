import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Device, Employee, Role } from '@prisma/client';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { Actor, DeviceActor, EmployeeActor } from '../../common/auth/actor';
import { generateToken, hashPin, sha256, verifyPassword } from '../../common/crypto';
import { DEVICE_PERMISSIONS } from '../../common/permissions';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';

export const DEVICE_TOKEN_PREFIX = 'dev_';
export const REFRESH_TOKEN_PREFIX = 'rt_';
const LAST_SEEN_INTERVAL_MS = 60_000;

type EmployeeWithRole = Employee & { role: Role };

interface AccessPayload {
  sub: string;
  did?: string;
}

export function toEmployeeProfile(employee: EmployeeWithRole) {
  return {
    id: employee.id,
    name: employee.name,
    email: employee.email,
    role: { id: employee.role.id, name: employee.role.name },
    permissions: employee.role.permissions,
  };
}

export function toDeviceProfile(device: Device) {
  return {
    id: device.id,
    name: device.name,
    type: device.type,
    tableId: device.tableId,
    stationId: device.stationId,
  };
}

@Injectable()
export class AuthService {
  private readonly env = loadEnv();
  private readonly loginLimiter = new AttemptLimiter(5, 5 * 60_000);
  private readonly pinLimiter = new AttemptLimiter(5, 5 * 60_000);
  private readonly pairLimiter = new AttemptLimiter(10, 15 * 60_000);

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly audit: AuditService,
  ) {}

  // ───────── Empleados: email + contraseña ─────────

  async login(email: string, password: string, ip: string, userAgent?: string) {
    const normalizedEmail = email.trim().toLowerCase();
    const key = `${ip}|${normalizedEmail}`;
    this.loginLimiter.assertAllowed(key);

    const employee = await this.prisma.employee.findUnique({
      where: { email: normalizedEmail },
      include: { role: true },
    });
    const valid =
      !!employee?.isActive &&
      !!employee.passwordHash &&
      (await verifyPassword(password, employee.passwordHash));

    if (!employee || !valid) {
      this.loginLimiter.fail(key);
      await this.audit.log('system', 'auth.login_failed', 'employee', employee?.id ?? '-', {
        email: normalizedEmail,
        ip,
      });
      throw new UnauthorizedException('Email o contraseña incorrectos');
    }

    this.loginLimiter.reset(key);
    await this.audit.log('system', 'auth.login', 'employee', employee.id, { ip });
    return this.issueSession(employee, userAgent);
  }

  async refresh(refreshToken: string, userAgent?: string) {
    const session = await this.prisma.authSession.findUnique({
      where: { tokenHash: sha256(refreshToken) },
    });
    if (!session) throw new UnauthorizedException('Sesión inválida');

    if (session.revokedAt) {
      // Un token ya usado vuelve a aparecer: posible robo. Se cierran todas las sesiones.
      await this.revokeAllSessions(session.subject);
      await this.audit.log('system', 'auth.refresh_reuse_detected', 'session', session.id, {
        subject: session.subject,
      });
      throw new UnauthorizedException('Sesión inválida');
    }
    if (session.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('Sesión vencida');
    }

    const [kind, employeeId] = session.subject.split(':');
    const employee =
      kind === 'employee'
        ? await this.prisma.employee.findUnique({ where: { id: employeeId }, include: { role: true } })
        : null;
    if (!employee?.isActive) throw new UnauthorizedException('Sesión inválida');

    await this.prisma.authSession.update({
      where: { id: session.id },
      data: { revokedAt: new Date() },
    });
    return this.issueSession(employee, userAgent);
  }

  async logout(refreshToken: string): Promise<void> {
    await this.prisma.authSession.updateMany({
      where: { tokenHash: sha256(refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async revokeAllSessions(subject: string): Promise<void> {
    await this.prisma.authSession.updateMany({
      where: { subject, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  // ───────── Empleados: PIN en un dispositivo compartido ─────────

  async loginWithPin(device: DeviceActor, pin: string) {
    if (device.type === 'EMENU') {
      throw new ForbiddenException('Las tablets de mesa no admiten ingreso de empleados');
    }
    const key = device.id;
    this.pinLimiter.assertAllowed(key);

    const employee = await this.prisma.employee.findUnique({
      where: { pinHash: hashPin(pin, this.env.pinPepper) },
      include: { role: true },
    });
    if (!employee?.isActive) {
      this.pinLimiter.fail(key);
      await this.audit.log(device, 'auth.pin_failed', 'device', device.id);
      throw new UnauthorizedException('PIN incorrecto');
    }

    this.pinLimiter.reset(key);
    await this.audit.log(device, 'auth.pin_login', 'employee', employee.id);
    return {
      accessToken: this.signAccess(employee.id, device.id),
      expiresIn: this.env.accessTokenTtlSeconds,
      employee: toEmployeeProfile(employee),
    };
  }

  /**
   * Menú del personal en una tablet de mesa: confirma que el PIN es de alguien del equipo que
   * atiende mesas. No abre sesión ni dice de quién es el PIN si falla.
   */
  async verifyStaffPin(device: DeviceActor, pin: string) {
    const key = `staff:${device.id}`;
    this.pinLimiter.assertAllowed(key);
    const employee = await this.prisma.employee.findUnique({
      where: { pinHash: hashPin(pin, this.env.pinPepper) },
      include: { role: true },
    });
    const allowed =
      !!employee?.isActive &&
      (employee.role.permissions.includes('tables.operate') || employee.role.permissions.includes('devices.manage'));
    if (!employee || !allowed) {
      this.pinLimiter.fail(key);
      await this.audit.log(device, 'auth.staff_pin_failed', 'device', device.id);
      throw new UnauthorizedException('PIN incorrecto');
    }
    this.pinLimiter.reset(key);
    await this.audit.log(device, 'auth.staff_pin', 'employee', employee.id);
    return { name: employee.name };
  }

  // ───────── Dispositivos: vinculación con código ─────────

  async pairDevice(code: string, ip: string, appVersion?: string) {
    this.pairLimiter.assertAllowed(ip);

    const device = await this.prisma.device.findUnique({ where: { pairingCode: code } });
    const valid =
      !!device?.isActive &&
      !!device.pairingExpiresAt &&
      device.pairingExpiresAt.getTime() > Date.now();
    if (!device || !valid) {
      this.pairLimiter.fail(ip);
      throw new UnauthorizedException('Código inválido o vencido');
    }

    const deviceToken = DEVICE_TOKEN_PREFIX + generateToken();
    const updated = await this.prisma.device.update({
      where: { id: device.id },
      data: {
        tokenHash: sha256(deviceToken),
        pairingCode: null,
        pairingExpiresAt: null,
        appVersion: appVersion ?? null,
        lastSeenAt: new Date(),
      },
    });
    this.pairLimiter.reset(ip);
    await this.audit.log('system', 'device.paired', 'device', device.id, { ip, appVersion });
    return { deviceToken, device: toDeviceProfile(updated) };
  }

  // ───────── Resolución del token en cada petición ─────────

  async resolveActor(token: string): Promise<Actor> {
    if (token.startsWith(DEVICE_TOKEN_PREFIX)) return this.resolveDevice(token);

    let payload: AccessPayload;
    try {
      payload = this.jwt.verify<AccessPayload>(token, { secret: this.env.jwtAccessSecret });
    } catch {
      throw new UnauthorizedException('Token inválido o vencido');
    }

    const [kind, employeeId] = payload.sub.split(':');
    if (kind !== 'employee' || !employeeId) throw new UnauthorizedException('Token inválido');

    const employee = await this.prisma.employee.findUnique({
      where: { id: employeeId },
      include: { role: true },
    });
    if (!employee?.isActive) throw new UnauthorizedException('Usuario inactivo');

    if (payload.did) {
      // Ingreso por PIN: deja de valer si el dispositivo fue revocado.
      const device = await this.prisma.device.findUnique({ where: { id: payload.did } });
      if (!device?.isActive || !device.tokenHash) throw new UnauthorizedException('Dispositivo revocado');
    }

    const actor: EmployeeActor = {
      kind: 'employee',
      id: employee.id,
      name: employee.name,
      roleId: employee.role.id,
      roleName: employee.role.name,
      permissions: new Set(employee.role.permissions),
      deviceId: payload.did ?? null,
    };
    return actor;
  }

  private async resolveDevice(token: string): Promise<DeviceActor> {
    const device = await this.prisma.device.findUnique({ where: { tokenHash: sha256(token) } });
    if (!device?.isActive) throw new UnauthorizedException('Dispositivo no autorizado');

    const now = Date.now();
    if (!device.lastSeenAt || now - device.lastSeenAt.getTime() > LAST_SEEN_INTERVAL_MS) {
      void this.prisma.device
        .update({ where: { id: device.id }, data: { lastSeenAt: new Date(now) } })
        .catch(() => undefined);
    }

    return {
      kind: 'device',
      id: device.id,
      name: device.name,
      type: device.type,
      tableId: device.tableId,
      stationId: device.stationId,
      permissions: new Set(DEVICE_PERMISSIONS[device.type]),
    };
  }

  // ───────── Internos ─────────

  private async issueSession(employee: EmployeeWithRole, userAgent?: string) {
    const refreshToken = REFRESH_TOKEN_PREFIX + generateToken(48);
    const expiresAt = new Date(Date.now() + this.env.refreshTokenDays * 24 * 60 * 60 * 1000);
    await this.prisma.authSession.create({
      data: {
        subject: `employee:${employee.id}`,
        tokenHash: sha256(refreshToken),
        userAgent: userAgent?.slice(0, 300),
        expiresAt,
      },
    });
    return {
      accessToken: this.signAccess(employee.id, null),
      refreshToken,
      expiresIn: this.env.accessTokenTtlSeconds,
      employee: toEmployeeProfile(employee),
    };
  }

  private signAccess(employeeId: string, deviceId: string | null): string {
    const payload: AccessPayload = { sub: `employee:${employeeId}` };
    if (deviceId) payload.did = deviceId;
    return this.jwt.sign(payload, {
      secret: this.env.jwtAccessSecret,
      expiresIn: this.env.accessTokenTtlSeconds,
    });
  }
}
