import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { plateCost } from '../inventory/inventory.rules';
import { BUSINESS_DAY_CUTOFF_HOUR, businessDateFor } from '../orders/order.rules';
import { SettingsService } from '../settings/settings.service';
import { zonedToUtc } from '../timeclock/timeclock.rules';
import { classify, parsePeriod, percent, round, unitMargin, type MenuClass } from './menu.rules';

const n = (v: Prisma.Decimal | number | null | undefined) => (v == null ? 0 : Number(v));
const DAY = 86_400_000;
const iso = (d: Date) => d.toISOString().slice(0, 10);
const NOT_SOLD = ['PENDING_PAYMENT', 'CANCELLED', 'SCHEDULED'] as const;

type Disc = { amount: Prisma.Decimal; promotionId: string | null; couponId: string | null; appliedById: string | null };

/**
 * Análisis del menú y de las promociones de un período: qué platos venden y cuánto dejan
 * (con el costo real del inventario o el de su receta), su cuadrante de ingeniería de menú,
 * los que no se vendieron, y cuánto costaron las promociones, cupones y descuentos manuales.
 */
@Injectable()
export class MenuInsightsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
  ) {}

  async menu(fromParam?: string, toParam?: string) {
    const s = await this.settings.get();
    const tz = s.timezone;
    let period: ReturnType<typeof parsePeriod>;
    try {
      period = parsePeriod(fromParam, toParam, iso(businessDateFor(new Date(), tz)));
    } catch (e) {
      throw new BadRequestException((e as Error).message);
    }
    const { from, to, days } = period;
    const cutoff = `${String(BUSINESS_DAY_CUTOFF_HOUR).padStart(2, '0')}:00`;
    const start = zonedToUtc(iso(from), cutoff, tz);
    const end = zonedToUtc(iso(new Date(to.getTime() + DAY)), cutoff, tz);

    const discountSelect = { select: { amount: true, promotionId: true, couponId: true, appliedById: true } } as const;
    const [orders, products, promotions] = await Promise.all([
      this.prisma.order.findMany({
        where: { businessDate: { gte: from, lte: to }, status: { notIn: [...NOT_SOLD] } },
        select: {
          id: true,
          billId: true,
          items: {
            where: { status: 'ACTIVE' },
            select: { id: true, productId: true, nameSnapshot: true, quantity: true, lineTotal: true, discounts: discountSelect },
          },
        },
      }),
      this.prisma.product.findMany({
        select: {
          id: true,
          name: true,
          price: true,
          isActive: true,
          isAvailable: true,
          createdAt: true,
          category: { select: { name: true, isActive: true } },
          recipe: { select: { quantity: true, item: { select: { costPerUnit: true } } } },
        },
      }),
      this.prisma.promotion.findMany({ select: { id: true, name: true, type: true, isActive: true, requiresCoupon: true, startsAt: true, endsAt: true } }),
    ]);

    const itemIds = new Set(orders.flatMap((o) => o.items.map((i) => i.id)));
    const billIds = new Set(orders.map((o) => o.billId));
    // Lo que el inventario descontó por cada plato vendido (incluye devoluciones si se anuló algo).
    // Se busca por fecha con margen (pedidos programados) y luego se filtra por los platos del período.
    const [movements, billDiscounts, redemptions] = await Promise.all([
      this.prisma.stockMovement.findMany({
        where: { type: 'SALE', orderItemId: { not: null }, createdAt: { gte: new Date(start.getTime() - 8 * DAY), lt: new Date(end.getTime() + DAY) } },
        select: { orderItemId: true, quantity: true, unitCost: true },
      }),
      this.prisma.discount.findMany({
        where: { orderItemId: null, createdAt: { gte: new Date(start.getTime() - 8 * DAY), lt: new Date(end.getTime() + DAY) } },
        select: { billId: true, amount: true, promotionId: true, couponId: true, appliedById: true },
      }),
      this.prisma.couponRedemption.findMany({
        where: { order: { businessDate: { gte: from, lte: to }, status: { notIn: [...NOT_SOLD] } } },
        select: { orderId: true, amount: true, customerId: true, customerPhone: true, coupon: { select: { id: true, code: true, name: true, type: true, isActive: true } } },
      }),
    ]);

    const costByItem = new Map<string, number>();
    for (const m of movements) {
      if (!m.orderItemId || !itemIds.has(m.orderItemId)) continue;
      costByItem.set(m.orderItemId, (costByItem.get(m.orderItemId) ?? 0) - n(m.quantity) * n(m.unitCost));
    }
    const productById = new Map(products.map((p) => [p.id, p]));
    const recipeCost = new Map<string, number>();
    for (const p of products) {
      if (p.recipe.length) recipeCost.set(p.id, n(plateCost(p.price, p.recipe.map((l) => ({ quantity: l.quantity, costPerUnit: l.item.costPerUnit }))).cost));
    }

    // ── Platos ──
    type Agg = { id: string; name: string; quantity: number; gross: number; net: number; actualCost: number; recipeCost: number; actualUnits: number; recipeUnits: number; unknownUnits: number };
    const byProduct = new Map<string, Agg>();
    const itemNet = (i: { lineTotal: Prisma.Decimal; discounts: Disc[] }) => n(i.lineTotal) - i.discounts.reduce((a, d) => a + n(d.amount), 0);
    const orderNet = new Map<string, number>();
    for (const o of orders) {
      let total = 0;
      for (const i of o.items) {
        const net = itemNet(i);
        total += net;
        const key = i.productId ?? `name:${i.nameSnapshot}`;
        const a = byProduct.get(key) ?? { id: key, name: productById.get(i.productId ?? '')?.name ?? i.nameSnapshot, quantity: 0, gross: 0, net: 0, actualCost: 0, recipeCost: 0, actualUnits: 0, recipeUnits: 0, unknownUnits: 0 };
        a.quantity += i.quantity;
        a.gross += n(i.lineTotal);
        a.net += net;
        const real = costByItem.get(i.id);
        const plate = i.productId ? recipeCost.get(i.productId) : undefined;
        if (real !== undefined) {
          a.actualCost += real;
          a.actualUnits += i.quantity;
        } else if (plate !== undefined) {
          a.recipeCost += plate * i.quantity;
          a.recipeUnits += i.quantity;
        } else a.unknownUnits += i.quantity;
        byProduct.set(key, a);
      }
      orderNet.set(o.id, total);
    }
    // Un plato con algunas unidades sin costo conocido se estima con el promedio de las que sí.
    const costOf = (a: Agg) => {
      const knownUnits = a.actualUnits + a.recipeUnits;
      if (!knownUnits) return null;
      const known = a.actualCost + a.recipeCost;
      return known + (known / knownUnits) * a.unknownUnits;
    };
    const unsold = products.filter((p) => p.isActive && p.category.isActive && !byProduct.has(p.id));
    const inputs = [
      ...[...byProduct.values()].map((a) => ({ id: a.id, quantity: a.quantity, net: a.net, cost: costOf(a) })),
      ...unsold.map((p) => {
        const c = recipeCost.get(p.id);
        return { id: p.id, quantity: 0, net: 0, cost: c === undefined ? null : 0, listUnitMargin: c === undefined ? null : n(p.price) - c };
      }),
    ];
    const { popularityLine, marginLine, classes } = classify(inputs);
    const totalQty = [...byProduct.values()].reduce((a, x) => a + x.quantity, 0);
    const dishes = [...byProduct.values()]
      .map((a) => {
        const p = productById.get(a.id);
        const cost = costOf(a);
        const margin = cost === null ? null : a.net - cost;
        return {
          productId: p?.id ?? null,
          name: a.name,
          category: p?.category.name ?? null,
          price: p ? n(p.price) : null,
          active: p ? p.isActive : false,
          quantity: a.quantity,
          mix: percent(a.quantity, totalQty),
          gross: round(a.gross),
          net: round(a.net),
          cost: cost === null ? null : round(cost),
          margin: margin === null ? null : round(margin),
          unitMargin: (() => {
            const m = unitMargin({ id: a.id, quantity: a.quantity, net: a.net, cost });
            return m === null ? null : round(m);
          })(),
          foodCostPct: cost === null ? null : percent(cost, a.net),
          costSource: a.actualUnits && !a.recipeUnits ? 'inventory' : a.recipeUnits && !a.actualUnits ? 'recipe' : a.actualUnits ? 'mixed' : null,
          class: (classes.get(a.id) ?? null) as MenuClass | null,
        };
      })
      .sort((x, y) => (y.margin ?? -Infinity) - (x.margin ?? -Infinity) || y.net - x.net);

    const known = dishes.filter((d) => d.cost !== null);
    const knownNet = known.reduce((a, d) => a + d.net, 0);
    const knownCost = known.reduce((a, d) => a + (d.cost ?? 0), 0);
    const count = (c: MenuClass) => dishes.filter((d) => d.class === c).length + unsold.filter((p) => classes.get(p.id) === c).length;

    // ── Promociones, cupones y descuentos ──
    const periodBillDiscounts = billDiscounts.filter((d) => billIds.has(d.billId));
    type PromoAgg = { orders: Set<string>; units: number; discount: number };
    const promoAgg = new Map<string, PromoAgg>();
    let manualCount = 0;
    let manualAmount = 0;
    let itemDiscountTotal = 0;
    for (const o of orders) {
      for (const i of o.items) {
        for (const d of i.discounts) {
          itemDiscountTotal += n(d.amount);
          if (d.promotionId) {
            const a = promoAgg.get(d.promotionId) ?? { orders: new Set(), units: 0, discount: 0 };
            a.orders.add(o.id);
            a.units += i.quantity;
            a.discount += n(d.amount);
            promoAgg.set(d.promotionId, a);
          } else if (!d.couponId && d.appliedById) {
            manualCount += 1;
            manualAmount += n(d.amount);
          }
        }
      }
    }
    const ordersOfBill = new Map<string, string[]>();
    for (const o of orders) ordersOfBill.set(o.billId, [...(ordersOfBill.get(o.billId) ?? []), o.id]);
    for (const d of periodBillDiscounts) {
      if (d.promotionId) {
        const a = promoAgg.get(d.promotionId) ?? { orders: new Set(), units: 0, discount: 0 };
        for (const id of ordersOfBill.get(d.billId) ?? []) a.orders.add(id);
        a.discount += n(d.amount);
        promoAgg.set(d.promotionId, a);
      } else if (!d.couponId && d.appliedById) {
        manualCount += 1;
        manualAmount += n(d.amount);
      }
    }

    const totalNet = [...orderNet.values()].reduce((a, v) => a + v, 0);
    const totalGross = [...byProduct.values()].reduce((a, x) => a + x.gross, 0);
    const avgOrder = orders.length ? totalNet / orders.length : 0;
    const salesOf = (ids: Iterable<string>) => [...ids].reduce((a, id) => a + (orderNet.get(id) ?? 0), 0);

    const promoRows = promotions
      .filter((p) => promoAgg.has(p.id) || p.isActive)
      .map((p) => {
        const a = promoAgg.get(p.id);
        const ordersWith = a?.orders.size ?? 0;
        const sales = a ? salesOf(a.orders) : 0;
        return {
          id: p.id,
          name: p.name,
          type: p.type,
          active: p.isActive,
          byCoupon: p.requiresCoupon,
          orders: ordersWith,
          units: a?.units ?? 0,
          discount: round(a?.discount ?? 0),
          sales: round(sales),
          averageOrder: ordersWith ? round(sales / ordersWith) : null,
          discountPct: percent(a?.discount ?? 0, sales + (a?.discount ?? 0)),
        };
      })
      .sort((x, y) => y.discount - x.discount || y.orders - x.orders);

    type CouponAgg = { code: string; name: string; type: string; active: boolean; orders: Set<string>; customers: Set<string>; amount: number };
    const couponAgg = new Map<string, CouponAgg>();
    for (const r of redemptions) {
      const a = couponAgg.get(r.coupon.id) ?? { code: r.coupon.code, name: r.coupon.name, type: r.coupon.type, active: r.coupon.isActive, orders: new Set(), customers: new Set(), amount: 0 };
      a.orders.add(r.orderId);
      const who = r.customerId ?? r.customerPhone;
      if (who) a.customers.add(who);
      a.amount += n(r.amount);
      couponAgg.set(r.coupon.id, a);
    }
    const couponRows = [...couponAgg.entries()]
      .map(([id, a]) => {
        const sales = salesOf(a.orders);
        return {
          id,
          code: a.code,
          name: a.name,
          type: a.type,
          active: a.active,
          uses: a.orders.size,
          customers: a.customers.size,
          discount: round(a.amount),
          sales: round(sales),
          averageOrder: a.orders.size ? round(sales / a.orders.size) : null,
        };
      })
      .sort((x, y) => y.uses - x.uses || y.discount - x.discount);

    const promoTotal = promoRows.reduce((a, p) => a + p.discount, 0);
    const couponTotal = couponRows.reduce((a, c) => a + c.discount, 0);
    const discountTotal = itemDiscountTotal + periodBillDiscounts.reduce((a, d) => a + n(d.amount), 0);

    return {
      from: iso(from),
      to: iso(to),
      days,
      currency: s.currency,
      inventoryEnabled: s.inventoryEnabled,
      summary: {
        net: round(totalNet),
        orders: orders.length,
        dishesSold: byProduct.size,
        units: totalQty,
        cost: round(knownCost),
        margin: round(knownNet - knownCost),
        foodCostPct: percent(knownCost, knownNet),
        // Cuánto de las ventas tiene costo conocido (con receta).
        costCoverage: percent(knownNet, totalNet),
        withoutRecipe: dishes.filter((d) => d.cost === null).length,
        popularityLine,
        marginLine,
        classes: { star: count('star'), plowhorse: count('plowhorse'), puzzle: count('puzzle'), dog: count('dog') },
      },
      dishes,
      unsold: unsold
        .map((p) => {
          const c = recipeCost.get(p.id);
          return {
            productId: p.id,
            name: p.name,
            category: p.category.name,
            price: n(p.price),
            available: p.isAvailable,
            unitMargin: c === undefined ? null : round(n(p.price) - c),
            addedDaysAgo: Math.floor((Date.now() - p.createdAt.getTime()) / DAY),
            class: classes.get(p.id) ?? null,
          };
        })
        .sort((x, y) => x.category.localeCompare(y.category) || x.name.localeCompare(y.name)),
      promotions: {
        totalDiscount: round(discountTotal),
        discountPct: percent(discountTotal, totalGross),
        averageOrder: round(avgOrder),
        promotions: promoRows,
        promotionsTotal: round(promoTotal),
        coupons: couponRows,
        couponsTotal: round(couponTotal),
        manual: { count: manualCount, amount: round(manualAmount) },
      },
    };
  }
}
