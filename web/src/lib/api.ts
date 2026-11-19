import { Category, ProductDetail } from './types';

const API_URL = process.env.NEXT_PUBLIC_API_URL;

if (!API_URL) {
  throw new Error('NEXT_PUBLIC_API_URL is not defined');
}

export async function getMenu(): Promise<Category[]> {
  const res = await fetch(`${API_URL}/api/products`, {
    cache: 'no-store',
  });

  if (!res.ok) {
    throw new Error('Failed to fetch menu');
  }

  return res.json();
}

export async function getProduct(id: string): Promise<ProductDetail> {
  const res = await fetch(`${API_URL}/api/products/${id}`, {
    cache: 'no-store',
  });

  if (!res.ok) {
    throw new Error('Failed to fetch product');
  }

  return res.json();
}

export async function getCart(sessionId: string) {
  const res = await fetch(`${API_URL}/api/cart/${sessionId}`, {
    cache: 'no-store',
  });

  if (!res.ok) {
    throw new Error('Failed to fetch cart');
  }

  return res.json();
}

export async function deleteCartItem(itemId: string) {
  const res = await fetch(`${API_URL}/api/cart/items/${itemId}`, {
    method: 'DELETE',
  });

  if (!res.ok) {
    throw new Error('Failed to delete cart item');
  }

  return res.json();
}

export async function checkoutOrder(payload: {
  sessionId: string;
  customerName: string;
  customerPhone: string;
  customerEmail?: string;
  orderType: 'pickup' | 'delivery';
  deliveryStreet?: string;
  deliveryCity?: string;
  deliveryState?: string;
  deliveryZipCode?: string;
  deliveryInstructions?: string;
  notes?: string;
  tip?: number;
  paymentMethod?: 'in_person' | 'online';
}) {
  const res = await fetch(`${API_URL}/api/orders/checkout`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const error = await res.json().catch(() => null);
    throw new Error(error?.error || 'Failed to checkout');
  }

  return res.json();
}

export async function prepareStripePayment(payload: {
  sessionId: string;
  customerName: string;
  customerPhone: string;
  customerEmail?: string;
  orderType: 'pickup' | 'delivery';
  deliveryStreet?: string;
  deliveryCity?: string;
  deliveryState?: string;
  deliveryZipCode?: string;
  deliveryInstructions?: string;
  notes?: string;
  tip?: number;
}) {
  const res = await fetch(`${API_URL}/api/payments/stripe/prepare`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const error = await res.json().catch(() => null);
    throw new Error(error?.error || 'Failed to prepare Stripe payment');
  }

  return res.json() as Promise<{
  orderId: string;
  publicCode: string;
  clientSecret: string;
  paymentIntentId: string;
}>;
}