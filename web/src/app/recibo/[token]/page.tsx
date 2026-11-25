import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Unavailable } from '@/components/unavailable';
import { api, ApiError } from '@/lib/api';
import { pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import type { Receipt } from '@/lib/table-pay';
import { ReceiptView } from './receipt-view';

export async function generateMetadata(): Promise<Metadata> {
  return { title: pick(await getLang(), 'Tu recibo', 'Your receipt'), robots: { index: false } };
}

/** Recibo digital: llega por email, SMS o el QR del ticket impreso. */
export default async function ReceiptPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const receipt = await api
    .receipt(token)
    .catch((e: unknown): Receipt | null | undefined => (e instanceof ApiError && e.status === 404 ? null : undefined));
  if (receipt === null) notFound();
  if (!receipt) return <Unavailable />;
  return <ReceiptView receipt={receipt} />;
}
