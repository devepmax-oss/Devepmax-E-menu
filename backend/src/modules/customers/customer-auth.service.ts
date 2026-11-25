import { BadRequestException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Customer, Prisma } from '@prisma/client';
import { timingSafeEqual } from 'node:crypto';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { generatePairingCode, generateToken, hashPin, sha256 } from '../../common/crypto';
import { GoogleIdTokenVerifier } from '../../common/google-id-token';
import { checkSmsVerification, loginChannels, sendEmail, sendSms, startSmsVerification, twilioVerifyConfigured } from '../../common/messaging';
import { maskTarget, toE164 } from '../../common/phone';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { SettingsService } from '../settings/settings.service';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const CODE_MINUTES = 10;
const MAX_TRIES_PER_CODE = 5;
const SESSION_DAYS = 180;
export const CUSTOMER_TOKEN_HEADER = 'x-customer-token';

type Channel = 'sms' | 'email';

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/**
 * Entrar a la cuenta de cliente sin contraseña: un código de 6 dígitos por SMS o email.
 * La respuesta es la misma exista o no la cuenta (no revela quién es cliente). Al verificar
 * se crea la cuenta si no existía y se ligan los pedidos web hechos antes con ese dato.
 */
@Injectable()
export class CustomerAuthService {
  private readonly env = loadEnv();
  private readonly logger = new Logger('CuentasCliente');
  private readonly requestsByIp = new AttemptLimiter(20, 15 * 60_000);
  private readonly requestsByTarget = new AttemptLimiter(5, 60 * 60_000);
  private readonly failuresByIp = new AttemptLimiter(15, 15 * 60_000);
  private readonly googleVerifier = this.env.googleClientId ? new GoogleIdTokenVerifier(this.env.googleClientId) : null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
  ) {}

  normalize(raw: string): { target: string; channel: Channel } {
    const value = raw.trim();
    if (value.includes('@')) {
      const email = value.toLowerCase();
      if (!EMAIL.test(email) || email.length > 120) throw new BadRequestException('Revisa el email');
      return { target: email, channel: 'email' };
    }
    const phone = toE164(value);
    if (!phone) throw new BadRequestException('Escribe un teléfono de 10 dígitos o un email');
    return { target: phone, channel: 'sms' };
  }

  async requestCode(raw: string, ip: string, lang: 'es' | 'en' = 'es') {
    const { target, channel } = this.normalize(raw);
    this.requestsByIp.assertAllowed(ip);
    this.requestsByTarget.assertAllowed(target);
    this.requestsByIp.fail(ip);
    this.requestsByTarget.fail(target);

    const available = loginChannels()[channel];
    const production = this.env.nodeEnv === 'production';
    if (!available && production) {
      throw new ServiceUnavailableException(
        channel === 'sms' ? 'Por ahora no podemos enviar SMS. Entra con tu email.' : 'Por ahora no podemos enviar emails. Entra con tu teléfono.',
      );
    }

    // SMS con Twilio Verify: Twilio genera, envía y comprueba el código.
    if (channel === 'sms' && twilioVerifyConfigured()) {
      await startSmsVerification(target, lang);
      return { channel, sentTo: maskTarget(target), expiresInMinutes: CODE_MINUTES };
    }

    const code = generatePairingCode();
    const now = new Date();
    await this.prisma.$transaction([
      // Pedir un código nuevo anula los anteriores.
      this.prisma.customerLoginCode.updateMany({ where: { target, usedAt: null }, data: { usedAt: now } }),
      this.prisma.customerLoginCode.create({
        data: { target, codeHash: this.hash(target, code), expiresAt: new Date(now.getTime() + CODE_MINUTES * 60_000) },
      }),
    ]);

    const name = (await this.settings.get()).name;
    const text =
      lang === 'en'
        ? `${code} is your ${name} code. It expires in ${CODE_MINUTES} minutes. Don't share it.`
        : `${code} es tu código de ${name}. Vence en ${CODE_MINUTES} minutos. No lo compartas.`;
    let devCode: string | undefined;
    if (available) {
      if (channel === 'sms') await sendSms(target, text);
      else {
        const subject = lang === 'en' ? `${code} is your ${name} code` : `${code} es tu código de ${name}`;
        const html = `<!doctype html><html><body style="margin:0;background:#f4f1ec;font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#1d150e"><div style="max-width:440px;margin:0 auto;padding:24px"><div style="background:#fff;border-radius:16px;padding:28px;text-align:center"><h1 style="margin:0 0 8px;font-size:20px">${escapeHtml(name)}</h1><p style="margin:0 0 18px;color:#666">${lang === 'en' ? 'Your sign-in code' : 'Tu código para entrar'}</p><p style="margin:0;font-size:36px;font-weight:800;letter-spacing:8px">${code}</p><p style="margin:18px 0 0;color:#888;font-size:13px">${lang === 'en' ? `It expires in ${CODE_MINUTES} minutes. If you did not ask for it, ignore this email.` : `Vence en ${CODE_MINUTES} minutos. Si no lo pediste, ignora este email.`}</p></div></div></body></html>`;
        await sendEmail(target, subject, html, text);
      }
    } else {
      // Solo en desarrollo, sin Twilio/Resend: el código se ve en la terminal y vuelve en la respuesta.
      this.logger.warn(`Código para ${maskTarget(target)}: ${code} (sin ${channel === 'sms' ? 'Twilio' : 'Resend'} configurado; solo en desarrollo)`);
      devCode = code;
    }
    return { channel, sentTo: maskTarget(target), expiresInMinutes: CODE_MINUTES, ...(devCode ? { devCode } : {}) };
  }

  async verify(raw: string, code: string, ip: string) {
    const { target, channel } = this.normalize(raw);
    this.failuresByIp.assertAllowed(ip);
    const wrong = () => {
      this.failuresByIp.fail(ip);
      return new BadRequestException('El código no es correcto o ya venció. Pide uno nuevo.');
    };
    const now = new Date();
    if (channel === 'sms' && twilioVerifyConfigured()) {
      if (!(await checkSmsVerification(target, code.trim()))) throw wrong();
      return this.signIn(await this.findOrCreate(channel, target), channel, target);
    }
    const row = await this.prisma.customerLoginCode.findFirst({
      where: { target, usedAt: null, expiresAt: { gt: now } },
      orderBy: { createdAt: 'desc' },
    });
    if (!row || row.attempts >= MAX_TRIES_PER_CODE) throw wrong();
    const expected = Buffer.from(row.codeHash, 'hex');
    const given = Buffer.from(this.hash(target, code.trim()), 'hex');
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) {
      await this.prisma.customerLoginCode.update({ where: { id: row.id }, data: { attempts: { increment: 1 } } });
      throw wrong();
    }
    const used = await this.prisma.customerLoginCode.updateMany({ where: { id: row.id, usedAt: null }, data: { usedAt: now } });
    if (used.count !== 1) throw wrong();

    return this.signIn(await this.findOrCreate(channel, target), channel, target);
  }

  /** "Continuar con Google": el ID token que entrega Google en la web, verificado aquí. */
  async google(credential: string, ip: string) {
    if (!this.googleVerifier) throw new ServiceUnavailableException('Entrar con Google no está configurado');
    this.failuresByIp.assertAllowed(ip);
    const identity = await this.googleVerifier.verify(credential).catch(() => null);
    if (!identity) {
      this.failuresByIp.fail(ip);
      throw new BadRequestException('No pudimos entrar con Google. Intenta de nuevo.');
    }
    let customer =
      (await this.prisma.customer.findUnique({ where: { googleId: identity.sub } })) ??
      (await this.prisma.customer.findUnique({ where: { email: identity.email } }));
    if (customer) {
      if (customer.googleId !== identity.sub || (!customer.name.trim() && identity.name)) {
        customer = await this.prisma.customer.update({
          where: { id: customer.id },
          data: { googleId: identity.sub, ...(!customer.name.trim() && identity.name ? { name: identity.name } : {}) },
        });
      }
    } else {
      try {
        customer = await this.prisma.customer.create({ data: { name: identity.name ?? '', email: identity.email, googleId: identity.sub } });
      } catch (error) {
        customer = await this.prisma.customer.findUnique({ where: { googleId: identity.sub } });
        if (!customer) throw error;
      }
    }
    return this.signIn(customer, 'email', identity.email);
  }

  /** Qué formas de entrar ofrece la web. */
  options() {
    const channels = loginChannels();
    const dev = this.env.nodeEnv !== 'production';
    return { sms: channels.sms || dev, email: channels.email || dev, googleClientId: this.env.googleClientId ?? null };
  }

  private async signIn(customer: Customer, channel: Channel, target: string) {
    const now = new Date();
    await this.linkGuestOrders(customer.id, channel, target);
    const token = generateToken();
    await this.prisma.$transaction([
      this.prisma.customerSession.create({
        data: { customerId: customer.id, tokenHash: sha256(token), expiresAt: new Date(now.getTime() + SESSION_DAYS * 86_400_000) },
      }),
      this.prisma.customer.update({ where: { id: customer.id }, data: { lastLoginAt: now } }),
    ]);
    return { token, customerId: customer.id };
  }

  /** El cliente de la sesión (o null si no hay sesión válida). */
  async resolve(token: string | undefined): Promise<Customer | null> {
    if (!token || token.length < 20 || token.length > 100) return null;
    const session = await this.prisma.customerSession.findUnique({ where: { tokenHash: sha256(token) }, include: { customer: true } });
    if (!session || session.expiresAt <= new Date()) return null;
    if (Date.now() - session.lastUsedAt.getTime() > 3_600_000) {
      await this.prisma.customerSession.update({ where: { id: session.id }, data: { lastUsedAt: new Date() } }).catch(() => undefined);
    }
    return session.customer;
  }

  async logout(token: string | undefined) {
    if (!token) return;
    await this.prisma.customerSession.deleteMany({ where: { tokenHash: sha256(token) } });
  }

  private hash(target: string, code: string) {
    return hashPin(`customer-login:${target}:${code}`, this.env.pinPepper);
  }

  private async findOrCreate(channel: Channel, target: string): Promise<Customer> {
    const where: Prisma.CustomerWhereUniqueInput = channel === 'sms' ? { phone: target } : { email: target };
    const existing = await this.prisma.customer.findUnique({ where });
    if (existing) return existing;
    try {
      return await this.prisma.customer.create({ data: channel === 'sms' ? { name: '', phone: target } : { name: '', email: target } });
    } catch (error) {
      // Dos verificaciones a la vez: la otra ya la creó.
      const again = await this.prisma.customer.findUnique({ where });
      if (again) return again;
      throw error;
    }
  }

  /** Los pedidos web hechos antes sin cuenta, con ese mismo teléfono o email, pasan a su historial. */
  private async linkGuestOrders(customerId: string, channel: Channel, target: string) {
    const candidates = await this.prisma.order.findMany({
      where: {
        customerId: null,
        channel: 'ONLINE',
        ...(channel === 'email'
          ? { customerEmail: { equals: target, mode: 'insensitive' } }
          : { customerPhone: { contains: target.slice(-4) } }),
      },
      select: { id: true, billId: true, customerPhone: true },
      take: 500,
    });
    const matches = channel === 'email' ? candidates : candidates.filter((o) => o.customerPhone && toE164(o.customerPhone) === target);
    if (!matches.length) return;
    await this.prisma.$transaction([
      this.prisma.order.updateMany({ where: { id: { in: matches.map((o) => o.id) } }, data: { customerId } }),
      this.prisma.bill.updateMany({ where: { id: { in: matches.map((o) => o.billId) }, customerId: null }, data: { customerId } }),
    ]);
  }
}
