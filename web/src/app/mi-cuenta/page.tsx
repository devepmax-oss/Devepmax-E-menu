import type { Metadata } from 'next';
import { Unavailable } from '@/components/unavailable';
import { api } from '@/lib/api';
import { localizeMenu, pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import { getConfig, safe } from '@/lib/server';
import { AccountView } from './account-view';

export async function generateMetadata(): Promise<Metadata> {
  return { title: pick(await getLang(), 'Mi cuenta', 'My account'), robots: { index: false } };
}

/** Cuenta del cliente: entrar con código, datos, direcciones y pedidos anteriores. */
export default async function AccountPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const [query, config, menu, lang] = await Promise.all([searchParams, getConfig(), safe(api.menu()), getLang()]);
  if (!config) return <Unavailable />;
  if (config.maintenanceMode) return <Unavailable name={config.name} logoUrl={config.logoUrl} maintenance />;
  const back = typeof query.volver === 'string' && query.volver.startsWith('/') && !query.volver.startsWith('//') ? query.volver : null;
  return <AccountView config={config} menu={menu ? localizeMenu(menu, lang) : null} back={back} />;
}
