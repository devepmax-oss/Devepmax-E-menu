import { createPublicKey, verify as verifySignature, type JsonWebKey } from 'node:crypto';

/** Lo que nos importa del ID token de "Continuar con Google". */
export interface GoogleIdentity {
  sub: string;
  email: string;
  name: string | null;
}

type Jwk = JsonWebKey & { kid?: string; alg?: string };
export type JwksFetcher = () => Promise<{ keys: Jwk[]; maxAgeSeconds: number }>;

const GOOGLE_CERTS = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];
const SKEW_SECONDS = 60;

const fetchGoogleKeys: JwksFetcher = async () => {
  const response = await fetch(GOOGLE_CERTS);
  if (!response.ok) throw new Error(`Google certs ${response.status}`);
  const maxAge = /max-age=(\d+)/.exec(response.headers.get('cache-control') ?? '')?.[1];
  return { keys: ((await response.json()) as { keys: Jwk[] }).keys, maxAgeSeconds: maxAge ? Number(maxAge) : 3600 };
};

const b64 = (part: string) => Buffer.from(part, 'base64url');

/**
 * Verifica el ID token que entrega Google en la web: firma RS256 con las llaves públicas de
 * Google, emisor, audiencia (nuestro ID de cliente), vencimiento y email verificado.
 * Sin dependencias: las llaves se guardan en memoria el tiempo que Google indica.
 */
export class GoogleIdTokenVerifier {
  private cache: { keys: Jwk[]; until: number } | null = null;

  constructor(
    private readonly clientId: string,
    private readonly fetchKeys: JwksFetcher = fetchGoogleKeys,
    private readonly now: () => number = Date.now,
  ) {}

  async verify(token: string): Promise<GoogleIdentity | null> {
    const parts = token.split('.');
    if (parts.length !== 3 || token.length > 4096) return null;
    let header: { alg?: string; kid?: string };
    let payload: Record<string, unknown>;
    try {
      header = JSON.parse(b64(parts[0]).toString('utf8'));
      payload = JSON.parse(b64(parts[1]).toString('utf8'));
    } catch {
      return null;
    }
    if (header.alg !== 'RS256' || !header.kid) return null;

    const jwk = await this.key(header.kid);
    if (!jwk) return null;
    const signed = verifySignature('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), createPublicKey({ key: jwk, format: 'jwk' }), b64(parts[2]));
    if (!signed) return null;

    const nowSeconds = Math.floor(this.now() / 1000);
    const aud = payload.aud;
    if (!ISSUERS.includes(String(payload.iss))) return null;
    if (Array.isArray(aud) ? !aud.includes(this.clientId) : aud !== this.clientId) return null;
    if (typeof payload.exp !== 'number' || payload.exp + SKEW_SECONDS < nowSeconds) return null;
    if (typeof payload.iat === 'number' && payload.iat - SKEW_SECONDS > nowSeconds) return null;
    if (payload.email_verified !== true && payload.email_verified !== 'true') return null;
    if (typeof payload.sub !== 'string' || typeof payload.email !== 'string') return null;
    return {
      sub: payload.sub,
      email: payload.email.toLowerCase(),
      name: typeof payload.name === 'string' && payload.name.trim() ? payload.name.trim().slice(0, 80) : null,
    };
  }

  private async key(kid: string): Promise<Jwk | undefined> {
    const fresh = this.cache && this.cache.until > this.now();
    let found = fresh ? this.cache!.keys.find((k) => k.kid === kid) : undefined;
    // Llave desconocida o caché vencida: Google rota sus llaves, se vuelven a pedir.
    if (!found) {
      const { keys, maxAgeSeconds } = await this.fetchKeys();
      this.cache = { keys, until: this.now() + Math.min(maxAgeSeconds, 86_400) * 1000 };
      found = keys.find((k) => k.kid === kid);
    }
    return found;
  }
}
