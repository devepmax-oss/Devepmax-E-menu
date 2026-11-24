'use client';

import { Printer } from 'lucide-react';
import { BrandMark, Button, Pill } from '@/components/ui';
import { money, toNumber } from '@/lib/format';
import type { Receipt } from '@/lib/table-pay';

function Row({ label, value, strong, tone }: { label: string; value: string; strong?: boolean; tone?: 'success' }) {
  return (
    <div className={`flex items-baseline justify-between gap-3 ${strong ? 'text-lg font-extrabold text-ink' : 'text-sm text-soft'} ${tone === 'success' ? 'text-success' : ''}`}>
      <span>{label}</span>
      <span className="tabular-nums">{value}</span>
    </div>
  );
}

const KIND: Record<Receipt['kind'], string> = { TABLE: 'Mesa', COUNTER: 'Mostrador', PICKUP: 'Para recoger', DELIVERY: 'Delivery' };

/** El recibo como hoja: se ve bien en el celular y se imprime o guarda como PDF. */
export function ReceiptView({ receipt: r }: { receipt: Receipt }) {
  const c = r.currency;
  const date = new Intl.DateTimeFormat('es-US', { dateStyle: 'medium', timeStyle: 'short', timeZone: r.timezone }).format(new Date(r.date));
  const refunded = toNumber(r.refundedTotal);

  return (
    <main className="mx-auto w-full max-w-md px-4 py-6 print:max-w-none print:p-0">
      <article className="flex flex-col gap-5 rounded-[26px] border border-line bg-surface p-6 print:rounded-none print:border-0 print:bg-white print:text-black">
        <header className="flex flex-col items-center gap-2 text-center">
          <BrandMark name={r.restaurant.name} logoUrl={r.restaurant.logoUrl} size={52} />
          {r.restaurant.logoUrl ? <p className="m-0 font-heading text-lg font-extrabold">{r.restaurant.name}</p> : null}
          <div className="text-xs text-muted">
            {r.restaurant.address.map((line) => (
              <p key={line} className="m-0">{line}</p>
            ))}
            {r.restaurant.phone ? <p className="m-0">{r.restaurant.phone}</p> : null}
          </div>
        </header>

        <div className="flex flex-wrap items-center justify-between gap-2 border-y border-dashed border-line py-3 text-sm">
          <div className="flex flex-col">
            <span className="font-bold text-ink">{r.kind === 'TABLE' ? r.label : `${KIND[r.kind]} · ${r.label}`}</span>
            <span className="text-muted">{date}</span>
          </div>
          {r.status === 'REFUNDED' ? <Pill tone="danger">Reembolsado</Pill> : toNumber(r.due) > 0 ? <Pill tone="muted">Pendiente</Pill> : <Pill tone="success">Pagado</Pill>}
        </div>

        <ul className="m-0 flex list-none flex-col gap-2.5 p-0">
          {r.items.map((i) => (
            <li key={i.id} className="flex items-start justify-between gap-3 text-sm">
              <span className="min-w-0">
                <span className="font-semibold text-ink">
                  {i.quantity}× {i.name}
                </span>
                {i.modifiers.length ? <span className="block text-xs text-muted">{i.modifiers.join(', ')}</span> : null}
              </span>
              <span className="tabular-nums text-soft">{money(i.lineTotal, c)}</span>
            </li>
          ))}
        </ul>

        <div className="flex flex-col gap-1.5 border-t border-line pt-3">
          <Row label="Subtotal" value={money(r.subtotal, c)} />
          {r.discounts.map((d) => (
            <Row key={d.id} label={`Descuento · ${d.item ?? d.reason}`} value={`−${money(d.amount, c)}`} tone="success" />
          ))}
          {toNumber(r.discountTotal) > 0 && r.discounts.length === 0 ? <Row label="Descuentos" value={`−${money(r.discountTotal, c)}`} tone="success" /> : null}
          {toNumber(r.deliveryFee) > 0 ? <Row label="Envío" value={money(r.deliveryFee, c)} /> : null}
          <Row label="Impuestos" value={money(r.taxTotal, c)} />
          {toNumber(r.tipTotal) > 0 ? <Row label="Propina" value={money(r.tipTotal, c)} /> : null}
          <Row label="Total" value={money(r.total, c)} strong />
        </div>

        {r.payments.length ? (
          <div className="flex flex-col gap-1.5 border-t border-line pt-3">
            {r.payments.map((p) => (
              <div key={p.id} className="flex flex-col gap-0.5">
                <Row label={p.reference ? `${p.method} · ${p.reference}` : p.method} value={money(p.amount, c)} />
                {toNumber(p.changeGiven) > 0 ? <Row label={`Recibido ${money(p.cashTendered, c)} · cambio`} value={money(p.changeGiven, c)} /> : null}
              </div>
            ))}
            {refunded > 0 ? <Row label="Reembolsado" value={`−${money(refunded, c)}`} tone="success" /> : null}
            {toNumber(r.due) > 0 ? <Row label="Por pagar" value={money(r.due, c)} strong /> : null}
          </div>
        ) : null}

        <footer className="flex flex-col items-center gap-1 text-center text-xs text-muted">
          {r.orderNumbers.length ? <p className="m-0">Orden {r.orderNumbers.map((n) => `#${n}`).join(', ')}</p> : null}
          {r.restaurant.footer ? <p className="m-0 text-sm text-soft">{r.restaurant.footer}</p> : <p className="m-0 text-sm text-soft">¡Gracias por tu visita!</p>}
          {r.restaurant.legalName ? <p className="m-0">{r.restaurant.legalName}</p> : null}
        </footer>
      </article>

      <div className="mt-5 flex justify-center print:hidden">
        <Button tone="ghost" onClick={() => window.print()}>
          <Printer aria-hidden className="size-4" /> Imprimir o guardar PDF
        </Button>
      </div>
    </main>
  );
}
