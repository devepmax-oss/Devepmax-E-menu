'use client';

import { useState } from 'react';
import {
  ExpressCheckoutElement,
  PaymentElement,
  useElements,
  useStripe,
} from '@stripe/react-stripe-js';

type Props = {
  customerName: string;
  customerEmail: string;
  onPaid?: () => void;
};

export default function StripePaymentForm({
  customerName,
  customerEmail,
  onPaid,
}: Props) {
  const stripe = useStripe();
  const elements = useElements();

  const [processing, setProcessing] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');

  async function confirmCurrentPayment() {
    if (!stripe || !elements) return;

    setProcessing(true);
    setErrorMessage('');

    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: {
        return_url: `${window.location.origin}/order-success`,
        payment_method_data: {
          billing_details: {
            name: customerName || undefined,
            email: customerEmail || undefined,
          },
        },
      },
      redirect: 'if_required',
    });

    if (error) {
      setErrorMessage(error.message || 'No se pudo completar el pago.');
      setProcessing(false);
      return;
    }

    setProcessing(false);
    onPaid?.();
  }

  return (
    <div className="mt-4 rounded-2xl bg-neutral-100 p-4 transition-colors dark:bg-neutral-900">
      <div className="mb-4">
        <ExpressCheckoutElement
          options={{
            buttonTheme: {
              applePay: 'black',
              googlePay: 'black',
            },
            buttonHeight: 48,
          }}
          onConfirm={async () => {
            await confirmCurrentPayment();
          }}
        />
      </div>

      <div className="mb-4">
        <PaymentElement
          options={{
            layout: 'tabs',
          }}
        />
      </div>

      {errorMessage ? (
        <p className="mb-4 text-sm text-red-600 dark:text-red-400">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        onClick={confirmCurrentPayment}
        disabled={!stripe || !elements || processing}
        className="w-full rounded-2xl bg-yellow-400 px-6 py-4 text-base font-semibold text-black transition hover:bg-yellow-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {processing ? 'Procesando pago...' : 'Pagar ahora'}
      </button>
    </div>
  );
}