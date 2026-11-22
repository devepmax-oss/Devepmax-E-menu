import type { Metadata, Viewport } from 'next';
import './globals.css';
import { brandStyle } from '@/lib/brand';
import { fontPair } from '@/lib/fonts';
import { getConfig as loadConfig } from '@/lib/server';

export async function generateMetadata(): Promise<Metadata> {
  const config = await loadConfig();
  const name = config?.name ?? 'Pedidos en línea';
  return {
    title: { default: `${name} · Ordena en línea`, template: `%s · ${name}` },
    description: `Pide en línea a ${name}: recoge en el local o recibe a domicilio.`,
    icons: config?.logoUrl ? { icon: config.logoUrl } : { icon: '/favicon.png' },
  };
}

export async function generateViewport(): Promise<Viewport> {
  const config = await loadConfig();
  return { themeColor: config?.themeMode === 'light' ? '#FBF6F0' : '#120E0B', width: 'device-width', initialScale: 1 };
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const config = await loadConfig();
  const fonts = fontPair(config?.fontPair ?? 'bricolage-inter');
  const style = { ...brandStyle(config ?? {}), ...fonts.style };
  return (
    <html lang="es" className={fonts.className} style={style}>
      <body>{children}</body>
    </html>
  );
}
