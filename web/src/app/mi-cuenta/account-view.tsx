'use client';

import { Cake, ChevronLeft, Gift, LogOut, MapPin, Plus, Receipt, RotateCcw, Star, Trash2, UserRound } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { GoogleButton } from '@/components/google-button';
import { LanguageSwitch, useLang, useT } from '@/components/i18n';
import { BrandMark, Button, Notice, Pill } from '@/components/ui';
import { account, pendingCoupon, reorderLines, useAccount, type CodeSent, type HistoryEntry, type LoginOptions, type LoyaltySummary, type Profile } from '@/lib/account';
import { ApiError } from '@/lib/api';
import { cart } from '@/lib/cart';
import { money } from '@/lib/format';
import { intlLocale } from '@/lib/i18n';
import type { OnlineConfig, PublicMenu } from '@/lib/types';

const errorText = (e: unknown, fallback: string) => (e instanceof ApiError ? e.message : fallback);

function Card({ title, children, aside }: { title: string; children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-4 rounded-[26px] border border-line bg-surface p-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="m-0 text-xl font-bold">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

function Input(props: React.InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  const { label, className = '', ...input } = props;
  return (
    <label className={`flex flex-col gap-1.5 ${className}`}>
      <span className="text-sm font-semibold text-soft">{label}</span>
      <input {...input} className="h-12 rounded-2xl border border-line bg-surface-2 px-4 text-base text-ink placeholder:text-muted" />
    </label>
  );
}

export function AccountView({
  config,
  menu,
  back,
  options,
}: {
  config: OnlineConfig;
  menu: PublicMenu | null;
  back: string | null;
  options: LoginOptions;
}) {
  const t = useT();
  const router = useRouter();
  const { token, profile } = useAccount();
  const [ready, setReady] = useState(false);

  // Al abrir, se actualizan los datos de la cuenta (la sesión puede haber vencido).
  useEffect(() => {
    if (!token) return setReady(true);
    account
      .refresh()
      .catch(() => undefined)
      .finally(() => setReady(true));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const done = () => {
    if (back) router.push(back);
  };

  return (
    <main className="mx-auto w-full max-w-2xl px-4 pb-16 sm:px-6">
      <header className="flex items-center justify-between gap-3 py-4">
        <div className="flex items-center gap-3">
          <Link href={back ?? '/'} aria-label={t('Volver', 'Back')} className="press flex size-11 items-center justify-center rounded-full border border-line-strong bg-surface text-ink">
            <ChevronLeft aria-hidden className="size-5" />
          </Link>
          <BrandMark name={config.name} logoUrl={config.logoUrl} size={40} />
        </div>
        <LanguageSwitch offered={config.locales} />
      </header>

      <h1 className="m-0 mb-5 text-3xl font-extrabold">{t('Mi cuenta', 'My account')}</h1>

      {!ready ? (
        <div className="h-40 animate-pulse rounded-[26px] bg-surface-2" aria-hidden />
      ) : !token || !profile ? (
        <LoginCard onDone={done} options={options} dark={config.themeMode === 'dark'} />
      ) : profile.needsName ? (
        <NameCard onDone={done} />
      ) : (
        <Signed profile={profile} config={config} menu={menu} back={back} />
      )}
    </main>
  );
}

function LoginCard({ onDone, options, dark }: { onDone: () => void; options: LoginOptions; dark: boolean }) {
  const t = useT();
  const lang = useLang();
  const [target, setTarget] = useState('');
  const [sent, setSent] = useState<CodeSent | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const send = async () => {
    setError(null);
    setBusy(true);
    try {
      setSent(await account.requestCode(target, lang));
      setCode('');
    } catch (e) {
      setError(errorText(e, t('No pudimos enviar el código. Intenta de nuevo.', 'We could not send the code. Please try again.')));
    } finally {
      setBusy(false);
    }
  };

  const withGoogle = useCallback(
    async (credential: string) => {
      setError(null);
      setBusy(true);
      try {
        const profile = await account.google(credential);
        if (!profile.needsName) onDone();
      } catch (e) {
        setError(errorText(e, t('No pudimos entrar con Google. Intenta de nuevo.', 'We could not sign you in with Google. Please try again.')));
      } finally {
        setBusy(false);
      }
    },
    [onDone, t],
  );
  const googleFailed = useCallback(() => setError(t('No pudimos cargar Google. Usa tu teléfono o email.', 'Google could not load. Use your phone or email.')), [t]);
  const codes = options.sms || options.email;
  const targetLabel = options.sms && options.email ? t('Teléfono o email', 'Phone or email') : options.sms ? t('Teléfono', 'Phone') : 'Email';

  const verify = async () => {
    setError(null);
    setBusy(true);
    try {
      const profile = await account.verify(target, code);
      if (!profile.needsName) onDone();
    } catch (e) {
      setError(errorText(e, t('No pudimos entrar. Intenta de nuevo.', 'We could not sign you in. Please try again.')));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title={sent ? t('Escribe el código', 'Enter the code') : t('Entra o crea tu cuenta', 'Sign in or create your account')}>
      {!sent ? (
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            void send();
          }}
        >
          <p className="m-0 text-soft">
            {t(
              'Guarda tus datos y tus direcciones, y repite tus pedidos con un toque. Sin contraseñas.',
              'Save your details and addresses, and reorder with one tap. No passwords.',
            )}
          </p>
          {options.googleClientId ? (
            <>
              <GoogleButton clientId={options.googleClientId} dark={dark} onCredential={(c) => void withGoogle(c)} onError={googleFailed} />
              {codes ? (
                <div className="flex items-center gap-3 text-xs font-semibold tracking-wide text-muted uppercase">
                  <span className="h-px flex-1 bg-line" /> {t('o con un código', 'or with a code')} <span className="h-px flex-1 bg-line" />
                </div>
              ) : null}
            </>
          ) : null}
          {codes ? (
          <>
          <Input
            label={targetLabel}
            value={target}
            onChange={(e) => setTarget(e.target.value)}
            autoComplete="username"
            inputMode={options.email ? 'email' : 'tel'}
            placeholder="(305) 555-0123"
            required
          />
          <Button type="submit" className="h-14 text-base" loading={busy} disabled={target.trim().length < 5}>
            {t('Enviar código', 'Send code')}
          </Button>
          </>
          ) : null}
          {error ? <Notice tone="danger">{error}</Notice> : null}
        </form>
      ) : (
        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            void verify();
          }}
        >
          <p className="m-0 text-soft">
            {sent.channel === 'sms'
              ? t(`Lo enviamos por SMS a ${sent.sentTo}. Vence en ${sent.expiresInMinutes} minutos.`, `We texted it to ${sent.sentTo}. It expires in ${sent.expiresInMinutes} minutes.`)
              : t(`Lo enviamos a ${sent.sentTo}. Vence en ${sent.expiresInMinutes} minutos.`, `We emailed it to ${sent.sentTo}. It expires in ${sent.expiresInMinutes} minutes.`)}
          </p>
          {sent.devCode ? (
            <Notice tone="accent">
              {t('Modo de prueba (sin SMS ni email configurados). Tu código:', 'Test mode (no SMS or email set up). Your code:')} <span className="font-heading text-lg font-extrabold tracking-[0.2em]">{sent.devCode}</span>
            </Notice>
          ) : null}
          <Input
            label={t('Código', 'Code')}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            autoComplete="one-time-code"
            inputMode="numeric"
            placeholder="123456"
            className="[&_input]:text-center [&_input]:font-heading [&_input]:text-2xl [&_input]:tracking-[0.4em]"
            autoFocus
          />
          {error ? <Notice tone="danger">{error}</Notice> : null}
          <Button type="submit" className="h-14 text-base" loading={busy} disabled={code.length !== 6}>
            {t('Entrar', 'Sign in')}
          </Button>
          <div className="flex flex-wrap justify-center gap-4 text-sm">
            <button type="button" onClick={() => void send()} disabled={busy} className="cursor-pointer border-0 bg-transparent font-semibold text-muted underline">
              {t('Enviar otro código', 'Send a new code')}
            </button>
            <button type="button" onClick={() => setSent(null)} className="cursor-pointer border-0 bg-transparent font-semibold text-muted underline">
              {t('Usar otro teléfono o email', 'Use another phone or email')}
            </button>
          </div>
        </form>
      )}
    </Card>
  );
}

function NameCard({ onDone }: { onDone: () => void }) {
  const t = useT();
  const lang = useLang();
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await account.update({ name: name.trim(), lang });
      onDone();
    } catch (e) {
      setError(errorText(e, t('No pudimos guardar. Intenta de nuevo.', 'We could not save. Please try again.')));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Card title={t('¡Bienvenido! ¿Cómo te llamas?', 'Welcome! What is your name?')}>
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          void save();
        }}
      >
        <Input label={t('Nombre', 'Name')} value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" autoFocus />
        {error ? <Notice tone="danger">{error}</Notice> : null}
        <Button type="submit" className="h-14 text-base" loading={busy} disabled={name.trim().length < 2}>
          {t('Continuar', 'Continue')}
        </Button>
      </form>
    </Card>
  );
}

function Signed({ profile, config, menu, back }: { profile: Profile; config: OnlineConfig; menu: PublicMenu | null; back: string | null }) {
  const t = useT();
  const router = useRouter();
  const [leaving, setLeaving] = useState(false);
  return (
    <div className="flex flex-col gap-5">
      {back ? (
        <Button className="h-14 text-base" onClick={() => router.push(back)}>
          {t('Seguir con mi pedido', 'Continue with my order')}
        </Button>
      ) : null}
      <ProfileCard profile={profile} birthdayGift={!!config.loyalty?.birthday} />
      {config.loyalty?.enabled || config.loyalty?.birthday ? <LoyaltyCard config={config} /> : null}
      <OrdersCard config={config} menu={menu} />
      <AddressesCard profile={profile} />
      <Button
        tone="ghost"
        loading={leaving}
        onClick={async () => {
          setLeaving(true);
          await account.logout();
          setLeaving(false);
        }}
      >
        <LogOut aria-hidden className="size-4" /> {t('Salir de mi cuenta', 'Sign out')}
      </Button>
    </div>
  );
}

function ProfileCard({ profile, birthdayGift }: { profile: Profile; birthdayGift: boolean }) {
  const t = useT();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(profile.name);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const save = async (body: { name?: string; marketingOptIn?: boolean }) => {
    setBusy(true);
    setError(null);
    try {
      await account.update(body);
      setEditing(false);
    } catch (e) {
      setError(errorText(e, t('No pudimos guardar. Intenta de nuevo.', 'We could not save. Please try again.')));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Card title={t('Mis datos', 'My details')} aside={<UserRound aria-hidden className="size-5 text-accent-text" />}>
      {editing ? (
        <form
          className="flex flex-col gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            void save({ name: name.trim() });
          }}
        >
          <Input label={t('Nombre', 'Name')} value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" />
          <div className="flex gap-2">
            <Button type="submit" loading={busy} disabled={name.trim().length < 2}>
              {t('Guardar', 'Save')}
            </Button>
            <Button type="button" tone="ghost" onClick={() => setEditing(false)}>
              {t('Cancelar', 'Cancel')}
            </Button>
          </div>
        </form>
      ) : (
        <div className="flex items-start justify-between gap-3">
          <div className="flex min-w-0 flex-col gap-0.5">
            <span className="text-lg font-bold">{profile.name}</span>
            {profile.phone ? <span className="text-sm text-soft">{profile.phone}</span> : null}
            {profile.email ? <span className="truncate text-sm text-soft">{profile.email}</span> : null}
          </div>
          <button type="button" onClick={() => setEditing(true)} className="cursor-pointer border-0 bg-transparent text-sm font-bold text-accent-text">
            {t('Editar', 'Edit')}
          </button>
        </div>
      )}
      <label className="flex cursor-pointer items-center gap-3 text-sm text-soft">
        <input type="checkbox" checked={profile.marketingOptIn} disabled={busy} onChange={(e) => void save({ marketingOptIn: e.target.checked })} className="size-5 accent-[var(--brand)]" />
        {t('Quiero recibir promociones del restaurante', 'I want to receive promotions from the restaurant')}
      </label>
      <BirthdayRow profile={profile} gift={birthdayGift} />
      {error ? <Notice tone="danger">{error}</Notice> : null}
    </Card>
  );
}

const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const MONTHS_EN = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** Cumpleaños: se pone una vez (para el regalo del mes). */
function BirthdayRow({ profile, gift }: { profile: Profile; gift: boolean }) {
  const t = useT();
  const lang = useLang();
  const months = lang === 'en' ? MONTHS_EN : MONTHS_ES;
  const [month, setMonth] = useState(0);
  const [day, setDay] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (profile.birthday) {
    const m = months[profile.birthday.month - 1];
    return (
      <p className="m-0 flex items-center gap-2 text-sm text-soft">
        <Cake aria-hidden className="size-4 text-accent-text" />
        {t(`Cumpleaños: ${profile.birthday.day} de ${m}`, `Birthday: ${m} ${profile.birthday.day}`)}
      </p>
    );
  }
  const days = month ? [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] : 31;
  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await account.update({ birthMonth: month, birthDay: day });
    } catch (e) {
      setError(errorText(e, t('No pudimos guardar tu cumpleaños.', 'We could not save your birthday.')));
    } finally {
      setBusy(false);
    }
  };
  const select = 'h-11 rounded-2xl border border-line bg-surface-2 px-3 text-ink';
  return (
    <div className="flex flex-col gap-2 border-t border-line pt-4">
      <span className="flex items-center gap-2 text-sm font-semibold text-soft">
        <Cake aria-hidden className="size-4 text-accent-text" />
        {gift ? t('Tu cumpleaños (te enviamos un regalo ese mes)', 'Your birthday (we send you a gift that month)') : t('Tu cumpleaños', 'Your birthday')}
      </span>
      <div className="flex flex-wrap items-center gap-2">
        <select aria-label={t('Mes', 'Month')} value={month} onChange={(e) => setMonth(Number(e.target.value))} className={select}>
          <option value={0}>{t('Mes', 'Month')}</option>
          {months.map((m, i) => (
            <option key={m} value={i + 1}>
              {m}
            </option>
          ))}
        </select>
        <select aria-label={t('Día', 'Day')} value={day} onChange={(e) => setDay(Number(e.target.value))} className={select}>
          <option value={0}>{t('Día', 'Day')}</option>
          {Array.from({ length: days }, (_, i) => (
            <option key={i + 1} value={i + 1}>
              {i + 1}
            </option>
          ))}
        </select>
        <Button tone="ghost" className="h-11" loading={busy} disabled={!month || !day || day > days} onClick={save}>
          {t('Guardar', 'Save')}
        </Button>
      </div>
      {error ? <span className="text-sm text-danger">{error}</span> : null}
    </div>
  );
}

/** Puntos, premios y regalo de cumpleaños. */
function LoyaltyCard({ config }: { config: OnlineConfig }) {
  const t = useT();
  const lang = useLang();
  const router = useRouter();
  const [data, setData] = useState<LoyaltySummary | null>(null);
  useEffect(() => {
    let cancelled = false;
    account
      .loyalty()
      .then((d) => !cancelled && setData(d))
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, []);
  if (!data) return <div className="h-32 animate-pulse rounded-[26px] bg-surface-2" aria-hidden />;
  const progress = data.rewardPoints > 0 ? Math.min(100, Math.round((data.points / data.rewardPoints) * 100)) : 0;
  const until = (iso: string | null) =>
    iso ? new Intl.DateTimeFormat(intlLocale(lang), { dateStyle: 'medium', timeZone: config.timezone }).format(new Date(new Date(iso).getTime() - 1000)) : null;
  const use = (code: string) => {
    pendingCoupon.set(code);
    router.push('/pedido');
  };
  return (
    <Card title={t('Mis puntos', 'My points')} aside={<Star aria-hidden className="size-5 text-accent-text" />}>
      {data.enabled ? (
        <>
          <div className="flex items-end justify-between gap-3">
            <span className="font-heading text-5xl leading-none font-extrabold">{data.points}</span>
            <span className="text-right text-sm text-soft">
              {t(`${data.pointsPerDollar} punto por cada $1`, `${data.pointsPerDollar} point per $1`)}
              <br />
              {t(`${data.rewardPoints} puntos = ${money(data.rewardAmount, config.currency)}`, `${data.rewardPoints} points = ${money(data.rewardAmount, config.currency)}`)}
            </span>
          </div>
          <div className="h-2.5 overflow-hidden rounded-full bg-surface-3" aria-hidden>
            <div className="h-full rounded-full bg-brand" style={{ width: `${progress}%` }} />
          </div>
          <p className="m-0 text-sm text-soft">
            {t(
              `Te faltan ${data.toNextReward} puntos para tu próximo premio de ${money(data.rewardAmount, config.currency)}.`,
              `${data.toNextReward} more points to your next ${money(data.rewardAmount, config.currency)} reward.`,
            )}
          </p>
        </>
      ) : null}
      {data.rewards.length ? (
        <ul className="m-0 flex list-none flex-col gap-2 p-0">
          {data.rewards.map((r) => (
            <li key={r.code} className="flex items-center gap-3 rounded-2xl border border-brand/40 bg-brand-soft px-4 py-3">
              {r.code.startsWith('CUMPLE-') ? <Cake aria-hidden className="size-5 shrink-0 text-brand-text" /> : <Gift aria-hidden className="size-5 shrink-0 text-brand-text" />}
              <div className="flex min-w-0 flex-1 flex-col">
                <span className="font-bold">{r.type === 'AMOUNT' && r.value ? `${money(r.value, config.currency)} · ${r.code}` : r.code}</span>
                <span className="truncate text-xs text-soft">
                  {r.name}
                  {r.endsAt ? ` · ${t('vence', 'expires')} ${until(r.endsAt)}` : ''}
                </span>
              </div>
              <Button className="h-10 px-4 text-sm" onClick={() => use(r.code)}>
                {t('Usar', 'Use')}
              </Button>
            </li>
          ))}
        </ul>
      ) : null}
      {data.history.length ? (
        <details className="text-sm">
          <summary className="cursor-pointer font-semibold text-soft">{t('Movimientos', 'Activity')}</summary>
          <ul className="m-0 mt-2 flex list-none flex-col gap-1 p-0">
            {data.history.slice(0, 10).map((h) => (
              <li key={h.id} className="flex justify-between gap-3 text-soft">
                <span>
                  {h.type === 'REWARD' ? t('Premio canjeado', 'Reward redeemed') : h.type === 'ADJUST' ? (h.reason ?? t('Ajuste', 'Adjustment')) : h.points > 0 ? t('Compra', 'Purchase') : t('Ajuste', 'Adjustment')}
                  {' · '}
                  {new Intl.DateTimeFormat(intlLocale(lang), { dateStyle: 'short', timeZone: config.timezone }).format(new Date(h.date))}
                </span>
                <span className={`tabular-nums font-semibold ${h.points > 0 ? 'text-success' : 'text-ink'}`}>{h.points > 0 ? `+${h.points}` : h.points}</span>
              </li>
            ))}
          </ul>
        </details>
      ) : null}
    </Card>
  );
}

function AddressesCard({ profile }: { profile: Profile }) {
  const t = useT();
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState({ label: '', street: '', city: '', state: '', zipCode: '', instructions: '' });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [k]: e.target.value }));
  const valid = form.street.trim().length >= 3 && form.city.trim().length >= 2 && form.state.trim().length >= 2 && /^\d{5}(-\d{4})?$/.test(form.zipCode.trim());

  const add = async () => {
    setBusy(true);
    setError(null);
    try {
      await account.addAddress({
        label: form.label.trim() || undefined,
        street: form.street.trim(),
        city: form.city.trim(),
        state: form.state.trim(),
        zipCode: form.zipCode.trim(),
        instructions: form.instructions.trim() || undefined,
      });
      setAdding(false);
      setForm({ label: '', street: '', city: '', state: '', zipCode: '', instructions: '' });
    } catch (e) {
      setError(errorText(e, t('No pudimos guardar la dirección.', 'We could not save the address.')));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card title={t('Mis direcciones', 'My addresses')} aside={<MapPin aria-hidden className="size-5 text-accent-text" />}>
      {profile.addresses.length === 0 && !adding ? <p className="m-0 text-sm text-muted">{t('Todavía no guardas direcciones. Se guardan al pedir a domicilio.', 'No saved addresses yet. They are saved when you order delivery.')}</p> : null}
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {profile.addresses.map((a) => (
          <li key={a.id} className="flex items-center gap-3 rounded-2xl bg-surface-2 px-4 py-3">
            <div className="flex min-w-0 flex-1 flex-col">
              <span className="font-semibold">{a.label ?? a.street}</span>
              <span className="truncate text-sm text-muted">{[a.label ? a.street : null, a.city, `${a.state} ${a.zipCode}`].filter(Boolean).join(', ')}</span>
            </div>
            <button
              type="button"
              aria-label={t(`Borrar ${a.label ?? a.street}`, `Delete ${a.label ?? a.street}`)}
              onClick={() => void account.removeAddress(a.id).catch(() => undefined)}
              className="press flex size-10 cursor-pointer items-center justify-center rounded-full border-0 bg-transparent text-muted hover:text-danger"
            >
              <Trash2 aria-hidden className="size-4" />
            </button>
          </li>
        ))}
      </ul>
      {adding ? (
        <form
          className="grid gap-3 sm:grid-cols-6"
          onSubmit={(e) => {
            e.preventDefault();
            void add();
          }}
        >
          <Input label={t('Nombre (opcional)', 'Label (optional)')} placeholder={t('Casa, Trabajo…', 'Home, Work…')} value={form.label} onChange={set('label')} maxLength={40} className="sm:col-span-6" />
          <Input label={t('Dirección', 'Street address')} placeholder="123 Main St, Apt 4" value={form.street} onChange={set('street')} autoComplete="address-line1" className="sm:col-span-6" />
          <Input label={t('Ciudad', 'City')} value={form.city} onChange={set('city')} autoComplete="address-level2" className="sm:col-span-3" />
          <Input label={t('Estado', 'State')} placeholder="FL" value={form.state} onChange={set('state')} autoComplete="address-level1" className="sm:col-span-1" />
          <Input label={t('Código postal', 'ZIP code')} value={form.zipCode} onChange={set('zipCode')} inputMode="numeric" autoComplete="postal-code" className="sm:col-span-2" />
          <Input label={t('Instrucciones (opcional)', 'Instructions (optional)')} value={form.instructions} onChange={set('instructions')} maxLength={300} className="sm:col-span-6" />
          {error ? (
            <div className="sm:col-span-6">
              <Notice tone="danger">{error}</Notice>
            </div>
          ) : null}
          <div className="flex gap-2 sm:col-span-6">
            <Button type="submit" loading={busy} disabled={!valid}>
              {t('Guardar dirección', 'Save address')}
            </Button>
            <Button type="button" tone="ghost" onClick={() => setAdding(false)}>
              {t('Cancelar', 'Cancel')}
            </Button>
          </div>
        </form>
      ) : profile.addresses.length < 10 ? (
        <button type="button" onClick={() => setAdding(true)} className="flex cursor-pointer items-center gap-2 self-start border-0 bg-transparent p-0 text-sm font-bold text-accent-text">
          <Plus aria-hidden className="size-4" /> {t('Agregar dirección', 'Add address')}
        </button>
      ) : null}
    </Card>
  );
}

function OrdersCard({ config, menu }: { config: OnlineConfig; menu: PublicMenu | null }) {
  const t = useT();
  const lang = useLang();
  const router = useRouter();
  const [entries, setEntries] = useState<HistoryEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    account
      .history()
      .then((list) => !cancelled && setEntries(list))
      .catch((e: unknown) => !cancelled && setError(errorText(e, t('No pudimos cargar tus pedidos.', 'We could not load your orders.'))));
    return () => {
      cancelled = true;
    };
  }, [t]);

  const date = (iso: string) => new Intl.DateTimeFormat(intlLocale(lang), { dateStyle: 'medium', timeStyle: 'short', timeZone: config.timezone }).format(new Date(iso));
  const kindLabel = (e: HistoryEntry) =>
    e.kind === 'TABLE'
      ? t(`Mesa ${e.table ?? ''}`.trim(), `Table ${e.table ?? ''}`.trim())
      : e.kind === 'DELIVERY'
        ? t('A domicilio', 'Delivery')
        : e.kind === 'PICKUP'
          ? t('Para recoger', 'Pickup')
          : t('En el local', 'In store');

  const repeat = (entry: HistoryEntry) => {
    if (!menu) return;
    const { lines, skipped } = reorderLines(entry, menu);
    if (!lines.length) {
      setNotice(t('Nada de ese pedido está disponible ahora.', 'Nothing from that order is available right now.'));
      return;
    }
    cart.replace(lines);
    if (skipped) setNotice(t(`${skipped} producto(s) ya no están disponibles y no se agregaron.`, `${skipped} item(s) are no longer available and were not added.`));
    router.push('/pedido');
  };

  return (
    <Card title={t('Mis pedidos', 'My orders')} aside={<Receipt aria-hidden className="size-5 text-accent-text" />}>
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {notice ? <Notice tone="accent">{notice}</Notice> : null}
      {entries === null && !error ? <div className="h-24 animate-pulse rounded-2xl bg-surface-2" aria-hidden /> : null}
      {entries?.length === 0 ? <p className="m-0 text-sm text-muted">{t('Aquí verás tus pedidos para repetirlos con un toque.', 'Your orders will show up here so you can reorder with one tap.')}</p> : null}
      <ul className="m-0 flex list-none flex-col gap-3 p-0">
        {entries?.map((e) => {
          const cancelled = e.status === 'CANCELLED';
          const canRepeat = !!menu && e.items.some((i) => i.productId);
          return (
            <li key={e.id} className="flex flex-col gap-2 rounded-2xl border border-line p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="flex min-w-0 flex-col">
                  <span className="font-bold">
                    {kindLabel(e)}
                    {e.orderNumbers.length ? ` · #${e.orderNumbers.join(', #')}` : ''}
                  </span>
                  <span className="text-xs text-muted">{date(e.date)}</span>
                </div>
                <div className="flex flex-col items-end gap-1">
                  <span className="font-heading text-lg font-bold tabular-nums">{money(e.total, config.currency)}</span>
                  {cancelled ? <Pill tone="danger">{t('Cancelado', 'Cancelled')}</Pill> : null}
                </div>
              </div>
              <p className="m-0 line-clamp-2 text-sm text-soft">{e.items.map((i) => (i.quantity > 1 ? `${i.quantity}× ${i.name}` : i.name)).join(' · ')}</p>
              <div className="flex flex-wrap gap-2">
                {canRepeat ? (
                  <Button className="h-10 px-4 text-sm" onClick={() => repeat(e)}>
                    <RotateCcw aria-hidden className="size-4" /> {t('Repetir', 'Reorder')}
                  </Button>
                ) : null}
                {e.trackingCode && !cancelled ? (
                  <Link href={`/pedido/${e.trackingCode}`} className="press flex h-10 items-center rounded-full border border-line-strong px-4 text-sm font-bold text-ink no-underline">
                    {t('Ver pedido', 'View order')}
                  </Link>
                ) : null}
                {e.receiptUrl ? (
                  <a href={e.receiptUrl} className="press flex h-10 items-center rounded-full border border-line-strong px-4 text-sm font-bold text-ink no-underline">
                    {t('Recibo', 'Receipt')}
                  </a>
                ) : null}
              </div>
            </li>
          );
        })}
      </ul>
    </Card>
  );
}
