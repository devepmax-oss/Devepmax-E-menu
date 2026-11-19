import Link from 'next/link';

type Props = {
  searchParams: Promise<{
    code?: string;
  }>;
};

export default async function OrderSuccessPage({ searchParams }: Props) {
  const { code } = await searchParams;

  return (
    <main className="min-h-screen bg-black px-4 py-14 text-white">
      <section className="mx-auto flex max-w-3xl flex-col items-center text-center">
        <div className="mb-8 flex h-24 w-24 items-center justify-center rounded-full bg-yellow-400 text-5xl shadow-[0_0_60px_rgba(250,204,21,0.35)]">
          🔥
        </div>

        <div className="w-full rounded-[36px] border border-white/10 bg-neutral-950 p-8 shadow-2xl sm:p-12">
          <p className="mb-4 inline-flex rounded-full bg-yellow-400 px-4 py-2 text-xs font-black uppercase tracking-[0.24em] text-black">
            Pedido recibido
          </p>

          <h1 className="text-4xl font-black tracking-tight sm:text-6xl">
            ¡Gracias por ordenar!
          </h1>

          <p className="mx-auto mt-5 max-w-xl text-base leading-7 text-neutral-300 sm:text-lg">
            Tu pedido ya fue enviado a Go Picadera. Nuestro equipo comenzará a
            prepararlo con todo el flow dominicano.
          </p>

          {code ? (
            <div className="mx-auto mt-8 max-w-sm rounded-3xl border border-yellow-400/30 bg-yellow-400/10 p-5">
              <p className="text-sm font-semibold text-neutral-300">
                Código de tu pedido
              </p>
              <p className="mt-2 text-3xl font-black tracking-tight text-yellow-400">
                {code}
              </p>
            </div>
          ) : null}

          <div className="mt-8 grid gap-4 text-left sm:grid-cols-3">
            <div className="rounded-3xl bg-neutral-900 p-5">
              <p className="text-2xl">👨‍🍳</p>
              <h3 className="mt-3 font-bold">Preparación</h3>
              <p className="mt-1 text-sm text-neutral-400">
                Estamos revisando tu orden.
              </p>
            </div>

            <div className="rounded-3xl bg-neutral-900 p-5">
              <p className="text-2xl">⏱️</p>
              <h3 className="mt-3 font-bold">Tiempo estimado</h3>
              <p className="mt-1 text-sm text-neutral-400">
                Recibirás tu pedido lo antes posible.
              </p>
            </div>

            <div className="rounded-3xl bg-neutral-900 p-5">
              <p className="text-2xl">📱</p>
              <h3 className="mt-3 font-bold">Mantente atento</h3>
              <p className="mt-1 text-sm text-neutral-400">
                Te contactaremos si hace falta confirmar algo.
              </p>
            </div>
          </div>

          <div className="mt-10 flex flex-col gap-3 sm:flex-row">
            <Link
              href="/menu"
              className="flex-1 rounded-2xl bg-yellow-400 px-6 py-4 text-center font-black text-black transition hover:bg-yellow-300"
            >
              Volver al menú
            </Link>

            <Link
              href="/"
              className="flex-1 rounded-2xl border border-white/10 bg-neutral-900 px-6 py-4 text-center font-bold text-white transition hover:bg-neutral-800"
            >
              Ir al inicio
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}