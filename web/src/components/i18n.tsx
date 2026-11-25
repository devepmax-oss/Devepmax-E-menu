'use client';

import { useRouter } from 'next/navigation';
import { createContext, useCallback, useContext, useTransition } from 'react';
import { LANG_COOKIE, type Lang } from '@/lib/i18n';

const LangContext = createContext<Lang>('es');

export function I18nProvider({ lang, children }: { lang: Lang; children: React.ReactNode }) {
  return <LangContext.Provider value={lang}>{children}</LangContext.Provider>;
}

export const useLang = () => useContext(LangContext);

/** t('Texto en español', 'English text') */
export function useT() {
  const lang = useContext(LangContext);
  return useCallback((es: string, en: string) => (lang === 'en' ? en : es), [lang]);
}

/** Botón ES / EN: guarda la elección y vuelve a pintar la página en ese idioma. */
export function LanguageSwitch({ offered = ['es', 'en'], className = '' }: { offered?: string[]; className?: string }) {
  const lang = useLang();
  const router = useRouter();
  const [pending, start] = useTransition();
  if (!offered.includes('es') || !offered.includes('en')) return null;
  const choose = (next: Lang) => {
    if (next === lang) return;
    document.cookie = `${LANG_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;
    start(() => router.refresh());
  };
  return (
    <div role="radiogroup" aria-label={lang === 'en' ? 'Language' : 'Idioma'} className={`inline-flex rounded-full border border-line bg-surface p-0.5 ${pending ? 'opacity-60' : ''} ${className}`}>
      {(['es', 'en'] as const).map((l) => (
        <button
          key={l}
          type="button"
          role="radio"
          aria-checked={lang === l}
          onClick={() => choose(l)}
          className={`press cursor-pointer rounded-full px-3 py-1.5 text-xs font-extrabold ${lang === l ? 'bg-ink text-bg' : 'text-soft hover:text-ink'}`}
        >
          {l === 'es' ? 'ES' : 'EN'}
        </button>
      ))}
    </div>
  );
}
