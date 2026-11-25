import type { PublicMenu, PublicPromotion } from './types';

/** Idiomas de la web: español e inglés. */
export type Lang = 'es' | 'en';

export const LANG_COOKIE = 'lang';

/** El texto en el idioma del cliente. */
export const pick = (lang: Lang, es: string, en: string) => (lang === 'en' ? en : es);

type Translations = Record<string, Record<string, string> | undefined> | null | undefined;

/** Texto traducido del menú ({ en: { name, description } }); si falta, el original. */
export function translated<T extends string | null>(translations: unknown, lang: Lang, field: string, fallback: T): T | string {
  if (lang === 'es' || !translations || typeof translations !== 'object') return fallback;
  const value = (translations as Translations)?.[lang]?.[field];
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

type WithTranslations = { translations?: unknown };

/** El menú con nombres y descripciones en el idioma del cliente. */
export function localizeMenu(menu: PublicMenu, lang: Lang): PublicMenu {
  if (lang === 'es') return menu;
  return {
    ...menu,
    categories: menu.categories.map((c) => ({
      ...c,
      name: translated((c as WithTranslations).translations, lang, 'name', c.name),
      products: c.products.map((p) => ({
        ...p,
        name: translated((p as WithTranslations).translations, lang, 'name', p.name),
        description: translated((p as WithTranslations).translations, lang, 'description', p.description),
        modifierGroups: p.modifierGroups.map((g) => ({
          ...g,
          name: translated((g as WithTranslations).translations, lang, 'name', g.name),
          options: g.options.map((o) => ({ ...o, name: translated((o as WithTranslations).translations, lang, 'name', o.name) })),
        })),
      })),
    })),
  };
}

export function localizePromotions(promotions: PublicPromotion[], lang: Lang): PublicPromotion[] {
  if (lang === 'es') return promotions;
  return promotions.map((p) => ({
    ...p,
    name: translated((p as WithTranslations).translations, lang, 'name', p.name),
    description: translated((p as WithTranslations).translations, lang, 'description', p.description),
  }));
}

/** Formato de fecha y hora del idioma. */
export const intlLocale = (lang: Lang) => (lang === 'en' ? 'en-US' : 'es-US');
