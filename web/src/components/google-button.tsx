'use client';

import { useEffect, useRef } from 'react';
import { useLang } from './i18n';

type GoogleId = {
  accounts: {
    id: {
      initialize(options: Record<string, unknown>): void;
      renderButton(el: HTMLElement, options: Record<string, unknown>): void;
    };
  };
};

declare global {
  interface Window {
    google?: GoogleId;
  }
}

let loading: Promise<void> | null = null;
function loadGoogle(): Promise<void> {
  if (window.google?.accounts?.id) return Promise.resolve();
  loading ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://accounts.google.com/gsi/client';
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => {
      loading = null;
      reject(new Error('No se pudo cargar Google'));
    };
    document.head.appendChild(script);
  });
  return loading;
}

/** Botón oficial "Continuar con Google". Entrega el ID token para verificarlo en el servidor. */
export function GoogleButton({ clientId, dark, onCredential, onError }: { clientId: string; dark: boolean; onCredential: (credential: string) => void; onError?: () => void }) {
  const box = useRef<HTMLDivElement>(null);
  const lang = useLang();
  const callback = useRef(onCredential);
  useEffect(() => {
    callback.current = onCredential;
  }, [onCredential]);

  useEffect(() => {
    let cancelled = false;
    loadGoogle()
      .then(() => {
        const el = box.current;
        if (cancelled || !el || !window.google) return;
        window.google.accounts.id.initialize({
          client_id: clientId,
          callback: (response: { credential?: string }) => response.credential && callback.current(response.credential),
          ux_mode: 'popup',
          auto_select: false,
          cancel_on_tap_outside: true,
        });
        el.innerHTML = '';
        window.google.accounts.id.renderButton(el, {
          type: 'standard',
          theme: dark ? 'filled_black' : 'outline',
          size: 'large',
          text: 'continue_with',
          shape: 'pill',
          logo_alignment: 'center',
          locale: lang,
          width: Math.min(400, Math.max(240, el.offsetWidth)),
        });
      })
      .catch(() => onError?.());
    return () => {
      cancelled = true;
    };
  }, [clientId, dark, lang, onError]);

  return <div ref={box} className="flex min-h-11 w-full justify-center" />;
}
