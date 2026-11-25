import { BadRequestException, Injectable, Logger, NotFoundException, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, RestaurantSettings } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { randomCouponCode } from '../coupons/coupon.rules';
import { SettingsService } from '../settings/settings.service';
import { birthdayCouponEnd, monthIn, pointsForBill, rewardsFor } from './loyalty.rules';

const SIX_HOURS = 6 * 3_600_000;

/**
 * Programa de lealtad: puntos por dólar en cada cuenta pagada de un cliente identificado (web,
 * caja o mesa). Al llegar a la meta se entrega un cupón personal; en el mes de su cumpleaños,
 * un regalo. Los puntos se recalculan si hay reembolso o si cambia el cliente de la cuenta.
 */
@Injectable()
export class LoyaltyService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Lealtad');
  private unsubscribe?: () => void;
  private readonly queue = new Map<string, Promise<void>>();
  private timer?: NodeJS.Timeout;
  private firstRun?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEventsService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
  ) {}

  onModuleInit() {
    this.unsubscribe = this.events.subscribe((e) => {
      const billId =
        e.name === 'bill.updated'
          ? (e.payload as { id?: string }).id
          : e.name === 'order.updated'
            ? (e.payload as { bill?: { id?: string } }).bill?.id
            : undefined;
      if (billId) this.enqueue(billId);
    });
    this.firstRun = setTimeout(() => void this.birthdays().catch((e) => this.logger.error(`Cumpleaños: ${String(e)}`)), 30_000);
    this.timer = setInterval(() => void this.birthdays().catch((e) => this.logger.error(`Cumpleaños: ${String(e)}`)), SIX_HOURS);
  }

  onModuleDestroy() {
    this.unsubscribe?.();
    clearTimeout(this.firstRun);
    clearInterval(this.timer);
  }

  /** Una cuenta a la vez (en orden) para no dar puntos dos veces. */
  enqueue(billId: string): Promise<void> {
    const previous = this.queue.get(billId) ?? Promise.resolve();
    const next = previous
      .then(() => this.syncBill(billId))
      .catch((e) => this.logger.error(`No se pudieron calcular los puntos de la cuenta ${billId}: ${String(e)}`))
      .finally(() => {
        if (this.queue.get(billId) === next) this.queue.delete(billId);
      });
    this.queue.set(billId, next);
    return next;
  }

  /** Deja los puntos de la cuenta como deben ser (y entrega premios si alcanza la meta). */
  async syncBill(billId: string) {
    const s = await this.settings.get();
    if (!s.loyaltyEnabled) return;
    const bill = await this.prisma.bill.findUnique({
      where: { id: billId },
      include: { payments: { where: { status: 'SUCCEEDED' }, include: { refunds: true } } },
    });
    if (!bill) return;
    const refunded = bill.payments.flatMap((p) => p.refunds).reduce((sum, r) => sum.plus(r.amount), new Prisma.Decimal(0));
    const target = bill.customerId ? pointsForBill({ ...bill, refunded }, s.loyaltyPointsPerDollar) : 0;

    const earned = await this.prisma.loyaltyTransaction.groupBy({
      by: ['customerId'],
      where: { billId, type: 'EARN' },
      _sum: { points: true },
    });
    const have = new Map(earned.map((e) => [e.customerId, e._sum.points ?? 0]));
    const customers = new Set([...have.keys(), ...(bill.customerId ? [bill.customerId] : [])]);
    for (const customerId of customers) {
      const want = customerId === bill.customerId ? target : 0;
      const delta = want - (have.get(customerId) ?? 0);
      if (delta === 0) continue;
      const exists = await this.prisma.customer.findUnique({ where: { id: customerId }, select: { id: true } });
      if (!exists) continue;
      await this.prisma.$transaction([
        this.prisma.loyaltyTransaction.create({
          data: { customerId, type: 'EARN', points: delta, billId, reason: delta > 0 ? 'Compra' : 'Ajuste por reembolso o cambio de cliente' },
        }),
        this.prisma.customer.update({ where: { id: customerId }, data: { points: { increment: delta } } }),
      ]);
    }
    if (bill.customerId) await this.issueRewards(bill.customerId, s);
  }

  /** Si el saldo alcanza la meta, entrega el premio como cupón personal. */
  async issueRewards(customerId: string, s?: RestaurantSettings) {
    const settings = s ?? (await this.settings.get());
    if (!settings.loyaltyEnabled) return;
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) return;
    const { rewards } = rewardsFor(customer.points, settings.loyaltyRewardPoints);
    for (let i = 0; i < rewards; i++) {
      const coupon = await this.personalCoupon(customerId, {
        prefix: 'PREMIO-',
        name: `Premio de lealtad · $${settings.loyaltyRewardAmount.toFixed(0)}`,
        amount: settings.loyaltyRewardAmount,
        endsAt: new Date(Date.now() + settings.loyaltyRewardDays * 86_400_000),
      });
      await this.prisma.$transaction([
        this.prisma.loyaltyTransaction.create({
          data: { customerId, type: 'REWARD', points: -settings.loyaltyRewardPoints, couponId: coupon.id, reason: 'Premio' },
        }),
        this.prisma.customer.update({ where: { id: customerId }, data: { points: { decrement: settings.loyaltyRewardPoints } } }),
      ]);
    }
  }

  /** Regalo de cumpleaños: en el mes del cumpleaños, un cupón personal (una vez al año). */
  async birthdays() {
    const s = await this.settings.get();
    if (!s.birthdayRewardEnabled) return 0;
    const { year, month } = monthIn(s.timezone);
    const due = await this.prisma.customer.findMany({
      where: { birthMonth: month, OR: [{ birthdayRewardYear: null }, { birthdayRewardYear: { lt: year } }], name: { not: '' } },
      select: { id: true },
      take: 500,
    });
    for (const c of due) {
      // Se marca primero: si dos procesos corrieran a la vez, solo uno entrega el regalo.
      const claimed = await this.prisma.customer.updateMany({
        where: { id: c.id, OR: [{ birthdayRewardYear: null }, { birthdayRewardYear: { lt: year } }] },
        data: { birthdayRewardYear: year },
      });
      if (claimed.count !== 1) continue;
      await this.personalCoupon(c.id, {
        prefix: 'CUMPLE-',
        name: `Regalo de cumpleaños · $${s.birthdayRewardAmount.toFixed(0)}`,
        amount: s.birthdayRewardAmount,
        endsAt: birthdayCouponEnd(year, month),
      });
    }
    if (due.length) this.logger.log(`Regalos de cumpleaños entregados: ${due.length}`);
    return due.length;
  }

  // ───────── Para el cliente y el personal ─────────

  /** Lo que el cliente ve: saldo, meta, premios vigentes y últimos movimientos. */
  async summary(customerId: string) {
    const [s, customer, rewards, moves] = await Promise.all([
      this.settings.get(),
      this.prisma.customer.findUnique({ where: { id: customerId } }),
      this.activeRewards(customerId),
      this.prisma.loyaltyTransaction.findMany({ where: { customerId }, orderBy: { createdAt: 'desc' }, take: 30 }),
    ]);
    if (!customer) throw new NotFoundException('Cliente no encontrado');
    return {
      enabled: s.loyaltyEnabled,
      points: customer.points,
      pointsPerDollar: s.loyaltyPointsPerDollar,
      rewardPoints: s.loyaltyRewardPoints,
      rewardAmount: s.loyaltyRewardAmount,
      toNextReward: Math.max(0, s.loyaltyRewardPoints - customer.points),
      birthday: customer.birthMonth && customer.birthDay ? { month: customer.birthMonth, day: customer.birthDay } : null,
      birthdayRewardEnabled: s.birthdayRewardEnabled,
      birthdayRewardAmount: s.birthdayRewardAmount,
      rewards,
      history: moves.map((m) => ({ id: m.id, type: m.type, points: m.points, reason: m.reason, date: m.createdAt })),
    };
  }

  /** Cupones personales sin usar y vigentes (premios, cumpleaños u otros). */
  async activeRewards(customerId: string) {
    const now = new Date();
    const coupons = await this.prisma.coupon.findMany({
      where: {
        customerId,
        isActive: true,
        OR: [{ endsAt: null }, { endsAt: { gt: now } }],
      },
      include: { redemptions: { where: { order: { status: { not: 'CANCELLED' } } }, select: { id: true } } },
      orderBy: { endsAt: 'asc' },
    });
    return coupons
      .filter((c) => !c.maxUses || c.redemptions.length < c.maxUses)
      .map((c) => ({ code: c.code, name: c.name, type: c.type, value: c.value, endsAt: c.endsAt }));
  }

  /** Ajuste manual (el personal): suma o resta puntos con un motivo. */
  async adjust(actor: EmployeeActor, customerId: string, points: number, reason: string) {
    if (!Number.isInteger(points) || points === 0) throw new BadRequestException('Escribe cuántos puntos sumar o restar');
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) throw new NotFoundException('Cliente no encontrado');
    if (customer.points + points < 0) throw new BadRequestException(`El cliente solo tiene ${customer.points} puntos`);
    await this.prisma.$transaction([
      this.prisma.loyaltyTransaction.create({ data: { customerId, type: 'ADJUST', points, reason: reason.trim(), employeeId: actor.id } }),
      this.prisma.customer.update({ where: { id: customerId }, data: { points: { increment: points } } }),
    ]);
    await this.audit.log(actor, 'loyalty.adjust', 'customer', customerId, { points, reason });
    await this.issueRewards(customerId);
    return this.summary(customerId);
  }

  private async personalCoupon(customerId: string, o: { prefix: string; name: string; amount: Prisma.Decimal; endsAt: Date }) {
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        return await this.prisma.coupon.create({
          data: {
            code: randomCouponCode(o.prefix, 6),
            name: o.name,
            type: 'AMOUNT',
            value: o.amount,
            customerId,
            maxUses: 1,
            appliesOnline: true,
            appliesInStore: true,
            endsAt: o.endsAt,
          },
        });
      } catch (error) {
        if (attempt === 4) throw error; // código repetido: se intenta con otro
      }
    }
    throw new Error('No se pudo crear el cupón');
  }
}
