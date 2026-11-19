'use client';

type Review = {
  id: number;
  name: string;
  time: string;
  text: string;
  rating: number;
};

const REVIEWS: Review[] = [
  {
    id: 1,
    name: 'Dara Fernández',
    time: '4 months ago',
    rating: 5,
    text: 'Muy bueno y las porciones son generosas.',
  },
  {
    id: 2,
    name: 'Dani',
    time: '5 months ago',
    rating: 5,
    text: 'Excelente servicio al cliente y la comida estuvo muy sabrosa.',
  },
  {
    id: 3,
    name: 'Nathaly Jiménez',
    time: '5 months ago',
    rating: 5,
    text: 'La comida está en su punto, muy deliciosa y el servicio excelente.',
  },
  {
    id: 4,
    name: 'Edy Suarez',
    time: '5 months ago',
    rating: 5,
    text: 'Muy buena atención y el sabor fue excepcional.',
  },
];

function Stars({ count }: { count: number }) {
  return (
    <div className="flex items-center gap-1">
      {Array.from({ length: count }).map((_, index) => (
        <span key={index} className="text-sm text-yellow-400">
          ★
        </span>
      ))}
    </div>
  );
}

export default function ReviewsSection() {
  return (
    <section className="px-6 pb-20 lg:px-8">
      <div className="mx-auto max-w-7xl overflow-hidden rounded-[36px] border border-black/5 bg-white shadow-[0_20px_80px_rgba(0,0,0,0.12)] transition-colors dark:border-white/10 dark:bg-[#050505] dark:shadow-[0_20px_80px_rgba(0,0,0,0.35)]">
        <div className="bg-yellow-400 px-8 py-8 text-center sm:px-12">
          <h2 className="text-4xl font-extrabold tracking-tight text-black sm:text-5xl">
            What our customers say
          </h2>
        </div>

        <div className="grid gap-10 px-8 py-10 sm:px-12 lg:grid-cols-[0.36fr_0.64fr]">
          <div className="rounded-[28px] bg-neutral-100 p-6 transition-colors dark:bg-white/5">
            <p className="text-xs font-bold uppercase tracking-[0.25em] text-neutral-500 dark:text-white/50">
              Excellent
            </p>

            <div className="mt-4">
              <Stars count={5} />
            </div>

            <p className="mt-4 text-4xl font-extrabold tracking-tight text-neutral-950 dark:text-white">
              4.9
            </p>

            <p className="mt-2 text-sm text-neutral-600 dark:text-white/65">
              Based on 84 reviews
            </p>

            <div className="mt-6 inline-flex items-center rounded-full bg-white px-4 py-2 text-sm font-semibold text-neutral-950 shadow-sm dark:bg-neutral-900 dark:text-white">
              Google
            </div>
          </div>

          <div>
            <div className="mb-8 text-center">
              <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-yellow-400 text-sm font-bold text-black">
                CL
              </div>

              <p className="mt-4 text-lg font-bold text-neutral-950 dark:text-white">
                Carol Lizeth
              </p>
              <p className="text-sm text-neutral-500 dark:text-white/50">
                Happy client
              </p>

              <p className="mx-auto mt-5 max-w-3xl text-xl leading-9 text-neutral-700 dark:text-white/80">
                Este lugar fue realmente increíble. Desde las entradas hasta las
                bebidas, los platos fuertes deliciosos y todo estaba preparado a
                la perfección.
              </p>
            </div>

            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              {REVIEWS.map((review) => (
                <article
                  key={review.id}
                  className="rounded-[24px] border border-black/5 bg-neutral-100 p-4 transition-colors dark:border-white/10 dark:bg-white/5"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-sm font-semibold text-neutral-950 dark:text-white">
                        {review.name}
                      </p>
                      <p className="text-xs text-neutral-500 dark:text-white/50">
                        {review.time}
                      </p>
                    </div>

                    <div className="inline-flex h-8 w-8 items-center justify-center rounded-full bg-white text-xs font-bold text-neutral-900 dark:bg-neutral-900 dark:text-white">
                      G
                    </div>
                  </div>

                  <div className="mt-3">
                    <Stars count={review.rating} />
                  </div>

                  <p className="mt-4 text-sm leading-6 text-neutral-700 dark:text-white/70">
                    {review.text}
                  </p>
                </article>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}