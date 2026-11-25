import type { Receipt, TablePayIntent, TablePayView } from './table-pay';
import type { CreatedOrder, OnlineConfig, OrderLineInput, PublicMenu, PublicOrder, PublicPromotion, Quote } from './types';

/** URL del backend. En el navegador y en el servidor de Next se usa la misma. */
export const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000/api/v1').replace(/\/+$/, '');

/** Origen del backend (para Socket.IO). */
export const API_ORIGIN = API_URL.replace(/\/api\/v\d+$/, '');

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

export async function request<T>(path: string, init?: RequestInit): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
      cache: 'no-store',
    });
  } catch {
    throw new ApiError('No pudimos conectar con el restaurante. Revisa tu conexión e intenta de nuevo.', 0);
  }
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const raw = data?.message;
    const message = Array.isArray(raw) ? raw[0] : typeof raw === 'string' ? raw : 'Algo salió mal. Intenta de nuevo.';
    throw new ApiError(message, response.status);
  }
  return data as T;
}

export const api = {
  config: () => request<OnlineConfig>('/online/config'),
  menu: () => request<PublicMenu>('/menu?channel=online'),
  promotions: () => request<PublicPromotion[]>('/promotions/public?channel=online'),
  quote: (
    body: { fulfillmentType: 'PICKUP' | 'DELIVERY'; items: OrderLineInput[]; tipAmount?: number; couponCode?: string; phone?: string },
    customerToken?: string,
  ) =>
    request<Quote>('/online/quote', {
      method: 'POST',
      body: JSON.stringify(body),
      ...(customerToken ? { headers: { 'x-customer-token': customerToken } } : {}),
    }),
  createOrder: (body: unknown, customerToken?: string) =>
    request<CreatedOrder>('/online/orders', {
      method: 'POST',
      body: JSON.stringify(body),
      ...(customerToken ? { headers: { 'x-customer-token': customerToken } } : {}),
    }),
  order: (code: string) => request<PublicOrder>(`/online/orders/${encodeURIComponent(code)}`),
  receipt: (token: string) => request<Receipt>(`/receipts/${encodeURIComponent(token)}`),
  tablePay: (token: string) => request<TablePayView>(`/pay/${encodeURIComponent(token)}`),
  tablePayIntent: (token: string, body: { clientRequestId: string; billId: string; amount: number; tip?: number; email?: string }) =>
    request<TablePayIntent>(`/pay/${encodeURIComponent(token)}/intent`, { method: 'POST', body: JSON.stringify(body) }),
  tablePayConfirm: (token: string, paymentIntentId: string) =>
    request<{ status: 'succeeded' | 'pending' | 'failed'; view: TablePayView }>(`/pay/${encodeURIComponent(token)}/confirm`, {
      method: 'POST',
      body: JSON.stringify({ paymentIntentId }),
    }),
  confirmPayment: (code: string) =>
    request<PublicOrder>(`/online/orders/${encodeURIComponent(code)}/confirm-payment`, { method: 'POST' }),
};
