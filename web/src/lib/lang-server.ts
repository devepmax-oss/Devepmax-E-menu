import { cookies, headers } from 'next/headers';
import { cache } from 'react';
import { LANG_COOKIE, type Lang } from './i18n';
import { getConfig } from './server';

/**
 * Idioma de esta visita: el que eligió el cliente (cookie); si no eligió, el de su navegador
 * cuando el restaurante lo ofrece; si no, el idioma principal del restaurante.
 */
export const getLang = cache(async (): Promise<Lang> => {
  const [jar, head, config] = await Promise.all([cookies(), headers(), getConfig()]);
  const offered = (config?.locales ?? ['es', 'en']).filter((l): l is Lang => l === 'es' || l === 'en');
  const chosen = jar.get(LANG_COOKIE)?.value;
  if ((chosen === 'es' || chosen === 'en') && offered.includes(chosen)) return chosen;
  const browser = (head.get('accept-language') ?? '').toLowerCase();
  const preferred = browser.split(',').map((part) => part.trim().slice(0, 2)).find((l): l is Lang => l === 'es' || l === 'en');
  if (preferred && offered.includes(preferred)) return preferred;
  return offered[0] ?? 'es';
});
