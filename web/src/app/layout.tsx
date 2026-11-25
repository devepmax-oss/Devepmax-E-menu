import type { Metadata, Viewport } from 'next';
import './globals.css';
import { brandStyle } from '@/lib/brand';
import { fontPair } from '@/lib/fonts';
import { I18nProvider } from '@/components/i18n';
import { pick } from '@/lib/i18n';
import { getLang } from '@/lib/lang-server';
import { getConfig as loadConfig } from '@/lib/server';

export async function generateMetadata(): Promise<Metadata> {
  const [config, lang] = await Promise.all([loadConfig(), getLang()]);
  const name = config?.name ?? pick(lang, 'Pedidos en línea', 'Online ordering');
  return {
    title: { default: `${name} · ${pick(lang, 'Ordena en línea', 'Order online')}`, template: `%s · ${name}` },
    description: pick(lang, `Pide en línea a ${name}: recoge en el local o recibe a domicilio.`, `Order online from ${name}: pickup or delivery.`),
    icons: config?.logoUrl ? { icon: config.logoUrl } : { icon: '/favicon.png' },
  };
}

export async function generateViewport(): Promise<Viewport> {
  const config = await loadConfig();
  return { themeColor: config?.themeMode === 'light' ? '#FBF6F0' : '#120E0B', width: 'device-width', initialScale: 1 };
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const [config, lang] = await Promise.all([loadConfig(), getLang()]);
  const fonts = fontPair(config?.fontPair ?? 'bricolage-inter');
  const style = { ...brandStyle(config ?? {}), ...fonts.style };
  return (
    <html lang={lang} className={fonts.className} style={style}>
      <body>
        <I18nProvider lang={lang}>{children}</I18nProvider>
      </body>
    </html>
  );
}
