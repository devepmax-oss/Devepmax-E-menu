import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { LoaderCircle } from 'lucide-react';

type Tone = 'brand' | 'ink' | 'ghost' | 'surface';

const TONES: Record<Tone, string> = {
  brand: 'bg-brand text-on-brand',
  ink: 'bg-ink text-bg',
  ghost: 'bg-transparent text-ink border border-line-strong',
  surface: 'bg-surface-2 text-ink border border-line',
};

export function Button({
  tone = 'brand',
  loading,
  className = '',
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { tone?: Tone; loading?: boolean }) {
  return (
    <button
      {...props}
      disabled={props.disabled || loading}
      className={`press inline-flex min-h-11 cursor-pointer items-center justify-center gap-2 rounded-full px-5 font-bold ${TONES[tone]} ${className}`}
    >
      {loading ? <LoaderCircle aria-hidden className="spin size-5" /> : null}
      {children}
    </button>
  );
}

export function Pill({ children, tone = 'accent', className = '' }: { children: ReactNode; tone?: 'accent' | 'brand' | 'muted' | 'success' | 'danger'; className?: string }) {
  const tones = {
    accent: 'bg-accent text-on-accent',
    brand: 'bg-brand text-on-brand',
    muted: 'bg-surface-3 text-soft',
    success: 'bg-success/15 text-success',
    danger: 'bg-danger/15 text-danger',
  };
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-extrabold tracking-wide uppercase ${tones[tone]} ${className}`}>
      {children}
    </span>
  );
}

export function Stepper({
  value,
  onChange,
  min = 0,
  max = 99,
  label,
  size = 'md',
}: {
  value: number;
  onChange: (n: number) => void;
  min?: number;
  max?: number;
  label: string;
  size?: 'sm' | 'md';
}) {
  const btn = size === 'sm' ? 'size-9' : 'size-11';
  return (
    <div className="inline-flex items-center gap-1 rounded-full border border-line bg-surface-2 p-1" role="group" aria-label={label}>
      <button
        type="button"
        className={`press ${btn} flex cursor-pointer items-center justify-center rounded-full text-ink hover:bg-surface-3`}
        onClick={() => onChange(value - 1)}
        disabled={value <= min}
        aria-label={value - 1 <= 0 && min === 0 ? `Quitar ${label}` : `Uno menos de ${label}`}
      >
        <span aria-hidden className="text-xl leading-none font-bold">−</span>
      </button>
      <span className="min-w-6 text-center font-bold tabular-nums" aria-live="polite">{value}</span>
      <button
        type="button"
        className={`press ${btn} flex cursor-pointer items-center justify-center rounded-full text-ink hover:bg-surface-3`}
        onClick={() => onChange(value + 1)}
        disabled={value >= max}
        aria-label={`Uno más de ${label}`}
      >
        <span aria-hidden className="text-xl leading-none font-bold">+</span>
      </button>
    </div>
  );
}

export function BrandMark({ name, logoUrl, size = 46 }: { name: string; logoUrl: string | null; size?: number }) {
  if (logoUrl) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={logoUrl} alt={name} style={{ height: size }} className="block w-auto max-w-[180px] object-contain" />;
  }
  return <span className="font-heading text-2xl font-extrabold text-ink">{name}</span>;
}

export function Notice({ tone = 'muted', children }: { tone?: 'muted' | 'danger' | 'accent'; children: ReactNode }) {
  const tones = {
    muted: 'border-line bg-surface text-soft',
    danger: 'border-danger/30 bg-danger/10 text-ink',
    accent: 'border-accent/40 bg-accent/10 text-ink',
  };
  return <div className={`rounded-2xl border px-4 py-3 text-sm leading-relaxed ${tones[tone]}`}>{children}</div>;
}
