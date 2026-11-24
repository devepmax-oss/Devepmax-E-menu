import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Enlaces firmados. Pago de una mesa: identifica la visita (sesión) y va firmado, así nadie puede
 * inventar el de otra mesa. Deja de servir cuando la visita se cierra.
 */
function mac(scope: string, id: string, secret: string): string {
  const key = createHmac('sha256', secret).update(scope).digest();
  return createHmac('sha256', key).update(id).digest('base64url').slice(0, 22);
}

function sign(scope: string, id: string, secret: string): string {
  return `${Buffer.from(id, 'utf8').toString('base64url')}.${mac(scope, id, secret)}`;
}

function verify(scope: string, token: string, secret: string): string | null {
  if (typeof token !== 'string' || token.length > 120) return null;
  const [encoded, signature, extra] = token.split('.');
  if (!encoded || !signature || extra !== undefined) return null;
  const id = Buffer.from(encoded, 'base64url').toString('utf8');
  if (!/^[a-z0-9]{10,40}$/i.test(id)) return null;
  const expected = Buffer.from(mac(scope, id, secret));
  const given = Buffer.from(signature);
  return expected.length === given.length && timingSafeEqual(expected, given) ? id : null;
}

export const signTablePay = (sessionId: string, secret: string) => sign('table-pay:v1', sessionId, secret);

/** El id de la visita, o null si el enlace no es válido. */
export const verifyTablePay = (token: string, secret: string) => verify('table-pay:v1', token, secret);

/** Enlace del recibo digital de una cuenta (lo que llega por email o SMS y el QR del ticket). */
export const signReceipt = (billId: string, secret: string) => sign('receipt:v1', billId, secret);
export const verifyReceipt = (token: string, secret: string) => verify('receipt:v1', token, secret);
