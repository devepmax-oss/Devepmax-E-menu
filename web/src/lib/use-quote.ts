'use client';

import { useEffect, useState } from 'react';
import { api, ApiError } from './api';
import type { FulfillmentType, OrderLineInput, Quote } from './types';

/**
 * Cotización real del servidor (precios, promociones, impuesto y envío) cada vez que
 * cambia el carrito. Espera 250 ms para no consultar en cada toque.
 */
export function useQuote(mode: FulfillmentType, items: OrderLineInput[], enabled = true) {
  const [state, setState] = useState<{ key: string; quote: Quote | null; error: string | null }>({ key: '', quote: null, error: null });
  const key = JSON.stringify([mode, items]);
  const active = enabled && items.length > 0;

  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      api
        .quote({ fulfillmentType: mode, items })
        .then((quote) => !cancelled && setState({ key, quote, error: null }))
        .catch((e: unknown) => !cancelled && setState({ key, quote: null, error: e instanceof ApiError ? e.message : 'No se pudo calcular el total' }));
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
    // `key` resume mode + items
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, active]);

  if (!active) return { quote: null, error: null, loading: false };
  const fresh = state.key === key;
  return { quote: fresh ? state.quote : state.quote, error: fresh ? state.error : null, loading: !fresh };
}
