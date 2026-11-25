import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Coupon, Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { toE164 } from '../../common/phone';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { BillingService, BillView } from '../billing/billing.service';
import { couponSavings, normalizeCode, randomCouponCode } from './coupon.rules';
import { CouponDto } from './dto/coupons.dto';

const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const money = (v: Prisma.Decimal.Value) => `$${dec(v).toFixed(2)}`;
/** Un pedido web sin pagar por más de 30 min ya no ocupa el cupón. */
const STALE_MINUTES = 30;

export interface CouponContext {
  channel: 'online' | 'in_store';
  /** Lo que queda de la cuenta tras promociones y otros descuentos (sin impuesto, envío ni propina). */
  base: Prisma.Decimal.Value;
  deliveryFee?: Prisma.Decimal.Value;
  customerId?: string | null;
  phone?: string | null;
  /** La cuenta a la que se aplica (no cuenta como uso anterior). */
  billId?: string;
}

export interface CouponResult {
  coupon: Coupon;
  amount: Prisma.Decimal;
  freeDelivery: boolean;
  saved: Prisma.Decimal;
  label: string;
}

/** Usos que cuentan: pedidos no cancelados (y la web sin pagar solo por 30 minutos). */
function countedUse(now: Date): Prisma.CouponRedemptionWhereInput {
  return {
    order: {
      status: { not: 'CANCELLED' },
      NOT: { status: 'PENDING_PAYMENT', createdAt: { lt: new Date(now.getTime() - STALE_MINUTES * 60_000) } },
    },
  };
}

/**
 * Cupones: el cliente da un código en la caja o lo escribe al pagar en la web. Porcentaje (con
 * tope), monto fijo o envío gratis; vigencia, canales, mínimo de compra, usos totales y por
 * cliente, solo primer pedido y cupones personales.
 */
@Injectable()
export class CouponsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly billing: BillingService,
  ) {}

  // ───────── Administrar ─────────

  async list() {
    const now = new Date();
    const coupons = await this.prisma.coupon.findMany({
      include: { customer: { select: { id: true, name: true, phone: true } } },
      orderBy: [{ isActive: 'desc' }, { createdAt: 'desc' }],
    });
    const uses = await this.prisma.couponRedemption.groupBy({
      by: ['couponId'],
      where: { couponId: { in: coupons.map((c) => c.id) }, ...countedUse(now) },
      _count: { _all: true },
      _sum: { amount: true },
    });
    const byId = new Map(uses.map((u) => [u.couponId, u]));
    return coupons.map((c) => this.view(c, byId.get(c.id)?._count._all ?? 0, byId.get(c.id)?._sum.amount ?? dec(0), now));
  }

  suggestCode() {
    return { code: randomCouponCode() };
  }

  async create(actor: EmployeeActor, dto: CouponDto) {
    const data = await this.dataFrom(dto);
    if (await this.prisma.coupon.findUnique({ where: { code: data.code } })) throw new ConflictException('Ya existe un cupón con ese código');
    const coupon = await this.prisma.coupon.create({ data });
    await this.audit.log(actor, 'coupon.create', 'coupon', coupon.id, { code: coupon.code });
    return (await this.list()).find((c) => c.id === coupon.id)!;
  }

  async update(actor: EmployeeActor, id: string, dto: CouponDto) {
    const existing = await this.prisma.coupon.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Cupón no encontrado');
    const data = await this.dataFrom(dto);
    if (data.code !== existing.code && (await this.prisma.coupon.findUnique({ where: { code: data.code } }))) {
      throw new ConflictException('Ya existe un cupón con ese código');
    }
    await this.prisma.coupon.update({ where: { id }, data });
    await this.audit.log(actor, 'coupon.update', 'coupon', id, { code: data.code });
    return (await this.list()).find((c) => c.id === id)!;
  }

  /** Solo se borra si nunca se usó; si ya se usó, se pausa (para no perder el historial). */
  async remove(actor: EmployeeActor, id: string) {
    const coupon = await this.prisma.coupon.findUnique({ where: { id }, include: { _count: { select: { redemptions: true } } } });
    if (!coupon) throw new NotFoundException('Cupón no encontrado');
    if (coupon._count.redemptions > 0) throw new ConflictException('Este cupón ya se usó: páusalo en vez de borrarlo');
    await this.prisma.coupon.delete({ where: { id } });
    await this.audit.log(actor, 'coupon.delete', 'coupon', id, { code: coupon.code });
  }

  // ───────── Validar ─────────

  /** Revisa el cupón y calcula el descuento. Lanza un error claro si no se puede usar. */
  async check(rawCode: string, ctx: CouponContext): Promise<CouponResult> {
    const code = normalizeCode(rawCode);
    const coupon = code ? await this.prisma.coupon.findUnique({ where: { code } }) : null;
    if (!coupon) throw new BadRequestException('Ese cupón no existe');
    const now = new Date();
    if (!coupon.isActive) throw new BadRequestException('Este cupón ya no está activo');
    if (coupon.startsAt && coupon.startsAt > now) throw new BadRequestException('Este cupón todavía no empieza');
    if (coupon.endsAt && coupon.endsAt <= now) throw new BadRequestException('Este cupón ya venció');
    if (ctx.channel === 'online' && !coupon.appliesOnline) throw new BadRequestException('Este cupón es solo para usar en el restaurante');
    if (ctx.channel === 'in_store' && !coupon.appliesInStore) throw new BadRequestException('Este cupón es solo para pedidos en línea');
    if (coupon.type === 'FREE_DELIVERY') {
      if (ctx.channel !== 'online') throw new BadRequestException('El envío gratis es solo para pedidos a domicilio en línea');
      if (!ctx.deliveryFee || dec(ctx.deliveryFee).lte(0)) throw new BadRequestException('Este cupón es de envío gratis: elige Delivery');
    }
    if (coupon.minOrderTotal && dec(ctx.base).lt(coupon.minOrderTotal)) {
      throw new BadRequestException(`El pedido mínimo para este cupón es de ${money(coupon.minOrderTotal)}`);
    }

    const phone = ctx.phone ? toE164(ctx.phone) : null;
    if (coupon.customerId && coupon.customerId !== ctx.customerId) {
      throw new BadRequestException(
        ctx.channel === 'online'
          ? ctx.customerId
            ? 'Este cupón es de otro cliente'
            : 'Este cupón es personal: entra a tu cuenta para usarlo'
          : 'Este cupón es personal: identifica en la cuenta al cliente dueño del cupón',
      );
    }

    const used = countedUse(now);
    const notThisBill: Prisma.CouponRedemptionWhereInput = ctx.billId ? { NOT: { billId: ctx.billId } } : {};
    if (coupon.maxUses) {
      const total = await this.prisma.couponRedemption.count({ where: { couponId: coupon.id, ...used, ...notThisBill } });
      if (total >= coupon.maxUses) throw new BadRequestException('Este cupón ya se agotó');
    }
    const who: Prisma.CouponRedemptionWhereInput[] = [
      ...(ctx.customerId ? [{ customerId: ctx.customerId }] : []),
      ...(phone ? [{ customerPhone: phone }] : []),
    ];
    if (coupon.maxUsesPerCustomer || coupon.firstOrderOnly) {
      if (!who.length) {
        throw new BadRequestException(
          ctx.channel === 'online' ? 'Escribe tu teléfono para usar este cupón' : 'Identifica al cliente: este cupón tiene límite por cliente',
        );
      }
    }
    if (coupon.maxUsesPerCustomer) {
      const mine = await this.prisma.couponRedemption.count({ where: { couponId: coupon.id, ...used, ...notThisBill, OR: who } });
      if (mine >= coupon.maxUsesPerCustomer) {
        throw new BadRequestException(coupon.maxUsesPerCustomer === 1 ? 'Ya usaste este cupón' : 'Ya usaste este cupón las veces permitidas');
      }
    }
    if (coupon.firstOrderOnly && (await this.hasOrderedBefore(ctx.customerId ?? null, phone, ctx.billId))) {
      throw new BadRequestException('Este cupón es solo para el primer pedido');
    }

    const savings = couponSavings(coupon, ctx.base, ctx.deliveryFee ?? 0);
    if (savings.saved.lte(0)) throw new BadRequestException('No hay nada a qué aplicarle este cupón');
    return { coupon, ...savings, label: coupon.name.trim() || `Cupón ${coupon.code}` };
  }

  // ───────── Caja ─────────

  /** Aplica un cupón a una cuenta abierta de la caja. Uno por cuenta. */
  async applyToBill(actor: EmployeeActor, billId: string, rawCode: string): Promise<BillView> {
    const bill = await this.prisma.bill.findUnique({
      where: { id: billId },
      include: {
        discounts: { where: { couponId: { not: null } } },
        orders: { where: { status: { not: 'CANCELLED' } }, orderBy: { createdAt: 'asc' }, select: { id: true } },
        customer: { select: { id: true, phone: true } },
      },
    });
    if (!bill) throw new NotFoundException('Cuenta no encontrada');
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada o anulada');
    if (bill.discounts.length) throw new ConflictException('Esta cuenta ya tiene un cupón: quítalo primero');
    if (!bill.orders.length) throw new BadRequestException('La cuenta no tiene pedidos');

    const result = await this.check(rawCode, {
      channel: 'in_store',
      base: bill.subtotal.minus(bill.discountTotal),
      customerId: bill.customer?.id ?? null,
      phone: bill.customer?.phone ?? null,
      billId,
    });
    await this.prisma.$transaction(async (tx) => {
      await tx.discount.create({
        data: {
          billId,
          type: result.coupon.type === 'PERCENT' ? 'PERCENT' : 'AMOUNT',
          value: result.coupon.type === 'PERCENT' ? dec(result.coupon.value ?? 0) : result.amount,
          amount: result.amount,
          reason: result.label,
          couponId: result.coupon.id,
          appliedById: null,
        },
      });
      await tx.couponRedemption.create({
        data: {
          couponId: result.coupon.id,
          orderId: bill.orders[0].id,
          billId,
          customerId: bill.customer?.id ?? null,
          customerPhone: bill.customer?.phone ?? null,
          amount: result.saved,
        },
      });
      await this.billing.settle(tx, billId);
      const after = await tx.bill.findUniqueOrThrow({ where: { id: billId } });
      if (after.total.lt(after.amountPaid)) throw new ConflictException('El cupón deja la cuenta por debajo de lo ya cobrado');
    });
    await this.audit.log(actor, 'bill.coupon', 'bill', billId, { code: result.coupon.code, amount: result.amount.toString() });
    return this.billing.afterChange(actor, billId);
  }

  async removeFromBill(actor: EmployeeActor, billId: string): Promise<BillView> {
    const bill = await this.prisma.bill.findUnique({ where: { id: billId }, include: { discounts: { where: { couponId: { not: null } } } } });
    if (!bill) throw new NotFoundException('Cuenta no encontrada');
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada o anulada');
    const discount = bill.discounts[0];
    if (!discount) throw new NotFoundException('La cuenta no tiene cupón');
    await this.prisma.$transaction(async (tx) => {
      await tx.discount.delete({ where: { id: discount.id } });
      await tx.couponRedemption.deleteMany({ where: { couponId: discount.couponId!, billId } });
      await this.billing.settle(tx, billId);
    });
    await this.audit.log(actor, 'bill.coupon_removed', 'bill', billId, { couponId: discount.couponId });
    return this.billing.afterChange(actor, billId);
  }

  // ───────── Ayudantes ─────────

  private async hasOrderedBefore(customerId: string | null, phone: string | null, billId?: string) {
    if (customerId) {
      const bills = await this.prisma.bill.count({
        where: {
          customerId,
          status: { not: 'VOID' },
          orders: { some: { status: { notIn: ['PENDING_PAYMENT', 'CANCELLED'] } } },
          ...(billId ? { NOT: { id: billId } } : {}),
        },
      });
      if (bills > 0) return true;
    }
    if (phone) {
      const candidates = await this.prisma.order.findMany({
        where: {
          customerPhone: { contains: phone.slice(-4) },
          status: { notIn: ['PENDING_PAYMENT', 'CANCELLED'] },
          ...(billId ? { NOT: { billId } } : {}),
        },
        select: { customerPhone: true },
        take: 200,
      });
      if (candidates.some((o) => o.customerPhone && toE164(o.customerPhone) === phone)) return true;
    }
    return false;
  }

  private async dataFrom(dto: CouponDto) {
    const code = normalizeCode(dto.code);
    if (!code) throw new BadRequestException('El código lleva de 3 a 30 letras, números o guiones');
    if (dto.type !== 'FREE_DELIVERY' && !(dto.value && dto.value > 0)) throw new BadRequestException('Escribe cuánto descuenta el cupón');
    if (dto.type === 'PERCENT' && (dto.value ?? 0) > 100) throw new BadRequestException('El porcentaje va de 1 a 100');
    if (dto.type === 'FREE_DELIVERY' && dto.appliesInStore) throw new BadRequestException('El envío gratis es solo para pedidos en línea');
    const appliesOnline = dto.appliesOnline ?? true;
    const appliesInStore = dto.type === 'FREE_DELIVERY' ? false : (dto.appliesInStore ?? true);
    if (!appliesOnline && !appliesInStore) throw new BadRequestException('Elige dónde se puede usar: en línea, en el restaurante o ambos');
    const startsAt = dto.startsAt ? new Date(dto.startsAt) : null;
    const endsAt = dto.endsAt ? new Date(dto.endsAt) : null;
    if (startsAt && endsAt && endsAt <= startsAt) throw new BadRequestException('La fecha final debe ser después de la inicial');
    if (dto.customerId && !(await this.prisma.customer.findUnique({ where: { id: dto.customerId }, select: { id: true } }))) {
      throw new BadRequestException('Cliente no encontrado');
    }
    return {
      code,
      name: dto.name?.trim() ?? '',
      type: dto.type,
      value: dto.type === 'FREE_DELIVERY' ? null : dec(dto.value!),
      maxDiscount: dto.type === 'PERCENT' && dto.maxDiscount ? dec(dto.maxDiscount) : null,
      minOrderTotal: dto.minOrderTotal ? dec(dto.minOrderTotal) : null,
      appliesOnline,
      appliesInStore,
      firstOrderOnly: dto.firstOrderOnly ?? false,
      maxUses: dto.maxUses ?? null,
      maxUsesPerCustomer: dto.maxUsesPerCustomer ?? null,
      startsAt,
      endsAt,
      customerId: dto.customerId ?? null,
      isActive: dto.isActive ?? true,
    };
  }

  private view(
    c: Coupon & { customer: { id: string; name: string; phone: string | null } | null },
    uses: number,
    saved: Prisma.Decimal,
    now: Date,
  ) {
    const state = !c.isActive
      ? 'PAUSED'
      : c.endsAt && c.endsAt <= now
        ? 'EXPIRED'
        : c.startsAt && c.startsAt > now
          ? 'SCHEDULED'
          : c.maxUses && uses >= c.maxUses
            ? 'USED_UP'
            : 'ACTIVE';
    return {
      id: c.id,
      code: c.code,
      name: c.name,
      type: c.type,
      value: c.value,
      maxDiscount: c.maxDiscount,
      minOrderTotal: c.minOrderTotal,
      appliesOnline: c.appliesOnline,
      appliesInStore: c.appliesInStore,
      firstOrderOnly: c.firstOrderOnly,
      maxUses: c.maxUses,
      maxUsesPerCustomer: c.maxUsesPerCustomer,
      startsAt: c.startsAt,
      endsAt: c.endsAt,
      isActive: c.isActive,
      customer: c.customer,
      uses,
      saved,
      state,
      createdAt: c.createdAt,
    };
  }
}
