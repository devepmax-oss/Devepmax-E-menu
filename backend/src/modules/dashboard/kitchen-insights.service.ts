import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { businessDateFor } from '../orders/order.rules';
import { SettingsService } from '../settings/settings.service';
import { latePercent, stats, ticketTimes } from './kitchen.rules';
import { parsePeriod } from './menu.rules';

const iso = (d: Date) => d.toISOString().slice(0, 10);
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const avg = (v: number[]) => (v.length ? Math.round((v.reduce((a, x) => a + x, 0) / v.length) * 10) / 10 : null);

/**
 * Tiempos de cocina de un período: cuánto tarda un ticket desde que llega hasta que se marca
 * Listo (y cuánto de eso es espera y cuánto preparación), por estación, por plato, por hora y
 * por día de la semana, con los tickets más lentos. La meta es el tiempo de preparación del
 * restaurante (Ajustes); un plato con su propio tiempo se compara contra el suyo.
 */
@Injectable()
export class KitchenInsightsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
  ) {}

  async kitchen(fromParam?: string, toParam?: string) {
    const s = await this.settings.get();
    const tz = s.timezone;
    let period: ReturnType<typeof parsePeriod>;
    try {
      period = parsePeriod(fromParam, toParam, iso(businessDateFor(new Date(), tz)));
    } catch (e) {
      throw new BadRequestException((e as Error).message);
    }
    const { from, to, days } = period;
    const target = s.prepTimeMinutes;

    const tickets = await this.prisma.kitchenTicket.findMany({
      where: { status: { not: 'CANCELLED' }, order: { businessDate: { gte: from, lte: to }, status: { notIn: ['CANCELLED', 'PENDING_PAYMENT'] } } },
      select: {
        id: true,
        createdAt: true,
        startedAt: true,
        readyAt: true,
        stationId: true,
        station: { select: { name: true } },
        order: { select: { number: true, fulfillmentType: true, channel: true } },
        items: { where: { status: 'ACTIVE' }, select: { productId: true, nameSnapshot: true, quantity: true } },
      },
    });
    const productIds = [...new Set(tickets.flatMap((t) => t.items.map((i) => i.productId).filter((x): x is string => !!x)))];
    const products = await this.prisma.product.findMany({ where: { id: { in: productIds } }, select: { id: true, name: true, prepTimeMinutes: true } });
    const productById = new Map(products.map((p) => [p.id, p]));

    const timed = tickets.flatMap((t) => {
      const times = ticketTimes(t);
      return times ? [{ ...t, ...times }] : [];
    });
    const notMarked = tickets.length - timed.length;
    const totals = timed.map((t) => t.total);

    // Por estación.
    const byStation = new Map<string, { name: string; totals: number[]; waits: number[]; preps: number[] }>();
    for (const t of timed) {
      const a = byStation.get(t.stationId) ?? { name: t.station.name, totals: [], waits: [], preps: [] };
      a.totals.push(t.total);
      if (t.wait !== null) a.waits.push(t.wait);
      if (t.prep !== null) a.preps.push(t.prep);
      byStation.set(t.stationId, a);
    }

    // Por plato: el tiempo de los tickets donde iba ese plato.
    const byDish = new Map<string, { name: string; productId: string | null; totals: number[]; units: number }>();
    for (const t of timed) {
      const seen = new Set<string>();
      for (const i of t.items) {
        const key = i.productId ?? `name:${i.nameSnapshot}`;
        const a = byDish.get(key) ?? { name: (i.productId && productById.get(i.productId)?.name) || i.nameSnapshot, productId: i.productId, totals: [], units: 0 };
        a.units += i.quantity;
        if (!seen.has(key)) a.totals.push(t.total);
        seen.add(key);
        byDish.set(key, a);
      }
    }

    // Por hora y día de la semana (hora local del restaurante).
    const hourOf = new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: tz });
    const dayOf = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: tz });
    const byHour = new Map<number, number[]>();
    const byWeekday = new Map<number, number[]>();
    for (const t of timed) {
      const h = Number(hourOf.format(t.createdAt)) % 24;
      byHour.set(h, [...(byHour.get(h) ?? []), t.total]);
      const w = WEEKDAYS.indexOf(dayOf.format(t.createdAt));
      byWeekday.set(w, [...(byWeekday.get(w) ?? []), t.total]);
    }

    const summary = (list: number[]) => {
      const st = stats(list);
      return { ...st, latePct: latePercent(list, target) };
    };

    return {
      from: iso(from),
      to: iso(to),
      days,
      targetMinutes: target,
      summary: {
        ...summary(totals),
        tickets: tickets.length,
        notMarked,
        late: totals.filter((x) => x > target).length,
        wait: stats(timed.flatMap((t) => (t.wait === null ? [] : [t.wait]))),
        prep: stats(timed.flatMap((t) => (t.prep === null ? [] : [t.prep]))),
      },
      stations: [...byStation.entries()]
        .map(([id, a]) => ({ id, name: a.name, ...summary(a.totals), averageWait: avg(a.waits), averagePrep: avg(a.preps) }))
        .sort((x, y) => (y.average ?? 0) - (x.average ?? 0)),
      dishes: [...byDish.values()]
        .map((a) => {
          const own = a.productId ? productById.get(a.productId)?.prepTimeMinutes ?? null : null;
          const st = stats(a.totals);
          return {
            productId: a.productId,
            name: a.name,
            units: a.units,
            ...st,
            targetMinutes: own ?? target,
            ownTarget: own !== null,
            latePct: latePercent(a.totals, own ?? target),
          };
        })
        .sort((x, y) => (y.average ?? 0) - (x.average ?? 0))
        .slice(0, 40),
      hours: [...byHour.entries()]
        .sort((a, b) => ((a[0] - 4 + 24) % 24) - ((b[0] - 4 + 24) % 24))
        .map(([hour, list]) => ({ hour, count: list.length, average: avg(list), latePct: latePercent(list, target) })),
      weekdays: [...byWeekday.entries()]
        .filter(([w]) => w >= 0)
        .sort((a, b) => a[0] - b[0])
        .map(([weekday, list]) => ({ weekday, count: list.length, average: avg(list), latePct: latePercent(list, target) })),
      slowest: [...timed]
        .sort((a, b) => b.total - a.total)
        .slice(0, 15)
        .map((t) => ({
          ticketId: t.id,
          orderNumber: t.order.number,
          fulfillmentType: t.order.fulfillmentType,
          station: t.station.name,
          createdAt: t.createdAt,
          minutes: Math.round(t.total * 10) / 10,
          wait: t.wait === null ? null : Math.round(t.wait * 10) / 10,
          items: t.items.map((i) => `${i.quantity}× ${i.nameSnapshot}`).join(', '),
        })),
    };
  }
}
