import type { MenuCategory, PublicPromotion } from './types';
import { money, toNumber } from './format';

/** Etiqueta corta para la foto del producto: 2x1, −15 %, −$2, Combo. */
export function promoBadge(p: PublicPromotion, currency: string): string {
  switch (p.type) {
    case 'BUY_X_GET_Y':
      return `${(p.buyQuantity ?? 1) + (p.getQuantity ?? 1)}x${p.buyQuantity ?? 1}`;
    case 'PERCENT_OFF':
      return `−${toNumber(p.value)}%`;
    case 'AMOUNT_OFF':
      return `−${money(p.value, currency).replace('.00', '')}`;
    default:
      return 'Combo';
  }
}

/** Promociones que aplican a cada producto (por producto o por su categoría). */
export function promotionsByProduct(categories: MenuCategory[], promotions: PublicPromotion[]) {
  const map = new Map<string, PublicPromotion[]>();
  for (const category of categories) {
    for (const product of category.products) {
      const hits = promotions.filter(
        (p) =>
          p.type !== 'COMBO_PRICE' && (p.productIds.includes(product.id) || p.categoryIds.includes(category.id)),
      );
      if (hits.length) map.set(product.id, hits);
    }
  }
  return map;
}
