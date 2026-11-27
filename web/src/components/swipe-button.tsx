'use client';

import { Check, ChevronsRight, LoaderCircle, type LucideIcon } from 'lucide-react';
import { useId, useRef, useState } from 'react';
import { useT } from './i18n';

const KNOB = 54;
const INSET = 5;
const THRESHOLD = 0.85;

/**
 * Botón de "desliza para confirmar": se arrastra la perilla hasta el final.
 * - Un clic sin arrastrar solo hace un amago para enseñar el gesto.
 * - Con teclado (Enter o Espacio) o lector de pantalla confirma directo.
 * - Mientras `onConfirm` trabaja (o `loading`), la perilla se queda al final girando.
 */
export function SwipeButton({
  label,
  onConfirm,
  disabled,
  loading,
  busyLabel,
  icon: Icon = ChevronsRight,
  className = '',
}: {
  label: string;
  onConfirm: () => void | Promise<void>;
  disabled?: boolean;
  loading?: boolean;
  busyLabel?: string;
  icon?: LucideIcon;
  className?: string;
}) {
  const t = useT();
  const hintId = useId();
  const track = useRef<HTMLButtonElement>(null);
  const drag = useRef<{ startX: number; startPos: number; travel: number; moved: boolean } | null>(null);
  const [pos, setPos] = useState(0);
  const [dragging, setDragging] = useState(false);
  const [running, setRunning] = useState(false);
  const [hint, setHint] = useState(false);
  const busy = !!loading || running;
  const off = !!disabled || busy;
  const p = busy ? 1 : pos;

  const confirm = async () => {
    if (off) return;
    setPos(1);
    setRunning(true);
    try {
      await onConfirm();
    } finally {
      setRunning(false);
      setPos(0);
    }
  };

  const nudge = () => {
    if (off) return;
    setHint(false);
    requestAnimationFrame(() => setHint(true));
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (off || !track.current) return;
    const travel = Math.max(1, track.current.clientWidth - KNOB - INSET * 2);
    drag.current = { startX: e.clientX, startPos: pos, travel, moved: false };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    setDragging(true);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.startX;
    if (Math.abs(dx) > 4) d.moved = true;
    setPos(Math.min(1, Math.max(0, d.startPos + dx / d.travel)));
  };
  const onPointerUp = () => {
    const d = drag.current;
    if (!d) return;
    setDragging(false);
    if (pos >= THRESHOLD) void confirm();
    else setPos(0);
    // El clic que sigue a un arrastre no cuenta como toque.
    setTimeout(() => {
      if (drag.current === d) drag.current = null;
    }, 0);
  };

  return (
    <button
      ref={track}
      type="button"
      aria-label={busy ? (busyLabel ?? label) : label}
      aria-describedby={hintId}
      aria-disabled={off}
      onClick={(e) => {
        // detail 0 = Enter/Espacio o lector de pantalla: confirma directo.
        if (e.detail === 0) return void confirm();
        if (drag.current?.moved) return;
        nudge();
      }}
      className={`swipe-track relative block h-16 w-full touch-pan-y select-none overflow-hidden rounded-full border-0 p-0 text-left font-extrabold ${
        off && !busy ? 'cursor-not-allowed bg-surface-3 text-muted' : 'cursor-pointer bg-brand text-on-brand shadow-[0_10px_24px_-10px_var(--brand)]'
      } ${className}`}
    >
      <span id={hintId} className="sr-only">
        {t('Desliza la flecha hasta el final o pulsa Enter para confirmar', 'Slide the arrow to the end or press Enter to confirm')}
      </span>
      {/* Lo recorrido se aclara detrás de la perilla */}
      <span
        aria-hidden
        className={`absolute inset-y-0 left-0 rounded-full bg-current opacity-15 ${dragging ? '' : 'swipe-ease'}`}
        style={{ width: `calc(${KNOB + INSET * 2}px + (100% - ${KNOB + INSET * 2}px) * ${p})` }}
      />
      <span
        aria-hidden
        className="pointer-events-none absolute inset-0 flex items-center justify-center px-[70px] text-center text-[17px] leading-tight"
        style={{ opacity: busy ? 1 : Math.max(0, 1 - p * 1.5) }}
      >
        <span className="truncate">{busy ? (busyLabel ?? label) : label}</span>
      </span>
      <span
        aria-hidden
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onAnimationEnd={() => setHint(false)}
        className={`absolute top-[5px] flex touch-none items-center justify-center rounded-full ${
          off && !busy ? 'bg-surface-2 text-muted' : 'cursor-grab bg-[var(--on-brand)] text-brand shadow-md active:cursor-grabbing'
        } ${dragging ? '' : 'swipe-ease'} ${hint ? 'swipe-hint' : ''}`}
        style={{ width: KNOB, height: KNOB, left: `calc(${INSET}px + (100% - ${KNOB + INSET * 2}px) * ${p})` }}
      >
        {busy ? <LoaderCircle className="spin size-6" /> : p >= 0.98 ? <Check className="size-6" strokeWidth={3} /> : <Icon className="size-6" strokeWidth={2.6} />}
      </span>
    </button>
  );
}

/** Círculo grande de la marca con palomita que aparece con un rebote. */
export function SuccessMark({ size = 128 }: { size?: number }) {
  return (
    <span
      aria-hidden
      className="success-pop flex items-center justify-center rounded-full bg-brand text-on-brand shadow-[0_18px_40px_-12px_var(--brand)]"
      style={{ width: size, height: size }}
    >
      <Check className="success-check" style={{ width: size * 0.55, height: size * 0.55 }} strokeWidth={3} />
    </span>
  );
}
