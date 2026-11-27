'use client';

import { ShoppingBag, Trash2 } from 'lucide-react';
import Link from 'next/link';
import { useT } from '@/components/i18n';
import { Stepper } from '@/components/ui';
import { cart, type CartLine, useCart } from '@/lib/cart';
import { money, toNumber } from '@/lib/format';
import type { FulfillmentType, OnlineConfig, Quote } from '@/lib/types';

/** Productos del carrito con +/−. */
export function CartLines({ lines, currency, editable = true }: { lines: CartLine[]; currency: string; editable?: boolean }) {
  const tr = useT();
  return (
    <ul className="m-0 flex list-none flex-col divide-y divide-line p-0">
      {lines.map((l) => (
        <li key={l.key} className="flex gap-3 py-3 first:pt-0 last:pb-0">
          {l.imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={l.imageUrl} alt="" className="size-14 shrink-0 rounded-xl object-cover" />
          ) : (
            <span className="flex size-14 shrink-0 items-center justify-center rounded-xl bg-surface-2 font-heading text-lg font-bold text-muted">{l.name.slice(0, 1)}</span>
          )}
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <div className="flex items-start justify-between gap-2">
              <span className="font-bold">{l.name}</span>
              <span className="font-semibold tabular-nums">{money(l.unitPrice * l.quantity, currency)}</span>
            </div>
            {l.optionLabels.length ? <span className="text-[13px] leading-snug text-muted">{l.optionLabels.join(' · ')}</span> : null}
            {l.notes ? <span className="text-[13px] leading-snug text-muted italic">“{l.notes}”</span> : null}
            {editable ? (
              <div className="mt-1 flex items-center gap-2">
                <Stepper size="sm" value={l.quantity} onChange={(n) => cart.setQuantity(l.key, n)} label={l.name} />
                <button type="button" onClick={() => cart.setQuantity(l.key, 0)} aria-label={tr(`Quitar ${l.name}`, `Remove ${l.name}`)} className="press flex size-9 cursor-pointer items-center justify-center rounded-full border-0 bg-transparent text-muted hover:text-danger">
                  <Trash2 aria-hidden className="size-4" />
                </button>
              </div>
            ) : (
              <span className="text-[13px] text-soft">{tr('Cantidad', 'Qty')}: {l.quantity}</span>
            )}
          </div>
        </li>
      ))}
    </ul>
  );
}

/** Desglose del total con lo que calcula el servidor. */
export function TotalsSummary({ quote, currency, tip, mode }: { quote: Quote | null; currency: string; tip?: number; mode: FulfillmentType }) {
  const tr = useT();
  if (!quote) return <div className="h-24 animate-pulse rounded-2xl bg-surface-2" aria-hidden />;
  const t = quote.totals;
  const tipValue = tip ?? 0;
  const total = toNumber(t.total) + tipValue;
  const row = (label: string, value: string, className = '') => (
    <div className={`flex items-center justify-between gap-3 ${className}`}>
      <dt className={className ? '' : 'text-muted'}>{label}</dt>
      <dd className={`m-0 tabular-nums ${className ? '' : 'font-semibold text-ink'}`}>{value}</dd>
    </div>
  );
  return (
    <dl className="m-0 flex flex-col gap-1.5 text-[15px] text-soft">
      {row('Subtotal', money(t.subtotal, currency))}
      {quote.promotions.map((p) => row(p.name, `−${money(p.amount, currency)}`, 'font-semibold text-success'))}
      {quote.coupon && toNumber(quote.coupon.amount) > 0 ? row(quote.coupon.name, `−${money(quote.coupon.amount, currency)}`, 'font-semibold text-success') : null}
      {quote.coupon?.freeDelivery ? row(quote.coupon.name, tr('Envío gratis', 'Free delivery'), 'font-semibold text-success') : null}
      {row(tr('Impuestos', 'Tax'), money(t.taxTotal, currency))}
      {mode === 'DELIVERY' ? row(tr('Envío', 'Delivery'), toNumber(t.deliveryFee) > 0 ? money(t.deliveryFee, currency) : tr('Gratis', 'Free')) : null}
      {tip !== undefined ? row(tr('Propina', 'Tip'), money(tipValue, currency)) : null}
      <div className="mt-2 flex items-center justify-between gap-3 border-t border-line pt-3 text-ink">
        <dt className="text-lg font-bold">Total</dt>
        <dd className="m-0 font-heading text-2xl font-extrabold tabular-nums">{money(total, currency)}</dd>
      </div>
    </dl>
  );
}

/** Panel lateral del carrito (pantallas grandes). */
export function CartPanel({ config, mode, quote, canOrder }: { config: OnlineConfig; mode: FulfillmentType; quote: Quote | null; canOrder: boolean }) {
  const state = useCart();
  const tr = useT();
  const currency = config.currency;
  return (
    <section aria-label={tr('Tu pedido', 'Your order')} className="flex flex-col gap-4 rounded-[26px] border border-line bg-surface p-5">
      <h2 className="m-0 text-2xl font-extrabold">{tr('Tu pedido', 'Your order')}</h2>
      {state.lines.length === 0 ? (
        <div className="flex flex-col items-center gap-3 py-8 text-center text-muted">
          <span className="flex size-14 items-center justify-center rounded-2xl bg-surface-2">
            <ShoppingBag aria-hidden className="size-6" />
          </span>
          <p className="m-0 text-sm">{tr('Agrega productos del menú y aparecerán aquí.', 'Add items from the menu and they will show up here.')}</p>
        </div>
      ) : (
        <>
          <div className="no-scrollbar max-h-[46vh] overflow-y-auto">
            <CartLines lines={state.lines} currency={currency} />
          </div>
          <div className="border-t border-line pt-4">
            <TotalsSummary quote={quote} currency={currency} mode={mode} />
          </div>
          {quote && !quote.meetsMinimum && mode === 'DELIVERY' ? (
            <p className="m-0 text-sm text-danger">{tr(`El pedido mínimo para delivery es de ${money(quote.minOrder, currency)}.`, `The delivery minimum is ${money(quote.minOrder, currency)}.`)}</p>
          ) : null}
          <Link
            href="/pedido"
            aria-disabled={!canOrder}
            className={`press flex h-14 items-center justify-center rounded-2xl bg-brand text-base font-extrabold text-on-brand no-underline ${canOrder ? '' : 'pointer-events-none opacity-50'}`}
          >
            {tr('Continuar', 'Continue')}
          </Link>
        </>
      )}
    </section>
  );
}
