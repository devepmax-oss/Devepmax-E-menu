import { Unavailable } from '@/components/unavailable';
import { api } from '@/lib/api';
import { localizeMenu, localizePromotions } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import { getConfig, safe } from '@/lib/server';
import { MenuView } from './menu-view';

export default async function HomePage() {
  const [config, menu, promotions, lang] = await Promise.all([getConfig(), safe(api.menu()), safe(api.promotions()), getLang()]);
  if (!config || !menu) return <Unavailable />;
  if (config.maintenanceMode) return <Unavailable name={config.name} logoUrl={config.logoUrl} maintenance />;
  return <MenuView config={config} menu={localizeMenu(menu, lang)} promotions={localizePromotions(promotions ?? [], lang)} />;
}
