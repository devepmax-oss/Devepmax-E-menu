import { NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { sanitizeTranslations } from './menu.rules';

export const TRANSLATION_FIELDS = {
  category: { name: 80 },
  product: { name: 120, description: 1000 },
  modifierGroup: { name: 80 },
  modifierOption: { name: 80 },
} as const;

/** Traducciones → valor para Prisma (undefined = no cambiar, null = borrar). */
export function translationsInput(
  value: Record<string, Record<string, unknown>> | null | undefined,
  fields: Record<string, number>,
): Prisma.InputJsonValue | typeof Prisma.DbNull | undefined {
  const clean = sanitizeTranslations(value, fields);
  if (clean === undefined) return undefined;
  if (clean === null || Object.keys(clean).length === 0) return Prisma.DbNull;
  return clean;
}

export function found<T>(entity: T | null, message: string): T {
  if (!entity) throw new NotFoundException(message);
  return entity;
}
