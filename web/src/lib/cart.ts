'use client';

import type { FulfillmentType, OrderLineInput } from './types';
import { createStore } from './store';

export interface CartLine {
  key: string;
  productId: string;
  name: string;
  imageUrl: string | null;
  /** Precio unitario mostrado (base + opciones). El servidor recalcula el real. */
  unitPrice: number;
  quantity: number;
  optionIds: string[];
  optionLabels: string[];
  notes: string;
}

export interface CartState {
  mode: FulfillmentType;
  lines: CartLine[];
}

const store = createStore<CartState>('dm-cart-v1', { mode: 'PICKUP', lines: [] });

export const useCart = store.use;

export const lineKey = (productId: string, optionIds: string[], notes: string) =>
  [productId, [...optionIds].sort().join('.'), notes.trim().toLowerCase()].join('|');

export const cart = {
  setMode(mode: FulfillmentType) {
    store.set((s) => ({ ...s, mode }));
  },
  add(line: Omit<CartLine, 'key'>) {
    const key = lineKey(line.productId, line.optionIds, line.notes);
    store.set((s) => {
      const existing = s.lines.find((l) => l.key === key);
      const lines = existing
        ? s.lines.map((l) => (l.key === key ? { ...l, quantity: Math.min(99, l.quantity + line.quantity) } : l))
        : [...s.lines, { ...line, key }];
      return { ...s, lines };
    });
  },
  setQuantity(key: string, quantity: number) {
    store.set((s) => ({
      ...s,
      lines: quantity <= 0 ? s.lines.filter((l) => l.key !== key) : s.lines.map((l) => (l.key === key ? { ...l, quantity: Math.min(99, quantity) } : l)),
    }));
  },
  replace(lines: CartLine[]) {
    store.set((s) => ({ ...s, lines }));
  },
  clear() {
    store.set((s) => ({ ...s, lines: [] }));
  },
};

export const cartCount = (s: CartState) => s.lines.reduce((n, l) => n + l.quantity, 0);
export const cartSubtotal = (s: CartState) => s.lines.reduce((n, l) => n + l.unitPrice * l.quantity, 0);

export const toOrderLines = (s: CartState): OrderLineInput[] =>
  s.lines.map((l) => ({ productId: l.productId, quantity: l.quantity, optionIds: l.optionIds, ...(l.notes ? { notes: l.notes } : {}) }));

/** Datos del cliente para no escribirlos cada vez (solo en este navegador). */
export interface CustomerInfo {
  name: string;
  phone: string;
  email: string;
  street: string;
  city: string;
  state: string;
  zipCode: string;
  instructions: string;
}

const customerStore = createStore<CustomerInfo>('dm-customer-v1', {
  name: '',
  phone: '',
  email: '',
  street: '',
  city: '',
  state: '',
  zipCode: '',
  instructions: '',
});
export const useCustomer = customerStore.use;
export const saveCustomer = (info: CustomerInfo) => customerStore.set(info);

/** Último pedido, para "Pide otra vez" y para volver al seguimiento. */
export interface LastOrder {
  code: string;
  number: number;
  lines: CartLine[];
  placedAt: string;
}
const lastOrderStore = createStore<{ order: LastOrder | null }>('dm-last-order-v1', { order: null });
export const useLastOrder = () => lastOrderStore.use().order;
export const saveLastOrder = (order: LastOrder) => lastOrderStore.set({ order });
