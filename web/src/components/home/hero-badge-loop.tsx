'use client';

import { useEffect, useRef, useState } from 'react';

const PHRASES = [
  'Ordena online',
  'Entrega a domicilio',
  'Pickup disponible',
  'Personaliza tu pedido',
  'Favoritos en minutos',
];

export default function HeroBadgeLoop() {
  const [index, setIndex] = useState(0);
  const [visible, setVisible] = useState(true);

  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const interval = setInterval(() => {
      setVisible(false);

      timeoutRef.current = setTimeout(() => {
        setIndex((prev) => (prev + 1) % PHRASES.length);
        setVisible(true);
      }, 180);
    }, 2200);

    return () => {
      clearInterval(interval);

      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  return (
    <span className="inline-flex rounded-full bg-black px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-white transition-colors dark:bg-white dark:text-black">
      <span
        className={`transition-all duration-200 ${
          visible ? 'translate-y-0 opacity-100' : 'translate-y-1 opacity-0'
        }`}
      >
        {PHRASES[index]}
      </span>
    </span>
  );
}