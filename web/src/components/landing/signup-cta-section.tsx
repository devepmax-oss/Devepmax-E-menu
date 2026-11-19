import Link from 'next/link';

export default function SignupCtaSection() {
  return (
    <section className="px-6 pb-20 lg:px-8">
      <div className="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="overflow-hidden rounded-[36px] border border-black/5 bg-white shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)]">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/signup-food.jpg"
            alt="Go Picadera promo"
            className="h-full w-full object-cover"
          />
        </div>

        <div className="flex items-center">
          <div className="w-full rounded-[36px] border border-black/5 bg-white p-8 shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)] sm:p-10">
            <span className="inline-flex rounded-full bg-yellow-400 px-3 py-1 text-xs font-bold uppercase tracking-[0.22em] text-black">
              Promoción
            </span>

            <h2 className="mt-5 text-4xl font-extrabold tracking-tight text-neutral-950 dark:text-white sm:text-5xl">
              Would you like free food?
            </h2>

            <p className="mt-5 text-base leading-8 text-neutral-600 dark:text-white/70">
              Regístrate para recibir novedades, promociones y beneficios
              exclusivos de Go Picadera.
            </p>

            <div className="mt-8 flex flex-wrap gap-4">
              <Link
                href="/menu"
                className="inline-flex items-center rounded-2xl bg-yellow-400 px-6 py-4 text-sm font-bold text-black transition hover:bg-yellow-300"
              >
                Sign up
              </Link>

              <a
                href="https://wa.me/19297058086"
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center rounded-2xl border border-black/10 px-6 py-4 text-sm font-semibold text-neutral-950 transition hover:bg-neutral-100 dark:border-white/10 dark:text-white dark:hover:bg-white/5"
              >
                Contactar
              </a>
            </div>

            <p className="mt-5 text-sm text-neutral-500 dark:text-white/50">
              Puedes registrarte o escribirnos directamente por WhatsApp.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}