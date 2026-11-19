'use client';

import Link from 'next/link';
import dynamic from 'next/dynamic';
import CartIconButton from '@/components/cart/cart-icon-button';

const ThemeToggle = dynamic(() => import('@/components/theme/theme-toggle'), {
  ssr: false,
  loading: () => (
    <div className="flex h-12 w-12 items-center justify-center rounded-2xl border border-neutral-200 bg-white text-xl text-neutral-900 dark:border-neutral-800 dark:bg-neutral-950 dark:text-neutral-100">
      ☼
    </div>
  ),
});

function SocialIcon({
  href,
  label,
  children,
}: {
  href: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      aria-label={label}
      className="inline-flex h-10 w-10 items-center justify-center rounded-full border border-yellow-400/20 bg-white/5 text-yellow-400 transition hover:bg-yellow-400 hover:text-black"
    >
      {children}
    </a>
  );
}

export default function SiteHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-black/5 bg-white/80 backdrop-blur transition-colors dark:border-white/10 dark:bg-black/75">
      <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
        <Link href="/" className="flex items-center gap-4">
          <div className="h-35 w-35 overflow-hidden">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/logo.png"
              alt="Go Picadera"
              className="h-full w-full object-contain"
            />
          </div>
        </Link>

        <div className="hidden items-center gap-3 md:flex">
          <SocialIcon href="https://www.tiktok.com/@gopicadera" label="TikTok">
            <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current" aria-hidden="true">
              <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.12v12.4a2.67 2.67 0 1 1-2.67-2.67c.27 0 .53.04.78.12V8.67a5.8 5.8 0 1 0 5.01 5.73V8.09a7.9 7.9 0 0 0 4.77 1.6V6.69Z" />
            </svg>
          </SocialIcon>

          <SocialIcon href="https://www.instagram.com/gopicadera/" label="Instagram">
            <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current" aria-hidden="true">
              <path d="M7.75 2h8.5A5.75 5.75 0 0 1 22 7.75v8.5A5.75 5.75 0 0 1 16.25 22h-8.5A5.75 5.75 0 0 1 2 16.25v-8.5A5.75 5.75 0 0 1 7.75 2Zm0 1.75A4 4 0 0 0 3.75 7.75v8.5a4 4 0 0 0 4 4h8.5a4 4 0 0 0 4-4v-8.5a4 4 0 0 0-4-4h-8.5Zm8.88 1.87a1.13 1.13 0 1 1 0 2.26 1.13 1.13 0 0 1 0-2.26ZM12 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0 1.75A3.25 3.25 0 1 0 12 15.25 3.25 3.25 0 0 0 12 8.75Z" />
            </svg>
          </SocialIcon>

          <SocialIcon href="https://wa.me/19297058086" label="WhatsApp">
            <svg viewBox="0 0 24 24" className="h-4 w-4 fill-current" aria-hidden="true">
              <path d="M12 2a9.94 9.94 0 0 0-8.6 15l-1.2 4.38 4.5-1.18A10 10 0 1 0 12 2Zm0 18a8 8 0 0 1-4.08-1.12l-.3-.18-2.67.7.7-2.59-.2-.31A8 8 0 1 1 12 20Zm4.56-6.06c-.25-.13-1.47-.73-1.7-.82-.23-.08-.4-.12-.57.13-.17.25-.65.82-.8.99-.15.17-.3.19-.55.06-.25-.13-1.07-.39-2.03-1.24-.75-.67-1.26-1.49-1.4-1.74-.15-.25-.02-.38.11-.5.12-.12.25-.31.38-.46.13-.15.17-.25.25-.42.08-.17.04-.31-.02-.44-.06-.13-.57-1.38-.78-1.89-.2-.49-.41-.42-.57-.43h-.48c-.17 0-.44.06-.67.31-.23.25-.88.86-.88 2.09 0 1.23.9 2.43 1.03 2.59.13.17 1.77 2.7 4.28 3.79.6.26 1.08.42 1.45.54.61.19 1.16.16 1.59.1.49-.07 1.47-.6 1.68-1.18.21-.58.21-1.08.15-1.18-.06-.1-.23-.17-.48-.29Z" />
            </svg>
          </SocialIcon>
        </div>

        <div className="flex items-center gap-3">
          <Link
            href="/menu"
            className="inline-flex items-center gap-2 rounded-[18px] bg-yellow-400 px-6 py-3 text-sm font-bold text-black transition hover:bg-yellow-300"
          >
            <span>Order Now</span>
            <span className="text-base">→</span>
          </Link>

          <ThemeToggle />
          <CartIconButton />
        </div>
      </div>
    </header>
  );
}