import type { Metadata } from 'next';
import { Unavailable } from '@/components/unavailable';
import { getConfig } from '@/lib/server';
import { CheckoutView } from './checkout-view';

export const metadata: Metadata = { title: 'Tu pedido' };

export default async function CheckoutPage() {
  const config = await getConfig();
  if (!config) return <Unavailable />;
  if (config.maintenanceMode) return <Unavailable name={config.name} logoUrl={config.logoUrl} maintenance />;
  return <CheckoutView config={config} />;
}
