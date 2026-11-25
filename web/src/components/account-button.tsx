'use client';

import { UserRound } from 'lucide-react';
import Link from 'next/link';
import { useAccount } from '@/lib/account';
import { useT } from './i18n';

/** "Entrar" o el nombre del cliente con sesión; lleva a Mi cuenta. */
export function AccountButton() {
  const t = useT();
  const { token, profile } = useAccount();
  const first = profile?.name.trim().split(/\s+/)[0];
  return (
    <Link
      href="/mi-cuenta"
      aria-label={token ? t('Mi cuenta', 'My account') : t('Entrar', 'Sign in')}
      className="press flex h-11 items-center gap-2 rounded-full border border-line-strong bg-surface px-3.5 text-sm font-bold text-ink no-underline"
    >
      <UserRound aria-hidden className="size-4 text-accent-text" />
      <span className="hidden sm:inline">{token && first ? first : t('Entrar', 'Sign in')}</span>
    </Link>
  );
}
