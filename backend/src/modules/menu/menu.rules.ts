import { BadRequestException } from '@nestjs/common';
import { SelectionType } from '@prisma/client';

export const SUPPORTED_LOCALES = ['es', 'en'] as const;

/** Los 9 alérgenos principales en EE. UU. (FDA). */
export const ALLERGENS = [
  'milk',
  'eggs',
  'fish',
  'shellfish',
  'tree_nuts',
  'peanuts',
  'wheat',
  'soybeans',
  'sesame',
] as const;

export interface ModifierGroupRules {
  selectionType: SelectionType;
  minSelect: number;
  maxSelect: number;
}

/** Reglas de un grupo de modificadores. Lanza 400 con un mensaje claro si no se cumplen. */
export function assertModifierGroupRules(rules: ModifierGroupRules, defaultCount = 0): void {
  const { selectionType, minSelect, maxSelect } = rules;
  if (minSelect < 0 || maxSelect < 1) {
    throw new BadRequestException('El mínimo no puede ser negativo y el máximo debe ser al menos 1');
  }
  if (minSelect > maxSelect) {
    throw new BadRequestException('El mínimo no puede ser mayor que el máximo');
  }
  if (selectionType === 'SINGLE' && (maxSelect !== 1 || minSelect > 1)) {
    throw new BadRequestException('Un grupo de selección única debe tener máximo 1 (y mínimo 0 o 1)');
  }
  if (defaultCount > maxSelect) {
    throw new BadRequestException('Hay más opciones marcadas por defecto que el máximo permitido');
  }
}

type TranslationInput = Record<string, Record<string, unknown>> | null | undefined;

/**
 * Limpia traducciones: { en: { name: "…", description: "…" } }.
 * Solo idiomas soportados y campos conocidos; textos recortados y con longitud máxima.
 */
export function sanitizeTranslations(
  input: TranslationInput,
  fields: Record<string, number>,
): Record<string, Record<string, string>> | null | undefined {
  if (input === undefined) return undefined;
  if (input === null) return null;

  const result: Record<string, Record<string, string>> = {};
  for (const [locale, values] of Object.entries(input)) {
    if (!(SUPPORTED_LOCALES as readonly string[]).includes(locale)) {
      throw new BadRequestException(`Idioma no soportado: ${locale}`);
    }
    if (!values || typeof values !== 'object') continue;
    const clean: Record<string, string> = {};
    for (const [field, maxLength] of Object.entries(fields)) {
      const value = values[field];
      if (value === undefined || value === null || value === '') continue;
      if (typeof value !== 'string') throw new BadRequestException(`Traducción inválida: ${locale}.${field}`);
      const trimmed = value.trim();
      if (trimmed.length > maxLength) {
        throw new BadRequestException(`Traducción demasiado larga: ${locale}.${field}`);
      }
      if (trimmed) clean[field] = trimmed;
    }
    if (Object.keys(clean).length > 0) result[locale] = clean;
  }
  return result;
}
