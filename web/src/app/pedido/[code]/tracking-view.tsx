'use client';

import { Bike, Check, ChefHat, ChevronLeft, CircleAlert, Clock, MapPin, PackageCheck, Phone, Receipt, Share2, ShoppingBag, Store, Wallet, type LucideIcon } from 'lucide-react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { useLang, useT } from '@/components/i18n';
import { Button, Notice, Pill } from '@/components/ui';
import { api, API_ORIGIN } from '@/lib/api';
import { cart } from '@/lib/cart';
import { clockTime, money, plural, toNumber } from '@/lib/format';
import { pick, type Lang } from '@/lib/i18n';
import type { OnlineConfig, PublicOrder, PublicStage } from '@/lib/types';

// El mapa solo existe en el navegador (Leaflet usa window).
const LiveMap = dynamic(() => import('./live-map').then((m) => m.LiveMap), { ssr: false });

const newer = (a: PublicOrder, b: PublicOrder) => new Date(a.updatedAt).getTime() >= new Date(b.updatedAt).getTime();

type Copy = { title: (o: PublicOrder) => string; text: (o: PublicOrder, place: string) => string; icon: LucideIcon };

function copyFor(lang: Lang): Record<PublicStage, Copy> {
  const p = (es: string, en: string) => pick(lang, es, en);
  return {
    awaiting_payment: {
      title: () => p('Esperando el pago', 'Waiting for payment'),
      text: () => p('Tu pedido pasa a la cocina en cuanto se confirme el pago.', 'Your order goes to the kitchen as soon as the payment is confirmed.'),
      icon: Wallet,
    },
    received: {
      title: () => p('Recibimos tu pedido', 'We got your order'),
      text: (_, place) => p(`${place} ya lo tiene y empieza en un momento.`, `${place} has it and will start in a moment.`),
      icon: Receipt,
    },
    preparing: {
      title: () => p('Lo estamos preparando', 'We are preparing it'),
      text: () => p('La cocina está en ello. Te avisamos aquí mismo cuando esté listo.', 'The kitchen is on it. We will let you know right here when it is ready.'),
      icon: ChefHat,
    },
    ready: {
      title: (o) => (o.fulfillmentType === 'DELIVERY' ? p('¡Listo! Sale en breve', 'Ready! Leaving shortly') : p('¡Listo para recoger!', 'Ready for pickup!')),
      text: (o) =>
        o.fulfillmentType === 'DELIVERY'
          ? p('Tu pedido está empacado y espera al repartidor.', 'Your order is packed and waiting for the driver.')
          : p(`Di el número #${o.number} al llegar al mostrador.`, `Give number #${o.number} at the counter.`),
      icon: PackageCheck,
    },
    on_the_way: { title: () => p('Va en camino', 'On the way'), text: () => p('Tu pedido salió del local y va hacia ti.', 'Your order left the restaurant and is heading to you.'), icon: Bike },
    completed: { title: () => p('¡Buen provecho!', 'Enjoy your meal!'), text: () => p('Tu pedido fue entregado. Gracias por pedir con nosotros.', 'Your order was delivered. Thanks for ordering with us.'), icon: Check },
    cancelled: { title: () => p('Pedido cancelado', 'Order cancelled'), text: () => p('Si tienes dudas, llámanos y con gusto te ayudamos.', 'If you have questions, call us and we will gladly help.'), icon: CircleAlert },
  };
}

function steps(order: PublicOrder, lang: Lang) {
  const delivery = order.fulfillmentType === 'DELIVERY';
  const labels = delivery
    ? [pick(lang, 'Recibido', 'Received'), pick(lang, 'Preparando', 'Preparing'), pick(lang, 'En camino', 'On the way'), pick(lang, 'Entregado', 'Delivered')]
    : [pick(lang, 'Recibido', 'Received'), pick(lang, 'Preparando', 'Preparing'), pick(lang, 'Listo', 'Ready'), pick(lang, 'Entregado', 'Picked up')];
  const index: Record<PublicStage, number> = {
    awaiting_payment: -1,
    received: 0,
    preparing: 1,
    ready: delivery ? 1 : 2,
    on_the_way: 2,
    completed: 3,
    cancelled: -1,
  };
  return { labels, current: index[order.stage] };
}

export function TrackingView({ config, initial, fromPayment }: { config: OnlineConfig; initial: PublicOrder; fromPayment: boolean }) {
  const lang = useLang();
  const t = useT();
  const [order, setOrder] = useState(initial);
  const [live, setLive] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  const [shared, setShared] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);
  const [location, setLocation] = useState(initial.driverLocation);
  const code = initial.publicCode;
  const currency = config.currency;
  const confirmedOnce = useRef(false);

  const apply = useCallback((next: PublicOrder) => {
    setOrder((prev) => (newer(next, prev) ? next : prev));
    if (next.driverLocation) setLocation(next.driverLocation);
  }, []);
  const refresh = useCallback(() => api.order(code).then(apply).catch(() => undefined), [code, apply]);

  // En vivo: el servidor manda cada cambio de este pedido (y nada más).
  useEffect(() => {
    const socket = io(API_ORIGIN, { auth: { track: code }, transports: ['websocket', 'polling'] });
    socket.on('ready', () => {
      setLive(true);
      refresh();
    });
    socket.on('disconnect', () => setLive(false));
    socket.on('connect_error', () => setLive(false));
    socket.on('order.public', (data: PublicOrder) => apply(data));
    socket.on('driver.location', (d: { lat: number; lng: number; at: string }) => setLocation({ lat: d.lat, lng: d.lng, at: d.at }));
    return () => {
      socket.close();
    };
  }, [code, apply, refresh]);

  // Respaldo si el tiempo real se cae + reloj para "listo en X min".
  useEffect(() => {
    const tick = setInterval(() => setNow(Date.now()), 30_000);
    const poll = setInterval(() => {
      if (!live && document.visibilityState === 'visible') refresh();
    }, 20_000);
    return () => {
      clearInterval(tick);
      clearInterval(poll);
    };
  }, [live, refresh]);

  // Volviendo de Stripe (Apple Pay, banco, etc.): confirmar el pago y vaciar el carrito.
  useEffect(() => {
    if (!fromPayment || confirmedOnce.current) return;
    confirmedOnce.current = true;
    cart.clear();
    if (initial.stage === 'awaiting_payment') api.confirmPayment(code).then(apply).catch(() => undefined);
  }, [fromPayment, initial.stage, code, apply]);

  const checkPayment = async () => {
    setChecking(true);
    await api.confirmPayment(code).then(apply).catch(() => undefined);
    setChecking(false);
  };

  const share = async () => {
    const url = window.location.href.split('?')[0];
    try {
      if (navigator.share) await navigator.share({ title: `${t('Pedido', 'Order')} #${order.number} · ${config.name}`, url });
      else {
        await navigator.clipboard.writeText(url);
        setShared(t('Enlace copiado', 'Link copied'));
        setTimeout(() => setShared(null), 2500);
      }
    } catch {
      // el cliente cerró el menú de compartir
    }
  };

  const copy = copyFor(lang)[order.stage];
  const Icon = copy.icon;
  const { labels, current } = steps(order, lang);
  const delivery = order.fulfillmentType === 'DELIVERY';
  const active = !['completed', 'cancelled', 'awaiting_payment'].includes(order.stage);
  const eta = order.estimatedReadyAt ? Math.max(0, Math.round((new Date(order.estimatedReadyAt).getTime() - now) / 60_000)) + (delivery ? config.delivery.etaMinutes - config.prepTimeMinutes : 0) : null;
  const showEta = eta !== null && (order.stage === 'received' || order.stage === 'preparing' || (delivery && order.stage === 'ready'));
  const itemCount = order.items.reduce((n, i) => n + i.quantity, 0);
  const address = [config.address.line, config.address.city].filter(Boolean).join(', ');
  const mapsUrl = address ? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(`${config.name} ${address}`)}` : null;
  const due = toNumber(order.totals.total) - toNumber(order.totals.amountPaid);
  const storeLat = Number(config.address.lat);
  const storeLng = Number(config.address.lng);
  const store = config.address.lat && config.address.lng && Number.isFinite(storeLat) && Number.isFinite(storeLng) ? { lat: storeLat, lng: storeLng } : null;
  const showMap = order.stage === 'on_the_way' && (!!location || !!order.destination);
  const driverPoint = useMemo(() => (location ? { lat: location.lat, lng: location.lng } : null), [location]);

  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-xl flex-col">
      {/* Cabecera con el estado */}
      <div className={`relative flex shrink-0 items-center justify-center overflow-hidden ${showMap ? 'h-[420px] sm:h-[460px]' : 'h-[300px] sm:h-[340px]'}`}>
        {showMap ? (
          <>
            <LiveMap driver={driverPoint} destination={order.destination} store={store} />
            <span className="absolute bottom-12 left-4 z-[500] rounded-full border border-line-strong bg-bg/85 px-3 py-1.5 font-heading text-lg font-extrabold backdrop-blur">#{order.number}</span>
            {!location ? (
              <span className="absolute right-4 bottom-12 z-[500] rounded-full border border-line-strong bg-bg/85 px-3 py-1.5 text-xs font-semibold text-soft backdrop-blur">{t('Esperando la ubicación del repartidor…', 'Waiting for the driver location…')}</span>
            ) : null}
          </>
        ) : (
          <>
        <div aria-hidden className={`absolute inset-0 ${order.stage === 'cancelled' ? 'bg-surface-2' : 'bg-gradient-to-br from-brand/35 via-surface to-accent/25'}`} />
        <div aria-hidden className="absolute -top-24 -right-24 size-72 rounded-full bg-brand/20 blur-3xl" />
        <div aria-hidden className="absolute -bottom-28 -left-20 size-72 rounded-full bg-accent/15 blur-3xl" />
        <div className="relative flex flex-col items-center gap-4">
          <span className={`relative flex size-28 items-center justify-center rounded-full ${order.stage === 'cancelled' ? 'bg-surface-3 text-danger' : 'bg-brand text-on-brand'} shadow-float`}>
            {active ? <span aria-hidden className="live absolute inset-0 rounded-full ring-8 ring-brand/30" /> : null}
            <Icon aria-hidden className="size-12" strokeWidth={2.2} />
          </span>
          <span className="font-heading text-5xl font-extrabold tracking-tight">#{order.number}</span>
        </div>
          </>
        )}
        <Link href="/" aria-label={t('Volver al menú', 'Back to the menu')} className="press absolute top-4 left-4 z-[500] flex size-11 items-center justify-center rounded-full border border-line-strong bg-bg/80 text-ink backdrop-blur">
          <ChevronLeft aria-hidden className="size-5" />
        </Link>
        {active ? (
          <span className="absolute top-5 right-4 z-[500] flex items-center gap-1.5 rounded-full border border-line-strong bg-bg/80 px-3 py-1.5 text-xs font-bold tracking-wide backdrop-blur">
            <span aria-hidden className={`size-2 rounded-full ${live ? 'live bg-[#FF5A4E]' : 'bg-muted'}`} />
            {live ? t('EN VIVO', 'LIVE') : t('CONECTANDO', 'CONNECTING')}
          </span>
        ) : null}
      </div>

      {/* Hoja inferior */}
      <section className="relative z-[600] -mt-8 flex flex-1 flex-col gap-5 rounded-t-[30px] border-t border-line bg-surface px-5 pt-3 pb-10 shadow-[0_-20px_40px_rgba(0,0,0,0.25)]">
        <span aria-hidden className="h-[5px] w-10 self-center rounded-full bg-surface-3" />

        <div className="flex flex-col gap-1" aria-live="polite">
          {showEta ? (
            <div className="flex items-end justify-between gap-3">
              <div className="flex flex-col gap-1">
                <span className="text-[13px] font-semibold tracking-wider text-muted uppercase">{delivery ? t('Llega en', 'Arrives in') : t('Listo en', 'Ready in')}</span>
                <span className="font-heading text-[46px] leading-[0.95] font-extrabold tracking-tight">{eta! <= 1 ? t('Ya casi', 'Almost there') : `${eta} min`}</span>
              </div>
              {order.estimatedReadyAt ? (
                <span className="pb-1.5 text-sm text-soft">
                  {t('Hora estimada', 'Estimated time')} {clockTime(new Date(new Date(order.estimatedReadyAt).getTime() + (delivery ? (config.delivery.etaMinutes - config.prepTimeMinutes) * 60_000 : 0)).toISOString(), config.timezone, lang)}
                </span>
              ) : null}
            </div>
          ) : null}
          <h1 className={`m-0 font-extrabold ${showEta ? 'mt-3 text-xl' : 'text-3xl'}`}>{copy.title(order)}</h1>
          <p className="m-0 text-[15px] text-soft">{copy.text(order, config.name)}</p>
        </div>

        {current >= 0 ? (
          <div>
            <div className="grid grid-cols-4 gap-1.5" aria-hidden>
              {labels.map((l, i) => (
                <span key={l} className={`h-1.5 rounded-full ${i < current || (i === current && order.stage === 'completed') ? 'bg-brand' : i === current ? 'live bg-brand' : 'bg-surface-3'}`} />
              ))}
            </div>
            <ol className="m-0 mt-2 grid list-none grid-cols-4 gap-1.5 p-0 text-[11px] font-semibold text-muted">
              {labels.map((l, i) => (
                <li key={l} className={i <= current ? 'text-ink' : ''} aria-current={i === current ? 'step' : undefined}>
                  {l}
                </li>
              ))}
            </ol>
          </div>
        ) : null}

        {order.stage === 'awaiting_payment' ? (
          <div className="flex flex-col gap-3">
            <Notice tone="accent">{t('Si ya pagaste, en unos segundos se actualiza solo.', 'If you already paid, this updates on its own in a few seconds.')}</Notice>
            <Button tone="ghost" onClick={checkPayment} loading={checking}>
              {t('Revisar el pago', 'Check payment')}
            </Button>
          </div>
        ) : null}

        {!delivery && order.stage !== 'cancelled' && order.stage !== 'completed' && address ? (
          <div className="flex items-center gap-3 rounded-[20px] bg-surface-2 p-3">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand-text">
              <Store aria-hidden className="size-5" />
            </span>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="font-bold">{t(`Recoges en ${config.name}`, `Pickup at ${config.name}`)}</span>
              <span className="truncate text-[13px] text-muted">{address}</span>
            </div>
            {mapsUrl ? (
              <a href={mapsUrl} target="_blank" rel="noreferrer" aria-label={t('Cómo llegar', 'Directions')} className="press flex size-[46px] items-center justify-center rounded-full border border-line-strong text-ink">
                <MapPin aria-hidden className="size-5" />
              </a>
            ) : null}
            {config.phone ? (
              <a href={`tel:${config.phone}`} aria-label={t(`Llamar a ${config.name}`, `Call ${config.name}`)} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
                <Phone aria-hidden className="size-5" />
              </a>
            ) : null}
          </div>
        ) : null}

        {delivery && order.driver && order.stage !== 'completed' && order.stage !== 'cancelled' ? (
          <div className="flex items-center gap-3 rounded-[20px] bg-surface-2 p-3">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft font-heading text-xl font-extrabold text-accent-text">
              {order.driver.firstName.slice(0, 1).toUpperCase()}
            </span>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="font-bold">{order.driver.firstName}</span>
              <span className="truncate text-[13px] text-muted">
                {order.stage === 'on_the_way' ? t('Va hacia ti', 'Heading to you') : t('Recogerá tu pedido', 'Will pick up your order')} · {order.driver.vehicle ?? t(`Repartidor de ${config.name}`, `${config.name} driver`)}
              </span>
            </div>
            {order.driver.phone ? (
              <a href={`tel:${order.driver.phone}`} aria-label={t(`Llamar a ${order.driver.firstName}`, `Call ${order.driver.firstName}`)} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
                <Phone aria-hidden className="size-5" />
              </a>
            ) : null}
          </div>
        ) : null}

        {delivery && !order.driver && config.phone && order.stage !== 'completed' && order.stage !== 'cancelled' ? (
          <div className="flex items-center gap-3 rounded-[20px] bg-surface-2 p-3">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand-text">
              <Bike aria-hidden className="size-5" />
            </span>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="font-bold">{t(`Delivery de ${config.name}`, `${config.name} delivery`)}</span>
              <span className="text-[13px] text-muted">{t('¿Alguna duda con tu entrega? Llámanos.', 'Questions about your delivery? Call us.')}</span>
            </div>
            <a href={`tel:${config.phone}`} aria-label={t(`Llamar a ${config.name}`, `Call ${config.name}`)} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
              <Phone aria-hidden className="size-5" />
            </a>
          </div>
        ) : null}

        <details className="group rounded-[20px] border border-line">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3.5 text-[15px] text-soft">
            <span className="flex items-center gap-2">
              <ShoppingBag aria-hidden className="size-4 text-accent-text" />
              {t('Pedido', 'Order')} #{order.number} · {lang === 'en' ? plural(itemCount, 'item', 'items') : plural(itemCount, 'producto', 'productos')}
            </span>
            <span className="flex items-center gap-2">
              {order.totals.paid ? <Pill tone="success">{t('Pagado', 'Paid')}</Pill> : null}
              <span className="font-bold text-ink">{money(order.totals.total, currency)}</span>
            </span>
          </summary>
          <div className="flex flex-col gap-3 border-t border-line px-4 py-4">
            <ul className="m-0 flex list-none flex-col gap-2 p-0">
              {order.items.map((item, i) => (
                <li key={i} className="flex justify-between gap-3 text-[15px]">
                  <span className="flex flex-col">
                    <span className="font-semibold">
                      {item.quantity} × {item.name}
                    </span>
                    {item.modifiers.length ? <span className="text-[13px] text-muted">{item.modifiers.map((m) => m.option).join(' · ')}</span> : null}
                  </span>
                  <span className="tabular-nums">{money(item.lineTotal, currency)}</span>
                </li>
              ))}
            </ul>
            <dl className="m-0 flex flex-col gap-1 border-t border-line pt-3 text-sm text-soft">
              {[
                ['Subtotal', money(order.totals.subtotal, currency)],
                ...order.promotions.map((p) => [p.name, `−${money(p.amount, currency)}`]),
                [t('Impuestos', 'Tax'), money(order.totals.taxTotal, currency)],
                ...(delivery ? [[t('Envío', 'Delivery'), money(order.totals.deliveryFee, currency)]] : []),
                ...(toNumber(order.totals.tipTotal) > 0 ? [[t('Propina', 'Tip'), money(order.totals.tipTotal, currency)]] : []),
              ].map(([k, v]) => (
                <div key={k} className="flex justify-between">
                  <dt>{k}</dt>
                  <dd className="m-0 tabular-nums">{v}</dd>
                </div>
              ))}
              <div className="flex justify-between pt-1 text-base font-bold text-ink">
                <dt>Total</dt>
                <dd className="m-0 tabular-nums">{money(order.totals.total, currency)}</dd>
              </div>
            </dl>
          </div>
        </details>

        {!order.totals.paid && order.stage !== 'awaiting_payment' && order.stage !== 'cancelled' && due > 0 ? (
          <p className="m-0 flex items-center gap-2 text-sm text-soft">
            <Wallet aria-hidden className="size-4 text-accent-text" /> {t('Pagas al recoger', 'Pay at pickup')}: <span className="font-bold text-ink">{money(due, currency)}</span>
          </p>
        ) : null}

        <div className="flex-1" />
        <div className="flex flex-col gap-2">
          {active ? (
            <Button tone="ghost" className="h-[52px]" onClick={share}>
              <Share2 aria-hidden className="size-[18px]" /> {shared ?? t('Compartir seguimiento', 'Share tracking')}
            </Button>
          ) : (
            <Link href="/" className="press flex h-[52px] items-center justify-center rounded-full bg-brand font-bold text-on-brand no-underline">
              {t('Pedir otra vez', 'Order again')}
            </Link>
          )}
          <p className="m-0 flex items-center justify-center gap-1.5 text-xs text-muted">
            <Clock aria-hidden className="size-3.5" /> {t('Hecho a las', 'Placed at')} {clockTime(order.createdAt, config.timezone, lang)}
          </p>
        </div>
      </section>
    </div>
  );
}
