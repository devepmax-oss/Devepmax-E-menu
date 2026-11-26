import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { BUSINESS_DAY_CUTOFF_HOUR, businessDateFor } from '../orders/order.rules';
import { rateOn } from '../payroll/payroll.rules';
import { SettingsService } from '../settings/settings.service';
import { MISSING_OUT_HOURS, workedMinutes, zonedToUtc } from '../timeclock/timeclock.rules';
import { THRESHOLDS, buildAlerts, change } from './dashboard.rules';

const n = (v: Prisma.Decimal | number | null | undefined) => (v == null ? 0 : Number(v));
const round2 = (v: number) => Math.round(v * 100) / 100;
const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const IN_KITCHEN = ['PLACED', 'ACCEPTED', 'PREPARING'] as const;
const LIVE_EXCLUDED = ['PENDING_PAYMENT', 'CANCELLED', 'SCHEDULED'] as const;

type ItemLite = { status: string; quantity: number; lineTotal: Prisma.Decimal; nameSnapshot: string; discounts: { amount: Prisma.Decimal }[] };
const itemNet = (i: ItemLite) => n(i.lineTotal) - i.discounts.reduce((a, d) => a + n(d.amount), 0);

/**
 * Tablero del dueño: cómo va el día de operación (desde las 4 a. m.) contra el mismo día de
 * la semana pasada a la misma hora, qué está pasando ahora y las alertas que piden atención.
 */
@Injectable()
export class DashboardService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
  ) {}

  async today() {
    const s = await this.settings.get();
    const tz = s.timezone;
    const now = new Date();
    const bd = businessDateFor(now, tz);
    const day = bd.toISOString().slice(0, 10);
    const dayStart = zonedToUtc(day, `${String(BUSINESS_DAY_CUTOFF_HOUR).padStart(2, '0')}:00`, tz);
    const lastBd = new Date(bd.getTime() - 7 * DAY);
    const lastDay = lastBd.toISOString().slice(0, 10);
    const lastStart = zonedToUtc(lastDay, `${String(BUSINESS_DAY_CUTOFF_HOUR).padStart(2, '0')}:00`, tz);
    const sameTimeLastWeek = new Date(lastStart.getTime() + (now.getTime() - dayStart.getTime()));

    const itemSelect = { select: { status: true, quantity: true, lineTotal: true, nameSnapshot: true, discounts: { select: { amount: true } } } } as const;
    const [todayOrders, lastOrders, billDiscounts, lastBillDiscounts, payments, active, sessions, entries, rates, tickets] = await Promise.all([
      this.prisma.order.findMany({
        where: { businessDate: bd, status: { not: 'PENDING_PAYMENT' } },
        select: { id: true, status: true, channel: true, billId: true, createdAt: true, items: itemSelect },
      }),
      this.prisma.order.findMany({
        where: { businessDate: lastBd, status: { notIn: [...LIVE_EXCLUDED] } },
        select: { createdAt: true, items: itemSelect },
      }),
      // Descuentos de toda la cuenta (cupones, descuento manual a la cuenta).
      this.prisma.discount.findMany({
        where: { orderItemId: null, createdAt: { gte: dayStart, lte: now } },
        select: { amount: true, appliedById: true },
      }),
      this.prisma.discount.findMany({
        where: { orderItemId: null, createdAt: { gte: lastStart, lt: new Date(lastStart.getTime() + DAY) } },
        select: { amount: true, createdAt: true },
      }),
      this.prisma.payment.findMany({
        where: { status: { in: ['SUCCEEDED', 'PARTIALLY_REFUNDED'] }, createdAt: { gte: dayStart, lte: now } },
        select: { amount: true, tipAmount: true },
      }),
      this.prisma.order.groupBy({
        by: ['status'],
        where: { status: { in: ['PENDING_APPROVAL', ...IN_KITCHEN, 'READY', 'OUT_FOR_DELIVERY'] } },
        _count: { _all: true },
      }),
      this.prisma.tableSession.findMany({ where: { status: { in: ['OPEN', 'BILL_REQUESTED'] } }, select: { guestCount: true } }),
      this.prisma.timeEntry.findMany({
        where: { OR: [{ clockIn: { gte: dayStart } }, { clockOut: null }] },
        include: { breaks: true },
      }),
      this.prisma.payRate.findMany(),
      this.prisma.kitchenTicket.findMany({
        where: { status: { in: ['NEW', 'ACCEPTED', 'PREPARING'] }, order: { status: { in: [...IN_KITCHEN] } } },
        select: { createdAt: true },
      }),
    ]);

    // Ventas de hoy (lo pedido, sin impuesto ni propina; menos descuentos).
    const live = todayOrders.filter((o) => !(LIVE_EXCLUDED as readonly string[]).includes(o.status));
    const activeItems = live.flatMap((o) => o.items.filter((i) => i.status === 'ACTIVE'));
    const gross = activeItems.reduce((a, i) => a + n(i.lineTotal), 0);
    const billDisc = billDiscounts.reduce((a, d) => a + n(d.amount), 0);
    const net = round2(activeItems.reduce((a, i) => a + itemNet(i), 0) - billDisc);
    const bills = new Set(live.map((o) => o.billId)).size;

    // La semana pasada hasta esta misma hora, y el día completo.
    const lastItems = (until?: Date) =>
      lastOrders
        .filter((o) => !until || o.createdAt <= until)
        .flatMap((o) => o.items.filter((i) => i.status === 'ACTIVE'))
        .reduce((a, i) => a + itemNet(i), 0);
    const lastDisc = (until?: Date) => lastBillDiscounts.filter((d) => !until || d.createdAt <= until).reduce((a, d) => a + n(d.amount), 0);
    const lastWeekSoFar = round2(lastItems(sameTimeLastWeek) - lastDisc(sameTimeLastWeek));
    const lastWeekDay = round2(lastItems() - lastDisc());
    const lastOrdersSoFar = lastOrders.filter((o) => o.createdAt <= sameTimeLastWeek).length;

    // Por hora (hora local) y por canal.
    const hourOf = new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: tz });
    const slot = (d: Date) => (Number(hourOf.format(d)) - BUSINESS_DAY_CUTOFF_HOUR + 24) % 24;
    const hourly = Array.from({ length: 24 }, (_, i) => ({ hour: (i + BUSINESS_DAY_CUTOFF_HOUR) % 24, today: 0, lastWeek: 0 }));
    for (const o of live) hourly[slot(o.createdAt)].today += o.items.filter((i) => i.status === 'ACTIVE').reduce((a, i) => a + itemNet(i), 0);
    for (const o of lastOrders) hourly[slot(o.createdAt)].lastWeek += o.items.filter((i) => i.status === 'ACTIVE').reduce((a, i) => a + itemNet(i), 0);
    const nowSlot = slot(now);
    const used = hourly.map((h, i) => ({ ...h, i })).filter((h) => h.today > 0 || h.lastWeek > 0 || h.i === nowSlot);
    const first = used.length ? Math.min(...used.map((h) => h.i)) : nowSlot;
    const last = used.length ? Math.max(...used.map((h) => h.i)) : nowSlot;
    const byChannel = new Map<string, { orders: number; net: number }>();
    for (const o of live) {
      const c = byChannel.get(o.channel) ?? { orders: 0, net: 0 };
      c.orders += 1;
      c.net += o.items.filter((i) => i.status === 'ACTIVE').reduce((a, i) => a + itemNet(i), 0);
      byChannel.set(o.channel, c);
    }
    const byProduct = new Map<string, { quantity: number; net: number }>();
    for (const i of activeItems) {
      const p = byProduct.get(i.nameSnapshot) ?? { quantity: 0, net: 0 };
      p.quantity += i.quantity;
      p.net += itemNet(i);
      byProduct.set(i.nameSnapshot, p);
    }

    // Personal: quién trabaja y cuánto cuesta hoy (con la tarifa de cada uno).
    const ratesOf = new Map<string, { effectiveFrom: string; hourlyRate: number }[]>();
    for (const r of rates) {
      const list = ratesOf.get(r.employeeId) ?? [];
      list.push({ effectiveFrom: r.effectiveFrom.toISOString().slice(0, 10), hourlyRate: n(r.hourlyRate) });
      ratesOf.set(r.employeeId, list);
    }
    const stale = (e: { clockIn: Date; clockOut: Date | null }) => !e.clockOut && now.getTime() - e.clockIn.getTime() >= MISSING_OUT_HOURS * HOUR;
    let laborMinutes = 0;
    let laborCost = 0;
    for (const e of entries.filter((x) => !stale(x))) {
      // Solo lo trabajado desde que empezó el día de operación.
      const from = e.clockIn < dayStart ? dayStart : e.clockIn;
      const m = workedMinutes(from, e.clockOut, e.breaks.filter((b) => (b.end ?? now) > from), s.paidBreakMinutes, now).workedMinutes;
      laborMinutes += m;
      laborCost += (m / 60) * (rateOn(ratesOf.get(e.employeeId) ?? [], day) ?? 0);
    }
    const working = entries.filter((e) => !e.clockOut && !stale(e)).length;
    const missingOut = entries.filter(stale).length;

    // Inventario: costo de lo vendido hoy y lo que está bajo el mínimo.
    let foodCost: number | null = null;
    let lowStock: string[] = [];
    if (s.inventoryEnabled) {
      const [sales, items] = await Promise.all([
        this.prisma.stockMovement.findMany({ where: { type: 'SALE', createdAt: { gte: dayStart } }, select: { quantity: true, unitCost: true } }),
        this.prisma.inventoryItem.findMany({ where: { isActive: true, minLevel: { not: null } }, select: { name: true, onHand: true, minLevel: true } }),
      ]);
      foodCost = round2(sales.reduce((a, m) => a - n(m.quantity) * n(m.unitCost), 0));
      lowStock = items.filter((i) => n(i.onHand) <= n(i.minLevel)).map((i) => i.name).sort();
    }

    const lateCut = now.getTime() - THRESHOLDS.kitchenLateMinutes * 60_000;
    const late = tickets.filter((t) => t.createdAt.getTime() < lateCut);
    const oldest = late.length ? Math.round((now.getTime() - Math.min(...late.map((t) => t.createdAt.getTime()))) / 60_000) : 0;
    const cancellations = todayOrders.filter((o) => o.status === 'CANCELLED').length;
    const manual = billDiscounts.filter((d) => d.appliedById);
    const itemManual = await this.prisma.discount.findMany({
      where: { orderItemId: { not: null }, appliedById: { not: null }, createdAt: { gte: dayStart, lte: now } },
      select: { amount: true },
    });
    const manualCount = manual.length + itemManual.length;
    const manualAmount = manual.reduce((a, d) => a + n(d.amount), 0) + itemManual.reduce((a, d) => a + n(d.amount), 0);
    const count = (status: string) => active.find((a) => a.status === status)?._count._all ?? 0;
    const scheduledToday = todayOrders.filter((o) => o.status === 'SCHEDULED').length;
    const tips = round2(payments.reduce((a, p) => a + n(p.tipAmount), 0));

    return {
      at: now,
      businessDate: day,
      compareDate: lastDay,
      sales: {
        net,
        lastWeekSoFar,
        lastWeekDay,
        change: change(net, lastWeekSoFar),
        orders: live.length,
        lastWeekOrders: lastOrdersSoFar,
        bills,
        averageTicket: bills ? round2(net / bills) : 0,
        collected: round2(payments.reduce((a, p) => a + n(p.amount), 0)),
        tips,
        cancellations,
        scheduledToday,
      },
      labor: {
        working,
        minutes: laborMinutes,
        cost: round2(laborCost),
        percent: net > 0 && laborCost > 0 ? Math.round((laborCost / net) * 1000) / 10 : null,
      },
      foodCost: foodCost === null ? null : { cost: foodCost, percent: net > 0 ? Math.round((foodCost / net) * 1000) / 10 : null },
      now: {
        approval: count('PENDING_APPROVAL'),
        kitchen: IN_KITCHEN.reduce((a, st) => a + count(st), 0),
        ready: count('READY'),
        onTheWay: count('OUT_FOR_DELIVERY'),
        lateTickets: late.length,
        openTables: sessions.length,
        guests: sessions.reduce((a, x) => a + (x.guestCount ?? 0), 0),
      },
      hourly: hourly.slice(first, last + 1).map((h) => ({ hour: h.hour, today: round2(h.today), lastWeek: round2(h.lastWeek) })),
      channels: [...byChannel.entries()].map(([channel, v]) => ({ channel, orders: v.orders, net: round2(v.net) })).sort((a, b) => b.net - a.net),
      topProducts: [...byProduct.entries()]
        .map(([name, v]) => ({ name, quantity: v.quantity, net: round2(v.net) }))
        .sort((a, b) => b.quantity - a.quantity || b.net - a.net)
        .slice(0, 8),
      alerts: buildAlerts({
        net,
        lastWeekSoFar,
        laborCost,
        foodCost,
        lowStock,
        lateTickets: late.length,
        oldestTicketMinutes: oldest,
        orders: todayOrders.filter((o) => o.status !== 'SCHEDULED').length,
        cancellations,
        manualDiscounts: manualCount,
        manualDiscountAmount: manualAmount,
        gross,
        missingOut,
        onlinePaused: s.onlineOrderingPaused,
      }),
    };
  }
}
