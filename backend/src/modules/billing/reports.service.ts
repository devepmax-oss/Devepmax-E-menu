import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { signPayload, verifyPayload } from '../../common/pay-token';
import { buildXlsx, Cell, Sheet } from '../../common/xlsx';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { businessDateFor } from '../orders/order.rules';
import { SettingsService } from '../settings/settings.service';
import { CashService } from './cash.service';

type D = Prisma.Decimal;
const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const ZERO = dec(0);
const sum = (values: D[]) => values.reduce((a, b) => a.plus(b), ZERO);
const money = (v: D) => v.toDecimalPlaces(2);

/** Suma por clave (cantidad, monto…), conservando el orden de mayor a menor. */
class Tally<T extends Record<string, number | D>> {
  private readonly rows = new Map<string, T>();
  constructor(private readonly empty: () => T) {}

  add(key: string, values: Partial<T>) {
    const row = this.rows.get(key) ?? this.empty();
    for (const [k, v] of Object.entries(values) as [keyof T, number | D][]) {
      const current = row[k];
      row[k] = (typeof current === 'number' ? current + (v as number) : (current as D).plus(v as D)) as T[keyof T];
    }
    this.rows.set(key, row);
  }

  list(by: keyof T) {
    return [...this.rows.entries()]
      .map(([key, v]) => ({ key, ...v }))
      .sort((a, b) => {
        const x = a[by] as number | D, y = b[by] as number | D;
        return typeof x === 'number' ? (y as number) - x : (y as D).comparedTo(x as D);
      });
  }
}

const DAY_MS = 86_400_000;
const MAX_DAYS = 400;
const iso = (d: Date) => d.toISOString().slice(0, 10);

/** Formato YYYY-MM-DD → fecha de operación (columna @db.Date). Sin fecha: hoy. */
function parseDay(day: string | undefined, timezone: string): Date {
  if (!day) return businessDateFor(new Date(), timezone);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new BadRequestException('Fecha inválida (usa AAAA-MM-DD)');
  const date = new Date(`${day}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || iso(date) !== day) throw new BadRequestException('Fecha inválida');
  return date;
}

/**
 * Reportes de ventas de un día o de un período: ventas, impuestos, propinas, formas de pago,
 * productos, canales, horas, días, quién cobró y quién atendió, descuentos, reembolsos,
 * cancelaciones y turnos de caja, con la comparación contra el período anterior.
 * Todo sale de las órdenes de los días de operación (cada uno termina a las 4 a. m.).
 * Un solo día es el cierre del día (reporte Z).
 */
@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly cash: CashService,
  ) {}

  private readonly env = loadEnv();

  /** Un día (cierre del día). */
  day(date?: string) {
    return this.range(date, date);
  }

  /** Del día [from] al día [to], ambos incluidos. Sin fechas: hoy. */
  async range(fromParam?: string, toParam?: string) {
    const settings = await this.settings.get();
    const tz = settings.timezone;
    const from = parseDay(fromParam ?? toParam, tz);
    const to = parseDay(toParam ?? fromParam, tz);
    if (to < from) throw new BadRequestException('La fecha final es anterior a la inicial');
    const days = Math.round((to.getTime() - from.getTime()) / DAY_MS) + 1;
    if (days > MAX_DAYS) throw new BadRequestException(`El período puede tener hasta ${MAX_DAYS} días`);
    const current = await this.compute(from, to, tz);
    // Mismo largo justo antes, para comparar.
    const prevTo = new Date(from.getTime() - DAY_MS);
    const prevFrom = new Date(prevTo.getTime() - (days - 1) * DAY_MS);
    const previous = await this.compute(prevFrom, prevTo, tz, true);
    return {
      ...current,
      from: iso(from),
      to: iso(to),
      date: iso(from),
      days,
      currency: settings.currency,
      restaurant: settings.name,
      timezone: tz,
      generatedAt: new Date().toISOString(),
      previous: { from: iso(prevFrom), to: iso(prevTo), summary: previous.summary },
    };
  }

  private async compute(from: Date, to: Date, tz: string, summaryOnly = false) {
    const orders = await this.prisma.order.findMany({
      where: { businessDate: { gte: from, lte: to }, status: { not: 'PENDING_PAYMENT' } },
      include: {
        items: { include: { discounts: true } },
        tableSession: { select: { id: true, waiterId: true, guestCount: true } },
      },
      orderBy: { createdAt: 'asc' },
    });
    const live = orders.filter((o) => o.status !== 'CANCELLED');
    const cancelled = orders.filter((o) => o.status === 'CANCELLED');
    const billIds = [...new Set(live.map((o) => o.billId))];
    const bills = await this.prisma.bill.findMany({
      where: { id: { in: billIds }, status: { not: 'VOID' } },
      include: {
        payments: { where: { status: 'SUCCEEDED' }, include: { refunds: true } },
        discounts: { include: { promotion: { select: { name: true } } } },
        orders: { select: { createdById: true, createdAt: true }, orderBy: { createdAt: 'asc' }, take: 1 },
        tableSession: { select: { waiterId: true } },
      },
    });

    // Productos → categoría (las líneas guardan el nombre; la categoría se busca aparte).
    const productIds = [...new Set(live.flatMap((o) => o.items.map((i) => i.productId)).filter((id): id is string => !!id))];
    const products = productIds.length
      ? await this.prisma.product.findMany({ where: { id: { in: productIds } }, select: { id: true, category: { select: { name: true } } } })
      : [];
    const categoryOf = new Map(products.map((p) => [p.id, p.category?.name ?? 'Sin categoría']));

    // Totales de las cuentas.
    const subtotal = sum(bills.map((b) => b.subtotal));
    const discountTotal = sum(bills.map((b) => b.discountTotal));
    const taxTotal = sum(bills.map((b) => b.taxTotal));
    const tipTotal = sum(bills.map((b) => b.tipTotal));
    const deliveryFees = sum(bills.map((b) => b.deliveryFee));
    const total = sum(bills.map((b) => b.total));
    const payments = bills.flatMap((b) => b.payments);
    const refunds = payments.flatMap((p) => p.refunds.map((r) => ({ ...r, method: p.method, billId: p.billId })));
    const collected = sum(payments.map((p) => p.amount));
    const refunded = sum(refunds.map((r) => r.amount));
    const openBills = bills.filter((b) => b.status === 'UNPAID' || b.status === 'PARTIALLY_PAID');
    const pending = sum(openBills.map((b) => Prisma.Decimal.max(b.total.minus(b.amountPaid), 0)));
    const paidBills = bills.filter((b) => b.status === 'PAID' || b.status === 'REFUNDED').length;
    const netSales = subtotal.minus(discountTotal);
    const sessions = new Map(live.filter((o) => o.tableSession).map((o) => [o.tableSession!.id, o.tableSession!.guestCount ?? 0]));
    const guests = [...sessions.values()].reduce((a, b) => a + b, 0);

    // Formas de pago.
    const byMethod = new Tally(() => ({ count: 0, amount: ZERO, tips: ZERO, refunded: ZERO }));
    for (const p of payments) byMethod.add(p.method, { count: 1, amount: p.amount, tips: p.tipAmount });
    for (const r of refunds) byMethod.add(r.method, { refunded: r.amount });

    // Lo vendido: productos, categorías, canales, tipo de pedido y horas.
    const itemNet = (i: (typeof live)[number]['items'][number]) => i.lineTotal.minus(sum(i.discounts.map((d) => d.amount)));
    const byProduct = new Tally(() => ({ quantity: 0, gross: ZERO, net: ZERO }));
    const byCategory = new Tally(() => ({ quantity: 0, net: ZERO }));
    const byChannel = new Tally(() => ({ orders: 0, net: ZERO }));
    const byFulfillment = new Tally(() => ({ orders: 0, net: ZERO }));
    const byHour = new Tally(() => ({ orders: 0, net: ZERO }));
    const hourOf = new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: tz });
    for (const o of live) {
      const active = o.items.filter((i) => i.status === 'ACTIVE');
      const net = sum(active.map(itemNet));
      byChannel.add(o.channel, { orders: 1, net });
      byFulfillment.add(o.fulfillmentType, { orders: 1, net });
      byHour.add(hourOf.format(o.createdAt).padStart(2, '0'), { orders: 1, net });
      for (const i of active) {
        byProduct.add(i.nameSnapshot, { quantity: i.quantity, gross: i.lineTotal, net: itemNet(i) });
        byCategory.add(i.productId ? categoryOf.get(i.productId) ?? 'Sin categoría' : 'Sin categoría', { quantity: i.quantity, net: itemNet(i) });
      }
    }

    // Personas: quién cobró y quién atendió (mesero de la mesa o quien tomó el pedido).
    const cashiers = new Tally(() => ({ payments: 0, amount: ZERO, tips: ZERO }));
    for (const p of payments) cashiers.add(p.employeeId ?? 'online', { payments: 1, amount: p.amount, tips: p.tipAmount });
    const servers = new Tally(() => ({ bills: 0, net: ZERO, tips: ZERO }));
    for (const b of bills) {
      const who = b.tableSession?.waiterId ?? b.orders[0]?.createdById ?? 'online';
      servers.add(who, { bills: 1, net: b.subtotal.minus(b.discountTotal), tips: b.tipTotal });
    }

    // Descuentos manuales (con quién y quién autorizó) y promociones.
    const manual = bills.flatMap((b) => b.discounts.filter((d) => d.appliedById).map((d) => ({ ...d, billId: b.id })));
    const promos = new Tally(() => ({ count: 0, amount: ZERO }));
    for (const b of bills) for (const d of b.discounts.filter((x) => !x.appliedById)) promos.add(d.promotion?.name ?? d.reason, { count: 1, amount: d.amount });

    // Turnos de caja de esos días de operación.
    const near = summaryOnly
      ? []
      : await this.prisma.cashShift.findMany({
          where: { openedAt: { gte: new Date(from.getTime() - DAY_MS), lt: new Date(to.getTime() + 2 * DAY_MS) } },
          orderBy: { openedAt: 'asc' },
        });
    const shifts = await Promise.all(
      near
        .filter((sh) => {
          const d = businessDateFor(sh.openedAt, tz).getTime();
          return d >= from.getTime() && d <= to.getTime();
        })
        .map((sh) => this.cash.summary(sh)),
    );

    // Por día (gráfica de ventas) y por día de la semana.
    const dayOfBill = new Map(live.map((o) => [o.billId, iso(o.businessDate)] as const));
    const byDay = new Tally(() => ({ orders: 0, net: ZERO, collected: ZERO, tips: ZERO }));
    for (let t = from.getTime(); t <= to.getTime(); t += DAY_MS) byDay.add(iso(new Date(t)), {});
    for (const o of live) {
      const net = sum(o.items.filter((i) => i.status === 'ACTIVE').map(itemNet));
      byDay.add(iso(o.businessDate), { orders: 1, net });
    }
    for (const b of bills) {
      const key = dayOfBill.get(b.id);
      if (key) byDay.add(key, { collected: sum(b.payments.map((p) => p.amount)), tips: b.tipTotal });
    }
    const byWeekday = new Tally(() => ({ orders: 0, net: ZERO }));
    for (const o of live) {
      const net = sum(o.items.filter((i) => i.status === 'ACTIVE').map(itemNet));
      byWeekday.add(String((o.businessDate.getUTCDay() + 6) % 7), { orders: 1, net }); // 0 = lunes
    }

    // Nombres de las personas.
    const ids = new Set<string>();
    for (const row of [...cashiers.list('amount'), ...servers.list('net')]) if (row.key !== 'online') ids.add(row.key);
    for (const d of manual) {
      if (d.appliedById) ids.add(d.appliedById);
      if (d.authorizedById) ids.add(d.authorizedById);
    }
    for (const r of refunds) ids.add(r.employeeId);
    for (const o of cancelled) if (o.cancelledById) ids.add(o.cancelledById);
    const people = ids.size ? await this.prisma.employee.findMany({ where: { id: { in: [...ids] } }, select: { id: true, name: true } }) : [];
    const name = (id: string | null | undefined) => (id === 'online' ? 'En línea' : (people.find((p) => p.id === id)?.name ?? '—'));

    const labelOf = new Map(
      orders.map((o) => [o.billId, `#${o.number}${o.customerName ? ` · ${o.customerName}` : ''}`] as const),
    );

    return {
      firstOrderAt: live[0]?.createdAt ?? null,
      lastOrderAt: live.at(-1)?.createdAt ?? null,
      summary: {
        orders: live.length,
        cancelledOrders: cancelled.length,
        guests,
        bills: bills.length,
        paidBills,
        openBills: openBills.length,
        grossSales: money(subtotal),
        discounts: money(discountTotal),
        netSales: money(netSales),
        tax: money(taxTotal),
        tips: money(tipTotal),
        deliveryFees: money(deliveryFees),
        total: money(total),
        collected: money(collected),
        refunded: money(refunded),
        netCollected: money(collected.minus(refunded)),
        pending: money(pending),
        averageCheck: paidBills ? money(netSales.div(paidBills)) : ZERO,
      },
      payments: byMethod.list('amount').map((r) => ({ method: r.key, count: r.count, amount: money(r.amount), tips: money(r.tips), refunded: money(r.refunded) })),
      channels: byChannel.list('net').map((r) => ({ channel: r.key, orders: r.orders, net: money(r.net) })),
      fulfillment: byFulfillment.list('net').map((r) => ({ type: r.key, orders: r.orders, net: money(r.net) })),
      hours: byHour
        .list('orders')
        .map((r) => ({ hour: Number(r.key), orders: r.orders, net: money(r.net) }))
        .sort((a, b) => a.hour - b.hour),
      products: byProduct.list('quantity').map((r) => ({ name: r.key, quantity: r.quantity, gross: money(r.gross), net: money(r.net) })),
      categories: byCategory.list('net').map((r) => ({ name: r.key, quantity: r.quantity, net: money(r.net) })),
      cashiers: cashiers.list('amount').map((r) => ({ id: r.key, name: name(r.key), payments: r.payments, amount: money(r.amount), tips: money(r.tips) })),
      servers: servers.list('net').map((r) => ({ id: r.key, name: name(r.key), bills: r.bills, net: money(r.net), tips: money(r.tips) })),
      promotions: promos.list('amount').map((r) => ({ name: r.key, count: r.count, amount: money(r.amount) })),
      discounts: manual.map((d) => ({
        id: d.id,
        bill: labelOf.get(d.billId) ?? '',
        reason: d.reason,
        amount: money(d.amount),
        appliedBy: name(d.appliedById),
        authorizedBy: d.authorizedById ? name(d.authorizedById) : null,
        createdAt: d.createdAt,
      })),
      refunds: refunds.map((r) => ({
        id: r.id,
        bill: labelOf.get(r.billId) ?? '',
        method: r.method,
        amount: money(r.amount),
        reason: r.reason,
        employee: name(r.employeeId),
        createdAt: r.createdAt,
      })),
      cancellations: cancelled.map((o) => ({
        id: o.id,
        number: o.number,
        reason: o.cancelReason,
        by: o.cancelledById ? name(o.cancelledById) : null,
        amount: money(sum(o.items.map((i) => i.lineTotal))),
        cancelledAt: o.cancelledAt,
      })),
      shifts,
      byDay: byDay
        .list('orders')
        .map((r) => ({ date: r.key, orders: r.orders, net: money(r.net), collected: money(r.collected), tips: money(r.tips) }))
        .sort((a, b) => a.date.localeCompare(b.date)),
      byWeekday: byWeekday
        .list('orders')
        .map((r) => ({ weekday: Number(r.key), orders: r.orders, net: money(r.net) }))
        .sort((a, b) => a.weekday - b.weekday),
    };
  }

  // ───────── Exportar a Excel ─────────

  /** Enlace de descarga válido 10 minutos (el navegador no puede mandar el token de sesión). */
  async exportLink(from?: string, to?: string) {
    const tz = (await this.settings.get()).timezone;
    const f = parseDay(from ?? to, tz);
    const t = parseDay(to ?? from, tz);
    const expires = Date.now() + 10 * 60_000;
    const token = signPayload('report-export:v1', `${iso(f)}|${iso(t)}|${expires}`, this.env.jwtAccessSecret);
    return { url: `${this.env.publicApiUrl}/reports/export/${token}`, expiresAt: new Date(expires).toISOString() };
  }

  async exportFromToken(token: string) {
    const payload = verifyPayload('report-export:v1', token, this.env.jwtAccessSecret);
    const [from, to, expires] = payload?.split('|') ?? [];
    if (!from || !to || !(Number(expires) > Date.now())) throw new UnauthorizedException('El enlace venció: vuelve a exportar desde la app');
    const report = await this.range(from, to);
    const name = report.from === report.to ? `ventas-${report.from}.xlsx` : `ventas-${report.from}-a-${report.to}.xlsx`;
    return { name, buffer: this.toXlsx(report) };
  }

  private toXlsx(r: Awaited<ReturnType<ReportsService['range']>>): Buffer {
    const n = (v: D) => ({ money: v.toNumber() });
    const s = r.summary;
    const p = r.previous.summary;
    const change = (a: D, b: D): Cell => (b.isZero() ? '' : { percent: a.minus(b).div(b).toNumber() });
    const METHOD: Record<string, string> = { CASH: 'Efectivo', CARD_TERMINAL: 'Tarjeta', CARD_ONLINE: 'Tarjeta en línea', CARD_QR: 'QR en la mesa', OTHER: 'Otro' };
    const CHANNEL: Record<string, string> = { TABLET: 'Tablet de mesa', POS: 'Caja', WAITER: 'Mesero', ONLINE: 'Web' };
    const TYPE: Record<string, string> = { DINE_IN: 'Comer aquí', TAKEOUT: 'Para llevar', PICKUP: 'Recoger', DELIVERY: 'Delivery' };
    const WEEKDAY = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    const when = (d: Date | string | null) => (d ? new Date(d).toLocaleString('es-US', { timeZone: r.timezone }) : '');

    const sheets: Sheet[] = [
      {
        name: 'Resumen',
        widths: [30, 16, 16, 12],
        rows: [
          ['Concepto', `${r.from} a ${r.to}`, `${r.previous.from} a ${r.previous.to}`, 'Cambio'],
          ['Órdenes', s.orders, p.orders, s.orders && p.orders ? { percent: (s.orders - p.orders) / p.orders } : ''],
          ['Órdenes canceladas', s.cancelledOrders, p.cancelledOrders],
          ['Clientes en mesa', s.guests, p.guests],
          ['Ventas brutas', n(s.grossSales), n(p.grossSales), change(s.grossSales, p.grossSales)],
          ['Descuentos y promociones', n(s.discounts), n(p.discounts), change(s.discounts, p.discounts)],
          ['Ventas netas', n(s.netSales), n(p.netSales), change(s.netSales, p.netSales)],
          ['Impuestos', n(s.tax), n(p.tax), change(s.tax, p.tax)],
          ['Propinas', n(s.tips), n(p.tips), change(s.tips, p.tips)],
          ['Envíos', n(s.deliveryFees), n(p.deliveryFees)],
          ['Total de las cuentas', n(s.total), n(p.total), change(s.total, p.total)],
          ['Cobrado', n(s.collected), n(p.collected), change(s.collected, p.collected)],
          ['Reembolsos', n(s.refunded), n(p.refunded)],
          ['Neto cobrado', n(s.netCollected), n(p.netCollected), change(s.netCollected, p.netCollected)],
          ['Por cobrar', n(s.pending), n(p.pending)],
          ['Ticket promedio', n(s.averageCheck), n(p.averageCheck), change(s.averageCheck, p.averageCheck)],
          [],
          ['Restaurante', r.restaurant],
          ['Generado', when(r.generatedAt)],
          ['Nota', 'Cada día de operación termina a las 4:00 a. m.'],
        ],
      },
      {
        name: 'Por día',
        widths: [14, 12, 10, 16, 16, 14],
        rows: [
          ['Fecha', 'Día', 'Órdenes', 'Ventas netas', 'Cobrado', 'Propinas'],
          ...r.byDay.map((d) => [d.date, WEEKDAY[(new Date(`${d.date}T00:00:00Z`).getUTCDay() + 6) % 7], d.orders, n(d.net), n(d.collected), n(d.tips)]),
        ],
      },
      {
        name: 'Formas de pago',
        widths: [20, 10, 16, 14, 14],
        rows: [['Forma de pago', 'Cobros', 'Monto', 'Propinas', 'Reembolsado'], ...r.payments.map((x) => [METHOD[x.method] ?? x.method, x.count, n(x.amount), n(x.tips), n(x.refunded)])],
      },
      {
        name: 'Productos',
        widths: [34, 10, 16, 16],
        rows: [['Producto', 'Cantidad', 'Venta bruta', 'Venta neta'], ...r.products.map((x) => [x.name, x.quantity, n(x.gross), n(x.net)])],
      },
      {
        name: 'Categorías',
        widths: [28, 10, 16],
        rows: [['Categoría', 'Cantidad', 'Venta neta'], ...r.categories.map((x) => [x.name, x.quantity, n(x.net)])],
      },
      {
        name: 'Canales',
        widths: [22, 10, 16],
        rows: [
          ['Canal', 'Órdenes', 'Venta neta'],
          ...r.channels.map((x) => [CHANNEL[x.channel] ?? x.channel, x.orders, n(x.net)]),
          [],
          ['Tipo de pedido', 'Órdenes', 'Venta neta'],
          ...r.fulfillment.map((x) => [TYPE[x.type] ?? x.type, x.orders, n(x.net)]),
        ],
      },
      {
        name: 'Horas y días',
        widths: [14, 10, 16],
        rows: [
          ['Hora', 'Órdenes', 'Venta neta'],
          ...r.hours.map((h) => [`${String(h.hour).padStart(2, '0')}:00`, h.orders, n(h.net)]),
          [],
          ['Día de la semana', 'Órdenes', 'Venta neta'],
          ...r.byWeekday.map((w) => [WEEKDAY[w.weekday], w.orders, n(w.net)]),
        ],
      },
      {
        name: 'Personal',
        widths: [26, 12, 16, 14],
        rows: [
          ['Quién atendió', 'Cuentas', 'Venta neta', 'Propinas'],
          ...r.servers.map((x) => [x.name, x.bills, n(x.net), n(x.tips)]),
          [],
          ['Quién cobró', 'Cobros', 'Monto', 'Propinas'],
          ...r.cashiers.map((x) => [x.name, x.payments, n(x.amount), n(x.tips)]),
        ],
      },
      {
        name: 'Descuentos',
        widths: [22, 30, 14, 20, 20, 22],
        rows: [
          ['Cuenta', 'Motivo', 'Monto', 'Aplicó', 'Autorizó', 'Fecha'],
          ...r.discounts.map((x) => [x.bill, x.reason, n(x.amount), x.appliedBy, x.authorizedBy ?? '', when(x.createdAt)]),
          [],
          ['Promoción', 'Veces', 'Monto'],
          ...r.promotions.map((x) => [x.name, x.count, n(x.amount)]),
        ],
      },
      {
        name: 'Reembolsos',
        widths: [22, 18, 14, 30, 20, 22],
        rows: [['Cuenta', 'Forma de pago', 'Monto', 'Motivo', 'Hizo', 'Fecha'], ...r.refunds.map((x) => [x.bill, METHOD[x.method] ?? x.method, n(x.amount), x.reason, x.employee, when(x.createdAt)])],
      },
      {
        name: 'Cancelaciones',
        widths: [10, 34, 20, 14, 22],
        rows: [['Orden', 'Motivo', 'Canceló', 'Monto', 'Fecha'], ...r.cancellations.map((x) => [`#${x.number}`, x.reason ?? '', x.by ?? '', n(x.amount), when(x.cancelledAt)])],
      },
      {
        name: 'Caja',
        widths: [20, 22, 22, 14, 16, 14, 14],
        rows: [
          ['Abrió', 'Apertura', 'Cierre', 'Fondo', 'Efectivo esperado', 'Contado', 'Diferencia'],
          ...r.shifts.map((x) => [
            x.openedBy ?? '',
            when(x.openedAt),
            when(x.closedAt),
            n(x.openingCash),
            n(x.expectedCash),
            x.countedCash === null ? '' : n(x.countedCash),
            x.difference === null ? '' : n(x.difference),
          ]),
        ],
      },
    ];
    return buildXlsx(sheets);
  }
}
