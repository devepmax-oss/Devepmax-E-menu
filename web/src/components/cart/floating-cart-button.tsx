'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

type CartResponse = {
  items: Array<{ id: string }>;
  subtotal?: string;
};

export default function FloatingCartButton() {
  const [count, setCount] = useState(0);
  const [subtotal, setSubtotal] = useState('0.00');

  useEffect(() => {
    let cancelled = false;

    async function loadCart() {
      try {
        await Promise.resolve();

        const sessionId = localStorage.getItem('guest_session_id');
        const apiUrl = process.env.NEXT_PUBLIC_API_URL;

        if (!sessionId || !apiUrl) {
          if (!cancelled) {
            setCount(0);
            setSubtotal('0.00');
          }
          return;
        }

        const res = await fetch(`${apiUrl}/api/cart/${sessionId}`, {
          cache: 'no-store',
        });

        if (!res.ok) {
          if (!cancelled) {
            setCount(0);
            setSubtotal('0.00');
          }
          return;
        }

        const data: CartResponse = await res.json();

        if (!cancelled) {
          setCount(data.items?.length ?? 0);
          setSubtotal(data.subtotal ?? '0.00');
        }
      } catch {
        if (!cancelled) {
          setCount(0);
          setSubtotal('0.00');
        }
      }
    }

    void loadCart();

    const refresh = () => {
      void loadCart();
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

  if (count <= 0) return null;

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-4 z-50 px-4 sm:hidden">
      <Link
        href="/cart"
        className="pointer-events-auto mx-auto flex max-w-md items-center justify-between rounded-2xl bg-black px-5 py-4 text-white shadow-lg dark:bg-white dark:text-black"
      >
        <div className="flex items-center gap-3">
          <span className="text-base">🛒</span>
          <span className="text-sm font-semibold">
            {count} item{count !== 1 ? 's' : ''}
          </span>
        </div>

        <span className="text-sm font-bold">${subtotal}</span>
      </Link>
    </div>
  );
}