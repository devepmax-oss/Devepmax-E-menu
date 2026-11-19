import Link from 'next/link';

export default function CateringSection() {
  return (
    <section className="px-6 pb-20 lg:px-8">
      <div className="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[1.05fr_0.95fr]">
        <div className="overflow-hidden rounded-[36px] border border-black/5 bg-white shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)]">
          <div className="aspect-video w-full bg-black">
            <video
              className="h-full w-full object-cover"
              autoPlay
              muted
              loop
              playsInline
              preload="metadata"
              poster="/catering-poster.jpg"
            >
              <source src="/catering.mp4" type="video/mp4" />
            </video>
          </div>
        </div>

        <div className="flex items-center">
          <div className="w-full rounded-[36px] border border-black/5 bg-white p-8 shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)] sm:p-10">
            <span className="inline-flex rounded-full bg-yellow-400 px-3 py-1 text-xs font-bold uppercase tracking-[0.22em] text-black">
              Catering
            </span>

            <h2 className="mt-5 text-4xl font-extrabold tracking-tight text-neutral-950 dark:text-white sm:text-5xl">
              Catering for all occasions
            </h2>

            <p className="mt-5 text-base leading-8 text-neutral-600 dark:text-white/70">
              Parties, eventos y reuniones familiares. Llevamos el sabor de Go
              Picadera a cualquier ocasión.
            </p>

            <div className="mt-8">
              <Link
                href="/menu"
                className="inline-flex items-center rounded-2xl bg-yellow-400 px-6 py-4 text-sm font-bold text-black transition hover:bg-yellow-300"
              >
                Ver menú
              </Link>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}