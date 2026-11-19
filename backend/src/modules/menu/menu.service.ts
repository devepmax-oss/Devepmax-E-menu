import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { PRODUCT_ADMIN_INCLUDE } from './products.service';

export type MenuChannel = 'dine_in' | 'online';

@Injectable()
export class MenuService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Menú para clientes (tablets, POS, web). Solo lo activo y visible en el canal.
   * Los productos agotados se incluyen con isAvailable = false para mostrarlos deshabilitados.
   */
  async getPublicMenu(channel: MenuChannel) {
    const visibility = channel === 'online' ? { visibleOnline: true } : { visibleDineIn: true };

    const [categories, defaultTax] = await Promise.all([
      this.prisma.category.findMany({
        where: { isActive: true, ...visibility },
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
        include: {
          products: {
            where: { isActive: true, ...visibility },
            orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
            include: {
              taxRate: true,
              modifierGroups: {
                where: { modifierGroup: { isActive: true } },
                orderBy: { sortOrder: 'asc' },
                include: { modifierGroup: { include: { options: { orderBy: { sortOrder: 'asc' } } } } },
              },
            },
          },
        },
      }),
      this.prisma.taxRate.findFirst({ where: { isDefault: true } }),
    ]);

    return {
      channel,
      categories: categories
        .filter((category) => category.products.length > 0)
        .map((category) => ({
          id: category.id,
          name: category.name,
          translations: category.translations,
          imageUrl: category.imageUrl,
          products: category.products.map((product) => ({
            id: product.id,
            name: product.name,
            description: product.description,
            translations: product.translations,
            price: product.price,
            imageUrl: product.imageUrl,
            isAvailable: product.isAvailable,
            allergens: product.allergens,
            prepTimeMinutes: product.prepTimeMinutes,
            taxRate: (product.taxRate ?? defaultTax)?.rate ?? '0',
            modifierGroups: product.modifierGroups.map(({ modifierGroup: group }) => ({
              id: group.id,
              name: group.name,
              translations: group.translations,
              selectionType: group.selectionType,
              minSelect: group.minSelect,
              maxSelect: group.maxSelect,
              options: group.options.map((option) => ({
                id: option.id,
                name: option.name,
                translations: option.translations,
                priceAdjustment: option.priceAdjustment,
                isDefault: option.isDefault,
                isAvailable: option.isAvailable,
              })),
            })),
          })),
        })),
    };
  }

  /** Todo el catálogo (incluye inactivos) para el panel de administración. */
  async getAdminMenu() {
    const [categories, modifierGroups, stations, taxRates] = await Promise.all([
      this.prisma.category.findMany({
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
        include: {
          products: { orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }], include: PRODUCT_ADMIN_INCLUDE },
        },
      }),
      this.prisma.modifierGroup.findMany({
        orderBy: { name: 'asc' },
        include: { options: { orderBy: { sortOrder: 'asc' } }, _count: { select: { products: true } } },
      }),
      this.prisma.kitchenStation.findMany({ orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] }),
      this.prisma.taxRate.findMany({ orderBy: [{ isDefault: 'desc' }, { name: 'asc' }] }),
    ]);
    return { categories, modifierGroups, stations, taxRates };
  }
}
