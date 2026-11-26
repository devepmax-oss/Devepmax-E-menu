import { OrderStatus, TicketStatus } from '@prisma/client';
import { Decimal } from '@prisma/client/runtime/library';
import { randomInt } from 'node:crypto';

// ───────── Fecha de operación ─────────

/** Hasta esta hora (local) las órdenes cuentan para el día anterior (restaurantes que cierran de madrugada). */
export const BUSINESS_DAY_CUTOFF_HOUR = 4;

/** Día de operación del restaurante en su zona horaria, como fecha UTC a medianoche (columna @db.Date). */
export function businessDateFor(now: Date, timezone: string, cutoffHour = BUSINESS_DAY_CUTOFF_HOUR): Date {
  const shifted = new Date(now.getTime() - cutoffHour * 60 * 60 * 1000);
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(shifted);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '01';
  return new Date(`${get('year')}-${get('month')}-${get('day')}T00:00:00.000Z`);
}

// ───────── Códigos ─────────

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin 0/O ni 1/I

/** Código público para seguimiento (8 caracteres fáciles de leer). */
export function generatePublicCode(length = 8): string {
  let code = '';
  for (let i = 0; i < length; i++) code += CODE_ALPHABET[randomInt(0, CODE_ALPHABET.length)];
  return code;
}

// ───────── Estados ─────────

const TICKET_FLOW: TicketStatus[] = ['NEW', 'ACCEPTED', 'PREPARING', 'READY', 'COMPLETED'];

/** Cocina puede avanzar a cualquier estado posterior o deshacer un paso. */
export function canMoveTicket(from: TicketStatus, to: TicketStatus): boolean {
  const a = TICKET_FLOW.indexOf(from);
  const b = TICKET_FLOW.indexOf(to);
  if (a < 0 || b < 0) return false;
  return b > a || b === a - 1;
}

const NOT_DERIVED: OrderStatus[] = ['SCHEDULED', 'PENDING_PAYMENT', 'PENDING_APPROVAL', 'OUT_FOR_DELIVERY', 'COMPLETED', 'CANCELLED'];

/** Estado de la orden a partir de sus tickets de cocina. */
export function deriveOrderStatus(current: OrderStatus, tickets: TicketStatus[]): OrderStatus {
  if (NOT_DERIVED.includes(current)) return current;
  const active = tickets.filter((t) => t !== 'CANCELLED');
  if (active.length === 0) return current;
  if (active.every((t) => t === 'READY' || t === 'COMPLETED')) return 'READY';
  if (active.some((t) => t === 'PREPARING' || t === 'READY' || t === 'COMPLETED')) return 'PREPARING';
  if (active.some((t) => t === 'ACCEPTED')) return 'ACCEPTED';
  return 'PLACED';
}

/** ¿La cocina ya empezó? (cancelar después requiere autorización de gerente) */
export function kitchenStarted(tickets: TicketStatus[]): boolean {
  return tickets.some((t) => t !== 'NEW' && t !== 'CANCELLED');
}

// ───────── Precios ─────────

export interface GroupRule {
  id: string;
  name: string;
  minSelect: number;
  maxSelect: number;
}

/** Valida cuántas opciones se eligieron de cada grupo. Devuelve el error o null. */
export function selectionError(productName: string, groups: GroupRule[], chosen: Map<string, number>): string | null {
  for (const group of groups) {
    const count = chosen.get(group.id) ?? 0;
    if (count < group.minSelect) {
      return group.minSelect === 1
        ? `${productName}: elige una opción de "${group.name}"`
        : `${productName}: elige al menos ${group.minSelect} opciones de "${group.name}"`;
    }
    if (count > group.maxSelect) {
      return `${productName}: puedes elegir como máximo ${group.maxSelect} de "${group.name}"`;
    }
  }
  return null;
}

export function money(value: Decimal.Value): Decimal {
  return new Decimal(value).toDecimalPlaces(2, Decimal.ROUND_HALF_UP);
}

/** Total de una línea: (precio base + modificadores) × cantidad. Nunca negativo. */
export function lineTotal(unitPrice: Decimal.Value, modifiersTotal: Decimal.Value, quantity: number): Decimal {
  const total = new Decimal(unitPrice).plus(modifiersTotal).times(quantity);
  return money(Decimal.max(total, 0));
}

export interface TotalsLine {
  lineTotal: Decimal.Value;
  taxRate: Decimal.Value;
  /** Descuento de promociones sobre esta línea. */
  discount?: Decimal.Value;
}

/**
 * Totales de una cuenta. Los descuentos por línea (promociones) reducen la base imponible de
 * esa línea; los descuentos sobre toda la cuenta, de forma proporcional. El impuesto se redondea
 * una sola vez al final (como en una caja registradora).
 */
export function computeTotals(
  lines: TotalsLine[],
  extras: { billDiscount?: Decimal.Value; deliveryFee?: Decimal.Value; tipTotal?: Decimal.Value } = {},
) {
  const subtotal = money(lines.reduce((sum, l) => sum.plus(l.lineTotal), new Decimal(0)));
  const netLines = lines.map((l) => {
    const discount = Decimal.min(new Decimal(l.discount ?? 0), new Decimal(l.lineTotal));
    return { net: new Decimal(l.lineTotal).minus(discount), discount, taxRate: l.taxRate };
  });
  const lineDiscounts = money(netLines.reduce((sum, l) => sum.plus(l.discount), new Decimal(0)));
  const afterLines = subtotal.minus(lineDiscounts);
  const billDiscount = money(Decimal.min(new Decimal(extras.billDiscount ?? 0), afterLines));
  const factor = afterLines.isZero() ? new Decimal(0) : afterLines.minus(billDiscount).div(afterLines);
  const rawTax = netLines.reduce((sum, l) => sum.plus(l.net.times(l.taxRate)), new Decimal(0));
  const taxTotal = money(rawTax.times(factor));
  const discountTotal = money(lineDiscounts.plus(billDiscount));
  const deliveryFee = money(extras.deliveryFee ?? 0);
  const tipTotal = money(extras.tipTotal ?? 0);
  const total = money(subtotal.minus(discountTotal).plus(taxTotal).plus(deliveryFee).plus(tipTotal));
  return { subtotal, discountTotal, taxTotal, deliveryFee, tipTotal, total };
}
