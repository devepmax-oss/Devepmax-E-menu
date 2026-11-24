import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Unavailable } from '@/components/unavailable';
import { api, ApiError } from '@/lib/api';
import { getConfig } from '@/lib/server';
import type { TablePayView } from '@/lib/table-pay';
import { PayView } from './pay-view';

export const metadata: Metadata = { title: 'Paga tu cuenta', robots: { index: false } };

/** Lo abre el cliente al escanear el QR de la tablet de su mesa. */
export default async function TablePayPage({
  params,
  searchParams,
}: {
  params: Promise<{ token: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ token }, query] = await Promise.all([params, searchParams]);
  const [config, view] = await Promise.all([
    getConfig(),
    api.tablePay(token).catch((e: unknown): TablePayView | null | undefined => (e instanceof ApiError && e.status === 404 ? null : undefined)),
  ]);
  if (view === null) notFound();
  if (!config || !view) return <Unavailable />;
  // Volvió de un método que abre otra página (p. ej. Cash App): se confirma ese pago.
  const returned = typeof query.payment_intent === 'string' ? query.payment_intent : null;
  return <PayView config={config} token={token} initial={view} returnedIntent={returned} />;
}
