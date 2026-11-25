import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Unavailable } from '@/components/unavailable';
import { api, ApiError } from '@/lib/api';
import { pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import { getConfig } from '@/lib/server';
import type { PublicOrder } from '@/lib/types';
import { TrackingView } from './tracking-view';

export async function generateMetadata(): Promise<Metadata> {
  return { title: pick(await getLang(), 'Seguimiento de tu pedido', 'Track your order'), robots: { index: false } };
}

export default async function TrackingPage({
  params,
  searchParams,
}: {
  params: Promise<{ code: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ code }, query] = await Promise.all([params, searchParams]);
  const [config, order] = await Promise.all([
    getConfig(),
    api.order(code).catch((e: unknown): PublicOrder | null | undefined => (e instanceof ApiError && e.status === 404 ? null : undefined)),
  ]);
  if (order === null) notFound();
  if (!config || !order) return <Unavailable />;
  const fromPayment = query.pago === '1' || typeof query.payment_intent === 'string';
  return <TrackingView config={config} initial={order} fromPayment={fromPayment} />;
}
