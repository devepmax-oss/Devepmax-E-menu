import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { Shift, TimeBreak, TimeEntry } from '@prisma/client';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { Actor, DeviceActor, EmployeeActor } from '../../common/auth/actor';
import { hashPin } from '../../common/crypto';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { SettingsService } from '../settings/settings.service';
import {
  CopyWeekDto,
  EntriesQueryDto,
  SaveEntryDto,
  SaveShiftDto,
  TimeclockSettingsDto,
} from './dto/timeclock.dto';
import {
  ClockAction,
  ClockState,
  MISSING_OUT_HOURS,
  addDays,
  allowedActions,
  invalidActionMessage,
  isDay,
  lateMinutes,
  localDay,
  localTime,
  shiftSpan,
  validateEntry,
  weekStart,
  workedMinutes,
  zonedToUtc,
} from './timeclock.rules';

type EntryWithBreaks = TimeEntry & { breaks: TimeBreak[] };
type Ctx = { tz: string; paidBreakMinutes: number; graceMinutes: number };

const HOUR = 3_600_000;
const MAX_RANGE_DAYS = 62;
const ACTION_AUDIT: Record<ClockAction, string> = {
  IN: 'timeclock.in',
  BREAK_START: 'timeclock.break_start',
  BREAK_END: 'timeclock.break_end',
  OUT: 'timeclock.out',
};
const ACTION_DONE: Record<ClockAction, string> = {
  IN: 'Entrada marcada',
  BREAK_START: 'Descanso iniciado',
  BREAK_END: 'Descanso terminado',
  OUT: 'Salida marcada',
};
const EMPLOYEE_BRIEF = { id: true, name: true, photoUrl: true, jobTitle: true, role: { select: { name: true } } } as const;

function stateOf(entry: EntryWithBreaks | null): ClockState {
  if (!entry || entry.clockOut) return 'OUT';
  return entry.breaks.some((b) => !b.end) ? 'BREAK' : 'IN';
}

/**
 * Reloj checador y horarios. Los empleados marcan con su PIN en la tablet de reloj; el gerente
 * ve quién está trabajando, corrige jornadas (con motivo, queda en el historial) y arma los
 * turnos de la semana. Nunca bloquea la venta: solo registra.
 */
@Injectable()
export class TimeclockService {
  private readonly env = loadEnv();
  private readonly pinLimiter = new AttemptLimiter(5, 5 * 60_000);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
  ) {}

  // ───────── Tablet de reloj ─────────

  /** Con el PIN: quién es, cómo está (fuera, trabajando, en descanso) y sus turnos. */
  async lookup(device: DeviceActor, pin: string) {
    const employee = await this.employeeByPin(device, pin);
    return this.statusFor(employee.id);
  }

  async punch(device: DeviceActor, pin: string, action: ClockAction) {
    const employee = await this.employeeByPin(device, pin);
    await this.applyPunch(employee.id, action, device, { deviceId: device.id, source: 'CLOCK' });
    return { ...(await this.statusFor(employee.id)), done: ACTION_DONE[action] };
  }

  // ───────── Gerente ─────────

  /** El gerente marca por un empleado (olvidó marcar o no hay tablet). */
  async managerPunch(actor: EmployeeActor, employeeId: string, action: ClockAction, reason?: string) {
    const employee = await this.prisma.employee.findUnique({ where: { id: employeeId } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    if (!employee.isActive) throw new BadRequestException('Está de baja');
    await this.applyPunch(employeeId, action, actor, {
      source: 'MANUAL',
      editedById: actor.id,
      reason: reason?.trim() || 'Marcado por el gerente',
    });
    return this.statusFor(employeeId);
  }

  /** Quién está trabajando ahora, quién debería y no ha marcado, y jornadas sin salida. */
  async now() {
    const ctx = await this.ctx();
    const now = new Date();
    const [open, shifts] = await Promise.all([
      this.prisma.timeEntry.findMany({
        where: { clockOut: null },
        include: { breaks: true, employee: { select: EMPLOYEE_BRIEF } },
        orderBy: { clockIn: 'asc' },
      }),
      this.prisma.shift.findMany({
        where: { start: { lte: new Date(now.getTime() - ctx.graceMinutes * 60_000) }, end: { gt: now }, employee: { isActive: true } },
        include: { employee: { select: EMPLOYEE_BRIEF } },
        orderBy: { start: 'asc' },
      }),
    ]);
    const working = open.filter((e) => now.getTime() - e.clockIn.getTime() < MISSING_OUT_HOURS * HOUR);
    const missingOut = open.filter((e) => now.getTime() - e.clockIn.getTime() >= MISSING_OUT_HOURS * HOUR);
    const clockedIn = new Set(open.map((e) => e.employeeId));
    // Entraron y salieron durante el turno (no cuentan como faltantes).
    const recent = await this.prisma.timeEntry.findMany({
      where: { employeeId: { in: shifts.map((s) => s.employeeId) }, clockIn: { gte: new Date(now.getTime() - 16 * HOUR) } },
      select: { employeeId: true, clockIn: true, clockOut: true },
    });
    const notIn = shifts.filter(
      (s) =>
        !clockedIn.has(s.employeeId) &&
        !recent.some((r) => r.employeeId === s.employeeId && r.clockOut && r.clockOut > s.start),
    );

    return {
      at: now,
      working: working.map((e) => ({
        entryId: e.id,
        employee: this.brief(e.employee),
        state: stateOf(e),
        since: e.clockIn,
        breakSince: e.breaks.find((b) => !b.end)?.start ?? null,
        ...workedMinutes(e.clockIn, null, e.breaks, ctx.paidBreakMinutes, now),
      })),
      notClockedIn: notIn.map((s) => ({ employee: this.brief(s.employee), shift: this.shiftView(s, ctx) })),
      missingOut: missingOut.map((e) => this.entryView(e, ctx, null, this.brief(e.employee))),
    };
  }

  /** Jornadas de un período (máx. 62 días), con horas, descansos, tardanzas y totales. */
  async entries(query: EntriesQueryDto) {
    const ctx = await this.ctx();
    const today = localDay(new Date(), ctx.tz);
    const from = query.from ?? addDays(today, -6);
    const to = query.to ?? today;
    if (!isDay(from) || !isDay(to)) throw new BadRequestException('Fecha inválida');
    if (to < from) throw new BadRequestException('La fecha final es antes de la inicial');
    if ((Date.parse(to) - Date.parse(from)) / 86_400_000 > MAX_RANGE_DAYS) {
      throw new BadRequestException(`Elige hasta ${MAX_RANGE_DAYS} días`);
    }
    const start = zonedToUtc(from, '00:00', ctx.tz);
    const end = zonedToUtc(addDays(to, 1), '00:00', ctx.tz);

    const [rows, shifts] = await Promise.all([
      this.prisma.timeEntry.findMany({
        where: { clockIn: { gte: start, lt: end }, ...(query.employeeId ? { employeeId: query.employeeId } : {}) },
        include: { breaks: { orderBy: { start: 'asc' } }, employee: { select: EMPLOYEE_BRIEF } },
        orderBy: { clockIn: 'asc' },
      }),
      this.prisma.shift.findMany({
        where: {
          start: { gte: new Date(start.getTime() - 12 * HOUR), lt: end },
          ...(query.employeeId ? { employeeId: query.employeeId } : {}),
        },
      }),
    ]);
    const editors = await this.names(rows.map((r) => r.editedById).filter((id): id is string => !!id));

    const entries = rows.map((e) => {
      const shift = this.matchShift(e, shifts);
      const employee = this.brief(e.employee);
      return { ...this.entryView(e, ctx, shift, employee, editors.get(e.editedById ?? '')), employee };
    });

    const totals = new Map<string, { employee: ReturnType<TimeclockService['brief']>; entries: number; workedMinutes: number; unpaidBreakMinutes: number; lateCount: number; lateMinutes: number }>();
    for (const e of entries) {
      const t = totals.get(e.employee.id) ?? { employee: e.employee, entries: 0, workedMinutes: 0, unpaidBreakMinutes: 0, lateCount: 0, lateMinutes: 0 };
      t.entries += 1;
      t.workedMinutes += e.workedMinutes;
      t.unpaidBreakMinutes += e.unpaidBreakMinutes;
      if (e.lateMinutes > 0) {
        t.lateCount += 1;
        t.lateMinutes += e.lateMinutes;
      }
      totals.set(e.employee.id, t);
    }
    return {
      from,
      to,
      entries,
      totals: [...totals.values()].sort((a, b) => b.workedMinutes - a.workedMinutes),
    };
  }

  async createEntry(actor: EmployeeActor, dto: SaveEntryDto) {
    const ctx = await this.ctx();
    const employee = await this.prisma.employee.findUnique({ where: { id: dto.employeeId } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    const times = this.entryTimes(dto, ctx);
    await this.assertNoOverlap(dto.employeeId, times.clockIn, times.clockOut, null);
    const entry = await this.prisma.timeEntry.create({
      data: {
        employeeId: dto.employeeId,
        clockIn: times.clockIn,
        clockOut: times.clockOut,
        source: 'MANUAL',
        editedAt: new Date(),
        editedById: actor.id,
        editReason: dto.reason.trim(),
        breaks: { create: times.breaks },
      },
      include: { breaks: true },
    });
    await this.audit.log(actor, 'timeclock.entry_create', 'employee', dto.employeeId, {
      entryId: entry.id,
      day: dto.day,
      clockIn: dto.clockIn,
      clockOut: dto.clockOut ?? null,
      reason: dto.reason.trim(),
    });
    return this.entryView(entry, ctx, null, null);
  }

  async updateEntry(actor: EmployeeActor, id: string, dto: SaveEntryDto) {
    const ctx = await this.ctx();
    const current = await this.prisma.timeEntry.findUnique({ where: { id }, include: { breaks: true } });
    if (!current) throw new NotFoundException('Jornada no encontrada');
    if (current.employeeId !== dto.employeeId) throw new BadRequestException('La jornada es de otro empleado');
    const times = this.entryTimes(dto, ctx);
    await this.assertNoOverlap(dto.employeeId, times.clockIn, times.clockOut, id);

    const entry = await this.prisma.$transaction(async (tx) => {
      await tx.timeBreak.deleteMany({ where: { entryId: id } });
      return tx.timeEntry.update({
        where: { id },
        data: {
          clockIn: times.clockIn,
          clockOut: times.clockOut,
          editedAt: new Date(),
          editedById: actor.id,
          editReason: dto.reason.trim(),
          breaks: { create: times.breaks },
        },
        include: { breaks: true },
      });
    });
    const before = {
      clockIn: localTime(current.clockIn, ctx.tz),
      clockOut: current.clockOut ? localTime(current.clockOut, ctx.tz) : null,
      breaks: current.breaks.length,
    };
    await this.audit.log(actor, 'timeclock.entry_update', 'employee', dto.employeeId, {
      entryId: id,
      day: dto.day,
      before,
      after: { clockIn: dto.clockIn, clockOut: dto.clockOut ?? null, breaks: times.breaks.length },
      reason: dto.reason.trim(),
    });
    return this.entryView(entry, ctx, null, null);
  }

  async deleteEntry(actor: EmployeeActor, id: string, reason: string) {
    const ctx = await this.ctx();
    const entry = await this.prisma.timeEntry.findUnique({ where: { id } });
    if (!entry) throw new NotFoundException('Jornada no encontrada');
    await this.prisma.timeEntry.delete({ where: { id } });
    await this.audit.log(actor, 'timeclock.entry_delete', 'employee', entry.employeeId, {
      entryId: id,
      day: localDay(entry.clockIn, ctx.tz),
      clockIn: localTime(entry.clockIn, ctx.tz),
      clockOut: entry.clockOut ? localTime(entry.clockOut, ctx.tz) : null,
      reason: reason.trim(),
    });
    return { ok: true };
  }

  async getSettings() {
    const s = await this.settings.get();
    return { paidBreakMinutes: s.paidBreakMinutes, clockGraceMinutes: s.clockGraceMinutes };
  }

  async updateSettings(actor: EmployeeActor, dto: TimeclockSettingsDto) {
    await this.settings.get();
    const s = await this.prisma.restaurantSettings.update({
      where: { id: 1 },
      data: { paidBreakMinutes: dto.paidBreakMinutes, clockGraceMinutes: dto.clockGraceMinutes },
    });
    await this.audit.log(actor, 'timeclock.settings', 'settings', '1', { ...dto });
    return { paidBreakMinutes: s.paidBreakMinutes, clockGraceMinutes: s.clockGraceMinutes };
  }

  // ───────── Horarios ─────────

  /** Turnos de una semana (lunes a domingo) con el personal activo. */
  async week(week?: string) {
    const ctx = await this.ctx();
    const monday = weekStart(week ?? localDay(new Date(), ctx.tz));
    const start = zonedToUtc(monday, '00:00', ctx.tz);
    const end = zonedToUtc(addDays(monday, 7), '00:00', ctx.tz);
    const [employees, shifts] = await Promise.all([
      this.prisma.employee.findMany({
        where: { isActive: true },
        select: EMPLOYEE_BRIEF,
        orderBy: { name: 'asc' },
      }),
      this.prisma.shift.findMany({ where: { start: { gte: start, lt: end } }, orderBy: { start: 'asc' } }),
    ]);
    const views = shifts.map((s) => this.shiftView(s, ctx));
    const totals: Record<string, number> = {};
    for (const s of views) totals[s.employeeId] = (totals[s.employeeId] ?? 0) + s.minutes;
    return {
      weekStart: monday,
      days: Array.from({ length: 7 }, (_, i) => addDays(monday, i)),
      employees: employees.map((e) => this.brief(e)),
      shifts: views,
      totals,
    };
  }

  async saveShift(actor: EmployeeActor, id: string | null, dto: SaveShiftDto) {
    const ctx = await this.ctx();
    const employee = await this.prisma.employee.findUnique({ where: { id: dto.employeeId } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    if (!employee.isActive) throw new BadRequestException('No se programan turnos a alguien de baja');
    if (!isDay(dto.day)) throw new BadRequestException('Fecha inválida');
    const span = shiftSpan(dto.day, dto.start, dto.end, ctx.tz);
    if (span.end.getTime() - span.start.getTime() > 16 * HOUR) {
      throw new BadRequestException('Un turno no puede pasar de 16 horas');
    }
    const overlap = await this.prisma.shift.findFirst({
      where: {
        employeeId: dto.employeeId,
        start: { lt: span.end },
        end: { gt: span.start },
        ...(id ? { NOT: { id } } : {}),
      },
    });
    if (overlap) throw new ConflictException(`${employee.name} ya tiene un turno que se cruza con ese horario`);

    const data = {
      employeeId: dto.employeeId,
      start: span.start,
      end: span.end,
      position: dto.position?.trim() || null,
      note: dto.note?.trim() || null,
    };
    if (id) {
      const current = await this.prisma.shift.findUnique({ where: { id } });
      if (!current) throw new NotFoundException('Turno no encontrado');
    }
    const shift = id
      ? await this.prisma.shift.update({ where: { id }, data })
      : await this.prisma.shift.create({ data });
    await this.audit.log(actor, id ? 'shift.update' : 'shift.create', 'shift', shift.id, {
      employeeId: dto.employeeId,
      day: dto.day,
      start: dto.start,
      end: dto.end,
    });
    return this.shiftView(shift, ctx);
  }

  async deleteShift(actor: EmployeeActor, id: string) {
    const shift = await this.prisma.shift.findUnique({ where: { id } });
    if (!shift) throw new NotFoundException('Turno no encontrado');
    await this.prisma.shift.delete({ where: { id } });
    await this.audit.log(actor, 'shift.delete', 'shift', id, { employeeId: shift.employeeId });
    return { ok: true };
  }

  /** Copia los turnos de una semana a otra. Salta a quien está de baja o ya tiene turno a esa hora. */
  async copyWeek(actor: EmployeeActor, dto: CopyWeekDto) {
    const ctx = await this.ctx();
    const fromMonday = weekStart(dto.fromWeek);
    const toMonday = weekStart(dto.toWeek);
    if (fromMonday === toMonday) throw new BadRequestException('Elige otra semana');
    const source = await this.prisma.shift.findMany({
      where: {
        start: { gte: zonedToUtc(fromMonday, '00:00', ctx.tz), lt: zonedToUtc(addDays(fromMonday, 7), '00:00', ctx.tz) },
        employee: { isActive: true },
        ...(dto.employeeId ? { employeeId: dto.employeeId } : {}),
      },
    });
    const days = Math.round((Date.parse(toMonday) - Date.parse(fromMonday)) / 86_400_000);
    let copied = 0;
    let skipped = 0;
    for (const s of source) {
      const v = this.shiftView(s, ctx);
      const span = shiftSpan(addDays(v.day, days), v.start, v.end, ctx.tz);
      const clash = await this.prisma.shift.findFirst({
        where: { employeeId: s.employeeId, start: { lt: span.end }, end: { gt: span.start } },
      });
      if (clash) {
        skipped++;
        continue;
      }
      await this.prisma.shift.create({
        data: { employeeId: s.employeeId, start: span.start, end: span.end, position: s.position, note: s.note },
      });
      copied++;
    }
    await this.audit.log(actor, 'shift.copy_week', 'shift', toMonday, { fromWeek: fromMonday, copied, skipped });
    return { copied, skipped };
  }

  // ───────── Internos ─────────

  private async ctx(): Promise<Ctx> {
    const s = await this.settings.get();
    return { tz: s.timezone, paidBreakMinutes: s.paidBreakMinutes, graceMinutes: s.clockGraceMinutes };
  }

  /** Busca al empleado por su PIN sin revelar nada si no existe; con límite de intentos por tablet. */
  private async employeeByPin(device: DeviceActor, pin: string) {
    const key = `clock:${device.id}`;
    this.pinLimiter.assertAllowed(key);
    const employee = await this.prisma.employee.findUnique({ where: { pinHash: hashPin(pin, this.env.pinPepper) } });
    if (!employee?.isActive) {
      this.pinLimiter.fail(key);
      await this.audit.log(device, 'timeclock.pin_failed', 'device', device.id);
      throw new UnauthorizedException('PIN incorrecto');
    }
    this.pinLimiter.reset(key);
    return employee;
  }

  /** Marca con un candado por empleado para que dos toques seguidos no dupliquen nada. */
  private async applyPunch(
    employeeId: string,
    action: ClockAction,
    actor: Actor,
    meta: { source: 'CLOCK' | 'MANUAL'; deviceId?: string; editedById?: string; reason?: string },
  ) {
    const at = new Date();
    await this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${'timeclock:' + employeeId}))`;
      const open = await tx.timeEntry.findFirst({
        where: { employeeId, clockOut: null },
        include: { breaks: true },
        orderBy: { clockIn: 'desc' },
      });
      const state = stateOf(open);
      if (!allowedActions(state).includes(action)) throw new ConflictException(invalidActionMessage(state, action));
      const edited = meta.source === 'MANUAL' ? { editedAt: at, editedById: meta.editedById, editReason: meta.reason } : {};

      if (action === 'IN') {
        await tx.timeEntry.create({
          data: { employeeId, clockIn: at, source: meta.source, deviceId: meta.deviceId, ...edited },
        });
        return;
      }
      const entry = open!;
      const openBreak = entry.breaks.find((b) => !b.end);
      if (action === 'BREAK_START') {
        await tx.timeBreak.create({ data: { entryId: entry.id, start: at } });
      } else if (action === 'BREAK_END') {
        await tx.timeBreak.update({ where: { id: openBreak!.id }, data: { end: at } });
      } else {
        if (openBreak) await tx.timeBreak.update({ where: { id: openBreak.id }, data: { end: at } });
        await tx.timeEntry.update({ where: { id: entry.id }, data: { clockOut: at, ...edited } });
      }
    });
    await this.audit.log(actor, ACTION_AUDIT[action], 'employee', employeeId, {
      ...(meta.source === 'MANUAL' ? { manual: true, reason: meta.reason } : {}),
    });
  }

  /** Lo que ve el empleado en la tablet: su estado, horas de hoy y sus turnos de los próximos 7 días. */
  private async statusFor(employeeId: string) {
    const ctx = await this.ctx();
    const now = new Date();
    const today = localDay(now, ctx.tz);
    const dayStart = zonedToUtc(today, '00:00', ctx.tz);
    const [employee, entries, shifts] = await Promise.all([
      this.prisma.employee.findUniqueOrThrow({ where: { id: employeeId }, select: EMPLOYEE_BRIEF }),
      this.prisma.timeEntry.findMany({
        where: { employeeId, OR: [{ clockIn: { gte: dayStart } }, { clockOut: null }] },
        include: { breaks: true },
        orderBy: { clockIn: 'desc' },
      }),
      this.prisma.shift.findMany({
        where: { employeeId, end: { gt: new Date(now.getTime() - 4 * HOUR) }, start: { lt: zonedToUtc(addDays(today, 8), '00:00', ctx.tz) } },
        orderBy: { start: 'asc' },
      }),
    ]);
    const open = entries.find((e) => !e.clockOut) ?? null;
    const state = stateOf(open);
    const todayMinutes = entries
      .filter((e) => e.clockIn >= dayStart || !e.clockOut)
      .reduce((sum, e) => sum + workedMinutes(e.clockIn, e.clockOut, e.breaks, ctx.paidBreakMinutes, now).workedMinutes, 0);
    const shiftViews = shifts.map((s) => this.shiftView(s, ctx));
    const current = shifts.find((s) => s.start <= new Date(now.getTime() + 2 * HOUR) && s.end > now);
    return {
      employee: this.brief(employee),
      state,
      since: open?.clockIn ?? null,
      breakSince: open?.breaks.find((b) => !b.end)?.start ?? null,
      actions: allowedActions(state),
      todayWorkedMinutes: todayMinutes,
      currentShift: current ? this.shiftView(current, ctx) : null,
      lateMinutes: open && current && open.clockIn >= new Date(current.start.getTime() - 2 * HOUR)
        ? lateMinutes(open.clockIn, current.start, ctx.graceMinutes)
        : 0,
      upcomingShifts: shiftViews,
    };
  }

  /** Convierte las horas locales de una jornada escrita a mano en instantes. */
  private entryTimes(dto: SaveEntryDto, ctx: Ctx) {
    if (!isDay(dto.day)) throw new BadRequestException('Fecha inválida');
    const at = (time: string) => zonedToUtc(time < dto.clockIn ? addDays(dto.day, 1) : dto.day, time, ctx.tz);
    const clockIn = zonedToUtc(dto.day, dto.clockIn, ctx.tz);
    const clockOut = dto.clockOut ? at(dto.clockOut) : null;
    const breaks = (dto.breaks ?? []).map((b) => ({ start: at(b.start), end: b.end ? at(b.end) : null }));
    if (clockOut && clockOut.getTime() === clockIn.getTime()) throw new BadRequestException('La salida debe ser después de la entrada');
    const error = validateEntry(clockIn, clockOut, breaks);
    if (error) throw new BadRequestException(error);
    return { clockIn, clockOut, breaks };
  }

  private async assertNoOverlap(employeeId: string, clockIn: Date, clockOut: Date | null, exceptId: string | null) {
    const end = clockOut ?? new Date(8.64e15);
    const clash = await this.prisma.timeEntry.findFirst({
      where: {
        employeeId,
        ...(exceptId ? { NOT: { id: exceptId } } : {}),
        clockIn: { lt: end },
        OR: [{ clockOut: null }, { clockOut: { gt: clockIn } }],
      },
    });
    if (clash) throw new ConflictException('Se cruza con otra jornada de este empleado');
  }

  /** El turno que corresponde a una jornada: el del mismo empleado más cercano a la entrada. */
  private matchShift(entry: TimeEntry, shifts: Shift[]): Shift | null {
    const candidates = shifts.filter(
      (s) =>
        s.employeeId === entry.employeeId &&
        entry.clockIn.getTime() >= s.start.getTime() - 4 * HOUR &&
        entry.clockIn.getTime() < s.end.getTime(),
    );
    candidates.sort(
      (a, b) => Math.abs(a.start.getTime() - entry.clockIn.getTime()) - Math.abs(b.start.getTime() - entry.clockIn.getTime()),
    );
    return candidates[0] ?? null;
  }

  private entryView(
    e: EntryWithBreaks,
    ctx: Ctx,
    shift: Shift | null,
    employee: ReturnType<TimeclockService['brief']> | null,
    editedByName?: string,
  ) {
    const now = new Date();
    const minutes = workedMinutes(e.clockIn, e.clockOut, e.breaks, ctx.paidBreakMinutes, now);
    const breaks = [...e.breaks].sort((a, b) => a.start.getTime() - b.start.getTime());
    return {
      id: e.id,
      employeeId: e.employeeId,
      ...(employee ? { employee } : {}),
      day: localDay(e.clockIn, ctx.tz),
      clockIn: e.clockIn,
      clockOut: e.clockOut,
      inTime: localTime(e.clockIn, ctx.tz),
      outTime: e.clockOut ? localTime(e.clockOut, ctx.tz) : null,
      breaks: breaks.map((b) => ({
        id: b.id,
        start: b.start,
        end: b.end,
        startTime: localTime(b.start, ctx.tz),
        endTime: b.end ? localTime(b.end, ctx.tz) : null,
      })),
      source: e.source,
      edited: e.editedAt ? { at: e.editedAt, byName: editedByName ?? null, reason: e.editReason } : null,
      open: !e.clockOut,
      missingOut: !e.clockOut && now.getTime() - e.clockIn.getTime() >= MISSING_OUT_HOURS * HOUR,
      shift: shift ? this.shiftView(shift, ctx) : null,
      lateMinutes: shift ? lateMinutes(e.clockIn, shift.start, ctx.graceMinutes) : 0,
      ...minutes,
    };
  }

  private shiftView(s: Shift, ctx: Ctx) {
    return {
      id: s.id,
      employeeId: s.employeeId,
      day: localDay(s.start, ctx.tz),
      start: localTime(s.start, ctx.tz),
      end: localTime(s.end, ctx.tz),
      startAt: s.start,
      endAt: s.end,
      minutes: Math.round((s.end.getTime() - s.start.getTime()) / 60_000),
      position: s.position,
      note: s.note,
    };
  }

  private brief(e: { id: string; name: string; photoUrl: string | null; jobTitle: string | null; role: { name: string } }) {
    return { id: e.id, name: e.name, photoUrl: e.photoUrl, jobTitle: e.jobTitle, roleName: e.role.name };
  }

  private async names(ids: string[]) {
    const rows = await this.prisma.employee.findMany({ where: { id: { in: [...new Set(ids)] } }, select: { id: true, name: true } });
    return new Map(rows.map((r) => [r.id, r.name]));
  }
}
