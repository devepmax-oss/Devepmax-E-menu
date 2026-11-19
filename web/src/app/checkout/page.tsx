'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { loadStripe } from '@stripe/stripe-js';
import { Elements } from '@stripe/react-stripe-js';
import { getCart, checkoutOrder, prepareStripePayment } from '@/lib/api';
import StripePaymentForm from '@/app/checkout/stripe-payment-form';

type CartResponse = {
  id?: string;
  sessionId: string;
  items: Array<{
    id: string;
    totalPrice: string;
    product: { name: string };
  }>;
  subtotal: string;
};

type SavedCustomerInfo = {
  customerName: string;
  customerPhone: string;
  customerEmail: string;
};

type PaymentMethod = 'in_person' | 'online';
type TipMode = 'none' | '5' | '10' | '15' | 'custom';

type PublicSettings = {
  currency?: string;
  acceptsPickup?: boolean;
  acceptsDelivery?: boolean;
  prepTimeMinutes?: number;
  isStoreOpen?: boolean;
  supportPhone?: string | null;
  taxRate?: number;
  taxPercentage?: number;
  storeStatusMessage?: string | null;
};

const EMPTY_CART: CartResponse = {
  sessionId: '',
  items: [],
  subtotal: '0.00',
};

const DEFAULT_SETTINGS: PublicSettings = {
  currency: 'USD',
  acceptsPickup: true,
  acceptsDelivery: true,
  prepTimeMinutes: 20,
  isStoreOpen: true,
  supportPhone: null,
  taxRate: 0,
  taxPercentage: 0,
  storeStatusMessage: null,
};

const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ||
  process.env.NEXT_PUBLIC_BACKEND_URL ||
  'https://gopicaderabackend-production.up.railway.app';

const stripePromise = loadStripe(
  process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY || '',
);

function roundMoney(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

function parseMoney(value: unknown) {
  const numberValue = Number(value ?? 0);
  return Number.isFinite(numberValue) && numberValue > 0 ? numberValue : 0;
}

function money(value: number) {
  return `$${roundMoney(value).toFixed(2)}`;
}

async function getPublicSettings(): Promise<PublicSettings> {
  const response = await fetch(`${API_BASE_URL}/api/settings/public`, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'Mozilla/5.0 Restaurant Web Checkout',
    },
    cache: 'no-store',
  });

  if (!response.ok) {
    throw new Error(`No se pudo cargar la configuración: ${response.status}`);
  }

  return response.json() as Promise<PublicSettings>;
}

export default function CheckoutPage() {
  const [cart, setCart] = useState<CartResponse | null>(null);
  const [settings, setSettings] = useState<PublicSettings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const [customerName, setCustomerName] = useState('');
  const [customerPhone, setCustomerPhone] = useState('');
  const [customerEmail, setCustomerEmail] = useState('');
  const [orderType, setOrderType] = useState<'pickup' | 'delivery'>('pickup');

  const [deliveryStreet, setDeliveryStreet] = useState('');
  const [deliveryCity, setDeliveryCity] = useState('');
  const [deliveryState, setDeliveryState] = useState('');
  const [deliveryZipCode, setDeliveryZipCode] = useState('');
  const [deliveryInstructions, setDeliveryInstructions] = useState('');

  const [notes, setNotes] = useState('');
  const [tipMode, setTipMode] = useState<TipMode>('none');
  const [customTip, setCustomTip] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('in_person');

  const [clientSecret, setClientSecret] = useState('');
  const [pendingOrderCode, setPendingOrderCode] = useState('');
  const [creatingPayment, setCreatingPayment] = useState(false);
  const [stripeError, setStripeError] = useState('');

  const onlineOrderCreatedRef = useRef(false);

  const subtotal = parseMoney(cart?.subtotal);
  const taxRate = parseMoney(settings.taxRate);
  const taxPercentage = Number.isFinite(Number(settings.taxPercentage))
    ? Number(settings.taxPercentage)
    : taxRate * 100;

  const taxAmount = useMemo(
    () => roundMoney(subtotal * taxRate),
    [subtotal, taxRate],
  );

  const tipAmount = useMemo(() => {
    if (tipMode === 'none') return 0;
    if (tipMode === 'custom') return roundMoney(parseMoney(customTip));

    const percentage = Number(tipMode);
    if (!Number.isFinite(percentage)) return 0;

    return roundMoney(subtotal * (percentage / 100));
  }, [customTip, subtotal, tipMode]);

  const grandTotal = useMemo(
    () => roundMoney(subtotal + taxAmount + tipAmount),
    [subtotal, taxAmount, tipAmount],
  );

  const storeOpen = settings.isStoreOpen !== false;
  const acceptsPickup = settings.acceptsPickup !== false;
  const acceptsDelivery = settings.acceptsDelivery !== false;
  const selectedOrderTypeAllowed =
    orderType === 'pickup' ? acceptsPickup : acceptsDelivery;
  const canCheckout = storeOpen && selectedOrderTypeAllowed;

  useEffect(() => {
    let cancelled = false;

    async function initializeCheckout() {
      try {
        const savedCustomerInfo = localStorage.getItem('customer_info');
        const sessionId = localStorage.getItem('guest_session_id');

        let parsedCustomerInfo: SavedCustomerInfo | null = null;

        if (savedCustomerInfo) {
          try {
            parsedCustomerInfo = JSON.parse(savedCustomerInfo) as SavedCustomerInfo;
          } catch (error) {
            console.error('Failed to parse customer_info', error);
          }
        }

        const [nextCart, nextSettings] = await Promise.all([
          sessionId ? getCart(sessionId) : Promise.resolve(EMPTY_CART),
          getPublicSettings().catch((error) => {
            console.error(error);
            return DEFAULT_SETTINGS;
          }),
        ]);

        if (!cancelled) {
          if (parsedCustomerInfo) {
            setCustomerName(parsedCustomerInfo.customerName || '');
            setCustomerPhone(parsedCustomerInfo.customerPhone || '');
            setCustomerEmail(parsedCustomerInfo.customerEmail || '');
          }

          setSettings({ ...DEFAULT_SETTINGS, ...nextSettings });
          setCart(nextCart);

          if (nextSettings.acceptsPickup === false && nextSettings.acceptsDelivery !== false) {
            setOrderType('delivery');
          }
        }
      } catch (error) {
        console.error(error);
        if (!cancelled) setCart(EMPTY_CART);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    void initializeCheckout();

    return () => {
      cancelled = true;
    };
  }, []);

  function resetStripeState() {
    setClientSecret('');
    setPendingOrderCode('');
    setStripeError('');
    setCreatingPayment(false);
    onlineOrderCreatedRef.current = false;
  }

  function selectTipMode(nextMode: TipMode) {
    setTipMode(nextMode);

    if (nextMode !== 'custom') {
      setCustomTip('');
    }

    if (paymentMethod === 'online') resetStripeState();
  }

  const customerReady = Boolean(customerName.trim() && customerPhone.trim());

  const deliveryReady =
    orderType === 'pickup' ||
    Boolean(
      deliveryStreet.trim() &&
        deliveryCity.trim() &&
        deliveryState.trim() &&
        deliveryZipCode.trim(),
    );

  const onlineReady =
    customerReady &&
    deliveryReady &&
    Boolean(cart?.items.length) &&
    canCheckout;

  useEffect(() => {
    if (paymentMethod !== 'online') return;
    if (!onlineReady) return;
    if (clientSecret || onlineOrderCreatedRef.current) return;

    async function prepareOnlinePayment() {
      try {
        const sessionId = localStorage.getItem('guest_session_id');

        if (!sessionId) {
          throw new Error('No se encontró el carrito');
        }

        onlineOrderCreatedRef.current = true;
        setCreatingPayment(true);
        setStripeError('');

        const paymentIntent = await prepareStripePayment({
          sessionId,
          customerName: customerName.trim(),
          customerPhone: customerPhone.trim(),
          customerEmail: customerEmail.trim() || undefined,
          orderType,
          deliveryStreet: orderType === 'delivery' ? deliveryStreet.trim() : undefined,
          deliveryCity: orderType === 'delivery' ? deliveryCity.trim() : undefined,
          deliveryState: orderType === 'delivery' ? deliveryState.trim() : undefined,
          deliveryZipCode: orderType === 'delivery' ? deliveryZipCode.trim() : undefined,
          deliveryInstructions:
            orderType === 'delivery' ? deliveryInstructions.trim() : undefined,
          notes: notes.trim() || undefined,
          tip: tipAmount,
        });

        setPendingOrderCode(paymentIntent.publicCode);
        setClientSecret(paymentIntent.clientSecret);

        localStorage.setItem(
          'customer_info',
          JSON.stringify({
            customerName,
            customerPhone,
            customerEmail,
          }),
        );
      } catch (error) {
        console.error(error);

        setStripeError(
          error instanceof Error
            ? error.message
            : 'No se pudieron cargar los métodos de pago',
        );

        onlineOrderCreatedRef.current = false;
      } finally {
        setCreatingPayment(false);
      }
    }

    void prepareOnlinePayment();
  }, [
    paymentMethod,
    onlineReady,
    clientSecret,
    customerName,
    customerPhone,
    customerEmail,
    orderType,
    deliveryStreet,
    deliveryCity,
    deliveryState,
    deliveryZipCode,
    deliveryInstructions,
    notes,
    tipAmount,
    cart?.items.length,
  ]);

  async function handleSubmitInPerson(e: React.FormEvent) {
    e.preventDefault();

    try {
      const sessionId = localStorage.getItem('guest_session_id');

      if (!sessionId) {
        alert('No se encontró el carrito');
        return;
      }

      if (!storeOpen) {
        alert(settings.storeStatusMessage || 'El restaurante está cerrado en este momento');
        return;
      }

      if (!selectedOrderTypeAllowed) {
        alert(
          orderType === 'pickup'
            ? 'Pickup no está disponible en este momento'
            : 'Delivery no está disponible en este momento',
        );
        return;
      }

      if (!customerName.trim() || !customerPhone.trim()) {
        alert('Nombre y teléfono son obligatorios');
        return;
      }

      if (
        orderType === 'delivery' &&
        (!deliveryStreet.trim() ||
          !deliveryCity.trim() ||
          !deliveryState.trim() ||
          !deliveryZipCode.trim())
      ) {
        alert('Completa la dirección de entrega');
        return;
      }

      setSubmitting(true);

      const order = await checkoutOrder({
        sessionId,
        customerName: customerName.trim(),
        customerPhone: customerPhone.trim(),
        customerEmail: customerEmail.trim() || undefined,
        orderType,
        deliveryStreet: orderType === 'delivery' ? deliveryStreet.trim() : undefined,
        deliveryCity: orderType === 'delivery' ? deliveryCity.trim() : undefined,
        deliveryState: orderType === 'delivery' ? deliveryState.trim() : undefined,
        deliveryZipCode: orderType === 'delivery' ? deliveryZipCode.trim() : undefined,
        deliveryInstructions:
          orderType === 'delivery' ? deliveryInstructions.trim() : undefined,
        notes: notes.trim() || undefined,
        tip: tipAmount,
        paymentMethod: 'in_person',
      });

      localStorage.setItem(
        'customer_info',
        JSON.stringify({
          customerName,
          customerPhone,
          customerEmail,
        }),
      );

      localStorage.removeItem('guest_session_id');
      window.dispatchEvent(new Event('cart-updated'));
      window.location.href = `/order-success?code=${order.publicCode}`;
    } catch (error) {
      console.error(error);
      alert(error instanceof Error ? error.message : 'No se pudo completar la orden');
    } finally {
      setSubmitting(false);
    }
  }

  if (loading) {
    return (
      <main className="min-h-screen bg-neutral-100 px-4 py-8 transition-colors dark:bg-black">
        <div className="mx-auto max-w-6xl text-neutral-700 dark:text-neutral-300">
          Cargando checkout...
        </div>
      </main>
    );
  }

  if (!cart?.items.length) {
    return (
      <main className="min-h-screen bg-neutral-100 px-4 py-8 transition-colors dark:bg-black">
        <div className="mx-auto max-w-6xl rounded-3xl bg-white p-8 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10 dark:text-neutral-100">
          Tu carrito está vacío.
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-neutral-100 px-4 py-8 transition-colors dark:bg-black">
      <section className="mx-auto max-w-6xl">
        <div className="mb-8">
          <h1 className="text-4xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
            Checkout
          </h1>
          <p className="mt-2 text-base text-neutral-600 transition-colors dark:text-neutral-400">
            Completa tus datos para confirmar el pedido
          </p>
        </div>

        {!storeOpen ? (
          <div className="mb-6 rounded-3xl bg-red-50 p-5 text-red-800 ring-1 ring-red-100 dark:bg-red-950/30 dark:text-red-200 dark:ring-red-900/40">
            <p className="text-lg font-extrabold">El restaurante está cerrado</p>
            <p className="mt-1 text-sm font-medium">
              {settings.storeStatusMessage ||
                'No estamos aceptando órdenes en este momento.'}
            </p>
          </div>
        ) : null}

        {storeOpen && settings.prepTimeMinutes ? (
          <div className="mb-6 rounded-3xl bg-emerald-50 p-5 text-emerald-900 ring-1 ring-emerald-100 dark:bg-emerald-950/30 dark:text-emerald-200 dark:ring-emerald-900/40">
            <p className="text-lg font-extrabold">Estamos abiertos</p>
            <p className="mt-1 text-sm font-medium">
              Tiempo estimado de preparación: {settings.prepTimeMinutes} minutos.
            </p>
          </div>
        ) : null}

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1.15fr_0.85fr]">
          <form
            onSubmit={handleSubmitInPerson}
            className="rounded-3xl bg-white p-6 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10 sm:p-8"
          >
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <input
                value={customerName}
                onChange={(e) => {
                  setCustomerName(e.target.value);
                  if (paymentMethod === 'online') resetStripeState();
                }}
                placeholder="Nombre completo"
                className="rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
              />

              <input
                value={customerPhone}
                onChange={(e) => {
                  setCustomerPhone(e.target.value);
                  if (paymentMethod === 'online') resetStripeState();
                }}
                placeholder="Teléfono"
                className="rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
              />

              <input
                value={customerEmail}
                onChange={(e) => {
                  setCustomerEmail(e.target.value);
                  if (paymentMethod === 'online') resetStripeState();
                }}
                placeholder="Email (opcional)"
                className="sm:col-span-2 rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
              />
            </div>

            <div className="mt-8">
              <p className="mb-3 text-sm font-semibold text-neutral-900 transition-colors dark:text-neutral-100">
                Tipo de orden
              </p>

              <div className="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  disabled={!acceptsPickup}
                  onClick={() => {
                    setOrderType('pickup');
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  className={`rounded-2xl px-4 py-3 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40 ${
                    orderType === 'pickup'
                      ? 'bg-neutral-950 text-white dark:bg-white dark:text-black'
                      : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                  }`}
                >
                  Pickup
                </button>

                <button
                  type="button"
                  disabled={!acceptsDelivery}
                  onClick={() => {
                    setOrderType('delivery');
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  className={`rounded-2xl px-4 py-3 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40 ${
                    orderType === 'delivery'
                      ? 'bg-neutral-950 text-white dark:bg-white dark:text-black'
                      : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                  }`}
                >
                  Delivery
                </button>
              </div>

              {!selectedOrderTypeAllowed ? (
                <div className="mt-4 rounded-2xl bg-red-50 p-4 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">
                  {orderType === 'pickup'
                    ? 'Pickup no está disponible en este momento.'
                    : 'Delivery no está disponible en este momento.'}
                </div>
              ) : null}
            </div>

            {orderType === 'delivery' ? (
              <div className="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <input
                  value={deliveryStreet}
                  onChange={(e) => {
                    setDeliveryStreet(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Calle / dirección"
                  className="sm:col-span-2 rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />

                <input
                  value={deliveryCity}
                  onChange={(e) => {
                    setDeliveryCity(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Ciudad"
                  className="rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />

                <input
                  value={deliveryState}
                  onChange={(e) => {
                    setDeliveryState(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Estado / provincia"
                  className="rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />

                <input
                  value={deliveryZipCode}
                  onChange={(e) => {
                    setDeliveryZipCode(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Zip code"
                  className="sm:col-span-2 rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />

                <textarea
                  value={deliveryInstructions}
                  onChange={(e) => {
                    setDeliveryInstructions(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Instrucciones de entrega"
                  className="sm:col-span-2 min-h-28 rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />
              </div>
            ) : null}

            <div className="mt-8">
              <p className="mb-3 text-sm font-semibold text-neutral-900 transition-colors dark:text-neutral-100">
                Propina
              </p>

              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                {[
                  { mode: 'none' as TipMode, label: 'Sin propina' },
                  { mode: '5' as TipMode, label: '5%' },
                  { mode: '10' as TipMode, label: '10%' },
                  { mode: '15' as TipMode, label: '15%' },
                ].map((option) => (
                  <button
                    key={option.mode}
                    type="button"
                    onClick={() => selectTipMode(option.mode)}
                    className={`rounded-2xl px-4 py-3 text-sm font-semibold transition ${
                      tipMode === option.mode
                        ? 'bg-yellow-400 text-black'
                        : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                    }`}
                  >
                    {option.label}
                  </button>
                ))}
              </div>

              <button
                type="button"
                onClick={() => selectTipMode('custom')}
                className={`mt-3 w-full rounded-2xl px-4 py-3 text-sm font-semibold transition ${
                  tipMode === 'custom'
                    ? 'bg-yellow-400 text-black'
                    : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                }`}
              >
                Propina personalizada
              </button>

              {tipMode === 'custom' ? (
                <input
                  value={customTip}
                  onChange={(e) => {
                    setCustomTip(e.target.value);
                    if (paymentMethod === 'online') resetStripeState();
                  }}
                  placeholder="Monto personalizado"
                  inputMode="decimal"
                  className="mt-3 w-full rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
                />
              ) : null}
            </div>

            <div className="mt-8">
              <p className="mb-3 text-sm font-semibold text-neutral-900 transition-colors dark:text-neutral-100">
                Método de pago
              </p>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <button
                  type="button"
                  onClick={() => {
                    setPaymentMethod('in_person');
                    resetStripeState();
                  }}
                  className={`rounded-2xl px-4 py-4 text-sm font-semibold transition ${
                    paymentMethod === 'in_person'
                      ? 'bg-yellow-400 text-black'
                      : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                  }`}
                >
                  Pago en persona
                </button>

                <button
                  type="button"
                  disabled={!canCheckout}
                  onClick={() => {
                    setPaymentMethod('online');
                    resetStripeState();
                  }}
                  className={`rounded-2xl px-4 py-4 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40 ${
                    paymentMethod === 'online'
                      ? 'bg-yellow-400 text-black'
                      : 'bg-neutral-100 text-neutral-900 ring-1 ring-black/5 dark:bg-neutral-900 dark:text-neutral-100 dark:ring-white/10'
                  }`}
                >
                  Pago online
                </button>
              </div>

              {paymentMethod === 'in_person' ? (
                <div className="mt-4 rounded-2xl bg-neutral-100 p-4 text-sm text-neutral-600 transition-colors dark:bg-neutral-900 dark:text-neutral-400">
                  Pagarás cuando recibas o retires tu pedido.
                </div>
              ) : null}

              {paymentMethod === 'online' && !onlineReady ? (
                <div className="mt-4 rounded-2xl bg-neutral-100 p-4 text-sm text-neutral-600 transition-colors dark:bg-neutral-900 dark:text-neutral-400">
                  Completa nombre, teléfono y dirección de entrega para cargar los
                  métodos de pago automáticamente.
                </div>
              ) : null}

              {paymentMethod === 'online' && creatingPayment && !clientSecret ? (
                <div className="mt-4 rounded-2xl bg-neutral-100 p-4 text-sm text-neutral-600 transition-colors dark:bg-neutral-900 dark:text-neutral-400">
                  Cargando métodos de pago...
                </div>
              ) : null}

              {paymentMethod === 'online' && stripeError ? (
                <div className="mt-4 rounded-2xl bg-red-50 p-4 text-sm text-red-600 dark:bg-red-950/30 dark:text-red-300">
                  {stripeError}
                </div>
              ) : null}

              {paymentMethod === 'online' && clientSecret ? (
                <div className="mt-4">
                  <Elements
                    key={clientSecret}
                    stripe={stripePromise}
                    options={{
                      clientSecret,
                      appearance: {
                        theme: 'night',
                        variables: {
                          colorPrimary: '#facc15',
                          borderRadius: '16px',
                        },
                      },
                    }}
                  >
                    <StripePaymentForm
                      customerName={customerName}
                      customerEmail={customerEmail}
                      onPaid={() => {
                        localStorage.removeItem('guest_session_id');
                        window.dispatchEvent(new Event('cart-updated'));

                        if (pendingOrderCode) {
                          window.location.href = `/order-success?code=${pendingOrderCode}`;
                        }
                      }}
                    />
                  </Elements>
                </div>
              ) : null}
            </div>

            <div className="mt-8 grid grid-cols-1 gap-4">
              <textarea
                value={notes}
                onChange={(e) => {
                  setNotes(e.target.value);
                  if (paymentMethod === 'online') resetStripeState();
                }}
                placeholder="Notas del pedido"
                className="min-h-28 rounded-2xl border border-neutral-300 bg-white px-4 py-3 text-sm text-neutral-950 outline-none transition focus:border-neutral-900 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-100 dark:placeholder:text-neutral-500 dark:focus:border-neutral-600"
              />
            </div>

            {paymentMethod === 'in_person' ? (
              <button
                type="submit"
                disabled={submitting || !canCheckout}
                className="mt-8 w-full rounded-2xl bg-yellow-400 px-6 py-4 text-base font-semibold text-black transition hover:bg-yellow-300 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {submitting ? 'Procesando...' : 'Confirmar pedido'}
              </button>
            ) : null}
          </form>

          <aside className="rounded-3xl bg-white p-6 shadow-sm ring-1 ring-black/5 transition-colors dark:bg-neutral-950 dark:ring-white/10 sm:p-8">
            <h2 className="mb-5 text-2xl font-bold text-neutral-950 transition-colors dark:text-neutral-100">
              Resumen
            </h2>

            <div className="space-y-4">
              {cart.items.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between gap-4 border-b border-neutral-200 pb-4 text-sm transition-colors dark:border-white/10"
                >
                  <span className="text-neutral-700 transition-colors dark:text-neutral-300">
                    {item.product.name}
                  </span>
                  <span className="font-semibold text-neutral-950 transition-colors dark:text-neutral-100">
                    ${item.totalPrice}
                  </span>
                </div>
              ))}
            </div>

            <div className="mt-6 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-base font-medium text-neutral-600 transition-colors dark:text-neutral-400">
                  Subtotal
                </span>
                <span className="text-xl font-bold text-neutral-950 transition-colors dark:text-neutral-100">
                  {money(subtotal)}
                </span>
              </div>

              <div className="flex items-center justify-between">
                <span className="text-base font-medium text-neutral-600 transition-colors dark:text-neutral-400">
                  Sales Tax ({taxPercentage.toFixed(2)}%)
                </span>
                <span className="text-xl font-bold text-neutral-950 transition-colors dark:text-neutral-100">
                  {money(taxAmount)}
                </span>
              </div>

              <div className="flex items-center justify-between">
                <span className="text-base font-medium text-neutral-600 transition-colors dark:text-neutral-400">
                  Propina
                </span>
                <span className="text-xl font-bold text-neutral-950 transition-colors dark:text-neutral-100">
                  {money(tipAmount)}
                </span>
              </div>

              <div className="flex items-center justify-between border-t border-neutral-200 pt-4 dark:border-white/10">
                <span className="text-lg font-semibold text-neutral-700 transition-colors dark:text-neutral-300">
                  Total estimado
                </span>
                <span className="text-3xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100">
                  {money(grandTotal)}
                </span>
              </div>
            </div>

            <div className="mt-6 rounded-2xl bg-neutral-100 p-4 text-sm text-neutral-600 transition-colors dark:bg-neutral-900 dark:text-neutral-400">
              Método de pago seleccionado:{' '}
              <span className="font-bold text-neutral-950 dark:text-neutral-100">
                {paymentMethod === 'in_person' ? 'Pago en persona' : 'Pago online'}
              </span>
            </div>
          </aside>
        </div>
      </section>
    </main>
  );
}
