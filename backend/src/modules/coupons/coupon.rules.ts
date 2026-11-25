import { Prisma } from '@prisma/client';

type D = Prisma.Decimal;
const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const ZERO = dec(0);

export type CouponKind = 'PERCENT' | 'AMOUNT' | 'FREE_DELIVERY';

export interface CouponTerms {
  type: CouponKind;
  value: Prisma.Decimal.Value | null;
  maxDiscount: Prisma.Decimal.Value | null;
}

/**
 * Cuánto descuenta un cupón. [base] = lo que queda de la cuenta después de promociones y otros
 * descuentos (sin impuesto, envío ni propina). El envío gratis no toca la base: quita el envío.
 */
export function couponSavings(c: CouponTerms, base: Prisma.Decimal.Value, deliveryFee: Prisma.Decimal.Value = 0) {
  const b = Prisma.Decimal.max(dec(base), ZERO);
  if (c.type === 'FREE_DELIVERY') {
    const fee = Prisma.Decimal.max(dec(deliveryFee), ZERO).toDecimalPlaces(2);
    return { amount: ZERO, freeDelivery: true, saved: fee };
  }
  const value = dec(c.value ?? 0);
  let amount: D = c.type === 'PERCENT' ? b.times(value).div(100) : value;
  if (c.type === 'PERCENT' && c.maxDiscount != null && dec(c.maxDiscount).gt(0)) amount = Prisma.Decimal.min(amount, dec(c.maxDiscount));
  amount = Prisma.Decimal.min(amount, b).toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP);
  return { amount, freeDelivery: false, saved: amount };
}

/** Códigos legibles: sin 0/O ni 1/I para que no se confundan al dictarlos. */
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function randomCouponCode(prefix = '', length = 6, random: () => number = Math.random): string {
  let out = '';
  for (let i = 0; i < length; i++) out += ALPHABET[Math.floor(random() * ALPHABET.length)];
  return `${prefix}${out}`;
}

/** "verano 10" → "VERANO10". Letras, números y guiones; 3 a 30 caracteres. */
export function normalizeCode(raw: string): string | null {
  const code = raw.trim().toUpperCase().replace(/\s+/g, '');
  return /^[A-Z0-9-]{3,30}$/.test(code) ? code : null;
}
