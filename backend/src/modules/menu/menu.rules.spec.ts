import { BadRequestException } from '@nestjs/common';
import { assertModifierGroupRules, sanitizeTranslations } from './menu.rules';

describe('assertModifierGroupRules', () => {
  it('acepta selección única opcional u obligatoria', () => {
    expect(() => assertModifierGroupRules({ selectionType: 'SINGLE', minSelect: 0, maxSelect: 1 })).not.toThrow();
    expect(() => assertModifierGroupRules({ selectionType: 'SINGLE', minSelect: 1, maxSelect: 1 })).not.toThrow();
  });

  it('rechaza selección única con máximo distinto de 1', () => {
    expect(() => assertModifierGroupRules({ selectionType: 'SINGLE', minSelect: 0, maxSelect: 2 })).toThrow(
      BadRequestException,
    );
  });

  it('rechaza mínimo mayor que máximo', () => {
    expect(() => assertModifierGroupRules({ selectionType: 'MULTIPLE', minSelect: 3, maxSelect: 2 })).toThrow(
      BadRequestException,
    );
  });

  it('rechaza más opciones por defecto que el máximo', () => {
    expect(() => assertModifierGroupRules({ selectionType: 'MULTIPLE', minSelect: 0, maxSelect: 2 }, 3)).toThrow(
      BadRequestException,
    );
  });
});

describe('sanitizeTranslations', () => {
  const fields = { name: 10, description: 50 };

  it('conserva idiomas y campos válidos, recorta espacios y descarta vacíos', () => {
    expect(sanitizeTranslations({ en: { name: '  Burger ', description: '', extra: 'x' } }, fields)).toEqual({
      en: { name: 'Burger' },
    });
  });

  it('rechaza idiomas no soportados', () => {
    expect(() => sanitizeTranslations({ fr: { name: 'x' } }, fields)).toThrow(BadRequestException);
  });

  it('rechaza textos demasiado largos', () => {
    expect(() => sanitizeTranslations({ en: { name: 'x'.repeat(11) } }, fields)).toThrow(BadRequestException);
  });

  it('respeta undefined (no cambiar) y null (borrar)', () => {
    expect(sanitizeTranslations(undefined, fields)).toBeUndefined();
    expect(sanitizeTranslations(null, fields)).toBeNull();
  });
});
