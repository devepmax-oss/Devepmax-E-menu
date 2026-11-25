import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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

/** Formato YYYY-MM-DD → fecha de operación (columna @db.Date). */
function parseDay(day: string | undefined, timezone: string): Date {
  if (!day) return businessDateFor(new Date(), timezone);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new BadRequestException('Fecha inválida (usa AAAA-MM-DD)');
  const date = new Date(`${day}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime())) throw new BadRequestException('Fecha inválida');
  return date;
}

/**
 * Cierre del día (reporte Z): ventas, impuestos, propinas, formas de pago, productos, canales,
 * horas, quién cobró y quién atendió, descuentos, reembolsos, cancelaciones y turnos de caja.
 * Todo sale de las órdenes del día de operación (que termina a las 4 a. m.).
 */
@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly cash: CashService,
  ) {}

  async day(dayParam?: string) {
    const settings = await this.settings.get();
    const tz = settings.timezone;
    const date = parseDay(dayParam, tz);

    const orders = await this.prisma.order.findMany({
      where: { businessDate: date, status: { not: 'PENDING_PAYMENT' } },
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

    // Turnos de caja de ese día de operación.
    const near = await this.prisma.cashShift.findMany({
      where: { openedAt: { gte: new Date(date.getTime() - 86_400_000), lt: new Date(date.getTime() + 2 * 86_400_000) } },
      orderBy: { openedAt: 'asc' },
    });
    const shifts = await Promise.all(
      near.filter((s) => businessDateFor(s.openedAt, tz).getTime() === date.getTime()).map((s) => this.cash.summary(s)),
    );

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
      date: date.toISOString().slice(0, 10),
      timezone: tz,
      currency: settings.currency,
      restaurant: settings.name,
      generatedAt: new Date().toISOString(),
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
    };
  }
}
