/** Pagar desde la mesa con el celular (lo que devuelve /pay/:token). */
type Money = string | number;

export interface TablePayItem {
  id: string;
  name: string;
  quantity: number;
  lineTotal: Money;
  discount: Money;
  modifiers: string[];
}

export interface TablePayBill {
  id: string;
  label: string;
  status: 'UNPAID' | 'PARTIALLY_PAID' | 'PAID' | 'REFUNDED' | 'VOID';
  items: TablePayItem[];
  subtotal: Money;
  discountTotal: Money;
  taxTotal: Money;
  tipTotal: Money;
  total: Money;
  amountPaid: Money;
  due: Money;
  payments: { id: string; amount: Money; tipAmount: Money; createdAt: string }[];
}

export interface TablePayView {
  table: string;
  closed: boolean;
  payable: boolean;
  publishableKey: string | null;
  tipPercents: number[];
  bills: TablePayBill[];
}

export interface TablePayIntent {
  paymentId: string;
  clientSecret: string;
  amount: Money;
}

/** Recibo digital (lo que devuelve /receipts/:token). */
export interface Receipt {
  restaurant: {
    name: string;
    legalName: string | null;
    logoUrl: string | null;
    phone: string | null;
    email: string | null;
    address: string[];
    footer: string | null;
  };
  currency: string;
  timezone: string;
  id: string;
  status: TablePayBill['status'];
  kind: 'TABLE' | 'COUNTER' | 'PICKUP' | 'DELIVERY';
  label: string;
  orderNumbers: number[];
  date: string;
  items: TablePayItem[];
  discounts: { id: string; reason: string; amount: Money; item: string | null }[];
  subtotal: Money;
  discountTotal: Money;
  taxTotal: Money;
  deliveryFee: Money;
  tipTotal: Money;
  total: Money;
  amountPaid: Money;
  due: Money;
  refundedTotal: Money;
  payments: {
    id: string;
    method: string;
    reference: string | null;
    amount: Money;
    tipAmount: Money;
    cashTendered: Money | null;
    changeGiven: Money | null;
    createdAt: string;
  }[];
  refunds: { id: string; amount: Money; createdAt: string; method: string }[];
}
