import { getMenu } from '@/lib/api';
import BestSellersSlider from '@/components/landing/best-sellers-slider';
import CateringSection from '@/components/landing/catering-section';
import ReviewsSection from '@/components/landing/reviews-section';
import SignupCtaSection from '@/components/landing/signup-cta-section';
import SiteFooter from '@/components/landing/site-footer';
import { Category } from '@/lib/types';

function getBestSellers(categories: Category[]) {
  return categories
    .flatMap((category) => category.products)
    .filter((product) => !!product.imageUrl)
    .slice(0, 6)
    .map((product) => ({
      id: product.id,
      name: product.name,
      price: product.price,
      imageUrl: product.imageUrl || '',
    }));
}

function FeatureCard({
  icon,
  title,
  text,
}: {
  icon: React.ReactNode;
  title: string;
  text: string;
}) {
  return (
    <div className="rounded-[28px] border border-black/5 bg-white/70 p-6 transition-colors dark:border-white/10 dark:bg-white/5">
      <div className="mb-4 inline-flex h-12 w-12 items-center justify-center rounded-2xl bg-yellow-400 text-black">
        {icon}
      </div>
      <h3 className="text-lg font-bold text-neutral-950 dark:text-white">
        {title}
      </h3>
      <p className="mt-3 text-sm leading-7 text-neutral-600 dark:text-white/70">
        {text}
      </p>
    </div>
  );
}

export default async function LandingPage() {
  const categories = await getMenu();
  const bestSellers = getBestSellers(categories);

  return (
    <main className="min-h-screen bg-neutral-100 text-neutral-950 transition-colors dark:bg-black dark:text-white">
      <section className="relative isolate overflow-hidden">
        <div className="absolute inset-0">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/hero-burger.png"
            alt="Burger hero"
            className="h-full w-full object-cover object-[center_18%]"
          />
          <div className="absolute inset-0 bg-black/25 dark:bg-black/35" />
          <div className="absolute inset-0 bg-gradient-to-t from-black/35 via-transparent to-black/20" />
        </div>

        <div className="relative mx-auto max-w-7xl px-6 pt-32 pb-24 lg:px-8 lg:pt-40 lg:pb-28">
          <div className="min-h-[420px] sm:min-h-[520px] lg:min-h-[620px]" />
        </div>
      </section>

      <section className="relative z-10 -mt-24 px-6 pb-8 lg:px-8">
        <div className="mx-auto max-w-7xl">
          <div className="rounded-[36px] border border-black/5 bg-white p-10 text-center shadow-[0_20px_80px_rgba(0,0,0,0.18)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.45)] sm:p-14">
            <p className="text-base font-semibold uppercase tracking-[0.35em] text-yellow-400 sm:text-lg">
              Sabor de RD
            </p>

              <h2 className="animate-flow-zoom text-6xl font-black uppercase leading-none tracking-tight text-neutral-950 dark:text-white sm:text-7xl lg:text-8xl">
              FLOW DE BK
            </h2>
          </div>
        </div>
      </section>

      <section
        id="best-sellers"
        className="relative z-10 px-6 pb-16 lg:px-8"
      >
        <div className="mx-auto max-w-7xl rounded-[36px] border border-black/5 bg-white p-6 shadow-[0_20px_80px_rgba(0,0,0,0.18)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.45)] sm:p-8">
          <BestSellersSlider items={bestSellers} />
        </div>
      </section>

      <section className="px-6 pb-20 lg:px-8">
        <div className="mx-auto grid max-w-7xl gap-6 md:grid-cols-2 xl:grid-cols-4">
          <FeatureCard
            icon={
              <svg viewBox="0 0 24 24" className="h-6 w-6 fill-current" aria-hidden="true">
                <path d="M17.04 7.91c-.7.43-1.8.77-2.73.67-.12-1.05.3-2.17.9-2.86.67-.78 1.84-1.34 2.78-1.39.1 1.08-.31 2.13-.95 2.86ZM19.4 17.77c-.54 1.2-.8 1.73-1.49 2.8-.96 1.48-2.31 3.33-4 3.34-1.5.02-1.88-.97-3.92-.96-2.05.01-2.46.98-3.96.97-1.69-.02-2.96-1.69-3.92-3.17C-.55 16.8-.82 11.93 1.3 8.67c1.5-2.3 3.86-3.65 6.08-3.65 1.8 0 2.94.99 4.43.99 1.45 0 2.34-.99 4.42-.99 1.98 0 4.07 1.08 5.56 2.95-4.9 2.69-4.1 9.7-2.39 11.8Z" />
              </svg>
            }
            title="Easy way to pay"
            text="Ordena en segundos, paga fácil y disfruta el sabor."
          />

          <FeatureCard
            icon={
              <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current" aria-hidden="true">
                <path d="M12 1.75A10.25 10.25 0 1 0 22.25 12 10.26 10.26 0 0 0 12 1.75Zm0 18.75A8.5 8.5 0 1 1 20.5 12 8.51 8.51 0 0 1 12 20.5Zm.88-13h-1.76v5.13l4.1 2.46.9-1.5-3.24-1.94Z" />
              </svg>
            }
            title="Fast & fresh"
            text="Siempre rápido. Siempre fresco."
          />

          <FeatureCard
            icon={
              <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current" aria-hidden="true">
                <path d="M19.5 8.25A7.49 7.49 0 0 0 12 2a7.5 7.5 0 0 0-7.5 7.5c0 4.5 6.36 10.79 6.63 11.05a1.25 1.25 0 0 0 1.74 0c.27-.26 6.63-6.55 6.63-11.05a7.4 7.4 0 0 0-.29-1.25h-1.84A5.75 5.75 0 0 1 18 9.5c0 2.86-3.72 7.17-6 9.48-2.28-2.31-6-6.62-6-9.48A5.75 5.75 0 0 1 12 3.75a5.71 5.71 0 0 1 5.44 4h-2.69l3.5 3.75 3.5-3.75Z" />
              </svg>
            }
            title="Authentic Dominican Flavor"
            text="Fast food con identidad real y sabor dominicano."
          />

          <FeatureCard
            icon={
              <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current" aria-hidden="true">
                <path d="M12 2a1 1 0 0 1 1 1v1.1A8 8 0 1 1 4.1 13H3a1 1 0 0 1 0-2h3.5A1.5 1.5 0 0 1 8 12.5V16a1 1 0 0 1-2 0v-1.89A6 6 0 1 0 13 6.1V7a1 1 0 0 1-2 0V3a1 1 0 0 1 1-1Z" />
              </svg>
            }
            title="On-time orders"
            text="Pedidos a tiempo con una experiencia simple y moderna."
          />
        </div>
      </section>

      <CateringSection />
      <ReviewsSection />
      <SignupCtaSection />
      <SiteFooter />
    </main>
  );
}