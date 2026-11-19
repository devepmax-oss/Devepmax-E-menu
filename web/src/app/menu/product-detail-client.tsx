'use client';

import { useMemo, useState } from 'react';
import { ProductDetail } from '@/lib/types';

type Props = {
  product: ProductDetail;
};

export default function ProductDetailClient({ product }: Props) {
  const [selected, setSelected] = useState<Record<string, string[]>>({});
  const [quantity, setQuantity] = useState(1);

  function toggleOption(
    groupId: string,
    optionId: string,
    selectionType: 'single' | 'multiple',
  ) {
    setSelected((prev) => {
      const current = prev[groupId] || [];

      if (selectionType === 'single') {
        return {
          ...prev,
          [groupId]: [optionId],
        };
      }

      const exists = current.includes(optionId);

      return {
        ...prev,
        [groupId]: exists
          ? current.filter((id) => id !== optionId)
          : [...current, optionId],
      };
    });
  }

  const selectedModifierTotal = useMemo(() => {
    let total = 0;

    for (const group of product.modifierGroups) {
      const selectedIds = selected[group.id] || [];

      for (const option of group.options) {
        if (selectedIds.includes(option.id)) {
          total += Number(option.priceAdjustment || 0);
        }
      }
    }

    return total;
  }, [product.modifierGroups, selected]);

  const basePrice = Number(product.price || 0);

  const hasAnySelection = useMemo(() => {
    return Object.values(selected).some((ids) => ids.length > 0);
  }, [selected]);

  const missingRequiredGroup = useMemo(() => {
    return product.modifierGroups.some((group) => {
      if (!group.isRequired) return false;
      const selectedIds = selected[group.id] || [];
      return selectedIds.length < group.minSelect;
    });
  }, [product.modifierGroups, selected]);

  const unitPrice = basePrice + selectedModifierTotal;
  const total = unitPrice * quantity;

  const showSelectionMessage =
    basePrice === 0 && !hasAnySelection && product.modifierGroups.length > 0;

  async function handleAddToCart() {
    if (missingRequiredGroup) {
      alert('Debes completar las opciones requeridas antes de continuar');
      return;
    }

    if (unitPrice <= 0) {
      alert('Selecciona una opción válida antes de agregar al carrito');
      return;
    }

    const sessionId =
      localStorage.getItem('guest_session_id') || `guest-${crypto.randomUUID()}`;

    localStorage.setItem('guest_session_id', sessionId);

    const modifierOptionIds = Object.values(selected).flat();

    const res = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/api/cart/items`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sessionId,
        productId: product.id,
        quantity,
        modifierOptionIds,
        notes: '',
      }),
    });

    if (!res.ok) {
      alert('No se pudo agregar al carrito');
      return;
    }

    window.dispatchEvent(new Event('cart-updated'));
    window.location.href = '/cart';
  }

  return (
    <main className="min-h-screen bg-neutral-100 transition-colors dark:bg-black">
      <section className="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 gap-10 lg:grid-cols-[1fr_520px]">
          <div className="overflow-hidden rounded-[32px] bg-white shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10">
            {product.imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={product.imageUrl}
                alt={product.name}
                className="h-[340px] w-full object-contain bg-neutral-50 transition-transform duration-300 hover:scale-[1.03] dark:bg-neutral-900 sm:h-[460px] lg:h-[680px]"
              />
            ) : (
              <div className="flex h-[340px] items-center justify-center text-sm text-neutral-500 transition-colors dark:text-neutral-400 sm:h-[460px] lg:h-[680px]">
                Sin imagen
              </div>
            )}
          </div>

          <div className="lg:sticky lg:top-24 lg:self-start">
            <div className="rounded-[32px] bg-white p-6 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10 sm:p-8">
              <div className="mb-8">
                <p className="mb-3 text-xs font-semibold uppercase tracking-[0.22em] text-neutral-500 transition-colors dark:text-neutral-400">
                  {product.category.name}
                </p>

                <h1 className="text-4xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                  {product.name}
                </h1>

                {product.description ? (
                  <p className="mt-4 text-lg leading-8 text-neutral-600 transition-colors dark:text-neutral-400">
                    {product.description}
                  </p>
                ) : null}
              </div>

              <div className="mb-8 flex items-center justify-between border-b border-neutral-200 pb-6 transition-colors dark:border-white/10">
                <span className="text-sm font-medium text-neutral-500 transition-colors dark:text-neutral-400">
                  Precio base
                </span>

                <span className="text-3xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                  ${basePrice.toFixed(2)}
                </span>
              </div>

              <div className="space-y-8">
                {product.modifierGroups.map((group) => (
                  <section key={group.id}>
                    <div className="mb-4">
                      <h2 className="text-xl font-bold text-neutral-950 transition-colors dark:text-neutral-100">
                        {group.name}
                      </h2>

                      <p className="mt-1 text-sm text-neutral-500 transition-colors dark:text-neutral-400">
                        {group.selectionType === 'single'
                          ? 'Selecciona una opción'
                          : 'Puedes seleccionar varias opciones'}
                        {group.isRequired ? ' · Requerido' : ''}
                      </p>
                    </div>

                    <div className="space-y-3">
                      {group.options.map((option) => {
                        const selectedIds = selected[group.id] || [];
                        const isSelected = selectedIds.includes(option.id);
                        const adjustment = Number(option.priceAdjustment || 0);

                        return (
                          <button
                            key={option.id}
                            type="button"
                            onClick={() =>
                              toggleOption(group.id, option.id, group.selectionType)
                            }
                            className={`flex w-full items-center justify-between rounded-2xl border px-4 py-4 text-left transition ${
                              isSelected
                                ? 'border-neutral-950 bg-neutral-950 text-white dark:border-white dark:bg-white dark:text-black'
                                : 'border-neutral-200 bg-white text-neutral-950 hover:border-neutral-400 dark:border-white/10 dark:bg-neutral-950 dark:text-neutral-100 dark:hover:border-neutral-600'
                            }`}
                          >
                            <span className="pr-4 text-sm font-semibold">
                              {option.name}
                            </span>

                            <span className="shrink-0 text-sm font-medium">
                              {adjustment > 0
                                ? `+$${adjustment.toFixed(2)}`
                                : 'Incluido'}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  </section>
                ))}
              </div>

              <div className="mt-10 border-t border-neutral-200 pt-6 transition-colors dark:border-white/10">
                <div className="mb-5 flex items-center justify-between">
                  <span className="text-sm font-medium text-neutral-500 transition-colors dark:text-neutral-400">
                    Cantidad
                  </span>

                  <div className="flex items-center gap-3">
                    <button
                      type="button"
                      onClick={() => setQuantity((q) => Math.max(1, q - 1))}
                      className="flex h-11 w-11 items-center justify-center rounded-2xl border border-neutral-300 text-xl text-neutral-950 transition hover:bg-neutral-50 dark:border-neutral-700 dark:text-neutral-100 dark:hover:bg-neutral-900"
                    >
                      −
                    </button>

                    <span className="min-w-8 text-center text-lg font-bold text-neutral-950 transition-colors dark:text-neutral-100">
                      {quantity}
                    </span>

                    <button
                      type="button"
                      onClick={() => setQuantity((q) => q + 1)}
                      className="flex h-11 w-11 items-center justify-center rounded-2xl border border-neutral-300 text-xl text-neutral-950 transition hover:bg-neutral-50 dark:border-neutral-700 dark:text-neutral-100 dark:hover:bg-neutral-900"
                    >
                      +
                    </button>
                  </div>
                </div>

                <div className="mb-6 space-y-3 rounded-2xl bg-neutral-100 p-4 transition-colors dark:bg-neutral-900">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-neutral-600 transition-colors dark:text-neutral-400">
                      Opciones seleccionadas
                    </span>
                    <span className="font-semibold text-neutral-950 transition-colors dark:text-neutral-100">
                      ${selectedModifierTotal.toFixed(2)}
                    </span>
                  </div>

                  <div className="flex items-center justify-between">
                    <span className="text-base font-medium text-neutral-700 transition-colors dark:text-neutral-300">
                      Total
                    </span>

                    <span className="text-3xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                      {showSelectionMessage ? '—' : `$${total.toFixed(2)}`}
                    </span>
                  </div>
                </div>

                {showSelectionMessage ? (
                  <p className="mb-4 text-sm text-neutral-500 transition-colors dark:text-neutral-400">
                    Selecciona una opción para calcular el precio.
                  </p>
                ) : null}

                <button
                  type="button"
                  onClick={handleAddToCart}
                  className="w-full rounded-2xl bg-neutral-950 px-5 py-4 text-base font-semibold text-white transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60 dark:bg-white dark:text-black"
                  disabled={missingRequiredGroup || unitPrice <= 0}
                >
                  Agregar al carrito
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}