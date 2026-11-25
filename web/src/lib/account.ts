'use client';

import { request } from './api';
import type { CartLine } from './cart';
import { lineKey } from './cart';
import { toNumber } from './format';
import { createStore } from './store';
import type { Money, PublicMenu } from './types';

export interface Address {
  id: string;
  label: string | null;
  street: string;
  city: string;
  state: string;
  zipCode: string;
  instructions: string | null;
}

export interface Profile {
  id: string;
  name: string;
  needsName: boolean;
  phone: string | null;
  email: string | null;
  marketingOptIn: boolean;
  lang: 'es' | 'en' | null;
  addresses: Address[];
}

export interface HistoryItem {
  productId: string | null;
  name: string;
  quantity: number;
  lineTotal: Money;
  notes: string | null;
  options: { id: string | null; name: string }[];
}

export interface HistoryEntry {
  id: string;
  date: string;
  kind: 'TABLE' | 'COUNTER' | 'PICKUP' | 'DELIVERY';
  table: string | null;
  orderNumbers: number[];
  status: string;
  trackingCode: string | null;
  total: Money;
  items: HistoryItem[];
  receiptUrl: string | null;
}

export interface CodeSent {
  channel: 'sms' | 'email';
  sentTo: string;
  expiresInMinutes: number;
  /** Solo en desarrollo (sin Twilio/Resend): el código para probar. */
  devCode?: string;
}

export type AddressInput = Omit<Address, 'id' | 'label' | 'instructions'> & { label?: string; instructions?: string };

interface Session {
  token: string;
  profile: Profile | null;
}

const store = createStore<Session>('dm-account-v1', { token: '', profile: null });

/** La sesión del cliente en este navegador. */
export const useAccount = store.use;
export const accountToken = () => store.get().token;

const withToken = (init: RequestInit = {}): RequestInit => ({
  ...init,
  headers: { ...(init.headers ?? {}), 'x-customer-token': store.get().token },
});

async function authed<T>(path: string, init?: RequestInit): Promise<T> {
  try {
    return await request<T>(path, withToken(init));
  } catch (e) {
    // La sesión venció o se cerró en otro lado.
    if (e && typeof e === 'object' && 'status' in e && (e as { status: number }).status === 401) store.set({ token: '', profile: null });
    throw e;
  }
}

const keep = (profile: Profile) => {
  store.set((s) => ({ ...s, profile }));
  return profile;
};

export const account = {
  requestCode: (target: string, lang: 'es' | 'en') =>
    request<CodeSent>('/customer-auth/request', { method: 'POST', body: JSON.stringify({ target, lang }) }),
  async verify(target: string, code: string) {
    const result = await request<{ token: string; customer: Profile }>('/customer-auth/verify', {
      method: 'POST',
      body: JSON.stringify({ target, code }),
    });
    store.set({ token: result.token, profile: result.customer });
    return result.customer;
  },
  async refresh() {
    if (!store.get().token) return null;
    return keep(await authed<Profile>('/me'));
  },
  async update(body: { name?: string; marketingOptIn?: boolean; lang?: 'es' | 'en' }) {
    return keep(await authed<Profile>('/me', { method: 'PATCH', body: JSON.stringify(body) }));
  },
  async addAddress(body: AddressInput) {
    return keep(await authed<Profile>('/me/addresses', { method: 'POST', body: JSON.stringify(body) }));
  },
  async removeAddress(id: string) {
    return keep(await authed<Profile>(`/me/addresses/${encodeURIComponent(id)}`, { method: 'DELETE' }));
  },
  history: () => authed<HistoryEntry[]>('/me/orders'),
  async logout() {
    const token = store.get().token;
    store.set({ token: '', profile: null });
    if (token) await request<null>('/customer-auth/logout', { method: 'POST', headers: { 'x-customer-token': token } }).catch(() => undefined);
  },
};

/**
 * Lo de un pedido anterior que se puede volver a pedir hoy, con el menú y los precios de hoy.
 * Lo agotado o que ya no está en el menú se deja fuera.
 */
export function reorderLines(entry: HistoryEntry, menu: PublicMenu): { lines: CartLine[]; skipped: number } {
  const products = new Map(menu.categories.flatMap((c) => c.products).map((p) => [p.id, p]));
  const lines: CartLine[] = [];
  let skipped = 0;
  for (const item of entry.items) {
    const product = item.productId ? products.get(item.productId) : undefined;
    if (!product || !product.isAvailable) {
      skipped++;
      continue;
    }
    const options = new Map(product.modifierGroups.flatMap((g) => g.options).map((o) => [o.id, o]));
    const chosen = item.options.map((o) => (o.id ? options.get(o.id) : undefined));
    if (chosen.some((o) => !o || !o.isAvailable)) {
      skipped++;
      continue;
    }
    // Que siga cumpliendo lo obligatorio de cada grupo.
    const ok = product.modifierGroups.every((g) => {
      const n = chosen.filter((o) => o && g.options.some((x) => x.id === o.id)).length;
      return n >= g.minSelect && (g.maxSelect == null || n <= g.maxSelect) && (g.selectionType !== 'SINGLE' || n <= 1);
    });
    if (!ok) {
      skipped++;
      continue;
    }
    const optionIds = chosen.map((o) => o!.id);
    const notes = item.notes ?? '';
    const existing = lines.find((l) => l.key === lineKey(product.id, optionIds, notes));
    if (existing) {
      existing.quantity = Math.min(99, existing.quantity + item.quantity);
      continue;
    }
    lines.push({
      key: lineKey(product.id, optionIds, notes),
      productId: product.id,
      name: product.name,
      imageUrl: product.imageUrl,
      unitPrice: toNumber(product.price) + chosen.reduce((n, o) => n + toNumber(o!.priceAdjustment), 0),
      quantity: Math.min(99, item.quantity),
      optionIds,
      optionLabels: chosen.map((o) => o!.name),
      notes,
    });
  }
  return { lines, skipped };
}
