'use client';

import { useSyncExternalStore } from 'react';

/**
 * Estado pequeño guardado en el navegador (carrito, datos del cliente).
 * En el servidor siempre es el valor vacío; en el navegador se lee de localStorage.
 */
export function createStore<T>(key: string, empty: T) {
  let state: T | undefined;
  const listeners = new Set<() => void>();

  const read = (): T => {
    if (state !== undefined) return state;
    try {
      const raw = window.localStorage.getItem(key);
      state = raw ? ({ ...empty, ...JSON.parse(raw) } as T) : empty;
    } catch {
      state = empty;
    }
    return state;
  };

  const set = (next: T | ((prev: T) => T)) => {
    state = typeof next === 'function' ? (next as (prev: T) => T)(read()) : next;
    try {
      window.localStorage.setItem(key, JSON.stringify(state));
    } catch {
      // modo privado o sin espacio: queda solo en memoria
    }
    listeners.forEach((l) => l());
  };

  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    const onStorage = (e: StorageEvent) => {
      if (e.key !== key) return;
      state = undefined; // otra pestaña lo cambió
      listener();
    };
    window.addEventListener('storage', onStorage);
    return () => {
      listeners.delete(listener);
      window.removeEventListener('storage', onStorage);
    };
  };

  const use = () => useSyncExternalStore(subscribe, read, () => empty);
  return { use, set, get: read };
}
