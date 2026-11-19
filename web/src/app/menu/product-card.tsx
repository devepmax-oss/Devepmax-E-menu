'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Product } from '@/lib/types';

type Props = {
  product: Product;
};

export default function ProductCard({ product }: Props) {
  const [adding, setAdding] = useState(false);
  const [added, setAdded] = useState(false);

  const price = Number(product.price || 0);
  const hasPrice = !Number.isNaN(price) && price > 0;
  const hasModifiers =
    Array.isArray(product.modifierGroups) && product.modifierGroups.length > 0;

  async function handleQuickAdd() {
    if (adding) return;

    try {
      setAdding(true);

      const sessionId =
        localStorage.getItem('guest_session_id') || `guest-${crypto.randomUUID()}`;

      localStorage.setItem('guest_session_id', sessionId);

      const res = await fetch(`${process.env.NEXT_PUBLIC_API_URL}/api/cart/items`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sessionId,
          productId: product.id,
          quantity: 1,
          modifierOptionIds: [],
          notes: '',
        }),
      });

      if (!res.ok) {
        alert('No se pudo agregar al carrito');
        return;
      }

      window.dispatchEvent(new Event('cart-updated'));
      setAdded(true);

      window.setTimeout(() => {
        setAdded(false);
      }, 1500);
    } catch (error) {
      console.error(error);
      alert('No se pudo agregar al carrito');
    } finally {
      setAdding(false);
    }
  }

  return (
    <article className="group overflow-hidden rounded-[30px] border border-black/5 bg-white p-3 shadow-[0_16px_40px_rgba(0,0,0,0.08)] transition-all duration-300 hover:-translate-y-1 hover:shadow-[0_22px_55px_rgba(0,0,0,0.14)] dark:border-white/10 dark:bg-[#080808] dark:shadow-[0_18px_40px_rgba(0,0,0,0.34)] dark:hover:shadow-[0_24px_60px_rgba(0,0,0,0.48)]">
      <Link href={`/product/${product.id}`} className="block">
        <div className="relative overflow-hidden rounded-[24px] bg-neutral-100 dark:bg-neutral-900">
          {product.imageUrl ? (
            <>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={product.imageUrl}
                alt={product.name}
                className="h-64 w-full object-cover transition duration-500 group-hover:scale-[1.05]"
              />
              <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/18 via-transparent to-transparent opacity-70 transition duration-300 group-hover:opacity-100" />
            </>
          ) : (
            <div className="flex h-64 items-center justify-center text-sm text-neutral-500 dark:text-neutral-400">
              Sin imagen
            </div>
          )}

          {hasPrice ? (
            <div className="absolute right-4 top-4 rounded-full bg-black/75 px-3 py-1 text-sm font-bold text-white backdrop-blur dark:bg-yellow-400 dark:text-black">
              ${price.toFixed(2)}
            </div>
          ) : null}
        </div>
      </Link>

      <div className="px-2 pb-2 pt-4">
        <h3 className="line-clamp-2 text-2xl font-extrabold tracking-tight text-neutral-950 dark:text-white">
          {product.name}
        </h3>

        {product.description ? (
          <p className="mt-3 line-clamp-3 text-[15px] leading-7 text-neutral-600 dark:text-white/65">
            {product.description
              .replace(/&nbsp;|\\n|<\/?p>/g, ' ')
              .replace(/\s+/g, ' ')
              .trim()}
          </p>
        ) : null}

        <div className="mt-5 flex items-center justify-end gap-4">
          {hasModifiers ? (
            <Link
              href={`/product/${product.id}`}
              className="inline-flex items-center gap-2 rounded-2xl bg-yellow-400 px-5 py-3 text-sm font-bold text-black transition hover:bg-yellow-300"
            >
              <span>Personalizar</span>
              <span className="text-base">→</span>
            </Link>
          ) : (
            <button
              type="button"
              onClick={handleQuickAdd}
              disabled={adding}
              className={`inline-flex items-center gap-2 rounded-2xl px-5 py-3 text-sm font-bold transition ${
                added
                  ? 'bg-green-500 text-white'
                  : 'bg-yellow-400 text-black hover:bg-yellow-300'
              } ${adding ? 'cursor-not-allowed opacity-70' : ''}`}
            >
              <span>
                {adding ? 'Agregando...' : added ? 'Agregado' : 'Agregar'}
              </span>
              <span className="text-base">
                {adding ? '…' : added ? '✓' : '+'}
              </span>
            </button>
          )}
        </div>
      </div>
    </article>
  );
}