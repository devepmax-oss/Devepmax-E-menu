import { generateKeyPairSync, sign } from 'node:crypto';
import { GoogleIdTokenVerifier } from './google-id-token';

const CLIENT = 'cliente-123.apps.googleusercontent.com';
const NOW = 1_800_000_000_000;
const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'k1', alg: 'RS256' };

function token(payload: Record<string, unknown>, kid = 'k1', key = privateKey) {
  const enc = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const head = enc({ alg: 'RS256', kid, typ: 'JWT' });
  const body = enc(payload);
  return `${head}.${body}.${sign('RSA-SHA256', Buffer.from(`${head}.${body}`), key).toString('base64url')}`;
}

const valid = {
  iss: 'https://accounts.google.com',
  aud: CLIENT,
  sub: '1234567890',
  email: 'Maria@Example.com',
  email_verified: true,
  name: 'María López',
  iat: NOW / 1000 - 10,
  exp: NOW / 1000 + 3600,
};

describe('Continuar con Google: ID token', () => {
  const verifier = () => new GoogleIdTokenVerifier(CLIENT, async () => ({ keys: [jwk], maxAgeSeconds: 3600 }), () => NOW);

  it('acepta un token válido de Google', async () => {
    expect(await verifier().verify(token(valid))).toEqual({ sub: '1234567890', email: 'maria@example.com', name: 'María López' });
  });

  it('rechaza otra audiencia, otro emisor, vencido o sin email verificado', async () => {
    const v = verifier();
    expect(await v.verify(token({ ...valid, aud: 'otra-app' }))).toBeNull();
    expect(await v.verify(token({ ...valid, iss: 'https://evil.example' }))).toBeNull();
    expect(await v.verify(token({ ...valid, exp: NOW / 1000 - 3600 }))).toBeNull();
    expect(await v.verify(token({ ...valid, email_verified: false }))).toBeNull();
  });

  it('rechaza una firma falsa o una llave desconocida', async () => {
    const other = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
    const v = verifier();
    expect(await v.verify(token(valid, 'k1', other))).toBeNull();
    expect(await v.verify(token(valid, 'k9'))).toBeNull();
    expect(await v.verify('no.es.untoken')).toBeNull();
  });
});
