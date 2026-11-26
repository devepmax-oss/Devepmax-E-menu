import { BadRequestException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { signPayload, verifyPayload } from '../../common/pay-token';
import { buildXlsx, Cell } from '../../common/xlsx';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { SettingsService } from '../settings/settings.service';
import { addDays, isDay, localDay, localTime, weekStart, workedMinutes, zonedToUtc } from '../timeclock/timeclock.rules';
import { PayrollSettingsDto, SetRateDto } from './dto/payroll.dto';
import { OvertimeRule, RULE_PRESETS, dayPayCents, isRuleValid, rateOn, splitWeek, tipOwner } from './payroll.rules';

const n = (v: Prisma.Decimal | number | null | undefined) => (v == null ? 0 : Number(v));
const cents = (v: number) => Math.round(v) / 100;
const round2 = (v: number) => Math.round(v * 100) / 100;
const EXPORT_SCOPE = 'payroll-export:v1';
const MAX_PERFORMANCE_DAYS = 93;
const CASH = 'CASH';

type Brief = { id: string; name: string; photoUrl: string | null; jobTitle: string | null; roleName: string; isActive: boolean };
type TipLine = { paymentId: string; at: Date; employeeId: string | null; method: string; tip: number };

/**
 * Nómina y desempeño. Las horas salen del reloj checador (descansos pagados según el ajuste),
 * las horas extra de la regla elegida, el pago de la tarifa vigente cada día y las propinas
 * de los cobros: en delivery al repartidor, en mesa al mesero, si no a quien cobró.
 */
@Injectable()
export class PayrollService {
  private readonly env = loadEnv();

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
  ) {}

  // ───────── Ajustes y tarifas ─────────

  async getSettings() {
    const s = await this.settings.get();
    const rule = this.ruleOf(s);
    const preset = (Object.entries(RULE_PRESETS) as [string, OvertimeRule][]).find(([, r]) =>
      (['weeklyHours', 'dailyHours', 'doubleDailyHours', 'overtimeMultiplier', 'doubleMultiplier'] as const).every((k) => r[k] === rule[k]),
    )?.[0];
    return { ...rule, preset: preset ?? 'custom' };
  }

  async updateSettings(actor: EmployeeActor, dto: PayrollSettingsDto) {
    const current = this.ruleOf(await this.settings.get());
    const next: OvertimeRule = {
      weeklyHours: dto.weeklyHours ?? current.weeklyHours,
      dailyHours: dto.dailyHours ?? current.dailyHours,
      doubleDailyHours: dto.doubleDailyHours ?? current.doubleDailyHours,
      overtimeMultiplier: dto.overtimeMultiplier ?? current.overtimeMultiplier,
      doubleMultiplier: dto.doubleMultiplier ?? current.doubleMultiplier,
    };
    if (!isRuleValid(next)) {
      throw new BadRequestException('Revisa la regla: lo doble debe empezar después de lo extra y pagar igual o más');
    }
    await this.prisma.restaurantSettings.update({
      where: { id: 1 },
      data: {
        overtimeWeeklyHours: next.weeklyHours,
        overtimeDailyHours: next.dailyHours,
        doubleTimeDailyHours: next.doubleDailyHours,
        overtimeMultiplier: next.overtimeMultiplier,
        doubleTimeMultiplier: next.doubleMultiplier,
      },
    });
    await this.audit.log(actor, 'payroll.settings', 'settings', '1', { ...next });
    return this.getSettings();
  }

  /** Personal con su tarifa de hoy y el historial de cambios. */
  async rates() {
    const tz = (await this.settings.get()).timezone;
    const today = localDay(new Date(), tz);
    const employees = await this.prisma.employee.findMany({
      include: { role: { select: { name: true } }, payRates: { orderBy: { effectiveFrom: 'desc' } } },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
    });
    return employees.map((e) => {
      const history = e.payRates.map((r) => ({
        id: r.id,
        hourlyRate: n(r.hourlyRate),
        effectiveFrom: r.effectiveFrom.toISOString().slice(0, 10),
      }));
      const upcoming = history.filter((r) => r.effectiveFrom > today);
      return {
        employee: this.brief(e),
        currentRate: rateOn(history, today),
        nextChange: upcoming.length ? upcoming[upcoming.length - 1] : null,
        history,
      };
    });
  }

  async setRate(actor: EmployeeActor, employeeId: string, dto: SetRateDto) {
    const tz = (await this.settings.get()).timezone;
    const employee = await this.prisma.employee.findUnique({ where: { id: employeeId } });
    if (!employee) throw new NotFoundException('Empleado no encontrado');
    const day = dto.effectiveFrom ?? localDay(new Date(), tz);
    if (!isDay(day)) throw new BadRequestException('Fecha inválida');
    const effectiveFrom = new Date(`${day}T00:00:00.000Z`);
    const rate = await this.prisma.payRate.upsert({
      where: { employeeId_effectiveFrom: { employeeId, effectiveFrom } },
      create: { employeeId, effectiveFrom, hourlyRate: dto.hourlyRate, createdById: actor.id },
      update: { hourlyRate: dto.hourlyRate, createdById: actor.id },
    });
    await this.audit.log(actor, 'payroll.rate', 'employee', employeeId, { hourlyRate: dto.hourlyRate, effectiveFrom: day });
    return { id: rate.id, hourlyRate: n(rate.hourlyRate), effectiveFrom: day };
  }

  async deleteRate(actor: EmployeeActor, rateId: string) {
    const rate = await this.prisma.payRate.findUnique({ where: { id: rateId } });
    if (!rate) throw new NotFoundException('Tarifa no encontrada');
    await this.prisma.payRate.delete({ where: { id: rateId } });
    await this.audit.log(actor, 'payroll.rate_delete', 'employee', rate.employeeId, {
      hourlyRate: n(rate.hourlyRate),
      effectiveFrom: rate.effectiveFrom.toISOString().slice(0, 10),
    });
    return { ok: true };
  }

  // ───────── Nómina ─────────

  /** Nómina de 1 o 2 semanas completas (lunes a domingo). */
  async payroll(week?: string, weeks = 1) {
    const s = await this.settings.get();
    const tz = s.timezone;
    const rule = this.ruleOf(s);
    const monday = weekStart(week ?? localDay(new Date(), tz));
    const weekStarts = Array.from({ length: weeks }, (_, i) => addDays(monday, i * 7));
    const from = monday;
    const to = addDays(monday, weeks * 7 - 1);
    const start = zonedToUtc(from, '00:00', tz);
    const end = zonedToUtc(addDays(to, 1), '00:00', tz);

    const [entries, rates, tips] = await Promise.all([
      this.prisma.timeEntry.findMany({
        where: { clockIn: { gte: start, lt: end } },
        include: { breaks: true },
        orderBy: { clockIn: 'asc' },
      }),
      this.prisma.payRate.findMany(),
      this.tipsIn(start, end),
    ]);
    const ids = new Set<string>([...entries.map((e) => e.employeeId), ...tips.map((t) => t.employeeId).filter((id): id is string => !!id)]);
    const people = await this.people([...ids]);
    const ratesOf = new Map<string, { effectiveFrom: string; hourlyRate: number }[]>();
    for (const r of rates) {
      const list = ratesOf.get(r.employeeId) ?? [];
      list.push({ effectiveFrom: r.effectiveFrom.toISOString().slice(0, 10), hourlyRate: n(r.hourlyRate) });
      ratesOf.set(r.employeeId, list);
    }

    const rows = [...ids].map((employeeId) => {
      const mine = entries.filter((e) => e.employeeId === employeeId);
      const closed = mine.filter((e) => e.clockOut);
      const perDay = new Map<string, number>();
      for (const e of closed) {
        const day = localDay(e.clockIn, tz);
        perDay.set(day, (perDay.get(day) ?? 0) + workedMinutes(e.clockIn, e.clockOut, e.breaks, s.paidBreakMinutes).workedMinutes);
      }
      const myRates = ratesOf.get(employeeId) ?? [];
      let regularMinutes = 0, overtimeMinutes = 0, doubleMinutes = 0;
      let regularPay = 0, overtimePay = 0, doublePay = 0;
      let daysWithoutRate = 0;
      const weekRows = weekStarts.map((ws) => {
        const days = [...perDay.entries()]
          .filter(([day]) => day >= ws && day <= addDays(ws, 6))
          .map(([day, minutes]) => ({ day, minutes }));
        const split = splitWeek(days, rule);
        const w = { weekStart: ws, regularMinutes: 0, overtimeMinutes: 0, doubleMinutes: 0 };
        for (const d of split) {
          w.regularMinutes += d.regular;
          w.overtimeMinutes += d.overtime;
          w.doubleMinutes += d.double;
          const rate = rateOn(myRates, d.day);
          if (rate == null) {
            if (d.regular + d.overtime + d.double > 0) daysWithoutRate++;
            continue;
          }
          const pay = dayPayCents(d, rate, rule);
          regularPay += pay.regular;
          overtimePay += pay.overtime;
          doublePay += pay.double;
        }
        regularMinutes += w.regularMinutes;
        overtimeMinutes += w.overtimeMinutes;
        doubleMinutes += w.doubleMinutes;
        return w;
      });
      const myTips = tips.filter((t) => t.employeeId === employeeId);
      const cashTips = round2(myTips.filter((t) => t.method === CASH).reduce((a, t) => a + t.tip, 0));
      const cardTips = round2(myTips.filter((t) => t.method !== CASH).reduce((a, t) => a + t.tip, 0));
      const wages = cents(regularPay) + cents(overtimePay) + cents(doublePay);
      return {
        employee: people.get(employeeId) ?? this.unknown(employeeId),
        currentRate: rateOn(myRates, to),
        daysWithoutRate,
        openEntries: mine.length - closed.length,
        entries: closed.length,
        weeks: weekRows,
        regularMinutes,
        overtimeMinutes,
        doubleMinutes,
        regularPay: cents(regularPay),
        overtimePay: cents(overtimePay),
        doublePay: cents(doublePay),
        wages: round2(wages),
        tips: { card: cardTips, cash: cashTips, total: round2(cardTips + cashTips) },
        total: round2(wages + cardTips + cashTips),
      };
    });
    rows.sort((a, b) => a.employee.name.localeCompare(b.employee.name));

    const unassigned = round2(tips.filter((t) => !t.employeeId).reduce((a, t) => a + t.tip, 0));
    const sum = (f: (r: (typeof rows)[number]) => number) => round2(rows.reduce((a, r) => a + f(r), 0));
    return {
      from,
      to,
      weeks,
      rule,
      paidBreakMinutes: s.paidBreakMinutes,
      employees: rows,
      totals: {
        regularMinutes: rows.reduce((a, r) => a + r.regularMinutes, 0),
        overtimeMinutes: rows.reduce((a, r) => a + r.overtimeMinutes, 0),
        doubleMinutes: rows.reduce((a, r) => a + r.doubleMinutes, 0),
        wages: sum((r) => r.wages),
        cardTips: sum((r) => r.tips.card),
        cashTips: sum((r) => r.tips.cash),
        total: sum((r) => r.total),
      },
      unassignedTips: unassigned,
    };
  }

  /** Enlace (10 min) para descargar la nómina en Excel. */
  exportLink(week?: string, weeks = 1) {
    const expires = Date.now() + 10 * 60_000;
    const token = signPayload(EXPORT_SCOPE, JSON.stringify({ w: week ?? null, n: weeks, e: expires }), this.env.jwtAccessSecret);
    return { url: `${this.env.publicApiUrl}/payroll/export/${token}`, expiresAt: new Date(expires).toISOString() };
  }

  async exportFromToken(token: string) {
    const raw = verifyPayload(EXPORT_SCOPE, token, this.env.jwtAccessSecret);
    let payload: { w?: string | null; n?: number; e?: number } | null = null;
    try {
      payload = raw ? JSON.parse(raw) : null;
    } catch {
      payload = null;
    }
    if (!payload || !(Number(payload.e) > Date.now())) throw new UnauthorizedException('El enlace venció: vuelve a exportar desde la app');
    const weeks = payload.n === 2 ? 2 : 1;
    const p = await this.payroll(payload.w ?? undefined, weeks);
    const s = await this.settings.get();
    const tz = s.timezone;
    const hours = (m: number) => Math.round((m / 60) * 100) / 100;

    const start = zonedToUtc(p.from, '00:00', tz);
    const end = zonedToUtc(addDays(p.to, 1), '00:00', tz);
    const [entries, tips] = await Promise.all([
      this.prisma.timeEntry.findMany({
        where: { clockIn: { gte: start, lt: end } },
        include: { breaks: true, employee: { select: { name: true } } },
        orderBy: [{ employee: { name: 'asc' } }, { clockIn: 'asc' }],
      }),
      this.tipsIn(start, end),
    ]);
    const names = new Map(p.employees.map((r) => [r.employee.id, r.employee.name]));

    const summary: Cell[][] = [
      ['Empleado', 'Puesto', 'Tarifa', 'Horas normales', 'Horas extra', 'Horas dobles', 'Pago normal', 'Pago extra', 'Pago doble', 'Sueldo', 'Propinas tarjeta', 'Propinas efectivo', 'Total', 'Avisos'],
      ...p.employees.map((r): Cell[] => [
        r.employee.name,
        r.employee.jobTitle ?? r.employee.roleName,
        r.currentRate == null ? '' : { money: r.currentRate },
        hours(r.regularMinutes),
        hours(r.overtimeMinutes),
        hours(r.doubleMinutes),
        { money: r.regularPay },
        { money: r.overtimePay },
        { money: r.doublePay },
        { money: r.wages },
        { money: r.tips.card },
        { money: r.tips.cash },
        { money: r.total },
        [
          r.daysWithoutRate ? `${r.daysWithoutRate} días sin tarifa` : '',
          r.openEntries ? `${r.openEntries} jornadas sin salida (no cuentan)` : '',
        ].filter(Boolean).join(' · '),
      ]),
      [
        'Total', '', '',
        hours(p.totals.regularMinutes), hours(p.totals.overtimeMinutes), hours(p.totals.doubleMinutes),
        '', '', '',
        { money: p.totals.wages }, { money: p.totals.cardTips }, { money: p.totals.cashTips }, { money: p.totals.total }, '',
      ],
    ];
    const ruleText = [
      p.rule.weeklyHours ? `extra después de ${p.rule.weeklyHours} h por semana` : '',
      p.rule.dailyHours ? `extra después de ${p.rule.dailyHours} h por día` : '',
      p.rule.doubleDailyHours ? `doble después de ${p.rule.doubleDailyHours} h por día` : '',
    ].filter(Boolean).join(', ') || 'sin horas extra';
    summary.push([], [`Período: ${p.from} a ${p.to}. Regla: ${ruleText} (extra ${p.rule.overtimeMultiplier}x, doble ${p.rule.doubleMultiplier}x).`]);
    if (p.unassignedTips > 0) summary.push([`Propinas sin asignar (pedidos web sin empleado): $${p.unassignedTips.toFixed(2)}`]);

    const entryRows: Cell[][] = [
      ['Empleado', 'Día', 'Entrada', 'Salida', 'Descansos (min)', 'Descansos sin pagar (min)', 'Horas trabajadas', 'Corregida', 'Motivo'],
      ...entries.map((e): Cell[] => {
        const m = workedMinutes(e.clockIn, e.clockOut, e.breaks, s.paidBreakMinutes);
        return [
          e.employee.name,
          localDay(e.clockIn, tz),
          localTime(e.clockIn, tz),
          e.clockOut ? localTime(e.clockOut, tz) : 'Sin salida',
          m.breakMinutes,
          m.unpaidBreakMinutes,
          e.clockOut ? hours(m.workedMinutes) : '',
          e.editedAt ? (e.source === 'MANUAL' ? 'Manual' : 'Sí') : '',
          e.editReason ?? '',
        ];
      }),
    ];
    const tipRows: Cell[][] = [
      ['Fecha', 'Hora', 'Empleado', 'Forma de pago', 'Propina'],
      ...tips
        .filter((t) => t.tip > 0)
        .map((t): Cell[] => [
          localDay(t.at, tz),
          localTime(t.at, tz),
          t.employeeId ? (names.get(t.employeeId) ?? '') : 'Sin asignar',
          t.method === CASH ? 'Efectivo' : 'Tarjeta u otro',
          { money: t.tip },
        ]),
    ];
    const buffer = buildXlsx([
      { name: 'Nómina', rows: summary, widths: [26, 18, 10, 14, 12, 12, 13, 12, 12, 12, 15, 16, 12, 34] },
      { name: 'Jornadas', rows: entryRows, widths: [26, 12, 9, 11, 15, 22, 16, 11, 30] },
      { name: 'Propinas', rows: tipRows, widths: [12, 8, 26, 16, 12] },
    ]);
    return { name: `nomina-${p.from}-a-${p.to}.xlsx`, buffer };
  }

  // ───────── Desempeño ─────────

  /** Por empleado en un período (días de operación): ventas, mesas, cobros, propinas, horas y control. */
  async performance(fromParam?: string, toParam?: string) {
    const s = await this.settings.get();
    const tz = s.timezone;
    const today = localDay(new Date(), tz);
    const from = fromParam ?? addDays(today, -6);
    const to = toParam ?? today;
    if (!isDay(from) || !isDay(to)) throw new BadRequestException('Fecha inválida');
    if (to < from) throw new BadRequestException('La fecha final es antes de la inicial');
    if ((Date.parse(to) - Date.parse(from)) / 86_400_000 + 1 > MAX_PERFORMANCE_DAYS) {
      throw new BadRequestException(`Elige hasta ${MAX_PERFORMANCE_DAYS} días`);
    }
    const start = zonedToUtc(from, '00:00', tz);
    const end = zonedToUtc(addDays(to, 1), '00:00', tz);
    const fromDate = new Date(`${from}T00:00:00.000Z`);
    const toDate = new Date(`${to}T00:00:00.000Z`);

    const [orders, voids, discounts, refunds, payments, entries, tips] = await Promise.all([
      this.prisma.order.findMany({
        where: { businessDate: { gte: fromDate, lte: toDate }, status: { not: 'PENDING_PAYMENT' } },
        select: { id: true, billId: true, status: true, createdById: true, cancelledById: true, createdAt: true },
      }),
      this.prisma.orderItem.findMany({
        where: { voidedById: { not: null }, voidedAt: { gte: start, lt: end } },
        select: { voidedById: true, lineTotal: true },
      }),
      this.prisma.discount.findMany({
        where: { createdAt: { gte: start, lt: end }, OR: [{ appliedById: { not: null } }, { authorizedById: { not: null } }] },
        select: { appliedById: true, authorizedById: true, amount: true },
      }),
      this.prisma.refund.findMany({ where: { createdAt: { gte: start, lt: end } }, select: { employeeId: true, amount: true } }),
      this.prisma.payment.findMany({
        where: { status: 'SUCCEEDED', createdAt: { gte: start, lt: end }, employeeId: { not: null } },
        select: { employeeId: true, amount: true },
      }),
      this.prisma.timeEntry.findMany({ where: { clockIn: { gte: start, lt: end } }, include: { breaks: true } }),
      this.tipsIn(start, end),
    ]);
    const liveBillIds = [...new Set(orders.filter((o) => o.status !== 'CANCELLED').map((o) => o.billId))];
    const bills = await this.prisma.bill.findMany({
      where: { id: { in: liveBillIds }, status: { not: 'VOID' } },
      select: {
        id: true,
        subtotal: true,
        discountTotal: true,
        tableSession: { select: { id: true, waiterId: true, guestCount: true } },
        orders: { select: { createdById: true }, orderBy: { createdAt: 'asc' }, take: 1 },
      },
    });

    type Row = {
      bills: number; net: number; guests: number; tables: Set<string>; ordersTaken: number; cancellations: number;
      voids: number; voidAmount: number; discounts: number; discountAmount: number; authorized: number;
      refunds: number; refundAmount: number; payments: number; collected: number; tips: number; minutes: number;
    };
    const rows = new Map<string, Row>();
    const row = (id: string) => {
      let r = rows.get(id);
      if (!r) {
        r = { bills: 0, net: 0, guests: 0, tables: new Set(), ordersTaken: 0, cancellations: 0, voids: 0, voidAmount: 0, discounts: 0, discountAmount: 0, authorized: 0, refunds: 0, refundAmount: 0, payments: 0, collected: 0, tips: 0, minutes: 0 };
        rows.set(id, r);
      }
      return r;
    };
    for (const b of bills) {
      const who = b.tableSession?.waiterId ?? b.orders[0]?.createdById;
      if (!who) continue;
      const r = row(who);
      r.bills += 1;
      r.net += n(b.subtotal) - n(b.discountTotal);
      if (b.tableSession) {
        r.tables.add(b.tableSession.id);
      }
    }
    // Comensales: una vez por mesa atendida.
    const sessions = new Map<string, { waiter: string; guests: number }>();
    for (const b of bills) {
      const who = b.tableSession?.waiterId ?? b.orders[0]?.createdById;
      if (who && b.tableSession) sessions.set(b.tableSession.id, { waiter: who, guests: b.tableSession.guestCount ?? 0 });
    }
    for (const sInfo of sessions.values()) row(sInfo.waiter).guests += sInfo.guests;
    for (const o of orders) {
      if (o.createdById) row(o.createdById).ordersTaken += 1;
      if (o.cancelledById) row(o.cancelledById).cancellations += 1;
    }
    for (const v of voids) {
      const r = row(v.voidedById!);
      r.voids += 1;
      r.voidAmount += n(v.lineTotal);
    }
    for (const d of discounts) {
      if (d.appliedById) {
        const r = row(d.appliedById);
        r.discounts += 1;
        r.discountAmount += n(d.amount);
      }
      if (d.authorizedById) row(d.authorizedById).authorized += 1;
    }
    for (const rf of refunds) {
      const r = row(rf.employeeId);
      r.refunds += 1;
      r.refundAmount += n(rf.amount);
    }
    for (const p of payments) {
      const r = row(p.employeeId!);
      r.payments += 1;
      r.collected += n(p.amount);
    }
    for (const t of tips) if (t.employeeId) row(t.employeeId).tips += t.tip;
    for (const e of entries) row(e.employeeId).minutes += workedMinutes(e.clockIn, e.clockOut, e.breaks, s.paidBreakMinutes).workedMinutes;

    const people = await this.people([...rows.keys()]);
    const employees = [...rows.entries()]
      .filter(([id]) => people.has(id))
      .map(([id, r]) => ({
        employee: people.get(id)!,
        bills: r.bills,
        netSales: round2(r.net),
        averageTicket: r.bills ? round2(r.net / r.bills) : 0,
        tables: r.tables.size,
        guests: r.guests,
        ordersTaken: r.ordersTaken,
        payments: r.payments,
        collected: round2(r.collected),
        tips: round2(r.tips),
        tipPercent: r.net > 0 ? Math.round((r.tips / r.net) * 1000) / 10 : 0,
        workedMinutes: r.minutes,
        salesPerHour: r.minutes > 0 ? round2(r.net / (r.minutes / 60)) : 0,
        cancellations: r.cancellations,
        voids: r.voids,
        voidAmount: round2(r.voidAmount),
        discounts: r.discounts,
        discountAmount: round2(r.discountAmount),
        discountsAuthorized: r.authorized,
        refunds: r.refunds,
        refundAmount: round2(r.refundAmount),
      }))
      .sort((a, b) => b.netSales - a.netSales || b.workedMinutes - a.workedMinutes);
    return { from, to, employees };
  }

  // ───────── Internos ─────────

  private ruleOf(s: {
    overtimeWeeklyHours: number;
    overtimeDailyHours: number;
    doubleTimeDailyHours: number;
    overtimeMultiplier: Prisma.Decimal;
    doubleTimeMultiplier: Prisma.Decimal;
  }): OvertimeRule {
    return {
      weeklyHours: s.overtimeWeeklyHours,
      dailyHours: s.overtimeDailyHours,
      doubleDailyHours: s.doubleTimeDailyHours,
      overtimeMultiplier: n(s.overtimeMultiplier),
      doubleMultiplier: n(s.doubleTimeMultiplier),
    };
  }

  /** Propinas cobradas en el período y a quién van. */
  private async tipsIn(start: Date, end: Date): Promise<TipLine[]> {
    const payments = await this.prisma.payment.findMany({
      where: { status: 'SUCCEEDED', createdAt: { gte: start, lt: end }, tipAmount: { gt: 0 } },
      select: {
        id: true,
        createdAt: true,
        method: true,
        tipAmount: true,
        employeeId: true,
        bill: {
          select: {
            tableSession: { select: { waiterId: true } },
            orders: {
              select: {
                createdById: true,
                fulfillmentType: true,
                deliveryAssignment: { select: { status: true, driver: { select: { employeeId: true } } } },
              },
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });
    return payments.map((p) => {
      const delivery = p.bill.orders.find((o) => o.fulfillmentType === 'DELIVERY');
      const assignment = delivery?.deliveryAssignment;
      return {
        paymentId: p.id,
        at: p.createdAt,
        method: p.method,
        tip: n(p.tipAmount),
        employeeId: tipOwner({
          isDelivery: !!delivery,
          driverEmployeeId: assignment && assignment.status !== 'CANCELLED' ? assignment.driver.employeeId : null,
          waiterId: p.bill.tableSession?.waiterId ?? null,
          cashierId: p.employeeId,
          orderCreatorId: p.bill.orders[0]?.createdById ?? null,
        }),
      };
    });
  }

  private async people(ids: string[]): Promise<Map<string, Brief>> {
    const list = await this.prisma.employee.findMany({
      where: { id: { in: ids } },
      include: { role: { select: { name: true } } },
    });
    return new Map(list.map((e) => [e.id, this.brief(e)]));
  }

  private brief(e: { id: string; name: string; photoUrl: string | null; jobTitle: string | null; isActive: boolean; role: { name: string } }): Brief {
    return { id: e.id, name: e.name, photoUrl: e.photoUrl, jobTitle: e.jobTitle, roleName: e.role.name, isActive: e.isActive };
  }

  private unknown(id: string): Brief {
    return { id, name: 'Empleado borrado', photoUrl: null, jobTitle: null, roleName: '', isActive: false };
  }
}
