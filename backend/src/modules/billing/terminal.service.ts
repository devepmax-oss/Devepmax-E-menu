import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type Stripe from 'stripe';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { isUniqueViolation } from '../../prisma/errors';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { StripeService } from '../payments/stripe.service';
import { SettingsService } from '../settings/settings.service';
import { BillingService, BillView } from './billing.service';

const toCents = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v).times(100).toDecimalPlaces(0).toNumber();
const fromCents = (c: number) => new Prisma.Decimal(c).div(100);

export type TerminalStatus = 'waiting' | 'succeeded' | 'failed' | 'cancelled';

/** Errores de Stripe en palabras para la caja. */
function friendly(error: unknown): string {
  const e = error as { code?: string; message?: string };
  switch (e.code) {
    case 'terminal_reader_offline':
      return 'El lector está apagado o sin internet';
    case 'terminal_reader_busy':
      return 'El lector está ocupado con otro cobro';
    case 'terminal_reader_timeout':
      return 'El lector no respondió a tiempo';
    case 'resource_missing':
      return 'No se encontró el lector';
    default:
      return e.message ?? 'No se pudo hablar con el lector';
  }
}

/**
 * Cobro con lector inteligente (Stripe Terminal, integración por servidor): la caja manda el
 * monto al lector, el cliente acerca o inserta su tarjeta o celular, elige la propina en el
 * lector y la cuenta queda pagada sola. En modo prueba se usa el lector simulado de Stripe.
 */
@Injectable()
export class TerminalService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TerminalService.name);
  private locationId?: string;
  private unsubscribe?: () => void;

  constructor(
    private readonly prisma: PrismaService,
    private readonly stripe: StripeService,
    private readonly settings: SettingsService,
    private readonly billing: BillingService,
    private readonly events: DomainEventsService,
    private readonly audit: AuditService,
  ) {}

  onModuleInit() {
    // Stripe avisa por webhook (producción): se aplica igual que al consultar el estado.
    this.unsubscribe = this.events.subscribe((e) => {
      if (e.name !== 'payment.terminal_intent') return;
      const intent = e.payload as Stripe.PaymentIntent;
      void this.applyIntent(intent, 'system').catch((err) => this.logger.error(`Cobro del lector: ${String(err)}`));
    });
  }

  onModuleDestroy() {
    this.unsubscribe?.();
  }

  config() {
    return { enabled: this.stripe.configured, testMode: this.stripe.testMode };
  }

  // ───────── Lectores ─────────

  /** Ubicación del restaurante en Stripe (se crea la primera vez, con propinas 15/18/20 % en el lector). */
  private async location(): Promise<string> {
    if (this.locationId) return this.locationId;
    const api = this.stripe.api;
    const existing = await api.terminal.locations.list({ limit: 100 });
    const found = existing.data.find((l) => l.metadata?.devepmax === 'restaurant');
    if (found) return (this.locationId = found.id);

    const s = await this.settings.get();
    if (!s.addressLine || !s.city || !s.state || !s.zipCode) {
      throw new BadRequestException('Completa la dirección del restaurante en Ajustes (calle, ciudad, estado y código postal)');
    }
    const configuration = await api.terminal.configurations.create({
      name: `${s.name} · propinas`,
      tipping: { usd: { percentages: [15, 18, 20] } },
    });
    const location = await api.terminal.locations.create({
      display_name: s.name,
      address: { line1: s.addressLine, city: s.city, state: s.state, postal_code: s.zipCode, country: 'US' },
      configuration_overrides: configuration.id,
      metadata: { devepmax: 'restaurant' },
    });
    return (this.locationId = location.id);
  }

  private requireStripe() {
    if (!this.stripe.configured) throw new ServiceUnavailableException('Configura las claves de Stripe para usar lectores');
  }

  async readers() {
    this.requireStripe();
    const location = await this.location();
    const list = await this.stripe.api.terminal.readers.list({ location, limit: 100 });
    return list.data.map((r) => ({
      id: r.id,
      label: r.label,
      deviceType: r.device_type,
      simulated: r.device_type.startsWith('simulated'),
      status: r.status,
      busy: r.action?.status === 'in_progress',
    }));
  }

  async register(actor: EmployeeActor, registrationCode: string, label: string) {
    this.requireStripe();
    const code = registrationCode.trim().toLowerCase();
    if (code.startsWith('simulated') && !this.stripe.testMode) throw new ForbiddenException('El lector de prueba solo funciona en modo prueba');
    try {
      const reader = await this.stripe.api.terminal.readers.create({ registration_code: code, label: label.trim(), location: await this.location() });
      await this.audit.log(actor, 'terminal.reader_added', 'reader', reader.id, { label: reader.label, type: reader.device_type });
      return { id: reader.id, label: reader.label };
    } catch (error) {
      if (error instanceof BadRequestException) throw error;
      throw new BadRequestException(
        (error as { code?: string }).code === 'resource_missing' || /registration/i.test(String((error as Error).message))
          ? 'Código de registro inválido: revísalo en la pantalla del lector'
          : friendly(error),
      );
    }
  }

  async remove(actor: EmployeeActor, readerId: string) {
    this.requireStripe();
    await this.stripe.api.terminal.readers.del(readerId);
    await this.audit.log(actor, 'terminal.reader_removed', 'reader', readerId);
    return { ok: true };
  }

  /** Tap to Pay (el teléfono o la tablet es el lector): token de conexión para el SDK de Stripe. */
  async connectionToken() {
    this.requireStripe();
    const location = await this.location();
    const token = await this.stripe.api.terminal.connectionTokens.create({ location });
    return { secret: token.secret, locationId: location, testMode: this.stripe.testMode };
  }

  // ───────── Cobrar ─────────

  /**
   * Tap to Pay: crea el cobro y devuelve el client secret; la app lo cobra con el NFC del aparato
   * y luego consulta el estado (igual que con el lector).
   */
  async tapToPay(actor: EmployeeActor, billId: string, dto: { amount: number; tip?: number; clientRequestId: string }) {
    this.requireStripe();
    const existing = await this.prisma.payment.findUnique({ where: { clientRequestId: dto.clientRequestId } });
    if (existing?.stripePaymentIntentId) {
      const intent = await this.stripe.api.paymentIntents.retrieve(existing.stripePaymentIntentId);
      return { paymentId: existing.id, clientSecret: intent.client_secret };
    }
    const bill = await this.billing.view(billId);
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada o anulada');
    const amount = new Prisma.Decimal(dto.amount).toDecimalPlaces(2);
    if (amount.gt(bill.due.plus(0.001))) throw new BadRequestException(`La cuenta tiene $${bill.due.toFixed(2)} por cobrar: el monto es mayor`);
    const tip = new Prisma.Decimal(dto.tip ?? 0).toDecimalPlaces(2);
    const cents = toCents(amount.plus(tip));
    if (cents < 50) throw new BadRequestException('Con tarjeta el mínimo es $0.50');

    const settings = await this.settings.get();
    const intent = await this.stripe.api.paymentIntents.create(
      {
        amount: cents,
        currency: settings.currency.toLowerCase(),
        allowed_payment_method_types: ['card_present'],
        capture_method: 'automatic',
        description: `${settings.name} · ${bill.label}`,
        metadata: { kind: 'terminal', billId, tapToPay: 'true', tipCents: String(toCents(tip)) },
      },
      { idempotencyKey: `taptopay-${dto.clientRequestId}` },
    );
    const shift = await this.prisma.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
    try {
      const payment = await this.prisma.payment.create({
        data: {
          billId,
          method: 'CARD_TERMINAL',
          status: 'PENDING',
          amount: amount.plus(tip),
          tipAmount: tip,
          stripePaymentIntentId: intent.id,
          clientRequestId: dto.clientRequestId,
          employeeId: actor.id,
          cashShiftId: shift?.id ?? null,
        },
      });
      await this.audit.log(actor, 'terminal.tap_to_pay', 'bill', billId, { amount: amount.toString(), tip: tip.toString() });
      return { paymentId: payment.id, clientSecret: intent.client_secret };
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      const again = await this.prisma.payment.findUniqueOrThrow({ where: { clientRequestId: dto.clientRequestId } });
      return { paymentId: again.id, clientSecret: intent.client_secret };
    }
  }

  /** Manda el cobro al lector. El cliente paga ahí; la caja consulta el estado hasta que termine. */
  async charge(
    actor: EmployeeActor,
    billId: string,
    dto: { readerId: string; amount: number; tipOnReader?: boolean; clientRequestId: string },
  ) {
    this.requireStripe();
    const existing = await this.prisma.payment.findUnique({ where: { clientRequestId: dto.clientRequestId } });
    if (existing) return this.status(actor, existing.id);

    const bill = await this.billing.view(billId);
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada o anulada');
    const amount = new Prisma.Decimal(dto.amount).toDecimalPlaces(2);
    if (amount.gt(bill.due.plus(0.001))) throw new BadRequestException(`La cuenta tiene $${bill.due.toFixed(2)} por cobrar: el monto es mayor`);
    const cents = toCents(amount);
    if (cents < 50) throw new BadRequestException('Con tarjeta el mínimo es $0.50');

    const settings = await this.settings.get();
    const intent = await this.stripe.api.paymentIntents.create(
      {
        amount: cents,
        currency: settings.currency.toLowerCase(),
        allowed_payment_method_types: ['card_present'],
        capture_method: 'automatic',
        description: `${settings.name} · ${bill.label}`,
        metadata: { kind: 'terminal', billId, readerId: dto.readerId },
      },
      { idempotencyKey: `terminal-${dto.clientRequestId}` },
    );
    const shift = await this.prisma.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
    let paymentId: string;
    try {
      const payment = await this.prisma.payment.create({
        data: {
          billId,
          method: 'CARD_TERMINAL',
          status: 'PENDING',
          amount,
          stripePaymentIntentId: intent.id,
          clientRequestId: dto.clientRequestId,
          employeeId: actor.id,
          cashShiftId: shift?.id ?? null,
        },
      });
      paymentId = payment.id;
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      const again = await this.prisma.payment.findUniqueOrThrow({ where: { clientRequestId: dto.clientRequestId } });
      return this.status(actor, again.id);
    }

    try {
      await this.stripe.api.terminal.readers.processPaymentIntent(dto.readerId, {
        payment_intent: intent.id,
        process_config: dto.tipOnReader === false ? { skip_tipping: true } : { tipping: { amount_eligible: cents } },
      });
    } catch (error) {
      await this.stripe.api.paymentIntents.cancel(intent.id).catch(() => undefined);
      await this.prisma.payment.update({ where: { id: paymentId }, data: { status: 'CANCELLED' } });
      throw new ConflictException(friendly(error));
    }
    await this.audit.log(actor, 'terminal.charge', 'bill', billId, { amount: amount.toString(), readerId: dto.readerId });
    return { paymentId, status: 'waiting' as TerminalStatus, message: 'Esperando la tarjeta en el lector' };
  }

  /** En qué va el cobro: esperando la tarjeta, aprobado, rechazado o cancelado. */
  async status(actor: EmployeeActor | 'system', paymentId: string): Promise<{
    paymentId: string;
    status: TerminalStatus;
    message: string;
    tip?: string;
    bill?: BillView;
  }> {
    const payment = await this.findPayment(paymentId);
    if (payment.status === 'SUCCEEDED') {
      return { paymentId, status: 'succeeded', message: 'Aprobado', tip: payment.tipAmount.toString(), bill: await this.billing.view(payment.billId) };
    }
    if (payment.status !== 'PENDING') return { paymentId, status: payment.status === 'FAILED' ? 'failed' : 'cancelled', message: 'Cobro cancelado' };

    const intent = await this.stripe.api.paymentIntents.retrieve(payment.stripePaymentIntentId!);
    if (intent.status === 'succeeded' || intent.status === 'canceled') {
      await this.applyIntent(intent, actor);
      return this.status(actor, paymentId);
    }
    // ¿El lector rechazó la tarjeta? Se informa y la caja puede reintentar.
    const readerId = intent.metadata?.readerId;
    if (readerId) {
      const reader = await this.stripe.api.terminal.readers.retrieve(readerId);
      if ('action' in reader && reader.action?.status === 'failed' && reader.action.process_payment_intent?.payment_intent === intent.id) {
        await this.stripe.api.paymentIntents.cancel(intent.id).catch(() => undefined);
        await this.prisma.payment.update({ where: { id: paymentId }, data: { status: 'FAILED' } });
        return { paymentId, status: 'failed', message: reader.action.failure_message ?? 'La tarjeta fue rechazada' };
      }
    }
    return { paymentId, status: 'waiting', message: 'Esperando la tarjeta en el lector' };
  }

  async cancel(actor: EmployeeActor, paymentId: string) {
    const payment = await this.findPayment(paymentId);
    if (payment.status !== 'PENDING') return this.status(actor, paymentId);
    const intent = await this.stripe.api.paymentIntents.retrieve(payment.stripePaymentIntentId!);
    const readerId = intent.metadata?.readerId;
    if (readerId) await this.stripe.api.terminal.readers.cancelAction(readerId).catch(() => undefined);
    await this.stripe.api.paymentIntents.cancel(intent.id).catch(() => undefined);
    // Si justo se aprobó antes de cancelar, se respeta el pago.
    const latest = await this.stripe.api.paymentIntents.retrieve(intent.id);
    await this.applyIntent(latest, actor);
    await this.audit.log(actor, 'terminal.cancel', 'bill', payment.billId, { paymentId });
    return this.status(actor, paymentId);
  }

  /** Modo prueba: simula que el cliente acercó su tarjeta (con propina opcional). */
  async simulate(paymentId: string, tip?: number, declined = false) {
    if (!this.stripe.testMode) throw new ForbiddenException('Solo en modo prueba');
    const payment = await this.findPayment(paymentId);
    const intent = await this.stripe.api.paymentIntents.retrieve(payment.stripePaymentIntentId!);
    const readerId = intent.metadata?.readerId;
    if (!readerId) throw new BadRequestException('Este cobro no tiene lector');
    try {
      await this.stripe.api.testHelpers.terminal.readers.presentPaymentMethod(readerId, {
        type: 'card_present',
        // Tarjeta de prueba de Stripe que siempre se rechaza.
        ...(declined ? { card_present: { number: '4000000000000002' } } : {}),
        ...(tip && tip > 0 ? { amount_tip: toCents(tip) } : {}),
      });
    } catch (error) {
      throw new ConflictException(friendly(error));
    }
    return { ok: true };
  }

  // ───────── Internos ─────────

  private async findPayment(paymentId: string) {
    const payment = await this.prisma.payment.findUnique({ where: { id: paymentId } });
    if (!payment || payment.method !== 'CARD_TERMINAL' || !payment.stripePaymentIntentId) throw new NotFoundException('Cobro no encontrado');
    return payment;
  }

  /** Aplica el resultado de Stripe una sola vez: suma el pago (con la propina del lector) a la cuenta. */
  private async applyIntent(intent: Stripe.PaymentIntent, actor: EmployeeActor | 'system') {
    if (intent.status === 'canceled') {
      await this.prisma.payment.updateMany({ where: { stripePaymentIntentId: intent.id, status: 'PENDING' }, data: { status: 'CANCELLED' } });
      return;
    }
    if (intent.status !== 'succeeded') return;
    const received = fromCents(intent.amount_received);
    const readerTip = intent.amount_details?.tip?.amount ?? 0;
    const tip = fromCents(readerTip > 0 ? readerTip : Number(intent.metadata?.tipCents ?? 0) || 0);
    const card = await this.cardLabel(intent);
    const billId = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.payment.findUnique({ where: { stripePaymentIntentId: intent.id } });
      if (!payment) return null;
      const updated = await tx.payment.updateMany({
        where: { id: payment.id, status: 'PENDING' },
        data: { status: 'SUCCEEDED', amount: received, tipAmount: tip, reference: card },
      });
      if (updated.count === 0) return null; // ya aplicado (webhook y consulta a la vez)
      if (tip.gt(0)) await tx.bill.update({ where: { id: payment.billId }, data: { tipTotal: { increment: tip } } });
      await this.billing.settle(tx, payment.billId);
      return payment.billId;
    });
    if (!billId) return;
    await this.audit.log(actor, 'payment.terminal_succeeded', 'bill', billId, { amount: received.toString(), tip: tip.toString(), card });
    await this.billing.afterChange(actor, billId);
  }

  /** "Visa •••• 4242 · Apple Pay" para el historial de la cuenta. */
  private async cardLabel(intent: Stripe.PaymentIntent): Promise<string | null> {
    try {
      const id = typeof intent.latest_charge === 'string' ? intent.latest_charge : intent.latest_charge?.id;
      if (!id) return null;
      const charge = await this.stripe.api.charges.retrieve(id);
      const c = charge.payment_method_details?.card_present;
      if (!c) return null;
      const brand = c.brand ? c.brand[0].toUpperCase() + c.brand.slice(1) : 'Tarjeta';
      const wallet = c.wallet?.type ? ` · ${c.wallet.type.replace('_', ' ')}` : '';
      return `${brand} •••• ${c.last4 ?? '????'}${wallet}`.slice(0, 60);
    } catch {
      return null;
    }
  }
}
