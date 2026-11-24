'use client';

import { CheckCircle2, ChevronDown, Receipt, Users } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BrandMark, Button, Notice, Stepper } from '@/components/ui';
import { api, ApiError } from '@/lib/api';
import { money, round2, toNumber } from '@/lib/format';
import type { TablePayBill, TablePayIntent, TablePayView } from '@/lib/table-pay';
import type { OnlineConfig } from '@/lib/types';
import { StripePay } from '../../pedido/stripe-pay';

type Share = { kind: 'all' } | { kind: 'split'; people: number } | { kind: 'custom'; value: string };
type Tip = { kind: 'percent'; value: number } | { kind: 'custom'; value: string } | { kind: 'none' };
type Done = { amount: number; tip: number; due: number };

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const newRequestId = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID().replace(/-/g, '') : `${Date.now()}${Math.random().toString(36).slice(2)}`;
/** Al dividir se redondea hacia arriba al centavo (que no falte dinero). */
const ceil2 = (n: number) => Math.ceil(n * 100 - 1e-6) / 100;

function Section({ title, children, aside }: { title: string; children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-[26px] border border-line bg-surface p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="m-0 text-xl font-bold">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

function Choice({ on, onClick, label, sub, disabled }: { on: boolean; onClick: () => void; label: string; sub?: string; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={on}
      disabled={disabled}
      onClick={onClick}
      className={`press flex min-h-16 cursor-pointer flex-col items-center justify-center rounded-2xl border px-2 text-center ${on ? 'border-brand bg-brand-soft text-ink' : 'border-line bg-surface-2 text-soft'}`}
    >
      <span className="font-bold text-ink">{label}</span>
      {sub ? <span className="text-xs">{sub}</span> : null}
    </button>
  );
}

function Row({ label, value, strong, tone }: { label: string; value: string; strong?: boolean; tone?: 'success' }) {
  return (
    <div className={`flex items-baseline justify-between gap-3 ${strong ? 'text-lg font-extrabold text-ink' : 'text-sm text-soft'} ${tone === 'success' ? 'text-success' : ''}`}>
      <span>{label}</span>
      <span className="tabular-nums">{value}</span>
    </div>
  );
}

/**
 * Pagar desde la mesa: el cliente ve la cuenta en su celular, elige si paga todo, su parte o
 * un monto, deja propina y paga con tarjeta, Apple Pay o Google Pay.
 */
export function PayView({ config, token, initial, returnedIntent }: { config: OnlineConfig; token: string; initial: TablePayView; returnedIntent: string | null }) {
  const currency = config.currency;
  const [view, setView] = useState(initial);
  const [billId, setBillId] = useState<string>(() => (initial.bills.find((b) => toNumber(b.due) > 0) ?? initial.bills[0])?.id ?? '');
  const [share, setShare] = useState<Share>({ kind: 'all' });
  const presets = config.tipPresets.length ? config.tipPresets : initial.tipPercents;
  const [tipChoice, setTipChoice] = useState<Tip>({ kind: 'percent', value: presets[Math.floor(presets.length / 2)] ?? 18 });
  const [email, setEmail] = useState('');
  const [showItems, setShowItems] = useState(false);
  const [intent, setIntent] = useState<(TablePayIntent & { amount: number; tip: number }) | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<Done | null>(null);
  const requestId = useRef(newRequestId());

  const bill: TablePayBill | undefined = view.bills.find((b) => b.id === billId) ?? view.bills[0];
  const due = toNumber(bill?.due);

  const amount = useMemo(() => {
    if (!bill) return 0;
    if (share.kind === 'all') return due;
    if (share.kind === 'split') return Math.min(due, ceil2(due / share.people));
    return Math.min(due, Math.max(0, round2(toNumber(share.value))));
  }, [bill, due, share]);
  const tip = tipChoice.kind === 'percent' ? round2((amount * tipChoice.value) / 100) : tipChoice.kind === 'custom' ? Math.max(0, round2(toNumber(tipChoice.value))) : 0;
  const total = round2(amount + tip);
  const emailError = email.trim() && !EMAIL.test(email.trim()) ? 'Revisa el correo' : null;

  const refresh = useCallback(async () => {
    try {
      setView(await api.tablePay(token));
    } catch {
      // sin conexión: se intenta en la próxima vuelta
    }
  }, [token]);

  // Mientras no está pagando, la cuenta se mantiene al día (alguien más de la mesa pudo pagar).
  useEffect(() => {
    if (intent) return;
    const id = window.setInterval(refresh, 10_000);
    return () => window.clearInterval(id);
  }, [intent, refresh]);

  const finish = useCallback(
    async (paymentIntentId: string, paid?: { amount: number; tip: number }) => {
      setBusy(true);
      try {
        const result = await api.tablePayConfirm(token, paymentIntentId);
        setView(result.view);
        setIntent(null);
        requestId.current = newRequestId();
        if (result.status === 'succeeded') {
          const after = result.view.bills.find((b) => b.id === billId) ?? result.view.bills[0];
          setDone({ amount: paid?.amount ?? 0, tip: paid?.tip ?? 0, due: toNumber(after?.due) });
        } else if (result.status === 'failed') {
          setError('El pago no se completó. Intenta de nuevo.');
        } else {
          setError('Tu banco todavía está procesando el pago. Si no se completa en un momento, intenta de nuevo.');
        }
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'No pudimos confirmar el pago. Recarga la página.');
      } finally {
        setBusy(false);
      }
    },
    [billId, token],
  );

  // Volvió de una página externa del método de pago.
  const handledReturn = useRef(false);
  useEffect(() => {
    if (!returnedIntent || handledReturn.current) return;
    handledReturn.current = true;
    window.history.replaceState(null, '', window.location.pathname);
    void finish(returnedIntent);
  }, [returnedIntent, finish]);

  const start = async () => {
    if (!bill || amount < 0.5 || emailError) return;
    setBusy(true);
    setError(null);
    try {
      const created = await api.tablePayIntent(token, {
        clientRequestId: requestId.current,
        billId: bill.id,
        amount,
        tip: tip || undefined,
        email: email.trim() || undefined,
      });
      setIntent({ ...created, amount, tip });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'No pudimos preparar el pago. Intenta de nuevo.');
      requestId.current = newRequestId();
      void refresh();
    } finally {
      setBusy(false);
    }
  };

  const header = (
    <header className="flex items-center justify-between gap-3 py-4">
      <BrandMark name={config.name} logoUrl={config.logoUrl} size={40} />
      <span className="rounded-full border border-line bg-surface px-3 py-1.5 text-sm font-bold text-ink">Mesa {view.table}</span>
    </header>
  );

  // ───── Pagado ─────
  const allPaid = view.bills.length > 0 && view.bills.every((b) => toNumber(b.due) <= 0);
  if (done || allPaid || view.closed) {
    const remaining = done ? done.due : 0;
    return (
      <main className="mx-auto flex min-h-dvh w-full max-w-lg flex-col px-4 pb-12">
        {header}
        <div className="flex flex-1 flex-col items-center justify-center gap-5 text-center">
          <span className="flex size-20 items-center justify-center rounded-full bg-success/15 text-success">
            <CheckCircle2 aria-hidden className="size-11" />
          </span>
          <div className="flex flex-col gap-2">
            <h1 className="m-0 text-3xl font-extrabold">{done ? '¡Gracias! Pago recibido' : 'Esta cuenta ya está pagada'}</h1>
            {done && done.amount > 0 ? (
              <p className="m-0 text-soft">
                Pagaste <span className="font-bold text-ink">{money(done.amount + done.tip, currency)}</span>
                {done.tip > 0 ? ` (incluye ${money(done.tip, currency)} de propina)` : ''}.
              </p>
            ) : null}
            {remaining > 0 ? (
              <p className="m-0 text-soft">
                En la mesa quedan <span className="font-bold text-ink">{money(remaining, currency)}</span> por pagar.
              </p>
            ) : (
              <p className="m-0 text-soft">Todo está pagado. ¡Que tengas buen día!</p>
            )}
            {email.trim() && done ? <p className="m-0 text-sm text-muted">Te enviamos el recibo a {email.trim()}.</p> : null}
          </div>
          {remaining > 0 && !view.closed ? (
            <Button
              tone="ghost"
              onClick={() => {
                setDone(null);
                setShare({ kind: 'all' });
              }}
            >
              Pagar otra parte
            </Button>
          ) : null}
        </div>
      </main>
    );
  }

  if (!bill) {
    return (
      <main className="mx-auto flex min-h-dvh w-full max-w-lg flex-col px-4">
        {header}
        <Notice>Todavía no hay nada en la cuenta de esta mesa.</Notice>
      </main>
    );
  }

  const locked = !!intent || busy;
  const discount = toNumber(bill.discountTotal);
  const paidSoFar = toNumber(bill.amountPaid);

  return (
    <main className="mx-auto w-full max-w-lg px-4 pb-16">
      {header}
      <div className="flex flex-col gap-5">
        <div className="flex flex-col gap-1">
          <h1 className="m-0 text-3xl font-extrabold">Paga desde tu celular</h1>
          <p className="m-0 text-soft">Todo, tu parte o el monto que quieras. Nadie más ve tu tarjeta.</p>
        </div>

        {view.bills.length > 1 ? (
          <div role="radiogroup" aria-label="Cuenta" className="flex flex-wrap gap-2">
            {view.bills.map((b) => (
              <button
                key={b.id}
                type="button"
                role="radio"
                aria-checked={b.id === bill.id}
                disabled={locked}
                onClick={() => setBillId(b.id)}
                className={`press cursor-pointer rounded-full border px-4 py-2 text-sm font-bold ${b.id === bill.id ? 'border-brand bg-brand-soft text-ink' : 'border-line bg-surface-2 text-soft'}`}
              >
                {b.label} · {toNumber(b.due) > 0 ? money(b.due, currency) : 'Pagada'}
              </button>
            ))}
          </div>
        ) : null}

        <Section
          title={bill.label}
          aside={<Receipt aria-hidden className="size-5 text-accent-text" />}
        >
          <button
            type="button"
            onClick={() => setShowItems((v) => !v)}
            aria-expanded={showItems}
            className="flex cursor-pointer items-center justify-between rounded-2xl border border-line bg-surface-2 px-4 py-3 text-left text-sm font-semibold text-ink"
          >
            Ver lo que pidieron ({bill.items.reduce((a, i) => a + i.quantity, 0)})
            <ChevronDown aria-hidden className={`size-4 transition-transform ${showItems ? 'rotate-180' : ''}`} />
          </button>
          {showItems ? (
            <ul className="m-0 flex list-none flex-col gap-2 p-0">
              {bill.items.map((i) => (
                <li key={i.id} className="flex items-start justify-between gap-3 text-sm">
                  <span className="min-w-0">
                    <span className="font-semibold text-ink">
                      {i.quantity}× {i.name}
                    </span>
                    {i.modifiers.length ? <span className="block text-xs text-muted">{i.modifiers.join(', ')}</span> : null}
                  </span>
                  <span className="tabular-nums text-soft">{money(i.lineTotal, currency)}</span>
                </li>
              ))}
            </ul>
          ) : null}
          <div className="flex flex-col gap-1.5 border-t border-line pt-3">
            <Row label="Subtotal" value={money(bill.subtotal, currency)} />
            {discount > 0 ? <Row label="Descuentos" value={`−${money(discount, currency)}`} tone="success" /> : null}
            <Row label="Impuestos" value={money(bill.taxTotal, currency)} />
            {toNumber(bill.tipTotal) > 0 ? <Row label="Propinas ya dejadas" value={money(bill.tipTotal, currency)} /> : null}
            <Row label="Total" value={money(bill.total, currency)} />
            {paidSoFar > 0 ? <Row label="Ya pagado" value={`−${money(paidSoFar, currency)}`} tone="success" /> : null}
            <Row label="Por pagar" value={money(due, currency)} strong />
          </div>
        </Section>

        <Section title="¿Cuánto vas a pagar?" aside={<Users aria-hidden className="size-5 text-accent-text" />}>
          <div role="radiogroup" aria-label="Cuánto pagar" className="grid grid-cols-3 gap-2">
            <Choice on={share.kind === 'all'} disabled={locked} onClick={() => setShare({ kind: 'all' })} label="Todo" sub={money(due, currency)} />
            <Choice
              on={share.kind === 'split'}
              disabled={locked}
              onClick={() => setShare({ kind: 'split', people: share.kind === 'split' ? share.people : 2 })}
              label="Dividir"
              sub="en partes iguales"
            />
            <Choice
              on={share.kind === 'custom'}
              disabled={locked}
              onClick={() => setShare({ kind: 'custom', value: share.kind === 'custom' ? share.value : '' })}
              label="Otro"
              sub="monto"
            />
          </div>
          {share.kind === 'split' ? (
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-line bg-surface-2 px-4 py-3">
              <span className="text-sm text-soft">
                Entre <span className="font-bold text-ink">{share.people}</span> personas:{' '}
                <span className="font-bold text-ink">{money(amount, currency)}</span> cada una
              </span>
              <Stepper label="personas" size="sm" min={2} max={20} value={share.people} onChange={(people) => !locked && setShare({ kind: 'split', people })} />
            </div>
          ) : null}
          {share.kind === 'custom' ? (
            <label className="flex flex-col gap-1.5">
              <span className="text-sm font-semibold text-soft">Monto (máximo {money(due, currency)})</span>
              <input
                inputMode="decimal"
                value={share.value}
                disabled={locked}
                onChange={(e) => setShare({ kind: 'custom', value: e.target.value.replace(/[^0-9.]/g, '') })}
                placeholder="0.00"
                className="h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base text-ink placeholder:text-muted"
              />
              {toNumber(share.value) > due ? <span className="text-sm text-danger">Es más de lo que falta: se cobrarán {money(due, currency)}</span> : null}
            </label>
          ) : null}
        </Section>

        <Section title="Propina">
          <div role="radiogroup" aria-label="Propina" className="grid grid-cols-3 gap-2 sm:grid-cols-5">
            {presets.map((p) => (
              <Choice
                key={p}
                on={tipChoice.kind === 'percent' && tipChoice.value === p}
                disabled={locked}
                onClick={() => setTipChoice({ kind: 'percent', value: p })}
                label={`${p}%`}
                sub={money(round2((amount * p) / 100), currency)}
              />
            ))}
            <Choice on={tipChoice.kind === 'custom'} disabled={locked} onClick={() => setTipChoice({ kind: 'custom', value: '' })} label="Otra" sub="monto" />
            <Choice on={tipChoice.kind === 'none'} disabled={locked} onClick={() => setTipChoice({ kind: 'none' })} label="Sin" sub="propina" />
          </div>
          {tipChoice.kind === 'custom' ? (
            <input
              aria-label="Monto de propina"
              inputMode="decimal"
              value={tipChoice.value}
              disabled={locked}
              onChange={(e) => setTipChoice({ kind: 'custom', value: e.target.value.replace(/[^0-9.]/g, '') })}
              placeholder="0.00"
              className="h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base text-ink placeholder:text-muted"
            />
          ) : null}
          <p className="m-0 text-xs text-muted">El 100 % de la propina es para el equipo.</p>
        </Section>

        <Section title="Pagar">
          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold text-soft">Email para el recibo (opcional)</span>
            <input
              type="email"
              autoComplete="email"
              value={email}
              disabled={locked}
              onChange={(e) => setEmail(e.target.value)}
              className="h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base text-ink"
            />
            {emailError ? <span className="text-sm text-danger">{emailError}</span> : null}
          </label>
          <div className="flex flex-col gap-1.5 border-t border-line pt-3">
            <Row label="Tu parte" value={money(amount, currency)} />
            <Row label="Propina" value={money(tip, currency)} />
            <Row label="Total a pagar" value={money(total, currency)} strong />
          </div>
          {error ? <Notice tone="danger">{error}</Notice> : null}
          {!view.payable ? (
            <Notice>El pago con el celular no está disponible ahora. Pide la cuenta a tu mesero.</Notice>
          ) : intent && view.publishableKey ? (
            <div className="flex flex-col gap-3">
              <StripePay
                publishableKey={view.publishableKey}
                clientSecret={intent.clientSecret}
                amountLabel={money(intent.amount + intent.tip, currency)}
                returnUrl={`${window.location.origin}/cuenta/${token}`}
                onPaid={(id) => {
                  if (id) void finish(id, { amount: intent.amount, tip: intent.tip });
                }}
              />
              <button
                type="button"
                onClick={() => {
                  setIntent(null);
                  requestId.current = newRequestId();
                }}
                className="cursor-pointer self-center border-0 bg-transparent text-sm font-semibold text-muted underline"
              >
                Cambiar el monto
              </button>
            </div>
          ) : (
            <Button className="h-14 w-full text-base" onClick={start} loading={busy} disabled={amount < 0.5 || !!emailError}>
              {amount < 0.5 ? 'Elige cuánto pagar' : `Continuar · ${money(total, currency)}`}
            </Button>
          )}
        </Section>
      </div>
    </main>
  );
}
