/** Teléfono de EE. UU. a +1XXXXXXXXXX (o el número tal cual si ya trae +código). */
export function toE164(phone: string): string | null {
  const trimmed = phone.trim();
  const digits = trimmed.replace(/\D/g, '');
  if (trimmed.startsWith('+')) return digits.length >= 8 && digits.length <= 15 ? `+${digits}` : null;
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return null;
}

/** (305) •••-••67 — para mostrar a quién se envió un código sin exponer el dato completo. */
export function maskTarget(target: string): string {
  if (target.includes('@')) {
    const [user, domain] = target.split('@');
    return `${user.slice(0, 2)}${'•'.repeat(Math.max(1, user.length - 2))}@${domain}`;
  }
  const digits = target.replace(/\D/g, '');
  return `•••-•••-${digits.slice(-4)}`;
}
