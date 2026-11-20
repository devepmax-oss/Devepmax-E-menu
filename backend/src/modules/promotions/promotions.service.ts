import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { TRANSLATION_FIELDS, translationsInput } from '../menu/menu.helpers';
import type { PricedLine } from '../orders/pricing.service';
import { CreatePromotionDto, UpdatePromotionDto } from './dto/promotion.dto';
import { Allocation, applyPromotions, EnginePromotion, PromotionType } from './promotion.engine';

const PROMOTION_INCLUDE = {
  targets: true,
  comboSlots: { orderBy: { sortOrder: 'asc' } },
  _count: { select: { discounts: true } },
} satisfies Prisma.PromotionInclude;

type PromotionWithRelations = Prisma.PromotionGetPayload<{ include: typeof PROMOTION_INCLUDE }>;

export type PromotionState = 'ACTIVE' | 'SCHEDULED' | 'EXPIRED' | 'INACTIVE';

export function promotionState(p: { isActive: boolean; startsAt: Date | null; endsAt: Date | null }, now = new Date()): PromotionState {
  if (!p.isActive) return 'INACTIVE';
  if (p.endsAt && p.endsAt <= now) return 'EXPIRED';
  if (p.startsAt && p.startsAt > now) return 'SCHEDULED';
  return 'ACTIVE';
}

export function toPromotionView(p: PromotionWithRelations) {
  return {
    id: p.id,
    name: p.name,
    description: p.description,
    translations: p.translations,
    type: p.type,
    value: p.value,
    buyQuantity: p.buyQuantity,
    getQuantity: p.getQuantity,
    comboPrice: p.comboPrice,
    appliesDineIn: p.appliesDineIn,
    appliesOnline: p.appliesOnline,
    startsAt: p.startsAt,
    endsAt: p.endsAt,
    priority: p.priority,
    isActive: p.isActive,
    state: promotionState(p),
    productIds: p.targets.flatMap((t) => (t.productId ? [t.productId] : [])),
    categoryIds: p.targets.flatMap((t) => (t.categoryId ? [t.categoryId] : [])),
    comboSlots: p.comboSlots.map((s) => ({
      name: s.name,
      quantity: s.quantity,
      productIds: s.productIds,
      categoryIds: s.categoryIds,
    })),
    timesApplied: p._count.discounts,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  };
}

interface MergedRules {
  type: PromotionType;
  value: number | null;
  buyQuantity: number | null;
  getQuantity: number | null;
  comboPrice: number | null;
  productIds: string[];
  categoryIds: string[];
  comboSlots: { productIds: string[]; categoryIds: string[] }[];
  startsAt: Date | null;
  endsAt: Date | null;
}

/** Reglas de cada tipo. Lanza 400 con un mensaje claro. */
export function assertPromotionRules(r: MergedRules): void {
  const hasTargets = r.productIds.length + r.categoryIds.length > 0;
  switch (r.type) {
    case 'PERCENT_OFF':
      if (r.value === null || r.value <= 0 || r.value > 100) throw new BadRequestException('El porcentaje debe estar entre 1 y 100');
      if (!hasTargets) throw new BadRequestException('Elige los productos o categorías con descuento');
      break;
    case 'AMOUNT_OFF':
      if (r.value === null || r.value <= 0) throw new BadRequestException('Escribe el monto del descuento');
      if (!hasTargets) throw new BadRequestException('Elige los productos o categorías con descuento');
      break;
    case 'BUY_X_GET_Y':
      if (!r.buyQuantity || !r.getQuantity) throw new BadRequestException('Indica cuántos compra y cuántos lleva gratis');
      if (!hasTargets) throw new BadRequestException('Elige los productos o categorías de la promoción');
      break;
    case 'COMBO_PRICE':
      if (r.comboPrice === null || r.comboPrice <= 0) throw new BadRequestException('Escribe el precio del combo');
      if (r.comboSlots.length < 2) throw new BadRequestException('Un combo necesita al menos 2 partes');
      if (r.comboSlots.some((s) => s.productIds.length + s.categoryIds.length === 0)) {
        throw new BadRequestException('Cada parte del combo necesita productos o categorías');
      }
      break;
  }
  if (r.startsAt && r.endsAt && r.endsAt <= r.startsAt) {
    throw new BadRequestException('La fecha de fin debe ser posterior a la de inicio');
  }
}

function toNumber(value: Prisma.Decimal | null): number | null {
  return value === null ? null : Number(value);
}

@Injectable()
export class PromotionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async list() {
    const promotions = await this.prisma.promotion.findMany({
      include: PROMOTION_INCLUDE,
      orderBy: [{ isActive: 'desc' }, { createdAt: 'desc' }],
    });
    return promotions.map(toPromotionView);
  }

  /** Promociones vigentes para mostrar en tablets y web (sin datos internos). */
  async listPublic(channel: 'dine_in' | 'online') {
    const promotions = await this.prisma.promotion.findMany({
      where: this.activeWhere(channel, new Date()),
      include: PROMOTION_INCLUDE,
      orderBy: [{ priority: 'desc' }, { createdAt: 'desc' }],
    });
    return promotions.map((p) => {
      const { timesApplied: _times, createdAt: _c, updatedAt: _u, isActive: _a, state: _s, ...rest } = toPromotionView(p);
      return rest;
    });
  }

  async create(actor: EmployeeActor, dto: CreatePromotionDto) {
    const rules: MergedRules = {
      type: dto.type,
      value: dto.value ?? null,
      buyQuantity: dto.buyQuantity ?? null,
      getQuantity: dto.getQuantity ?? null,
      comboPrice: dto.comboPrice ?? null,
      productIds: dto.productIds ?? [],
      categoryIds: dto.categoryIds ?? [],
      comboSlots: dto.comboSlots ?? [],
      startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
      endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
    };
    assertPromotionRules(rules);
    await this.assertReferences(rules);

    const promotion = await this.prisma.promotion.create({
      data: {
        name: dto.name.trim(),
        description: dto.description?.trim() || null,
        translations: translationsInput(dto.translations, TRANSLATION_FIELDS.product),
        type: dto.type,
        value: rules.value,
        buyQuantity: rules.buyQuantity,
        getQuantity: rules.getQuantity,
        comboPrice: rules.comboPrice,
        appliesDineIn: dto.appliesDineIn ?? true,
        appliesOnline: dto.appliesOnline ?? true,
        startsAt: rules.startsAt,
        endsAt: rules.endsAt,
        priority: dto.priority ?? 0,
        isActive: dto.isActive ?? true,
        targets: { create: this.targetRows(rules) },
        comboSlots: {
          create: (dto.comboSlots ?? []).map((slot, sortOrder) => ({ ...slot, name: slot.name.trim(), sortOrder })),
        },
      },
      include: PROMOTION_INCLUDE,
    });
    await this.audit.log(actor, 'promotion.create', 'promotion', promotion.id, { name: promotion.name, type: promotion.type });
    return toPromotionView(promotion);
  }

  async update(actor: EmployeeActor, id: string, dto: UpdatePromotionDto) {
    const current = await this.prisma.promotion.findUnique({ where: { id }, include: PROMOTION_INCLUDE });
    if (!current) throw new NotFoundException('Promoción no encontrada');
    const view = toPromotionView(current);

    const pick = <T>(next: T | undefined, prev: T): T => (next === undefined ? prev : next);
    const rules: MergedRules = {
      type: dto.type ?? current.type,
      value: pick(dto.value, toNumber(current.value)),
      buyQuantity: pick(dto.buyQuantity, current.buyQuantity),
      getQuantity: pick(dto.getQuantity, current.getQuantity),
      comboPrice: pick(dto.comboPrice, toNumber(current.comboPrice)),
      productIds: dto.productIds ?? view.productIds,
      categoryIds: dto.categoryIds ?? view.categoryIds,
      comboSlots: dto.comboSlots ?? view.comboSlots,
      startsAt: dto.startsAt === undefined ? current.startsAt : dto.startsAt ? new Date(dto.startsAt) : null,
      endsAt: dto.endsAt === undefined ? current.endsAt : dto.endsAt ? new Date(dto.endsAt) : null,
    };
    assertPromotionRules(rules);
    await this.assertReferences(rules);

    const promotion = await this.prisma.$transaction(async (tx) => {
      if (dto.productIds || dto.categoryIds) {
        await tx.promotionTarget.deleteMany({ where: { promotionId: id } });
        await tx.promotionTarget.createMany({ data: this.targetRows(rules).map((t) => ({ ...t, promotionId: id })) });
      }
      if (dto.comboSlots) {
        await tx.promotionComboSlot.deleteMany({ where: { promotionId: id } });
        await tx.promotionComboSlot.createMany({
          data: dto.comboSlots.map((slot, sortOrder) => ({ ...slot, name: slot.name.trim(), sortOrder, promotionId: id })),
        });
      }
      return tx.promotion.update({
        where: { id },
        data: {
          name: dto.name?.trim(),
          description: dto.description === null ? null : dto.description?.trim(),
          translations: translationsInput(dto.translations, TRANSLATION_FIELDS.product),
          type: dto.type,
          value: dto.value,
          buyQuantity: dto.buyQuantity,
          getQuantity: dto.getQuantity,
          comboPrice: dto.comboPrice,
          appliesDineIn: dto.appliesDineIn,
          appliesOnline: dto.appliesOnline,
          startsAt: rules.startsAt,
          endsAt: rules.endsAt,
          priority: dto.priority,
          isActive: dto.isActive,
        },
        include: PROMOTION_INCLUDE,
      });
    });
    await this.audit.log(actor, 'promotion.update', 'promotion', id, { fields: Object.keys(dto) });
    return toPromotionView(promotion);
  }

  /** Borrar no altera órdenes pasadas: sus descuentos conservan el nombre de la promoción. */
  async remove(actor: EmployeeActor, id: string) {
    const promotion = await this.prisma.promotion.findUnique({ where: { id } });
    if (!promotion) throw new NotFoundException('Promoción no encontrada');
    await this.prisma.promotion.delete({ where: { id } });
    await this.audit.log(actor, 'promotion.delete', 'promotion', id, { name: promotion.name });
  }

  /** Aplica las promociones vigentes del canal a las líneas de una orden. */
  async applyToLines(channel: 'dine_in' | 'online', lines: PricedLine[]): Promise<Allocation[]> {
    const promotions = await this.prisma.promotion.findMany({
      where: this.activeWhere(channel, new Date()),
      include: { targets: true, comboSlots: { orderBy: { sortOrder: 'asc' } } },
    });
    if (promotions.length === 0) return [];

    const engine: EnginePromotion[] = promotions.map((p) => ({
      id: p.id,
      name: p.name,
      type: p.type,
      value: p.value,
      buyQuantity: p.buyQuantity,
      getQuantity: p.getQuantity,
      comboPrice: p.comboPrice,
      priority: p.priority,
      targets: p.targets.map((t) => ({ productId: t.productId, categoryId: t.categoryId })),
      slots: p.comboSlots.map((s) => ({ quantity: s.quantity, productIds: s.productIds, categoryIds: s.categoryIds })),
    }));
    return applyPromotions(
      lines.map((line, index) => ({
        index,
        productId: line.productId,
        categoryId: line.categoryId,
        unitAmount: line.unitPrice.plus(line.modifiersTotal),
        quantity: line.quantity,
      })),
      engine,
    );
  }

  private activeWhere(channel: 'dine_in' | 'online', now: Date): Prisma.PromotionWhereInput {
    return {
      isActive: true,
      requiresCoupon: false,
      ...(channel === 'online' ? { appliesOnline: true } : { appliesDineIn: true }),
      AND: [{ OR: [{ startsAt: null }, { startsAt: { lte: now } }] }, { OR: [{ endsAt: null }, { endsAt: { gt: now } }] }],
    };
  }

  private targetRows(rules: MergedRules) {
    if (rules.type === 'COMBO_PRICE') return [];
    return [
      ...rules.productIds.map((productId) => ({ productId })),
      ...rules.categoryIds.map((categoryId) => ({ categoryId })),
    ];
  }

  private async assertReferences(rules: MergedRules): Promise<void> {
    const productIds = [...new Set([...rules.productIds, ...rules.comboSlots.flatMap((s) => s.productIds)])];
    const categoryIds = [...new Set([...rules.categoryIds, ...rules.comboSlots.flatMap((s) => s.categoryIds)])];
    const [products, categories] = await Promise.all([
      productIds.length ? this.prisma.product.count({ where: { id: { in: productIds } } }) : 0,
      categoryIds.length ? this.prisma.category.count({ where: { id: { in: categoryIds } } }) : 0,
    ]);
    if (products !== productIds.length) throw new BadRequestException('Algún producto de la promoción no existe');
    if (categories !== categoryIds.length) throw new BadRequestException('Alguna categoría de la promoción no existe');
  }
}
