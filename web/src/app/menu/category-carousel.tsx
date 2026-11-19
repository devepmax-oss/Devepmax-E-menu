'use client';

import { useMemo, useRef } from 'react';

type CategoryProduct = {
  id: string;
  imageUrl: string | null;
};

type Category = {
  id: string;
  name: string;
  isActive: boolean;
  products: CategoryProduct[];
};

type Props = {
  categories: Category[];
};

function getFallbackIcon(name: string) {
  const value = name.toLowerCase();

  if (value.includes('breakfast')) return '🍳';
  if (value.includes('burger')) return '🍔';
  if (value.includes('sandwich')) return '🥪';
  if (value.includes('pizza')) return '🍕';
  if (value.includes('drink')) return '🥤';
  if (value.includes('bebida')) return '🥤';
  if (value.includes('juice')) return '🧃';
  if (value.includes('coffee')) return '☕';
  if (value.includes('dessert')) return '🍰';
  if (value.includes('postre')) return '🍰';
  if (value.includes('chicken')) return '🍗';
  if (value.includes('pollo')) return '🍗';
  if (value.includes('salad')) return '🥗';
  if (value.includes('healthy')) return '🥗';
  if (value.includes('mex')) return '🌮';
  if (value.includes('taco')) return '🌮';
  if (value.includes('asian')) return '🍜';
  if (value.includes('china')) return '🥡';
  if (value.includes('rice')) return '🍚';
  if (value.includes('combo')) return '🍽️';
  if (value.includes('snack')) return '🍟';
  return '🍴';
}

export default function CategoryCarousel({ categories }: Props) {
  const scrollRef = useRef<HTMLDivElement | null>(null);

  const items = useMemo(() => {
    return categories.map((category) => {
      const previewImage =
        category.products.find((product) => product.imageUrl)?.imageUrl ?? null;

      return {
        ...category,
        previewImage,
      };
    });
  }, [categories]);

  function scrollToCategory(categoryId: string) {
    const element = document.getElementById(`category-${categoryId}`);
    if (!element) return;

    const y = element.getBoundingClientRect().top + window.scrollY - 110;

    window.scrollTo({
      top: y,
      behavior: 'smooth',
    });
  }

  function scrollLeft() {
    scrollRef.current?.scrollBy({
      left: -320,
      behavior: 'smooth',
    });
  }

  function scrollRight() {
    scrollRef.current?.scrollBy({
      left: 320,
      behavior: 'smooth',
    });
  }

  if (!items.length) return null;

  return (
    <div className="relative">
      {items.length > 6 ? (
        <button
          type="button"
          onClick={scrollLeft}
          aria-label="Desplazar categorías a la izquierda"
          className="absolute left-0 top-1/2 z-10 hidden h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border border-black/5 bg-white text-xl text-neutral-900 shadow-sm transition hover:bg-neutral-50 dark:border-white/10 dark:bg-neutral-950 dark:text-neutral-100 dark:hover:bg-neutral-900 md:flex"
        >
          ‹
        </button>
      ) : null}

      <div
        ref={scrollRef}
        className="flex gap-3 overflow-x-auto px-1 py-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {items.map((category) => (
          <button
            key={category.id}
            type="button"
            onClick={() => scrollToCategory(category.id)}
            className="group flex w-[108px] shrink-0 flex-col items-center gap-3 rounded-[28px] border border-black/5 bg-white px-3 py-4 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md dark:border-white/10 dark:bg-neutral-950"
          >
            <div className="flex h-16 w-16 items-center justify-center overflow-hidden rounded-full bg-neutral-100 transition-colors dark:bg-neutral-900">
              {category.previewImage ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={category.previewImage}
                  alt={category.name}
                  className="h-full w-full object-cover transition duration-300 group-hover:scale-105"
                />
              ) : (
                <span className="text-3xl">{getFallbackIcon(category.name)}</span>
              )}
            </div>

            <span className="line-clamp-2 text-center text-sm font-medium leading-tight text-neutral-900 transition-colors dark:text-neutral-100">
              {category.name}
            </span>
          </button>
        ))}
      </div>

      {items.length > 6 ? (
        <button
          type="button"
          onClick={scrollRight}
          aria-label="Desplazar categorías a la derecha"
          className="absolute right-0 top-1/2 z-10 hidden h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full border border-black/5 bg-white text-xl text-neutral-900 shadow-sm transition hover:bg-neutral-50 dark:border-white/10 dark:bg-neutral-950 dark:text-neutral-100 dark:hover:bg-neutral-900 md:flex"
        >
          ›
        </button>
      ) : null}
    </div>
  );
}