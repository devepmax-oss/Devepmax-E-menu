'use client';

import { ChevronLeft, CreditCard, MapPin, Store, Wallet } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useMemo, useRef, useState } from 'react';
import { useLang, useT } from '@/components/i18n';
import { Button, Notice } from '@/components/ui';
import { useAccount } from '@/lib/account';
import { api, ApiError } from '@/lib/api';
import { cart, cartCount, saveCustomer, saveLastOrder, toOrderLines, useCart, useCustomer, type CustomerInfo } from '@/lib/cart';
import { money, round2, toNumber } from '@/lib/format';
import type { CreatedOrder, FulfillmentType, OnlineConfig } from '@/lib/types';
import { useQuote } from '@/lib/use-quote';
import { CartLines, TotalsSummary } from '../cart-panel';
import { ModeToggle, modeInfo, orderingState } from '../menu-view';
import { StripePay } from './stripe-pay';

type Pay = 'card' | 'pay_at_pickup';
type Tip = { kind: 'percent'; value: number } | { kind: 'custom'; value: string } | { kind: 'none' };

const PHONE = /^[0-9+()\-.\s]{7,20}$/;
const ZIP = /^\d{5}(-\d{4})?$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const newRequestId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID().replace(/-/g, '') : `${Date.now()}${Math.random().toString(36).slice(2)}`;

function Field({
  label,
  error,
  hint,
  className = '',
  ...input
}: React.InputHTMLAttributes<HTMLInputElement> & { label: string; error?: string; hint?: string }) {
  const id = input.id ?? input.name;
  return (
    <label htmlFor={id} className={`flex flex-col gap-1.5 ${className}`}>
      <span className="text-sm font-semibold text-soft">{label}</span>
      <input
        {...input}
        id={id}
        aria-invalid={!!error}
        aria-describedby={error ? `${id}-error` : undefined}
        className={`h-13 min-h-12 rounded-2xl border bg-surface-2 px-4 text-base text-ink placeholder:text-muted ${error ? 'border-danger' : 'border-line'}`}
      />
      {error ? (
        <span id={`${id}-error`} className="text-sm text-danger">
          {error}
        </span>
      ) : hint ? (
        <span className="text-xs text-muted">{hint}</span>
      ) : null}
    </label>
  );
}

function Section({ title, children, id }: { title: string; children: React.ReactNode; id?: string }) {
  return (
    <section id={id} className="flex scroll-mt-6 flex-col gap-4 rounded-[26px] border border-line bg-surface p-5">
      <h2 className="m-0 text-xl font-bold">{title}</h2>
      {children}
    </section>
  );
}

export function CheckoutView({ config }: { config: OnlineConfig }) {
  const router = useRouter();
  const state = useCart();
  const saved = useCustomer();
  const currency = config.currency;
  const lang = useLang();
  const t = useT();
  const { modes, canOrder, reason } = orderingState(config, lang);
  const mode: FulfillmentType = modes.includes(state.mode) ? state.mode : (modes[0] ?? 'PICKUP');
  const delivery = mode === 'DELIVERY';

  const { token, profile } = useAccount();
  const [draft, setDraft] = useState<Partial<CustomerInfo>>({});
  const [saveAddress, setSaveAddress] = useState(true);
  const fromAccount: Partial<CustomerInfo> = profile
    ? { name: profile.name || saved.name, phone: profile.phone ?? saved.phone, email: profile.email ?? saved.email }
    : {};
  const info: CustomerInfo = { ...saved, ...fromAccount, ...draft };
  const signedIn = !!token && !!profile;
  const knownAddress = profile?.addresses.some(
    (a) => a.street.toLowerCase() === info.street.trim().toLowerCase() && a.zipCode === info.zipCode.trim(),
  );
  const set = (field: keyof CustomerInfo) => (e: React.ChangeEvent<HTMLInputElement>) => setDraft((d) => ({ ...d, [field]: e.target.value }));
  const [notes, setNotes] = useState('');
  const [tipChoice, setTipChoice] = useState<Tip | null>(null);
  const [payChoice, setPayChoice] = useState<Pay | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [created, setCreated] = useState<CreatedOrder | null>(null);
  const [leaving, setLeaving] = useState(false);
  const requestRef = useRef<{ key: string; id: string } | null>(null);

  const items = useMemo(() => toOrderLines(state), [state]);
  const { quote, error: quoteError } = useQuote(mode, items, canOrder);

  // Propina: sugerida en delivery, opcional en pickup.
  const presets = config.tipPresets.length ? config.tipPresets : [15, 18, 20];
  const tip: Tip = tipChoice ?? (delivery ? { kind: 'percent', value: presets[Math.floor(presets.length / 2)] } : { kind: 'none' });
  const tipBase = quote ? toNumber(quote.totals.subtotal) - toNumber(quote.totals.discountTotal) : 0;
  const tipAmount = tip.kind === 'percent' ? round2((tipBase * tip.value) / 100) : tip.kind === 'custom' ? Math.max(0, round2(toNumber(tip.value))) : 0;

  // Pago: con tarjeta si Stripe está activo; delivery siempre con tarjeta.
  const payOptions: Pay[] = [...(config.payments.card ? (['card'] as Pay[]) : []), ...(!delivery && config.payments.payAtPickup ? (['pay_at_pickup'] as Pay[]) : [])];
  const pay: Pay | null = payChoice && payOptions.includes(payChoice) ? payChoice : (payOptions[0] ?? null);
  const total = quote ? toNumber(quote.totals.total) + tipAmount : 0;

  if (leaving) {
    return (
      <main className="flex min-h-dvh items-center justify-center text-soft" aria-live="polite">
        {t('Abriendo tu pedido…', 'Opening your order…')}
      </main>
    );
  }

  if (cartCount(state) === 0 && !created) {
    return (
      <main className="mx-auto flex min-h-dvh max-w-md flex-col items-center justify-center gap-5 px-6 text-center">
        <h1 className="m-0 text-3xl font-extrabold">{t('Tu pedido está vacío', 'Your order is empty')}</h1>
        <p className="m-0 text-soft">{t('Elige algo rico del menú y vuelve aquí para pagar.', 'Pick something tasty from the menu and come back here to pay.')}</p>
        <Link href="/" className="press rounded-full bg-brand px-6 py-3 font-bold text-on-brand no-underline">
          {t('Ver el menú', 'See the menu')}
        </Link>
      </main>
    );
  }

  const validate = () => {
    const e: Record<string, string> = {};
    if (info.name.trim().length < 2) e.name = t('Escribe tu nombre', 'Enter your name');
    if (!PHONE.test(info.phone.trim())) e.phone = t('Escribe un teléfono válido', 'Enter a valid phone number');
    if (info.email.trim() && !EMAIL.test(info.email.trim())) e.email = t('Revisa el email', 'Check the email');
    if (delivery) {
      if (info.street.trim().length < 3) e.street = t('Escribe la dirección', 'Enter the address');
      if (info.city.trim().length < 2) e.city = t('Escribe la ciudad', 'Enter the city');
      if (info.state.trim().length < 2) e.state = t('Escribe el estado', 'Enter the state');
      if (!ZIP.test(info.zipCode.trim())) e.zipCode = t('Código postal de 5 dígitos', '5-digit ZIP code');
    }
    setErrors(e);
    const first = Object.keys(e)[0];
    if (first) document.getElementById(first)?.focus();
    return !first;
  };

  const submit = async () => {
    setSubmitError(null);
    if (!validate() || !quote || !pay) return;
    const clean: CustomerInfo = Object.fromEntries(Object.entries(info).map(([k, v]) => [k, String(v).trim()])) as unknown as CustomerInfo;
    const body = {
      fulfillmentType: mode,
      paymentMethod: pay,
      items,
      tipAmount: tipAmount || undefined,
      notes: notes.trim() || undefined,
      customer: { name: clean.name, phone: clean.phone, ...(clean.email ? { email: clean.email } : {}) },
      ...(delivery
        ? { deliveryAddress: { street: clean.street, city: clean.city, state: clean.state.toUpperCase(), zipCode: clean.zipCode, ...(clean.instructions ? { instructions: clean.instructions } : {}) } }
        : {}),
      ...(delivery && signedIn && saveAddress && !knownAddress ? { saveAddress: true } : {}),
    };
    // Mismo pedido → misma clave (tocar dos veces no duplica); pedido distinto → clave nueva.
    const key = JSON.stringify(body);
    if (requestRef.current?.key !== key) requestRef.current = { key, id: newRequestId() };
    setSubmitting(true);
    try {
      const result = await api.createOrder({ ...body, clientRequestId: requestRef.current.id }, signedIn ? token : undefined);
      saveCustomer(clean);
      saveLastOrder({ code: result.order.publicCode, number: result.order.number, lines: state.lines, placedAt: new Date().toISOString() });
      if (result.payment) {
        setCreated(result);
        setTimeout(() => document.getElementById('pago')?.scrollIntoView({ behavior: 'smooth', block: 'start' }), 50);
      } else {
        finish(result.order.publicCode);
      }
    } catch (e) {
      setSubmitError(e instanceof ApiError ? e.message : t('No pudimos enviar tu pedido. Intenta de nuevo.', 'We could not send your order. Please try again.'));
    } finally {
      setSubmitting(false);
    }
  };

  const finish = (code: string) => {
    setLeaving(true);
    cart.clear();
    router.push(`/pedido/${code}`);
  };

  const paid = async () => {
    if (!created) return;
    try {
      await api.confirmPayment(created.order.publicCode);
    } catch {
      // El webhook de Stripe también lo confirma; el seguimiento lo mostrará.
    }
    finish(created.order.publicCode);
  };

  const locked = !!created;
  const publishableKey = created?.payment?.publishableKey ?? config.payments.publishableKey;

  return (
    <div className="mx-auto w-full max-w-6xl px-4 pb-16 sm:px-6">
      <header className="flex items-center gap-3 py-4">
        <Link href="/" aria-label={t('Volver al menú', 'Back to the menu')} className="press flex size-11 items-center justify-center rounded-full border border-line-strong bg-surface text-ink">
          <ChevronLeft aria-hidden className="size-5" />
        </Link>
        <h1 className="m-0 text-3xl font-extrabold">{t('Tu pedido', 'Your order')}</h1>
      </header>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_400px] lg:items-start lg:gap-8">
        <div className="flex min-w-0 flex-col gap-5">
          {reason ? <Notice tone="accent">{reason}</Notice> : null}

          <Section title={t('¿Cómo lo quieres?', 'How do you want it?')}>
            {locked ? (
              <p className="m-0 flex items-center gap-2 font-semibold">
                {delivery ? <MapPin aria-hidden className="size-4 text-accent-text" /> : <Store aria-hidden className="size-4 text-accent-text" />}
                {delivery ? 'Delivery' : 'Pickup'}
              </p>
            ) : (
              <ModeToggle modes={modes} mode={mode} />
            )}
            <p className="m-0 text-sm text-soft">{modeInfo(config, mode, lang)}</p>
            {!delivery && config.address.line ? (
              <p className="m-0 text-sm text-soft">
                {t('Recoges en', 'Pick up at')} <span className="font-semibold text-ink">{[config.address.line, config.address.city].filter(Boolean).join(', ')}</span>
              </p>
            ) : null}
          </Section>

          <Section title={t('Productos', 'Items')}>
            <CartLines lines={state.lines} currency={currency} editable={!locked} />
            {!locked ? (
              <Link href="/" className="self-start text-sm font-bold">
                {t('+ Agregar algo más', '+ Add something else')}
              </Link>
            ) : null}
            {quoteError ? <Notice tone="danger">{quoteError}</Notice> : null}
          </Section>

          <Section title={t('Tus datos', 'Your details')} id="datos">
            {!signedIn && !locked ? (
              <p className="m-0 text-sm text-soft">
                {t('¿Ya tienes cuenta?', 'Have an account?')}{' '}
                <Link href="/mi-cuenta?volver=/pedido" className="font-bold">
                  {t('Entra para pedir más rápido', 'Sign in to order faster')}
                </Link>
              </p>
            ) : null}
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('Nombre', 'Name')} name="name" autoComplete="name" value={info.name} onChange={set('name')} error={errors.name} disabled={locked} />
              <Field label={t('Teléfono', 'Phone')} name="phone" type="tel" autoComplete="tel" inputMode="tel" value={info.phone} onChange={set('phone')} error={errors.phone} disabled={locked} hint={t('Te avisamos si hay algún cambio', 'We will let you know if anything changes')} />
              <Field label={t('Email (opcional)', 'Email (optional)')} name="email" type="email" autoComplete="email" value={info.email} onChange={set('email')} error={errors.email} disabled={locked} hint={t('Para enviarte el recibo', 'To send you the receipt')} className="sm:col-span-2" />
            </div>
          </Section>

          {delivery ? (
            <Section title={t('Dirección de entrega', 'Delivery address')}>
              {profile?.addresses.length && !locked ? (
                <div role="radiogroup" aria-label={t('Direcciones guardadas', 'Saved addresses')} className="flex flex-wrap gap-2">
                  {profile.addresses.map((a) => {
                    const on = a.street.toLowerCase() === info.street.trim().toLowerCase() && a.zipCode === info.zipCode.trim();
                    return (
                      <button
                        key={a.id}
                        type="button"
                        role="radio"
                        aria-checked={on}
                        onClick={() =>
                          setDraft((d) => ({ ...d, street: a.street, city: a.city, state: a.state, zipCode: a.zipCode, instructions: a.instructions ?? '' }))
                        }
                        className={`press flex cursor-pointer items-center gap-2 rounded-full border px-4 py-2 text-sm font-bold ${on ? 'border-brand bg-brand-soft text-ink' : 'border-line bg-surface-2 text-soft'}`}
                      >
                        <MapPin aria-hidden className="size-4" /> {a.label ?? a.street}
                      </button>
                    );
                  })}
                </div>
              ) : null}
              <div className="grid gap-4 sm:grid-cols-6">
                <Field label={t('Dirección', 'Street address')} name="street" autoComplete="address-line1" value={info.street} onChange={set('street')} error={errors.street} disabled={locked} placeholder="123 Main St, Apt 4" className="sm:col-span-6" />
                <Field label={t('Ciudad', 'City')} name="city" autoComplete="address-level2" value={info.city} onChange={set('city')} error={errors.city} disabled={locked} className="sm:col-span-3" />
                <Field label={t('Estado', 'State')} name="state" autoComplete="address-level1" value={info.state} onChange={set('state')} error={errors.state} disabled={locked} placeholder="FL" maxLength={50} className="sm:col-span-1" />
                <Field label={t('Código postal', 'ZIP code')} name="zipCode" autoComplete="postal-code" inputMode="numeric" value={info.zipCode} onChange={set('zipCode')} error={errors.zipCode} disabled={locked} className="sm:col-span-2" />
                <Field label={t('Instrucciones para el repartidor (opcional)', 'Instructions for the driver (optional)')} name="instructions" value={info.instructions} onChange={set('instructions')} disabled={locked} placeholder={t('Portón azul, timbre 2', 'Blue gate, buzzer 2')} maxLength={300} className="sm:col-span-6" />
              </div>
              {signedIn && !knownAddress && !locked ? (
                <label className="flex cursor-pointer items-center gap-3 text-sm text-soft">
                  <input type="checkbox" checked={saveAddress} onChange={(e) => setSaveAddress(e.target.checked)} className="size-5 accent-[var(--brand)]" />
                  {t('Guardar esta dirección en mi cuenta', 'Save this address to my account')}
                </label>
              ) : null}
            </Section>
          ) : null}

          <Section title={t('Nota para la cocina', 'Note for the kitchen')}>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              disabled={locked}
              maxLength={500}
              rows={2}
              placeholder={t('Opcional: alergias, cubiertos, etc.', 'Optional: allergies, utensils, etc.')}
              className="resize-none rounded-2xl border border-line bg-surface-2 px-4 py-3 text-base text-ink placeholder:text-muted"
            />
          </Section>

          <Section title={t('Propina', 'Tip')}>
            <div role="radiogroup" aria-label={t('Propina', 'Tip')} className="grid grid-cols-3 gap-2 sm:grid-cols-5">
              {[...presets.map((p) => ({ id: `p${p}`, label: `${p}%`, sub: money(round2((tipBase * p) / 100), currency), choice: { kind: 'percent', value: p } as Tip })),
                { id: 'custom', label: t('Otra', 'Other'), sub: t('monto', 'amount'), choice: { kind: 'custom', value: tip.kind === 'custom' ? tip.value : '' } as Tip },
                { id: 'none', label: t('Sin', 'No'), sub: t('propina', 'tip'), choice: { kind: 'none' } as Tip },
              ].map((o) => {
                const on = o.choice.kind === tip.kind && (o.choice.kind !== 'percent' || (tip.kind === 'percent' && o.choice.value === tip.value));
                return (
                  <button
                    key={o.id}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    disabled={locked}
                    onClick={() => setTipChoice(o.choice)}
                    className={`press flex h-16 cursor-pointer flex-col items-center justify-center rounded-2xl border ${on ? 'border-brand bg-brand-soft text-ink' : 'border-line bg-surface-2 text-soft'}`}
                  >
                    <span className="font-bold text-ink">{o.label}</span>
                    <span className="text-xs">{o.sub}</span>
                  </button>
                );
              })}
            </div>
            {tip.kind === 'custom' ? (
              <Field label={t('Monto de propina', 'Tip amount')} name="tip" inputMode="decimal" value={tip.value} disabled={locked} onChange={(e) => setTipChoice({ kind: 'custom', value: e.target.value.replace(/[^0-9.]/g, '') })} placeholder="0.00" />
            ) : null}
            <p className="m-0 text-xs text-muted">{delivery ? t('El 100 % de la propina es para quien te lleva el pedido.', '100% of the tip goes to your driver.') : t('El 100 % de la propina es para el equipo.', '100% of the tip goes to the team.')}</p>
          </Section>
        </div>

        <aside className="flex flex-col gap-5 lg:sticky lg:top-6">
          <Section title={t('Pago', 'Payment')} id="pago">
            {!locked ? (
              payOptions.length ? (
                <div role="radiogroup" aria-label={t('Forma de pago', 'Payment method')} className="flex flex-col gap-2">
                  {payOptions.map((p) => {
                    const on = p === pay;
                    return (
                      <button
                        key={p}
                        type="button"
                        role="radio"
                        aria-checked={on}
                        onClick={() => setPayChoice(p)}
                        className={`press flex min-h-16 cursor-pointer items-center gap-3 rounded-2xl border px-4 text-left ${on ? 'border-brand bg-brand-soft' : 'border-line bg-surface-2'}`}
                      >
                        {p === 'card' ? <CreditCard aria-hidden className="size-5 text-accent-text" /> : <Wallet aria-hidden className="size-5 text-accent-text" />}
                        <span className="flex flex-1 flex-col">
                          <span className="font-bold text-ink">{p === 'card' ? t('Pagar ahora', 'Pay now') : t('Pagar al recoger', 'Pay at pickup')}</span>
                          <span className="text-xs text-muted">{p === 'card' ? t('Tarjeta, Apple Pay o Google Pay', 'Card, Apple Pay or Google Pay') : t('En efectivo o tarjeta en el local', 'Cash or card at the restaurant')}</span>
                        </span>
                        <span aria-hidden className={`size-5 rounded-full border-2 ${on ? 'border-brand bg-brand shadow-[inset_0_0_0_3px_var(--surface-2)]' : 'border-line-strong'}`} />
                      </button>
                    );
                  })}
                </div>
              ) : (
                <Notice tone="accent">{delivery ? t('El delivery se paga en línea y el pago con tarjeta aún no está activo. Elige Pickup.', 'Delivery is paid online and card payments are not active yet. Choose Pickup.') : t('No hay formas de pago disponibles.', 'No payment methods available.')}</Notice>
              )
            ) : null}

            <TotalsSummary quote={quote} currency={currency} tip={tipAmount} mode={mode} />
            {quote && delivery && !quote.meetsMinimum ? <Notice tone="danger">{t(`El pedido mínimo para delivery es de ${money(quote.minOrder, currency)}.`, `The delivery minimum is ${money(quote.minOrder, currency)}.`)}</Notice> : null}
            {submitError ? <Notice tone="danger">{submitError}</Notice> : null}

            {created?.payment && publishableKey ? (
              <div className="flex flex-col gap-3 border-t border-line pt-4">
                <p className="m-0 text-sm text-soft">
                  {t('Pedido', 'Order')} <span className="font-bold text-ink">#{created.order.number}</span>{' '}
                  {t('listo. Completa el pago para enviarlo a la cocina.', 'is ready. Complete the payment to send it to the kitchen.')}
                </p>
                <StripePay
                  publishableKey={publishableKey}
                  clientSecret={created.payment.clientSecret}
                  amountLabel={money(created.order.totals.total, currency)}
                  returnUrl={`${window.location.origin}/pedido/${created.order.publicCode}?pago=1`}
                  customer={{ name: info.name.trim(), email: info.email.trim(), phone: info.phone.trim() }}
                  onPaid={paid}
                />
                <button type="button" onClick={() => setCreated(null)} className="cursor-pointer self-center border-0 bg-transparent text-sm font-semibold text-muted underline">
                  {t('Cambiar el pedido', 'Change the order')}
                </button>
              </div>
            ) : (
              <Button
                className="h-14 w-full text-base"
                onClick={submit}
                loading={submitting}
                disabled={!canOrder || !quote || !pay || !!quoteError || (delivery && !quote.meetsMinimum)}
              >
                {pay === 'pay_at_pickup' ? `${t('Hacer pedido', 'Place order')} · ${money(total, currency)}` : `${t('Continuar al pago', 'Continue to payment')} · ${money(total, currency)}`}
              </Button>
            )}
          </Section>
        </aside>
      </div>
    </div>
  );
}
