import { Unavailable } from '@/components/unavailable';
import { api } from '@/lib/api';
import { getConfig, safe } from '@/lib/server';
import { MenuView } from './menu-view';

export default async function HomePage() {
  const [config, menu, promotions] = await Promise.all([getConfig(), safe(api.menu()), safe(api.promotions())]);
  if (!config || !menu) return <Unavailable />;
  if (config.maintenanceMode) return <Unavailable name={config.name} logoUrl={config.logoUrl} maintenance />;
  return <MenuView config={config} menu={menu} promotions={promotions ?? []} />;
}
