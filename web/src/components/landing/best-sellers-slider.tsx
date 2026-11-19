'use client';

import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';

type BestSeller = {
  id: string;
  name: string;
  price: string;
  imageUrl: string;
};

type Props = {
  items: BestSeller[];
};

export default function BestSellersSlider({ items }: Props) {
  const ref = useRef<HTMLDivElement | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [activeIndex, setActiveIndex] = useState(0);

  const cardWidth = 290;
  const safeItems = useMemo(() => items.filter((item) => !!item.imageUrl), [items]);

  function updateActiveIndex() {
    const container = ref.current;
    if (!container) return;

    const index = Math.round(container.scrollLeft / cardWidth);
    setActiveIndex(Math.max(0, Math.min(index, safeItems.length - 1)));
  }

  function goToIndex(index: number) {
    const container = ref.current;
    if (!container) return;

    const bounded = Math.max(0, Math.min(index, safeItems.length - 1));
    container.scrollTo({
      left: bounded * cardWidth,
      behavior: 'smooth',
    });
    setActiveIndex(bounded);
  }

  function scrollLeft() {
    goToIndex(activeIndex - 1);
  }

  function scrollRight() {
    if (activeIndex >= safeItems.length - 1) {
      goToIndex(0);
      return;
    }

    goToIndex(activeIndex + 1);
  }

  function startAutoScroll() {
    if (intervalRef.current || safeItems.length <= 1) return;

    intervalRef.current = setInterval(() => {
      scrollRight();
    }, 3200);
  }

  function stopAutoScroll() {
    if (!intervalRef.current) return;
    clearInterval(intervalRef.current);
    intervalRef.current = null;
  }

  useEffect(() => {
    startAutoScroll();
    return () => stopAutoScroll();
  }, [activeIndex, safeItems.length]);

  if (!safeItems.length) return null;

  return (
    <section className="relative">
      <div className="mb-6 flex items-end justify-between gap-4">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.25em] text-yellow-400">
            Best sellers
          </p>
        </div>

        <div className="hidden items-center gap-3 md:flex">
          <button
            type="button"
            onClick={scrollLeft}
            className="flex h-11 w-11 items-center justify-center rounded-full border border-yellow-400/20 bg-neutral-100 text-yellow-500 transition hover:bg-neutral-200 dark:bg-white/5 dark:text-yellow-400 dark:hover:bg-white/10"
            aria-label="Anterior"
          >
            ‹
          </button>
          <button
            type="button"
            onClick={scrollRight}
            className="flex h-11 w-11 items-center justify-center rounded-full border border-yellow-400/20 bg-neutral-100 text-yellow-500 transition hover:bg-neutral-200 dark:bg-white/5 dark:text-yellow-400 dark:hover:bg-white/10"
            aria-label="Siguiente"
          >
            ›
          </button>
        </div>
      </div>

      <div
        ref={ref}
        onMouseEnter={stopAutoScroll}
        onMouseLeave={startAutoScroll}
        onScroll={updateActiveIndex}
        className="flex snap-x snap-mandatory gap-5 overflow-x-auto pb-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {safeItems.map((item) => (
          <article
            key={item.id}
            className="min-w-[270px] snap-start overflow-hidden rounded-[30px] border border-yellow-400/20 bg-neutral-100 p-4 shadow-[0_0_0_1px_rgba(250,204,21,0.08)] transition-colors dark:bg-[#0a0a0a]"
          >
            <div className="overflow-hidden rounded-[24px] bg-white dark:bg-black">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={item.imageUrl}
                alt={item.name}
                className="h-52 w-full object-cover transition duration-500 hover:scale-[1.05]"
              />
            </div>

            <div className="mt-4 flex items-start justify-between gap-3">
              <div>
                <h3 className="text-base font-bold text-neutral-950 dark:text-white">
                  {item.name}
                </h3>
                <p className="mt-1 text-sm text-neutral-600 dark:text-white/70">
                  ${item.price}
                </p>
              </div>

              <Link
                href={`/product/${item.id}`}
                className="inline-flex h-9 w-9 items-center justify-center rounded-full bg-yellow-400 text-lg font-bold text-black transition hover:bg-yellow-300"
                aria-label={`Ver ${item.name}`}
              >
                +
              </Link>
            </div>
          </article>
        ))}
      </div>

      <div className="mt-6 flex items-center justify-center gap-2">
        {safeItems.map((item, index) => (
          <button
            key={item.id}
            type="button"
            onClick={() => goToIndex(index)}
            aria-label={`Ir al slide ${index + 1}`}
            className={`h-2.5 rounded-full transition-all ${
              activeIndex === index
                ? 'w-8 bg-yellow-400'
                : 'w-2.5 bg-neutral-300 dark:bg-white/20'
            }`}
          />
        ))}
      </div>
    </section>
  );
}