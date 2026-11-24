import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { CashShift, Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CashMovementDto } from './dto/billing.dto';

const D = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const ZERO = D(0);

/**
 * Turno de caja: se abre con el fondo, se registran entradas y salidas de efectivo y se
 * cierra contando el efectivo. El sistema calcula cuánto debería haber y la diferencia.
 */
@Injectable()
export class CashService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  /** El turno abierto (o null) con su resumen. */
  async current() {
    const shift = await this.prisma.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
    return shift ? this.summary(shift) : null;
  }

  async history(limit = 15) {
    const shifts = await this.prisma.cashShift.findMany({ orderBy: { openedAt: 'desc' }, take: limit });
    return Promise.all(shifts.map((s) => this.summary(s)));
  }

  async open(actor: EmployeeActor, openingCash: number) {
    const existing = await this.prisma.cashShift.findFirst({ where: { closedAt: null } });
    if (existing) throw new ConflictException('La caja ya está abierta');
    const shift = await this.prisma.cashShift.create({
      data: { openedById: actor.id, openingCash: D(openingCash).toDecimalPlaces(2), deviceId: actor.deviceId },
    });
    await this.audit.log(actor, 'cash.open', 'cash_shift', shift.id, { openingCash });
    return this.summary(shift);
  }

  async movement(actor: EmployeeActor, dto: CashMovementDto) {
    const shift = await this.openShift();
    await this.prisma.cashMovement.create({
      data: { shiftId: shift.id, type: dto.type, amount: D(dto.amount).toDecimalPlaces(2), reason: dto.reason.trim(), employeeId: actor.id },
    });
    await this.audit.log(actor, 'cash.movement', 'cash_shift', shift.id, { type: dto.type, amount: dto.amount, reason: dto.reason });
    return this.summary(shift);
  }

  async close(actor: EmployeeActor, countedCash: number, notes?: string) {
    const shift = await this.openShift();
    const before = await this.summary(shift);
    const counted = D(countedCash).toDecimalPlaces(2);
    const closed = await this.prisma.cashShift.update({
      where: { id: shift.id },
      data: {
        closedAt: new Date(),
        closedById: actor.id,
        expectedCash: before.expectedCash,
        countedCash: counted,
        difference: counted.minus(before.expectedCash),
        notes: notes?.trim() || null,
      },
    });
    await this.audit.log(actor, 'cash.close', 'cash_shift', shift.id, {
      expected: before.expectedCash.toString(),
      counted: counted.toString(),
    });
    return this.summary(closed);
  }

  private async openShift(): Promise<CashShift> {
    const shift = await this.prisma.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
    if (!shift) throw new NotFoundException('La caja está cerrada');
    return shift;
  }

  /** Ventas del turno por forma de pago, propinas, movimientos y efectivo esperado. */
  async summary(shift: CashShift) {
    const [payments, movements, people, refunds] = await Promise.all([
      this.prisma.payment.findMany({ where: { cashShiftId: shift.id, status: 'SUCCEEDED' } }),
      this.prisma.cashMovement.findMany({ where: { shiftId: shift.id }, orderBy: { createdAt: 'asc' } }),
      this.prisma.employee.findMany({
        where: { id: { in: [shift.openedById, ...(shift.closedById ? [shift.closedById] : [])] } },
        select: { id: true, name: true },
      }),
      // Reembolsos hechos durante el turno (de cualquier forma de pago).
      this.prisma.refund.findMany({
        where: { createdAt: { gte: shift.openedAt, ...(shift.closedAt ? { lte: shift.closedAt } : {}) } },
        include: { payment: { select: { method: true } } },
      }),
    ]);
    const name = (id: string | null) => people.find((p) => p.id === id)?.name ?? null;
    const byMethod = new Map<string, { count: number; amount: Prisma.Decimal; tips: Prisma.Decimal }>();
    for (const p of payments) {
      const entry = byMethod.get(p.method) ?? { count: 0, amount: ZERO, tips: ZERO };
      byMethod.set(p.method, { count: entry.count + 1, amount: entry.amount.plus(p.amount), tips: entry.tips.plus(p.tipAmount) });
    }
    const total = (type: string) => movements.filter((m) => m.type === type).reduce((a, m) => a.plus(m.amount), ZERO);
    const cashSales = byMethod.get('CASH')?.amount ?? ZERO;
    const expectedCash = shift.openingCash.plus(cashSales).plus(total('PAY_IN')).minus(total('PAY_OUT')).minus(total('DROP'));
    return {
      id: shift.id,
      openedAt: shift.openedAt,
      closedAt: shift.closedAt,
      openedBy: name(shift.openedById),
      closedBy: name(shift.closedById),
      openingCash: shift.openingCash,
      sales: [...byMethod.entries()].map(([method, v]) => ({ method, count: v.count, amount: v.amount, tips: v.tips })),
      totalSales: payments.reduce((a, p) => a.plus(p.amount), ZERO),
      totalTips: payments.reduce((a, p) => a.plus(p.tipAmount), ZERO),
      refunds: [...refunds.reduce((m, r) => m.set(r.payment.method, (m.get(r.payment.method) ?? ZERO).plus(r.amount)), new Map<string, Prisma.Decimal>())].map(
        ([method, amount]) => ({ method, amount }),
      ),
      totalRefunds: refunds.reduce((a, r) => a.plus(r.amount), ZERO),
      movements: movements.map((m) => ({ id: m.id, type: m.type, amount: m.amount, reason: m.reason, createdAt: m.createdAt })),
      expectedCash: shift.closedAt && shift.expectedCash ? shift.expectedCash : expectedCash,
      countedCash: shift.countedCash,
      difference: shift.difference,
      notes: shift.notes,
    };
  }
}
