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
