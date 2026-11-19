'use client';

import { useEffect, useState } from 'react';
import { deleteCartItem, getCart } from '@/lib/api';

type CartModifier = {
  id: string;
  modifierOptionId: string;
  name: string;
  priceAdjustment: string;
};

type CartItem = {
  id: string;
  quantity: number;
  unitPrice: string;
  totalPrice: string;
  baseUnitPrice: string;
  notes?: string | null;
  product: {
    id: string;
    name: string;
    imageUrl?: string | null;
  };
  modifiers: CartModifier[];
};

type CartResponse = {
  id?: string;
  sessionId: string;
  items: CartItem[];
  subtotal: string;
};

const EMPTY_CART: CartResponse = {
  sessionId: '',
  items: [],
  subtotal: '0.00',
};

export default function CartPage() {
  const [cart, setCart] = useState<CartResponse | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadCart() {
      try {
        await Promise.resolve();

        const sessionId = localStorage.getItem('guest_session_id');
        const nextCart = sessionId ? await getCart(sessionId) : EMPTY_CART;

        if (!cancelled) {
          setCart(nextCart);
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) {
          setCart(EMPTY_CART);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadCart();

    return () => {
      cancelled = true;
    };
  }, []);

  async function handleDelete(itemId: string) {
    try {
      await deleteCartItem(itemId);
      window.dispatchEvent(new Event('cart-updated'));

      const sessionId = localStorage.getItem('guest_session_id');
      const nextCart = sessionId ? await getCart(sessionId) : EMPTY_CART;
      setCart(nextCart);
    } catch (error) {
      console.error(error);
      alert('No se pudo eliminar el producto');
    }
  }

  if (loading) {
    return (
      <main className="min-h-screen bg-neutral-100 px-4 py-8 transition-colors dark:bg-black">
        <div className="mx-auto max-w-5xl text-neutral-700 dark:text-neutral-300">
          Cargando carrito...
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-neutral-100 px-4 py-8 transition-colors dark:bg-black">
      <section className="mx-auto max-w-5xl space-y-6">
        <header>
          <h1 className="text-4xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
            Tu carrito
          </h1>
          <p className="mt-1 text-base text-neutral-600 transition-colors dark:text-neutral-400">
            Revisa tu pedido antes de continuar
          </p>
        </header>

        {!cart?.items.length ? (
          <div className="rounded-3xl bg-white p-8 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10">
            <p className="text-neutral-600 transition-colors dark:text-neutral-400">
              Tu carrito está vacío.
            </p>
          </div>
        ) : (
          <>
            <div className="space-y-5">
              {cart.items.map((item) => (
                <article
                  key={item.id}
                  className="rounded-3xl bg-white p-5 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10"
                >
                  <div className="flex items-start gap-4">
                    <div className="h-28 w-28 shrink-0 overflow-hidden rounded-2xl bg-neutral-100 transition-colors dark:bg-neutral-900">
                      {item.product?.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={item.product.imageUrl}
                          alt={item.product.name}
                          className="h-full w-full object-cover"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center text-xs text-neutral-500 dark:text-neutral-400">
                          Sin imagen
                        </div>
                      )}
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="mb-2 flex items-start justify-between gap-4">
                        <h2 className="text-xl font-bold leading-tight text-neutral-950 transition-colors dark:text-neutral-100">
                          {item.product?.name ?? 'Producto'}
                        </h2>

                        <p className="shrink-0 text-2xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                          ${item.totalPrice}
                        </p>
                      </div>

                      <div className="space-y-1 text-sm text-neutral-600 transition-colors dark:text-neutral-400">
                        <p>Cantidad: {item.quantity}</p>
                        <p>Base: ${item.baseUnitPrice}</p>
                      </div>

                      {item.modifiers.length > 0 ? (
                        <div className="mt-3">
                          <p className="mb-2 text-sm font-semibold text-neutral-900 transition-colors dark:text-neutral-100">
                            Extras
                          </p>

                          <ul className="space-y-1">
                            {item.modifiers.map((modifier) => (
                              <li
                                key={modifier.id}
                                className="flex items-center justify-between gap-4 text-sm text-neutral-700 transition-colors dark:text-neutral-300"
                              >
                                <span>{modifier.name}</span>
                                <span className="font-medium">
                                  +${modifier.priceAdjustment}
                                </span>
                              </li>
                            ))}
                          </ul>
                        </div>
                      ) : null}

                      {item.notes ? (
                        <p className="mt-3 text-sm text-neutral-500 transition-colors dark:text-neutral-400">
                          Nota: {item.notes}
                        </p>
                      ) : null}
                    </div>

                    <button
                      type="button"
                      onClick={() => handleDelete(item.id)}
                      aria-label="Eliminar producto"
                      className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-red-50 text-2xl text-red-600 transition hover:bg-red-100 dark:bg-red-950/30 dark:text-red-400 dark:hover:bg-red-950/50"
                    >
                      ×
                    </button>
                  </div>
                </article>
              ))}
            </div>

            <section className="rounded-3xl bg-white p-6 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10">
              <div className="mb-5 flex items-center justify-between">
                <span className="text-lg font-medium text-neutral-600 transition-colors dark:text-neutral-400">
                  Subtotal
                </span>
                <span className="text-4xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                  ${cart.subtotal}
                </span>
              </div>

              <a
                href="/checkout"
                className="block w-full rounded-2xl bg-neutral-950 px-6 py-4 text-center text-base font-semibold text-white transition hover:opacity-90 dark:bg-white dark:text-black"
              >
                Ir al checkout
              </a>
            </section>
          </>
        )}
      </section>
    </main>
  );
}