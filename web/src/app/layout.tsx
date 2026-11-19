import './globals.css';
import type { Metadata } from 'next';
import SiteHeader from '@/components/layout/site-header';
import FloatingCartButton from '@/components/cart/floating-cart-button';
import ThemeProvider from '@/components/theme/theme-provider';
import MaintenancePage from '@/maintenance/MaintenancePage';

export const metadata: Metadata = {
  title: 'Go Picadera',
  description: 'Ordena online',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const maintenanceMode =
    process.env.MAINTENANCE_MODE === 'true';

  if (maintenanceMode) {
    return (
      <html lang="es" suppressHydrationWarning>
        <body>
          <MaintenancePage />
        </body>
      </html>
    );
  }

  return (
    <html lang="es" suppressHydrationWarning>
      <body>
        <ThemeProvider>
          <SiteHeader />
          {children}
          <FloatingCartButton />
        </ThemeProvider>
      </body>
    </html>
  );
}