import { Store } from 'lucide-react';
import { BrandMark } from './ui';

/** Pantalla cuando no se puede pedir: backend caído o restaurante en mantenimiento. */
export function Unavailable({ name, logoUrl, maintenance }: { name?: string; logoUrl?: string | null; maintenance?: boolean }) {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-6 px-6 text-center">
      {name ? <BrandMark name={name} logoUrl={logoUrl ?? null} size={56} /> : null}
      <span className="flex size-16 items-center justify-center rounded-3xl bg-brand-soft text-brand-text">
        <Store aria-hidden className="size-8" />
      </span>
      <div className="flex flex-col gap-2">
        <h1 className="text-3xl font-extrabold">{maintenance ? 'Volvemos enseguida' : 'No pudimos cargar el menú'}</h1>
        <p className="text-soft">
          {maintenance
            ? 'Estamos haciendo unos ajustes. Los pedidos en línea vuelven en unos minutos.'
            : 'Revisa tu conexión y vuelve a intentarlo en un momento.'}
        </p>
      </div>
      <a href="" className="press rounded-full bg-ink px-6 py-3 font-bold text-bg no-underline">
        Intentar de nuevo
      </a>
    </main>
  );
}
