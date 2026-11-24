import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Enlace de pago de una mesa: identifica la visita (sesión) y va firmado, así nadie puede
 * inventar el de otra mesa. Deja de servir cuando la visita se cierra.
 */
function mac(sessionId: string, secret: string): string {
  const key = createHmac('sha256', secret).update('table-pay:v1').digest();
  return createHmac('sha256', key).update(sessionId).digest('base64url').slice(0, 22);
}

export function signTablePay(sessionId: string, secret: string): string {
  return `${Buffer.from(sessionId, 'utf8').toString('base64url')}.${mac(sessionId, secret)}`;
}

/** El id de la visita, o null si el enlace no es válido. */
export function verifyTablePay(token: string, secret: string): string | null {
  if (typeof token !== 'string' || token.length > 120) return null;
  const [id, signature, extra] = token.split('.');
  if (!id || !signature || extra !== undefined) return null;
  const sessionId = Buffer.from(id, 'base64url').toString('utf8');
  if (!/^[a-z0-9]{10,40}$/i.test(sessionId)) return null;
  const expected = Buffer.from(mac(sessionId, secret));
  const given = Buffer.from(signature);
  return expected.length === given.length && timingSafeEqual(expected, given) ? sessionId : null;
}
