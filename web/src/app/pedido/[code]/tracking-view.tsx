'use client';

import { Bike, Check, ChefHat, ChevronLeft, CircleAlert, Clock, MapPin, PackageCheck, Phone, Receipt, Share2, ShoppingBag, Store, Wallet, type LucideIcon } from 'lucide-react';
import dynamic from 'next/dynamic';
import Link from 'next/link';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { Button, Notice, Pill } from '@/components/ui';
import { api, API_ORIGIN } from '@/lib/api';
import { cart } from '@/lib/cart';
import { clockTime, money, plural, toNumber } from '@/lib/format';
import type { OnlineConfig, PublicOrder, PublicStage } from '@/lib/types';

// El mapa solo existe en el navegador (Leaflet usa window).
const LiveMap = dynamic(() => import('./live-map').then((m) => m.LiveMap), { ssr: false });

const newer = (a: PublicOrder, b: PublicOrder) => new Date(a.updatedAt).getTime() >= new Date(b.updatedAt).getTime();

const COPY: Record<PublicStage, { title: (o: PublicOrder) => string; text: (o: PublicOrder, place: string) => string; icon: LucideIcon }> = {
  awaiting_payment: { title: () => 'Esperando el pago', text: () => 'Tu pedido pasa a la cocina en cuanto se confirme el pago.', icon: Wallet },
  received: { title: () => 'Recibimos tu pedido', text: (_, place) => `${place} ya lo tiene y empieza en un momento.`, icon: Receipt },
  preparing: { title: () => 'Lo estamos preparando', text: () => 'La cocina está en ello. Te avisamos aquí mismo cuando esté listo.', icon: ChefHat },
  ready: {
    title: (o) => (o.fulfillmentType === 'DELIVERY' ? '¡Listo! Sale en breve' : '¡Listo para recoger!'),
    text: (o) => (o.fulfillmentType === 'DELIVERY' ? 'Tu pedido está empacado y espera al repartidor.' : `Di el número #${o.number} al llegar al mostrador.`),
    icon: PackageCheck,
  },
  on_the_way: { title: () => 'Va en camino', text: () => 'Tu pedido salió del local y va hacia ti.', icon: Bike },
  completed: { title: () => '¡Buen provecho!', text: () => 'Tu pedido fue entregado. Gracias por pedir con nosotros.', icon: Check },
  cancelled: { title: () => 'Pedido cancelado', text: () => 'Si tienes dudas, llámanos y con gusto te ayudamos.', icon: CircleAlert },
};

function steps(order: PublicOrder) {
  const delivery = order.fulfillmentType === 'DELIVERY';
  const labels = ['Recibido', 'Preparando', delivery ? 'En camino' : 'Listo', 'Entregado'];
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
      if (navigator.share) await navigator.share({ title: `Pedido #${order.number} · ${config.name}`, url });
      else {
        await navigator.clipboard.writeText(url);
        setShared('Enlace copiado');
        setTimeout(() => setShared(null), 2500);
      }
    } catch {
      // el cliente cerró el menú de compartir
    }
  };

  const copy = COPY[order.stage];
  const Icon = copy.icon;
  const { labels, current } = steps(order);
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
              <span className="absolute right-4 bottom-12 z-[500] rounded-full border border-line-strong bg-bg/85 px-3 py-1.5 text-xs font-semibold text-soft backdrop-blur">Esperando la ubicación del repartidor…</span>
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
        <Link href="/" aria-label="Volver al menú" className="press absolute top-4 left-4 z-[500] flex size-11 items-center justify-center rounded-full border border-line-strong bg-bg/80 text-ink backdrop-blur">
          <ChevronLeft aria-hidden className="size-5" />
        </Link>
        {active ? (
          <span className="absolute top-5 right-4 z-[500] flex items-center gap-1.5 rounded-full border border-line-strong bg-bg/80 px-3 py-1.5 text-xs font-bold tracking-wide backdrop-blur">
            <span aria-hidden className={`size-2 rounded-full ${live ? 'live bg-[#FF5A4E]' : 'bg-muted'}`} />
            {live ? 'EN VIVO' : 'CONECTANDO'}
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
                <span className="text-[13px] font-semibold tracking-wider text-muted uppercase">{delivery ? 'Llega en' : 'Listo en'}</span>
                <span className="font-heading text-[46px] leading-[0.95] font-extrabold tracking-tight">{eta! <= 1 ? 'Ya casi' : `${eta} min`}</span>
              </div>
              {order.estimatedReadyAt ? (
                <span className="pb-1.5 text-sm text-soft">
                  Hora estimada {clockTime(new Date(new Date(order.estimatedReadyAt).getTime() + (delivery ? (config.delivery.etaMinutes - config.prepTimeMinutes) * 60_000 : 0)).toISOString(), config.timezone)}
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
            <Notice tone="accent">Si ya pagaste, en unos segundos se actualiza solo.</Notice>
            <Button tone="ghost" onClick={checkPayment} loading={checking}>
              Revisar el pago
            </Button>
          </div>
        ) : null}

        {!delivery && order.stage !== 'cancelled' && order.stage !== 'completed' && address ? (
          <div className="flex items-center gap-3 rounded-[20px] bg-surface-2 p-3">
            <span className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-brand-text">
              <Store aria-hidden className="size-5" />
            </span>
            <div className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="font-bold">Recoges en {config.name}</span>
              <span className="truncate text-[13px] text-muted">{address}</span>
            </div>
            {mapsUrl ? (
              <a href={mapsUrl} target="_blank" rel="noreferrer" aria-label="Cómo llegar" className="press flex size-[46px] items-center justify-center rounded-full border border-line-strong text-ink">
                <MapPin aria-hidden className="size-5" />
              </a>
            ) : null}
            {config.phone ? (
              <a href={`tel:${config.phone}`} aria-label={`Llamar a ${config.name}`} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
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
                {order.stage === 'on_the_way' ? 'Va hacia ti' : 'Recogerá tu pedido'} · {order.driver.vehicle ?? `Repartidor de ${config.name}`}
              </span>
            </div>
            {order.driver.phone ? (
              <a href={`tel:${order.driver.phone}`} aria-label={`Llamar a ${order.driver.firstName}`} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
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
              <span className="font-bold">Delivery de {config.name}</span>
              <span className="text-[13px] text-muted">¿Alguna duda con tu entrega? Llámanos.</span>
            </div>
            <a href={`tel:${config.phone}`} aria-label={`Llamar a ${config.name}`} className="press flex size-[46px] items-center justify-center rounded-full bg-brand text-on-brand">
              <Phone aria-hidden className="size-5" />
            </a>
          </div>
        ) : null}

        <details className="group rounded-[20px] border border-line">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3.5 text-[15px] text-soft">
            <span className="flex items-center gap-2">
              <ShoppingBag aria-hidden className="size-4 text-accent-text" />
              Pedido #{order.number} · {plural(itemCount, 'producto', 'productos')}
            </span>
            <span className="flex items-center gap-2">
              {order.totals.paid ? <Pill tone="success">Pagado</Pill> : null}
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
                ['Impuestos', money(order.totals.taxTotal, currency)],
                ...(delivery ? [['Envío', money(order.totals.deliveryFee, currency)]] : []),
                ...(toNumber(order.totals.tipTotal) > 0 ? [['Propina', money(order.totals.tipTotal, currency)]] : []),
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
            <Wallet aria-hidden className="size-4 text-accent-text" /> Pagas al recoger: <span className="font-bold text-ink">{money(due, currency)}</span>
          </p>
        ) : null}

        <div className="flex-1" />
        <div className="flex flex-col gap-2">
          {active ? (
            <Button tone="ghost" className="h-[52px]" onClick={share}>
              <Share2 aria-hidden className="size-[18px]" /> {shared ?? 'Compartir seguimiento'}
            </Button>
          ) : (
            <Link href="/" className="press flex h-[52px] items-center justify-center rounded-full bg-brand font-bold text-on-brand no-underline">
              Pedir otra vez
            </Link>
          )}
          <p className="m-0 flex items-center justify-center gap-1.5 text-xs text-muted">
            <Clock aria-hidden className="size-3.5" /> Hecho a las {clockTime(order.createdAt, config.timezone)}
          </p>
        </div>
      </section>
    </div>
  );
}
