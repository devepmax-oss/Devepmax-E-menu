'use client';

import { Clock, MapPin, Phone } from 'lucide-react';
import { useLang, useT } from '@/components/i18n';
import { weekSchedule } from '@/lib/hours';
import type { OnlineConfig } from '@/lib/types';

export function SiteFooter({ config }: { config: OnlineConfig }) {
  const { address } = config;
  const addressText = [address.line, address.city, [address.state, address.zipCode].filter(Boolean).join(' ')].filter(Boolean).join(', ');
  const mapsUrl = addressText ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${config.name} ${addressText}`)}` : null;
  const lang = useLang();
  const t = useT();
  const schedule = weekSchedule(config.openingHours, lang);
  const social = Object.entries(config.socialLinks ?? {}).filter(([, url]) => typeof url === 'string' && url.startsWith('http'));

  return (
    <footer className="mt-10 border-t border-line pt-8 pb-36 text-sm text-soft lg:pb-12">
      <div className="grid gap-8 sm:grid-cols-2">
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-bold text-ink">{config.name}</h2>
          {addressText ? (
            <a href={mapsUrl ?? undefined} target="_blank" rel="noreferrer" className="flex items-start gap-2 text-soft no-underline hover:text-ink">
              <MapPin aria-hidden className="mt-0.5 size-4 shrink-0 text-accent-text" />
              {addressText}
            </a>
          ) : null}
          {config.phone ? (
            <a href={`tel:${config.phone}`} className="flex items-center gap-2 text-soft no-underline hover:text-ink">
              <Phone aria-hidden className="size-4 text-accent-text" />
              {config.phone}
            </a>
          ) : null}
          {social.length ? (
            <div className="flex flex-wrap gap-2 pt-1">
              {social.map(([name, url]) => (
                <a key={name} href={url} target="_blank" rel="noreferrer" className="rounded-full border border-line-strong px-3 py-1.5 text-xs font-bold text-ink capitalize no-underline">
                  {name}
                </a>
              ))}
            </div>
          ) : null}
        </div>
        {config.openingHours.length ? (
          <div className="flex flex-col gap-2">
            <h2 className="flex items-center gap-2 text-lg font-bold text-ink">
              <Clock aria-hidden className="size-4 text-accent-text" /> {t('Horario', 'Hours')}
            </h2>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1">
              {schedule.map((d) => (
                <div key={d.name} className="contents">
                  <dt className="capitalize">{d.name}</dt>
                  <dd className="m-0 text-ink">{d.windows.length ? d.windows.join(' · ') : t('Cerrado', 'Closed')}</dd>
                </div>
              ))}
            </dl>
          </div>
        ) : null}
      </div>
      <p className="mt-8 text-xs text-muted">{t('Pedidos en línea con Devepmax E‑Menu', 'Online ordering by Devepmax E‑Menu')}</p>
    </footer>
  );
}
