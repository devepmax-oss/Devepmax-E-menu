'use client';

import { Elements, ExpressCheckoutElement, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { loadStripe, type Appearance, type Stripe } from '@stripe/stripe-js';
import { Lock } from 'lucide-react';
import { useMemo, useState } from 'react';
import { useLang, useT } from '@/components/i18n';
import { Button, Notice } from '@/components/ui';

const stripes = new Map<string, Promise<Stripe | null>>();
const getStripe = (key: string) => {
  if (!stripes.has(key)) stripes.set(key, loadStripe(key));
  return stripes.get(key)!;
};

function cssVar(name: string, fallback: string) {
  if (typeof window === 'undefined') return fallback;
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback;
}

/** Formulario de pago de Stripe con los colores del restaurante. */
export function StripePay(props: {
  publishableKey: string;
  clientSecret: string;
  amountLabel: string;
  returnUrl: string;
  /** Si se conoce (pedido web), no se le vuelve a pedir nombre y teléfono. */
  customer?: { name: string; email: string; phone: string };
  onPaid: (paymentIntentId?: string) => void;
}) {
  const lang = useLang();
  const appearance = useMemo<Appearance>(() => {
    const dark = cssVar('color-scheme', 'dark') !== 'light';
    return {
      theme: dark ? 'night' : 'stripe',
      variables: {
        colorPrimary: cssVar('--brand', '#FF7A1A'),
        colorBackground: cssVar('--surface-2', dark ? '#221B15' : '#F4ECE2'),
        colorText: cssVar('--ink', dark ? '#F8F1E7' : '#1D150E'),
        colorTextSecondary: cssVar('--muted', '#A99A88'),
        colorDanger: cssVar('--danger', '#FF6B5E'),
        borderRadius: '14px',
        fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, sans-serif',
        spacingUnit: '4px',
      },
    };
  }, []);

  return (
    <Elements stripe={getStripe(props.publishableKey)} options={{ clientSecret: props.clientSecret, appearance, locale: lang }}>
      <PayForm {...props} />
    </Elements>
  );
}

function PayForm({
  amountLabel,
  returnUrl,
  customer,
  onPaid,
}: {
  amountLabel: string;
  returnUrl: string;
  customer?: { name: string; email: string; phone: string };
  onPaid: (paymentIntentId?: string) => void;
}) {
  const stripe = useStripe();
  const elements = useElements();
  const t = useT();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [express, setExpress] = useState(false);

  const confirm = async () => {
    if (!stripe || !elements) return;
    setBusy(true);
    setError(null);
    const { error: failure, paymentIntent } = await stripe.confirmPayment({
      elements,
      redirect: 'if_required',
      confirmParams: {
        return_url: returnUrl,
        ...(customer
          ? { payment_method_data: { billing_details: { name: customer.name, email: customer.email || undefined, phone: customer.phone } } }
          : {}),
      },
    });
    if (failure) {
      setError(failure.message ?? t('No se pudo completar el pago. Revisa los datos de la tarjeta.', 'The payment could not be completed. Check your card details.'));
      setBusy(false);
      return;
    }
    onPaid(paymentIntent?.id);
  };

  return (
    <div className="flex flex-col gap-4">
      <div className={express ? 'flex flex-col gap-3' : 'hidden'}>
        <ExpressCheckoutElement
          onReady={(e) => setExpress(!!e.availablePaymentMethods)}
          onConfirm={confirm}
          options={{ buttonHeight: 52, buttonType: { applePay: 'order', googlePay: 'order' } }}
        />
        <div className="flex items-center gap-3 text-xs font-semibold tracking-wide text-muted uppercase">
          <span className="h-px flex-1 bg-line" /> {t('o con tarjeta', 'or pay by card')} <span className="h-px flex-1 bg-line" />
        </div>
      </div>
      <PaymentElement options={{ layout: 'tabs', ...(customer ? { fields: { billingDetails: { name: 'never', phone: 'never' } } } : {}) }} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <Button className="h-14 w-full text-base" onClick={confirm} loading={busy} disabled={!stripe || !elements}>
        <Lock aria-hidden className="size-4" /> {t('Pagar', 'Pay')} {amountLabel}
      </Button>
      <p className="m-0 text-center text-xs text-muted">{t('Pago seguro con Stripe. Tus datos de tarjeta no pasan por el restaurante.', 'Secure payment with Stripe. Your card details never reach the restaurant.')}</p>
    </div>
  );
}
