'use client';

import { Store } from 'lucide-react';
import { useT } from './i18n';
import { BrandMark } from './ui';

/** Pantalla cuando no se puede pedir: backend caído o restaurante en mantenimiento. */
export function Unavailable({ name, logoUrl, maintenance }: { name?: string; logoUrl?: string | null; maintenance?: boolean }) {
  const t = useT();
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-6 px-6 text-center">
      {name ? <BrandMark name={name} logoUrl={logoUrl ?? null} size={56} /> : null}
      <span className="flex size-16 items-center justify-center rounded-3xl bg-brand-soft text-brand-text">
        <Store aria-hidden className="size-8" />
      </span>
      <div className="flex flex-col gap-2">
        <h1 className="text-3xl font-extrabold">{maintenance ? t('Volvemos enseguida', 'Back in a moment') : t('No pudimos cargar el menú', 'We could not load the menu')}</h1>
        <p className="text-soft">
          {maintenance
            ? t('Estamos haciendo unos ajustes. Los pedidos en línea vuelven en unos minutos.', 'We are making a few adjustments. Online ordering will be back in a few minutes.')
            : t('Revisa tu conexión y vuelve a intentarlo en un momento.', 'Check your connection and try again in a moment.')}
        </p>
      </div>
      <a href="" className="press rounded-full bg-ink px-6 py-3 font-bold text-bg no-underline">
        {t('Intentar de nuevo', 'Try again')}
      </a>
    </main>
  );
}
