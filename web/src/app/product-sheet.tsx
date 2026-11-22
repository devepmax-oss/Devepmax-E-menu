'use client';

import { Check, X } from 'lucide-react';
import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { Button, Pill, Stepper } from '@/components/ui';
import { cart } from '@/lib/cart';
import { money, toNumber } from '@/lib/format';
import type { MenuModifierGroup, MenuProduct } from '@/lib/types';

function groupRule(g: MenuModifierGroup) {
  const max = g.selectionType === 'SINGLE' ? 1 : g.maxSelect;
  if (g.minSelect > 0 && max === g.minSelect) return { text: `Elige ${g.minSelect}`, required: true, max };
  if (g.minSelect > 0) return { text: `Elige al menos ${g.minSelect}${max ? ` (hasta ${max})` : ''}`, required: true, max };
  return { text: max ? `Opcional · hasta ${max}` : 'Opcional', required: false, max };
}

function initialSelection(product: MenuProduct) {
  const selected: Record<string, string[]> = {};
  for (const g of product.modifierGroups) {
    const defaults = g.options.filter((o) => o.isDefault && o.isAvailable).map((o) => o.id);
    const max = g.selectionType === 'SINGLE' ? 1 : g.maxSelect ?? defaults.length;
    selected[g.id] = defaults.slice(0, max);
  }
  return selected;
}

export function ProductSheet({
  product,
  badges,
  currency,
  canOrder,
  onClose,
  onAdded,
}: {
  product: MenuProduct;
  badges: string[];
  currency: string;
  canOrder: boolean;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [selected, setSelected] = useState(() => initialSelection(product));
  const [quantity, setQuantity] = useState(1);
  const [notes, setNotes] = useState('');
  const [showErrors, setShowErrors] = useState(false);
  const titleId = useId();
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    dialogRef.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
      previous?.focus?.();
    };
  }, [onClose]);

  const optionsById = useMemo(() => new Map(product.modifierGroups.flatMap((g) => g.options.map((o) => [o.id, { option: o, group: g }] as const))), [product]);
  const optionIds = Object.values(selected).flat();
  const unitPrice = toNumber(product.price) + optionIds.reduce((sum, id) => sum + toNumber(optionsById.get(id)?.option.priceAdjustment), 0);

  const problems = product.modifierGroups
    .map((g) => ({ g, count: selected[g.id]?.length ?? 0 }))
    .filter(({ g, count }) => count < g.minSelect)
    .map(({ g }) => g.id);

  const toggle = (g: MenuModifierGroup, optionId: string) => {
    setSelected((prev) => {
      const current = prev[g.id] ?? [];
      if (g.selectionType === 'SINGLE') return { ...prev, [g.id]: current[0] === optionId && g.minSelect === 0 ? [] : [optionId] };
      if (current.includes(optionId)) return { ...prev, [g.id]: current.filter((id) => id !== optionId) };
      if (g.maxSelect && current.length >= g.maxSelect) return prev;
      return { ...prev, [g.id]: [...current, optionId] };
    });
  };

  const add = () => {
    if (problems.length) {
      setShowErrors(true);
      document.getElementById(`grupo-${problems[0]}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    cart.add({
      productId: product.id,
      name: product.name,
      imageUrl: product.imageUrl,
      unitPrice,
      quantity,
      optionIds,
      optionLabels: optionIds.map((id) => optionsById.get(id)?.option.name ?? '').filter(Boolean),
      notes: notes.trim(),
    });
    onAdded();
    onClose();
  };

  return (
    <div className="fade-in fixed inset-0 z-50 flex items-end justify-center bg-black/60 sm:items-center sm:p-6" onClick={onClose}>
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
        className="sheet-in relative flex max-h-[92dvh] w-full max-w-lg flex-col overflow-hidden rounded-t-[30px] bg-surface shadow-float outline-none sm:rounded-[30px]"
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Cerrar"
          className="press absolute top-3 right-3 z-10 flex size-11 cursor-pointer items-center justify-center rounded-full border border-line-strong bg-bg/80 text-ink backdrop-blur"
        >
          <X aria-hidden className="size-5" />
        </button>

        <div className="no-scrollbar flex-1 overflow-y-auto">
          {product.imageUrl ? (
            <div className="relative h-64 w-full bg-surface-2 sm:h-72">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={product.imageUrl} alt="" className="size-full object-cover" />
              <div className="absolute inset-0 bg-gradient-to-b from-transparent from-50% to-surface" />
            </div>
          ) : (
            <div className="h-14" />
          )}

          <div className="flex flex-col gap-5 px-5 pt-2 pb-6">
            <div className="flex flex-col gap-2">
              {badges.length ? (
                <div className="flex gap-1.5">
                  {badges.map((b) => (
                    <Pill key={b}>{b}</Pill>
                  ))}
                </div>
              ) : null}
              <h2 id={titleId} className="m-0 text-3xl leading-tight font-extrabold">
                {product.name}
              </h2>
              {product.description ? <p className="m-0 leading-relaxed text-soft">{product.description}</p> : null}
              <span className="font-heading text-xl font-bold">{money(product.price, currency)}</span>
              {product.allergens.length ? <span className="text-xs text-muted">Contiene: {product.allergens.join(', ')}</span> : null}
            </div>

            {product.modifierGroups.map((g) => {
              const rule = groupRule(g);
              const count = selected[g.id]?.length ?? 0;
              const missing = showErrors && problems.includes(g.id);
              return (
                <fieldset key={g.id} id={`grupo-${g.id}`} className="m-0 flex scroll-mt-24 flex-col gap-2 border-0 p-0">
                  <legend className="mb-2 flex w-full items-center justify-between gap-3 p-0">
                    <span className="text-lg font-bold">{g.name}</span>
                    <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${missing ? 'bg-danger text-white' : rule.required ? (count >= g.minSelect ? 'bg-success/15 text-success' : 'bg-surface-3 text-soft') : 'text-muted'}`}>
                      {rule.required && count >= g.minSelect ? 'Listo' : rule.text}
                    </span>
                  </legend>
                  {g.options.map((o) => {
                    const on = selected[g.id]?.includes(o.id) ?? false;
                    const full = !on && g.selectionType === 'MULTIPLE' && !!g.maxSelect && count >= g.maxSelect;
                    const disabled = !o.isAvailable || full;
                    return (
                      <button
                        key={o.id}
                        type="button"
                        role={g.selectionType === 'SINGLE' ? 'radio' : 'checkbox'}
                        aria-checked={on}
                        disabled={disabled}
                        onClick={() => toggle(g, o.id)}
                        className={`press flex min-h-14 w-full cursor-pointer items-center gap-3 rounded-2xl border px-4 text-left ${on ? 'border-brand bg-brand-soft' : 'border-line bg-surface-2'}`}
                      >
                        <span
                          aria-hidden
                          className={`flex size-6 shrink-0 items-center justify-center border-2 ${g.selectionType === 'SINGLE' ? 'rounded-full' : 'rounded-lg'} ${on ? 'border-brand bg-brand text-on-brand' : 'border-line-strong'}`}
                        >
                          {on ? <Check className="size-4" strokeWidth={3} /> : null}
                        </span>
                        <span className="flex-1 font-semibold text-ink">{o.name}</span>
                        <span className="text-sm text-soft">
                          {!o.isAvailable ? 'Agotado' : toNumber(o.priceAdjustment) ? `+${money(o.priceAdjustment, currency)}` : ''}
                        </span>
                      </button>
                    );
                  })}
                </fieldset>
              );
            })}

            <label className="flex flex-col gap-2">
              <span className="text-lg font-bold">Instrucciones especiales</span>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                maxLength={200}
                rows={2}
                placeholder="Ej.: sin cebolla, salsa aparte"
                className="resize-none rounded-2xl border border-line bg-surface-2 px-4 py-3 text-ink placeholder:text-muted"
              />
            </label>
          </div>
        </div>

        <div className="flex items-center gap-3 border-t border-line bg-surface px-5 pt-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          <Stepper value={quantity} onChange={setQuantity} min={1} label={product.name} />
          <Button className="h-14 flex-1 text-base" onClick={add} disabled={!canOrder || !product.isAvailable}>
            {!product.isAvailable ? 'Agotado' : !canOrder ? 'Pedidos cerrados' : `Agregar · ${money(unitPrice * quantity, currency)}`}
          </Button>
        </div>
      </div>
    </div>
  );
}
