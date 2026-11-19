'use client';

import { useMemo, useState } from 'react';
import CategorySection from '@/app/menu/category-section';
import CategoryCarousel from '@/app/menu/category-carousel';
import HeroBadgeLoop from '@/components/home/hero-badge-loop';
import { Category } from '@/lib/types';

type Props = {
  categories: Category[];
};

export default function MenuHomeClient({ categories }: Props) {
  const [query, setQuery] = useState('');

  const normalizedQuery = query.trim().toLowerCase();

  const filteredCategories = useMemo(() => {
    if (!normalizedQuery) return categories;

    return categories
      .map((category) => {
        const categoryMatch = category.name.toLowerCase().includes(normalizedQuery);

        const filteredProducts = category.products.filter((product) => {
          const nameMatch = product.name.toLowerCase().includes(normalizedQuery);
          const descriptionMatch = (product.description || '')
            .toLowerCase()
            .includes(normalizedQuery);

          return nameMatch || descriptionMatch || categoryMatch;
        });

        return {
          ...category,
          products: filteredProducts,
        };
      })
      .filter((category) => category.products.length > 0);
  }, [categories, normalizedQuery]);

  const hasResults = filteredCategories.length > 0;

  return (
    <main className="min-h-screen bg-neutral-100 transition-colors dark:bg-black">
      <section className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <header className="mb-8 space-y-6">
          <div className="space-y-3">
            <HeroBadgeLoop />

            <div className="max-w-3xl space-y-3">
              <h1 className="text-4xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100 sm:text-5xl">
                Pide tus favoritos en minutos
              </h1>

              <p className="text-base leading-7 text-neutral-600 transition-colors dark:text-neutral-400 sm:text-lg">
                Explora el menú, personaliza tus productos y realiza tu pedido
                desde cualquier dispositivo.
              </p>
            </div>
          </div>

          <div className="rounded-[28px] bg-white p-3 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10">
            <div className="flex items-center gap-3 rounded-2xl bg-neutral-100 px-4 py-4 transition-colors dark:bg-neutral-900">
              <span className="text-lg text-neutral-500 transition-colors dark:text-neutral-400">
                ⌕
              </span>

              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Buscar en el menú"
                className="w-full bg-transparent text-sm text-neutral-900 outline-none placeholder:text-neutral-500 dark:text-neutral-100 dark:placeholder:text-neutral-500"
              />

              {query ? (
                <button
                  type="button"
                  onClick={() => setQuery('')}
                  className="rounded-full px-2 py-1 text-sm text-neutral-500 transition hover:bg-neutral-200 hover:text-neutral-900 dark:text-neutral-400 dark:hover:bg-neutral-800 dark:hover:text-neutral-100"
                  aria-label="Limpiar búsqueda"
                >
                  ×
                </button>
              ) : null}
            </div>
          </div>

          <CategoryCarousel categories={filteredCategories} />
        </header>

        {hasResults ? (
          <div className="space-y-12">
            {filteredCategories.map((category) => (
              <CategorySection key={category.id} category={category} />
            ))}
          </div>
        ) : (
          <div className="rounded-[28px] bg-white p-10 text-center shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10">
            <p className="text-lg font-semibold text-neutral-950 transition-colors dark:text-neutral-100">
              No encontramos resultados
            </p>
            <p className="mt-2 text-neutral-600 transition-colors dark:text-neutral-400">
              Prueba con otro nombre de producto o categoría.
            </p>
          </div>
        )}
      </section>
    </main>
  );
}