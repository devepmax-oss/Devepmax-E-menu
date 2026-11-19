import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  scrypt,
  ScryptOptions,
  timingSafeEqual,
} from 'node:crypto';

const SCRYPT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEY_LENGTH = 64;

function scryptAsync(
  password: string,
  salt: Buffer,
  keyLength: number,
  options: ScryptOptions,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, keyLength, options, (error, key) => (error ? reject(error) : resolve(key)));
  });
}

/** Hash de contraseña con scrypt y sal aleatoria. Formato: scrypt$N$r$p$sal$hash */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scryptAsync(password, salt, KEY_LENGTH, { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P });
  return ['scrypt', SCRYPT_N, SCRYPT_R, SCRYPT_P, salt.toString('base64'), key.toString('base64')].join('$');
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, salt, hash] = parts;
  const expected = Buffer.from(hash, 'base64');
  const key = await scryptAsync(password, Buffer.from(salt, 'base64'), expected.length, {
    N: Number(n),
    r: Number(r),
    p: Number(p),
  });
  return key.length === expected.length && timingSafeEqual(key, expected);
}

/**
 * PIN → HMAC-SHA256 con un secreto del servidor (pepper).
 * Determinístico para poder buscar al empleado por PIN y garantizar que no se repita.
 */
export function hashPin(pin: string, pepper: string): string {
  return createHmac('sha256', pepper).update(pin).digest('hex');
}

export function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

/** Token opaco aleatorio (base64url, sin puntos). */
export function generateToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/** Código numérico de 6 dígitos para vincular dispositivos. */
export function generatePairingCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}

/**
 * PIN aleatorio de 6 dígitos para empleados. Lo genera siempre el servidor:
 * nadie lo elige, así no se puede adivinar el PIN de otro probando valores.
 * Se descartan PINs triviales (repetidos o secuenciales).
 */
export function generateEmployeePin(): string {
  for (;;) {
    const pin = String(randomInt(0, 1_000_000)).padStart(6, '0');
    if (!isTrivialPin(pin)) return pin;
  }
}

export function isTrivialPin(pin: string): boolean {
  if (/^(\d)\1+$/.test(pin)) return true;
  const digits = pin.split('').map(Number);
  const ascending = digits.every((d, i) => i === 0 || d === (digits[i - 1] + 1) % 10);
  const descending = digits.every((d, i) => i === 0 || d === (digits[i - 1] + 9) % 10);
  return ascending || descending;
}
