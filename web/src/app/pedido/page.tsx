import type { Metadata } from 'next';
import { Unavailable } from '@/components/unavailable';
import { pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import { getConfig } from '@/lib/server';
import { CheckoutView } from './checkout-view';

export async function generateMetadata(): Promise<Metadata> {
  return { title: pick(await getLang(), 'Tu pedido', 'Your order') };
}

export default async function CheckoutPage() {
  const config = await getConfig();
  if (!config) return <Unavailable />;
  if (config.maintenanceMode) return <Unavailable name={config.name} logoUrl={config.logoUrl} maintenance />;
  return <CheckoutView config={config} />;
}
