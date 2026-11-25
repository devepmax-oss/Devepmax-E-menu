'use client';

import { Bike, Clock, Plus, Receipt, RotateCcw, Store } from 'lucide-react';
import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { LanguageSwitch, useLang, useT } from '@/components/i18n';
import { SiteFooter } from '@/components/site-footer';
import { BrandMark, Notice, Pill } from '@/components/ui';
import { cart, cartCount, toOrderLines, useCart, useLastOrder } from '@/lib/cart';
import { money, plural, toNumber } from '@/lib/format';
import { hoursLabel } from '@/lib/hours';
import { pick, type Lang } from '@/lib/i18n';
import { promoBadge, promotionsByProduct } from '@/lib/promos';
import type { FulfillmentType, MenuProduct, OnlineConfig, PublicMenu, PublicPromotion } from '@/lib/types';
import { useQuote } from '@/lib/use-quote';
import { CartPanel } from './cart-panel';
import { ProductSheet } from './product-sheet';

export function orderingState(config: OnlineConfig, lang: Lang = 'es') {
  const modes: FulfillmentType[] = [];
  if (config.channels.pickup) modes.push('PICKUP');
  if (config.channels.delivery) modes.push('DELIVERY');
  const reason = config.channels.onlineOrderingPaused
    ? pick(lang, 'Ahora mismo no estamos recibiendo pedidos en línea.', 'We are not taking online orders right now.')
    : !config.isOpenNow
      ? pick(lang, 'Estamos cerrados. Puedes ver el menú y pedir cuando abramos.', 'We are closed. You can browse the menu and order when we open.')
      : modes.length === 0
        ? pick(lang, 'Los pedidos en línea no están disponibles.', 'Online ordering is not available.')
        : null;
  return { modes, canOrder: reason === null, reason };
}

export function modeInfo(config: OnlineConfig, mode: FulfillmentType, lang: Lang = 'es') {
  const prep = config.prepTimeMinutes;
  if (mode === 'PICKUP') return pick(lang, `Recoges en el local · listo en ${prep}–${prep + 5} min`, `Pickup at the restaurant · ready in ${prep}–${prep + 5} min`);
  const eta = config.delivery.etaMinutes;
  const fee = toNumber(config.delivery.fee);
  const feeText = fee > 0 ? pick(lang, `envío ${money(fee, config.currency)}`, `${money(fee, config.currency)} delivery fee`) : pick(lang, 'envío gratis', 'free delivery');
  return pick(lang, `A domicilio · llega en ${eta}–${eta + 10} min · ${feeText}`, `Delivery · arrives in ${eta}–${eta + 10} min · ${feeText}`);
}

export function ModeToggle({ modes, mode }: { modes: FulfillmentType[]; mode: FulfillmentType }) {
  const t = useT();
  if (modes.length < 2) return null;
  return (
    <div role="radiogroup" aria-label={t('Cómo quieres tu pedido', 'How do you want your order')} className="grid grid-cols-2 gap-1 rounded-full border border-line bg-surface p-1">
      {modes.map((m) => {
        const on = m === mode;
        return (
          <button
            key={m}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => cart.setMode(m)}
            className={`press flex h-11 cursor-pointer items-center justify-center gap-2 rounded-full text-[15px] ${on ? 'bg-ink font-bold text-bg' : 'font-semibold text-soft hover:text-ink'}`}
          >
            {m === 'PICKUP' ? <Store aria-hidden className="size-4" /> : <Bike aria-hidden className="size-4" />}
            {m === 'PICKUP' ? 'Pickup' : 'Delivery'}
          </button>
        );
      })}
    </div>
  );
}

export function MenuView({ config, menu, promotions }: { config: OnlineConfig; menu: PublicMenu; promotions: PublicPromotion[] }) {
  const state = useCart();
  const lastOrder = useLastOrder();
  const lang = useLang();
  const t = useT();
  const { modes, canOrder, reason } = orderingState(config, lang);
  const mode: FulfillmentType = modes.includes(state.mode) ? state.mode : (modes[0] ?? 'PICKUP');
  const [open, setOpen] = useState<MenuProduct | null>(null);
  const [bump, setBump] = useState(0);
  const [activeCat, setActiveCat] = useState(menu.categories[0]?.id ?? '');
  const [now] = useState(() => Date.now());
  const currency = config.currency;

  const promosByProduct = useMemo(() => promotionsByProduct(menu.categories, promotions), [menu.categories, promotions]);
  const products = useMemo(() => new Map(menu.categories.flatMap((c) => c.products.map((p) => [p.id, p] as const))), [menu.categories]);
  const badgesFor = (id: string) => (promosByProduct.get(id) ?? []).map((p) => promoBadge(p, currency));

  const items = toOrderLines(state);
  const { quote } = useQuote(mode, items, canOrder);
  const count = cartCount(state);

  const close = useCallback(() => setOpen(null), []);
  const added = useCallback(() => setBump((b) => b + 1), []);

  // Categoría visible mientras se desplaza el menú.
  useEffect(() => {
    const sections = menu.categories.map((c) => document.getElementById(`cat-${c.id}`)).filter(Boolean) as HTMLElement[];
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
        if (visible) setActiveCat(visible.target.id.slice(4));
      },
      { rootMargin: '-110px 0px -65% 0px' },
    );
    sections.forEach((s) => observer.observe(s));
    return () => observer.disconnect();
  }, [menu.categories]);

  useEffect(() => {
    document.getElementById(`chip-${activeCat}`)?.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
  }, [activeCat]);

  const quickAdd = (p: MenuProduct) => {
    if (p.modifierGroups.length > 0) return setOpen(p);
    cart.add({ productId: p.id, name: p.name, imageUrl: p.imageUrl, unitPrice: toNumber(p.price), quantity: 1, optionIds: [], optionLabels: [], notes: '' });
    added();
  };

  // Promoción destacada con la foto de uno de sus productos.
  const hero = useMemo(() => {
    const promo = promotions[0];
    if (!promo) return null;
    const targets = menu.categories.flatMap((c) => c.products.filter((p) => promo.productIds.includes(p.id) || promo.categoryIds.includes(c.id)));
    const withImage = targets.find((p) => p.imageUrl) ?? menu.categories.flatMap((c) => c.products).find((p) => p.imageUrl);
    const endsToday = promo.endsAt && new Date(promo.endsAt).getTime() - now < 24 * 3600_000;
    return { promo, product: targets.length === 1 ? targets[0] : null, image: withImage?.imageUrl ?? null, chip: endsToday ? pick(lang, 'Solo hoy', 'Today only') : promoBadge(promo, currency), firstTarget: targets[0] };
  }, [promotions, menu.categories, currency, now, lang]);

  const repeatable = lastOrder?.lines.filter((l) => products.get(l.productId)?.isAvailable) ?? [];
  const recentOrder = lastOrder && now - new Date(lastOrder.placedAt).getTime() < 12 * 3600_000 ? lastOrder : null;

  return (
    <div className="mx-auto w-full max-w-6xl px-4 sm:px-6">
      <div className="lg:grid lg:grid-cols-[minmax(0,1fr)_380px] lg:gap-10">
        <main className="flex min-w-0 flex-col gap-5 pt-4">
          <header className="flex items-center justify-between gap-3">
            <BrandMark name={config.name} logoUrl={config.logoUrl} />
            <div className="flex items-center gap-2">
              {recentOrder ? (
                <Link href={`/pedido/${recentOrder.code}`} className="press flex h-11 items-center gap-2 rounded-full border border-line-strong bg-surface px-4 text-sm font-bold text-ink no-underline">
                  <Receipt aria-hidden className="size-4 text-accent-text" /> {t('Pedido', 'Order')} #{recentOrder.number}
                </Link>
              ) : null}
              <LanguageSwitch offered={config.locales} />
            </div>
          </header>

          <div className="flex flex-col gap-2.5">
            <ModeToggle modes={modes} mode={mode} />
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-soft">
              <span className="flex items-center gap-2">
                <Clock aria-hidden className="size-4 text-accent-text" />
                {modeInfo(config, mode, lang)}
              </span>
              <span className={`flex items-center gap-1.5 font-semibold ${config.isOpenNow ? 'text-success' : 'text-danger'}`}>
                <span aria-hidden className="size-2 rounded-full bg-current" />
                {hoursLabel(config.openingHours, config.timezone, config.isOpenNow, new Date(), lang)}
              </span>
            </div>
          </div>

          {reason ? <Notice tone="accent">{reason}</Notice> : null}

          {hero ? (
            <button
              type="button"
              onClick={() => (hero.product ? setOpen(hero.product) : hero.firstTarget && document.getElementById(`cat-${menu.categories.find((c) => c.products.includes(hero.firstTarget!))?.id}`)?.scrollIntoView({ behavior: 'smooth' }))}
              className="press relative block h-52 w-full cursor-pointer overflow-hidden rounded-[26px] border-0 bg-surface-2 p-0 text-left text-white sm:h-64"
            >
              {hero.image ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={hero.image} alt="" className="absolute inset-0 size-full object-cover" />
              ) : (
                <div className="absolute inset-0 bg-gradient-to-br from-brand to-accent" />
              )}
              <div className="absolute inset-0 bg-gradient-to-b from-black/0 from-30% to-black/85" />
              <div className="absolute right-5 bottom-4 left-5 flex flex-col items-start gap-1.5">
                <Pill>{hero.chip}</Pill>
                <span className="font-heading text-3xl leading-none font-extrabold sm:text-4xl">{hero.promo.name}</span>
                {hero.promo.description ? <span className="text-sm text-white/80">{hero.promo.description}</span> : null}
              </div>
            </button>
          ) : null}

          {count === 0 && repeatable.length > 0 && canOrder ? (
            <div className="flex items-center gap-3 rounded-[22px] border border-line bg-surface py-3.5 pr-3.5 pl-4">
              <span className="flex size-11 shrink-0 items-center justify-center rounded-2xl bg-brand-soft text-brand-text">
                <RotateCcw aria-hidden className="size-5" />
              </span>
              <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="font-bold">{t('Pide otra vez', 'Order again')}</span>
                <span className="truncate text-sm text-muted">{repeatable.map((l) => (l.quantity > 1 ? `${l.quantity} ${l.name}` : l.name)).join(' + ')}</span>
              </div>
              <button
                type="button"
                onClick={() => {
                  cart.replace(repeatable);
                  added();
                }}
                className="press h-11 cursor-pointer rounded-full border-0 bg-ink px-4 text-sm font-bold text-bg"
              >
                {t('Repetir', 'Reorder')}
              </button>
            </div>
          ) : null}

          <nav aria-label={t('Categorías', 'Categories')} className="no-scrollbar sticky top-0 z-20 -mx-4 flex gap-2 overflow-x-auto bg-bg/90 px-4 py-2 backdrop-blur sm:-mx-6 sm:px-6">
            {menu.categories.map((c) => {
              const on = c.id === activeCat;
              return (
                <button
                  key={c.id}
                  id={`chip-${c.id}`}
                  type="button"
                  aria-current={on ? 'true' : undefined}
                  onClick={() => document.getElementById(`cat-${c.id}`)?.scrollIntoView({ behavior: 'smooth' })}
                  className={`press h-11 shrink-0 cursor-pointer rounded-full px-4 text-sm whitespace-nowrap ${on ? 'border-0 bg-brand font-bold text-on-brand' : 'border border-line-strong bg-surface font-semibold text-soft'}`}
                >
                  {c.name}
                </button>
              );
            })}
          </nav>

          {menu.categories.map((c) => (
            <section key={c.id} id={`cat-${c.id}`} aria-labelledby={`h-${c.id}`} className="flex scroll-mt-20 flex-col gap-3">
              <h2 id={`h-${c.id}`} className="m-0 text-2xl font-bold">
                {c.name}
              </h2>
              <div className="grid gap-3 md:grid-cols-2">
                {c.products.map((p) => (
                  <ProductCard key={p.id} product={p} badges={badgesFor(p.id)} currency={currency} canOrder={canOrder} onOpen={() => setOpen(p)} onAdd={() => quickAdd(p)} />
                ))}
              </div>
            </section>
          ))}

          {menu.categories.length === 0 ? <Notice>{t('Todavía no hay productos en el menú en línea.', 'There are no products on the online menu yet.')}</Notice> : null}

          <SiteFooter config={config} />
        </main>

        <aside className="hidden lg:block">
          <div className="sticky top-6 pt-4">
            <CartPanel config={config} mode={mode} quote={quote} canOrder={canOrder} />
          </div>
        </aside>
      </div>

      {count > 0 ? (
        <div className="fixed inset-x-3.5 bottom-[max(1rem,env(safe-area-inset-bottom))] z-30 lg:hidden">
          <Link
            key={bump}
            href="/pedido"
            className={`press flex h-[62px] items-center gap-3 rounded-[20px] bg-brand pr-5 pl-2.5 text-on-brand no-underline shadow-float ${bump ? 'bump' : ''}`}
          >
            <span className="flex h-[42px] min-w-[42px] items-center justify-center rounded-[14px] bg-black/15 px-2 text-[17px] font-extrabold">{count}</span>
            <span className="flex-1 text-[17px] font-extrabold">{t('Ver mi pedido', 'View my order')}</span>
            <span className="font-heading text-[19px] font-extrabold">
              {quote ? money(toNumber(quote.totals.subtotal) - toNumber(quote.totals.discountTotal), currency) : money(state.lines.reduce((n, l) => n + l.unitPrice * l.quantity, 0), currency)}
            </span>
          </Link>
          <span className="sr-only" aria-live="polite">
            {t(`${plural(count, 'producto', 'productos')} en tu pedido`, `${plural(count, 'item', 'items')} in your order`)}
          </span>
        </div>
      ) : null}

      {open ? <ProductSheet product={open} badges={badgesFor(open.id)} currency={currency} canOrder={canOrder} onClose={close} onAdded={added} /> : null}
    </div>
  );
}

function ProductCard({
  product: p,
  badges,
  currency,
  canOrder,
  onOpen,
  onAdd,
}: {
  product: MenuProduct;
  badges: string[];
  currency: string;
  canOrder: boolean;
  onOpen: () => void;
  onAdd: () => void;
}) {
  const soldOut = !p.isAvailable;
  const t = useT();
  return (
    <article onClick={onOpen} className={`group flex cursor-pointer gap-3.5 rounded-[22px] border border-line bg-surface p-2.5 transition-colors hover:border-line-strong ${soldOut ? 'opacity-60' : ''}`}>
      {p.imageUrl ? (
        <div className="relative size-[104px] shrink-0 overflow-hidden rounded-2xl bg-surface-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={p.imageUrl} alt="" loading="lazy" className={`size-full object-cover transition-transform duration-300 group-hover:scale-105 ${soldOut ? 'grayscale' : ''}`} />
          {badges[0] && !soldOut ? <Pill className="absolute top-1.5 left-1.5">{badges[0]}</Pill> : null}
        </div>
      ) : null}
      <div className="flex min-w-0 flex-1 flex-col gap-1 py-1 pr-1 pl-1.5">
        <h3 className="m-0 font-body text-base font-bold tracking-normal">
          <button type="button" onClick={(e) => {
            e.stopPropagation();
            onOpen();
          }} className="cursor-pointer border-0 bg-transparent p-0 text-left font-bold text-ink">
            {p.name}
          </button>
        </h3>
        {!p.imageUrl && badges[0] && !soldOut ? <Pill className="self-start">{badges[0]}</Pill> : null}
        {p.description ? <p className="m-0 line-clamp-2 text-[13px] leading-snug text-muted">{p.description}</p> : null}
        <div className="flex-1" />
        <div className="flex items-center justify-between gap-2">
          <span className="font-heading text-lg font-bold">{soldOut ? <span className="text-sm font-semibold text-muted">{t('Agotado', 'Sold out')}</span> : money(p.price, currency)}</span>
          {!soldOut ? (
            <button
              type="button"
              aria-label={t(`Agregar ${p.name}`, `Add ${p.name}`)}
              disabled={!canOrder}
              onClick={(e) => {
                e.stopPropagation();
                onAdd();
              }}
              className="press flex size-11 cursor-pointer items-center justify-center rounded-full border-0 bg-brand text-on-brand"
            >
              <Plus aria-hidden className="size-5" strokeWidth={2.6} />
            </button>
          ) : null}
        </div>
      </div>
    </article>
  );
}
