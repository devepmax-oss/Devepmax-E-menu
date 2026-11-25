import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { loadEnv } from '../config/env';

const logger = new Logger('Messaging');

/** Qué canales están configurados (claves de Resend y Twilio en .env). */
export function messagingConfig() {
  const r = loadEnv().receipts;
  return { email: !!(r.resendApiKey && r.emailFrom), sms: !!(r.twilioAccountSid && r.twilioAuthToken && r.smsFrom) };
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
