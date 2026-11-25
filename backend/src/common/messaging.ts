import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { loadEnv } from '../config/env';

const logger = new Logger('Messaging');

/** Qué canales están configurados (claves de Resend y Twilio en .env). */
export function messagingConfig() {
  const r = loadEnv().receipts;
  return { email: !!(r.resendApiKey && r.emailFrom), sms: !!(r.twilioAccountSid && r.twilioAuthToken && r.smsFrom) };
}

/** Canales para los códigos de entrada: el SMS también sirve con Twilio Verify. */
export function loginChannels() {
  const base = messagingConfig();
  return { email: base.email, sms: base.sms || twilioVerifyConfigured() };
}

/** Envía un email con Resend. */
export async function sendEmail(to: string, subject: string, html: string, text: string): Promise<void> {
  const { resendApiKey, emailFrom } = loadEnv().receipts;
  if (!resendApiKey || !emailFrom) throw new ServiceUnavailableException('El envío por email no está configurado');
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: emailFrom, to: [to], subject, html, text }),
  }).catch((e: unknown) => {
    logger.error(`Email: ${String(e)}`);
    return null;
  });
  if (!response?.ok) {
    const detail = response ? await response.text().catch(() => '') : '';
    logger.error(`Resend respondió ${response?.status}: ${detail.slice(0, 300)}`);
    throw new ServiceUnavailableException('No se pudo enviar el email. Intenta de nuevo.');
  }
}

/** Envía un SMS con Twilio (número en formato +1XXXXXXXXXX). */
export async function sendSms(to: string, body: string): Promise<void> {
  const { twilioAccountSid: sid, twilioAuthToken: token, smsFrom } = loadEnv().receipts;
  if (!sid || !token || !smsFrom) throw new ServiceUnavailableException('El envío por SMS no está configurado');
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ To: to, From: smsFrom, Body: body }).toString(),
  }).catch((e: unknown) => {
    logger.error(`SMS: ${String(e)}`);
    return null;
  });
  if (!response?.ok) {
    const detail = response ? await response.text().catch(() => '') : '';
    logger.error(`Twilio respondió ${response?.status}: ${detail.slice(0, 300)}`);
    throw new ServiceUnavailableException('No se pudo enviar el SMS. Revisa el número e intenta de nuevo.');
  }
}

// ───────── Twilio Verify (códigos de entrada por SMS) ─────────

/** Hay servicio de Verify configurado (cuenta, token y VA…). */
export function twilioVerifyConfigured() {
  const r = loadEnv().receipts;
  return !!(r.twilioAccountSid && r.twilioAuthToken && r.twilioVerifyServiceSid);
}

async function verifyCall(path: string, params: Record<string, string>) {
  const { twilioAccountSid: sid, twilioAuthToken: token, twilioVerifyServiceSid: service } = loadEnv().receipts;
  if (!sid || !token || !service) throw new ServiceUnavailableException('El envío por SMS no está configurado');
  const response = await fetch(`https://verify.twilio.com/v2/Services/${encodeURIComponent(service)}/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(params).toString(),
  }).catch((e: unknown) => {
    logger.error(`Twilio Verify: ${String(e)}`);
    return null;
  });
  const data = response ? ((await response.json().catch(() => null)) as Record<string, unknown> | null) : null;
  return { ok: !!response?.ok, status: response?.status ?? 0, data };
}

/** Twilio genera y envía el código (no requiere registro A2P 10DLC). */
export async function startSmsVerification(to: string, lang: 'es' | 'en') {
  const r = await verifyCall('Verifications', { To: to, Channel: 'sms', Locale: lang });
  if (!r.ok) {
    logger.error(`Twilio Verify respondió ${r.status}: ${JSON.stringify(r.data).slice(0, 300)}`);
    throw new ServiceUnavailableException('No se pudo enviar el SMS. Revisa el número e intenta de nuevo.');
  }
}

/** true si el código es el correcto y sigue vigente. */
export async function checkSmsVerification(to: string, code: string): Promise<boolean> {
  const r = await verifyCall('VerificationCheck', { To: to, Code: code });
  // 404: ya no hay verificación pendiente (venció, se usó o hubo demasiados intentos).
  if (!r.ok && r.status !== 404) logger.error(`Twilio Verify (comprobar) respondió ${r.status}: ${JSON.stringify(r.data).slice(0, 300)}`);
  return r.ok && r.data?.status === 'approved';
}
