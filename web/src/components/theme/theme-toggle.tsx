'use client';

import { useTheme } from 'next-themes';

export default function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();

  const isDark = resolvedTheme === 'dark';

  return (
    <button
      type="button"
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      aria-label="Cambiar tema"
      className="flex h-12 w-12 items-center justify-center rounded-2xl border border-neutral-200 bg-white text-xl text-neutral-900 transition hover:bg-neutral-50 dark:border-neutral-800 dark:bg-neutral-950 dark:text-neutral-100 dark:hover:bg-neutral-900"
    >
      {isDark ? '☀' : '☾'}
    </button>
  );
}