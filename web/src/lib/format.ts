const formatters = new Map<string, Intl.NumberFormat>();

/** $14.50 (la moneda del restaurante). */
export function money(value: string | number | null | undefined, currency = 'USD'): string {
  const n = typeof value === 'number' ? value : Number(value ?? 0);
  let f = formatters.get(currency);
  if (!f) {
    f = new Intl.NumberFormat('en-US', { style: 'currency', currency });
    formatters.set(currency, f);
  }
  return f.format(Number.isFinite(n) ? n : 0);
}

export const toNumber = (value: string | number | null | undefined) => {
  const n = typeof value === 'number' ? value : Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
};

export const round2 = (n: number) => Math.round(n * 100) / 100;

/** 8:41 p. m. en la zona del restaurante. */
export function clockTime(iso: string, timezone: string): string {
  return new Intl.DateTimeFormat('es-US', { hour: 'numeric', minute: '2-digit', timeZone: timezone }).format(new Date(iso));
}

export function plural(n: number, one: string, many: string) {
  return `${n} ${n === 1 ? one : many}`;
}
