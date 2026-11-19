import Link from 'next/link';

const BEST_SELLERS = [
  { name: 'Dominican hot dog', price: '$9.99' },
  { name: 'Dominican chimi', price: '$10.99' },
  { name: 'Special burger', price: '$15.99' },
  { name: 'Three-fongo combo', price: '$20.00' },
];

export default function SiteFooter() {
  return (
    <footer className="px-6 pb-10 lg:px-8">
      <div className="mx-auto max-w-7xl overflow-hidden rounded-[36px] border border-black/5 bg-white shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)]">
        <div className="relative h-64 w-full overflow-hidden border-b border-black/5 dark:border-white/10">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/footer-hero.jpg"
            alt="Go Picadera footer hero"
            className="h-full w-full object-cover"
          />
          <div className="absolute inset-0 bg-gradient-to-r from-black/40 via-transparent to-black/50" />
        </div>

        <div className="grid gap-10 px-8 py-10 sm:px-12 lg:grid-cols-[1fr_1fr_0.9fr]">
          <div>
            <h3 className="text-2xl font-extrabold tracking-tight text-neutral-950 dark:text-white">
              Menu
            </h3>

            <p className="mt-5 max-w-sm text-sm leading-7 text-neutral-600 dark:text-white/70">
              Dominican fast food restaurant, Dominican breakfast, Pica-pollo,
              Empanadas, Kipes, Yaroas, Dominican sandwiches, Pastas,
              Mofongos, Natural juices, Sodas y mucho más.
            </p>

            <div className="mt-6">
              <Link
                href="/menu"
                className="inline-flex items-center rounded-2xl bg-yellow-400 px-5 py-3 text-sm font-bold text-black transition hover:bg-yellow-300"
              >
                Ver menú
              </Link>
            </div>
          </div>

          <div>
            <h3 className="text-2xl font-extrabold tracking-tight text-neutral-950 dark:text-white">
              Contactos
            </h3>

            <div className="mt-5 space-y-4 text-sm text-neutral-700 dark:text-white/70">
              <p>
                <span className="font-semibold text-neutral-950 dark:text-white">
                  Phone:
                </span>{' '}
                (347) 463-9911
              </p>
              <p>
                <span className="font-semibold text-neutral-950 dark:text-white">
                  WhatsApp:
                </span>{' '}
                (929) 705-8086
              </p>
              <p>
                <span className="font-semibold text-neutral-950 dark:text-white">
                  Address:
                </span>{' '}
                4820 4th Ave, Brooklyn, NY 11220
              </p>
              <p>
                <span className="font-semibold text-neutral-950 dark:text-white">
                  Instagram:
                </span>{' '}
                @gopicadera
              </p>
            </div>
          </div>

          <div>
            <h3 className="text-2xl font-extrabold tracking-tight text-neutral-950 dark:text-white">
              Best sellers
            </h3>

            <div className="mt-5 space-y-4">
              {BEST_SELLERS.map((item) => (
                <div
                  key={item.name}
                  className="rounded-2xl bg-neutral-100 p-4 transition-colors dark:bg-white/5"
                >
                  <p className="text-sm font-semibold text-neutral-950 dark:text-white">
                    {item.name}
                  </p>
                  <p className="mt-1 text-sm text-neutral-600 dark:text-white/60">
                    {item.price}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="border-t border-black/5 px-8 py-5 text-center text-sm text-neutral-500 transition-colors dark:border-white/10 dark:text-white/45">
          © {new Date().getFullYear()} Go Picadera. All rights reserved.
        </div>
      </div>
    </footer>
  );
}