'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

type CartResponse = {
  items: Array<{ id: string }>;
};

export default function CartButton() {
  const [count, setCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function loadCartCount() {
      try {
        await Promise.resolve();

        const sessionId = localStorage.getItem('guest_session_id');
        const apiUrl = process.env.NEXT_PUBLIC_API_URL;

        if (!sessionId || !apiUrl) {
          if (!cancelled) {
            setCount(0);
          }
          return;
        }

        const res = await fetch(`${apiUrl}/api/cart/${sessionId}`, {
          cache: 'no-store',
        });

        if (!res.ok) {
          if (!cancelled) {
            setCount(0);
          }
          return;
        }

        const data: CartResponse = await res.json();

        if (!cancelled) {
          setCount(data.items?.length ?? 0);
        }
      } catch {
        if (!cancelled) {
          setCount(0);
        }
      }
    }

    void loadCartCount();

    const refresh = () => {
      void loadCartCount();
    };

    window.addEventListener('focus', refresh);
    window.addEventListener('storage', refresh);
    window.addEventListener('cart-updated', refresh as EventListener);

    return () => {
      cancelled = true;
      window.removeEventListener('focus', refresh);
      window.removeEventListener('storage', refresh);
      window.removeEventListener('cart-updated', refresh as EventListener);
    };
  }, []);

  return (
    <Link
      href="/cart"
      aria-label="Ver carrito"
      className="relative inline-flex h-12 min-w-12 items-center justify-center rounded-2xl bg-black px-4 text-sm font-semibold text-white transition hover:opacity-90 dark:bg-white dark:text-black"
    >
      <span className="text-base">Carrito</span>

      {count > 0 ? (
        <span className="absolute -right-2 -top-2 flex h-7 min-w-7 items-center justify-center rounded-full bg-red-600 px-2 text-xs font-bold text-white">
          {count}
        </span>
      ) : null}
    </Link>
  );
}