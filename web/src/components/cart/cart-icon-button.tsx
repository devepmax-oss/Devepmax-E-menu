'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

type CartResponse = {
  items: Array<{ id: string }>;
};

export default function CartIconButton() {
  const [count, setCount] = useState(0);
  const [animate, setAnimate] = useState(false);

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

    const handleCartUpdated = () => {
      setAnimate(true);
      void loadCartCount();

      window.setTimeout(() => {
        setAnimate(false);
      }, 550);
    };

    window.addEventListener('focus', refresh);
    window.addEventListener('storage', refresh);
    window.addEventListener('cart-updated', handleCartUpdated as EventListener);

    return () => {
      cancelled = true;
      window.removeEventListener('focus', refresh);
      window.removeEventListener('storage', refresh);
      window.removeEventListener('cart-updated', handleCartUpdated as EventListener);
    };
  }, []);

  return (
    <Link
      href="/cart"
      aria-label="Ver carrito"
      className="relative flex h-12 w-12 items-center justify-center rounded-2xl border border-neutral-200 bg-white text-neutral-900 transition hover:bg-neutral-50 dark:border-neutral-800 dark:bg-neutral-950 dark:text-neutral-100 dark:hover:bg-neutral-900"
    >
      <span
        className={`text-xl transition-transform duration-300 ${
          animate ? 'scale-125 -translate-y-0.5' : 'scale-100'
        }`}
      >
        🛒
      </span>

      {count > 0 ? (
        <span
          className={`absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-bold text-black transition-all duration-300 ${
            animate ? 'scale-125' : 'scale-100'
          } bg-yellow-400`}
        >
          {count}
        </span>
      ) : null}
    </Link>
  );
}