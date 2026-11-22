import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-5 px-6 text-center">
      <span className="font-heading text-6xl font-extrabold text-brand-text">404</span>
      <h1 className="m-0 text-2xl font-extrabold">No encontramos esa página</h1>
      <p className="m-0 text-soft">Si buscas un pedido, revisa que el enlace esté completo.</p>
      <Link href="/" className="press rounded-full bg-brand px-6 py-3 font-bold text-on-brand no-underline">
        Ir al menú
      </Link>
    </main>
  );
}
