import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Decimal } from '@prisma/client/runtime/library';
import { PrismaService } from '../../prisma/prisma.service';
import { lineTotal, money, selectionError } from './order.rules';

export interface OrderLineInput {
  productId: string;
  quantity: number;
  optionIds?: string[];
  notes?: string;
  seat?: number;
}

export interface PricedModifier {
  modifierOptionId: string;
  groupNameSnapshot: string;
  optionNameSnapshot: string;
  priceAdjustment: Decimal;
}

export interface PricedLine {
  productId: string;
  categoryId: string;
  stationId: string | null;
  nameSnapshot: string;
  unitPrice: Decimal;
  modifiersTotal: Decimal;
  quantity: number;
  lineTotal: Decimal;
  taxRate: Decimal;
  notes: string | null;
  seat: number | null;
  modifiers: PricedModifier[];
}

type Db = PrismaService | Prisma.TransactionClient;

/**
 * Calcula precios en el servidor a partir del menú vigente.
 * El cliente solo propone producto, cantidad y opciones: nunca precios.
 */
@Injectable()
export class PricingService {
  async priceLines(db: Db, channel: 'dine_in' | 'online', lines: OrderLineInput[]): Promise<PricedLine[]> {
    if (lines.length === 0) throw new BadRequestException('La orden no tiene productos');

    const productIds = [...new Set(lines.map((l) => l.productId))];
    const [products, defaultTax] = await Promise.all([
      db.product.findMany({
        where: { id: { in: productIds } },
        include: {
          category: true,
          taxRate: true,
          modifierGroups: { include: { modifierGroup: { include: { options: true } } } },
        },
      }),
      db.taxRate.findFirst({ where: { isDefault: true } }),
    ]);
    const byId = new Map(products.map((p) => [p.id, p]));

    return lines.map((line) => {
      const product = byId.get(line.productId);
      const visible = channel === 'online' ? product?.visibleOnline : product?.visibleDineIn;
      if (!product || !product.isActive || !product.category.isActive || !visible) {
        throw new BadRequestException('Un producto de la orden ya no está en el menú');
      }
      if (!product.isAvailable) throw new BadRequestException(`"${product.name}" está agotado`);

      const groups = product.modifierGroups.map((link) => link.modifierGroup).filter((g) => g.isActive);
      const options = new Map(groups.flatMap((g) => g.options.map((o) => [o.id, { option: o, group: g }] as const)));

      const chosen = new Map<string, number>();
      const modifiers: PricedModifier[] = [];
      for (const optionId of new Set(line.optionIds ?? [])) {
        const entry = options.get(optionId);
        if (!entry) throw new BadRequestException(`"${product.name}": una opción elegida no es válida`);
        if (!entry.option.isAvailable) {
          throw new BadRequestException(`"${product.name}": "${entry.option.name}" está agotado`);
        }
        chosen.set(entry.group.id, (chosen.get(entry.group.id) ?? 0) + 1);
        modifiers.push({
          modifierOptionId: entry.option.id,
          groupNameSnapshot: entry.group.name,
          optionNameSnapshot: entry.option.name,
          priceAdjustment: money(entry.option.priceAdjustment),
        });
      }

      const error = selectionError(product.name, groups, chosen);
      if (error) throw new BadRequestException(error);

      const modifiersTotal = money(modifiers.reduce((sum, m) => sum.plus(m.priceAdjustment), new Decimal(0)));
      const unitPrice = money(product.price);
      return {
        productId: product.id,
        categoryId: product.categoryId,
        stationId: product.stationId,
        nameSnapshot: product.name,
        unitPrice,
        modifiersTotal,
        quantity: line.quantity,
        lineTotal: lineTotal(unitPrice, modifiersTotal, line.quantity),
        taxRate: new Decimal((product.taxRate ?? defaultTax)?.rate ?? 0),
        notes: line.notes?.trim() || null,
        seat: line.seat ?? null,
        modifiers,
      };
    });
  }
}
