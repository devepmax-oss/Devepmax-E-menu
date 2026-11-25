import Link from 'next/link';
import { pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';

export default async function NotFound() {
  const lang = await getLang();
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-5 px-6 text-center">
      <span className="font-heading text-6xl font-extrabold text-brand-text">404</span>
      <h1 className="m-0 text-2xl font-extrabold">{pick(lang, 'No encontramos esa página', 'We could not find that page')}</h1>
      <p className="m-0 text-soft">{pick(lang, 'Si buscas un pedido, revisa que el enlace esté completo.', 'If you are looking for an order, check that the link is complete.')}</p>
      <Link href="/" className="press rounded-full bg-brand px-6 py-3 font-bold text-on-brand no-underline">
        {pick(lang, 'Ir al menú', 'Go to the menu')}
      </Link>
    </main>
  );
}
