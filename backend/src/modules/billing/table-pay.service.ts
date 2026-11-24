import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type Stripe from 'stripe';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { verifyTablePay } from '../../common/pay-token';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { isUniqueViolation } from '../../prisma/errors';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { StripeService } from '../payments/stripe.service';
import { SettingsService } from '../settings/settings.service';
import { BillingService, BillView } from './billing.service';
import { TablePayConfirmDto, TablePayIntentDto } from './dto/billing.dto';

const D = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const toCents = (v: Prisma.Decimal.Value) => D(v).times(100).toDecimalPlaces(0).toNumber();
const fromCents = (c: number) => D(c).div(100);
/** Después de cerrar la mesa, el enlace sigue mostrando "pagada" un rato (quien recarga la página). */
const CLOSED_GRACE_MS = 3 * 60 * 60_000;

/**
 * Pagar desde la mesa con el celular del cliente: la tablet muestra un QR, el cliente abre la
 * cuenta en su teléfono y paga todo, su parte o un monto, con tarjeta, Apple Pay o Google Pay,
 * y deja propina. La tarjeta nunca se escribe en la tablet del restaurante.
 */
@Injectable()
export class TablePayService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TablePayService.name);
  private readonly env = loadEnv();
  private readonly limiter = new AttemptLimiter(20, 15 * 60_000);
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
    // Stripe avisa por webhook: se aplica igual que cuando la web confirma.
    this.unsubscribe = this.events.subscribe((e) => {
      if (e.name !== 'payment.bill_intent') return;
      void this.applyIntent(e.payload as Stripe.PaymentIntent).catch((err) => this.logger.error(`Pago desde la mesa: ${String(err)}`));
    });
  }

  onModuleDestroy() {
    this.unsubscribe?.();
  }

  // ───────── Consultar ─────────

  /** La cuenta de la mesa como la ve el cliente (sin datos del personal). */
  async view(token: string) {
    const session = await this.session(token);
    const bills = await this.bills(session.id);
    const open = session.status === 'OPEN' || session.status === 'BILL_REQUESTED';
    const many = bills.length > 1;
    return {
      table: session.table.label,
      closed: !open,
      payable: open && this.stripe.configured && !!this.stripe.publishableKey,
      publishableKey: this.stripe.publishableKey,
      tipPercents: [15, 18, 20],
      bills: bills.map((b, i) => ({
        id: b.id,
        label: many ? `Cuenta ${i + 1}` : 'Cuenta',
        status: b.status,
        items: b.items.map((it) => ({
          id: it.id,
          name: it.name,
          quantity: it.quantity,
          lineTotal: it.lineTotal,
          discount: it.discount,
          modifiers: it.modifiers,
        })),
        subtotal: b.subtotal,
        discountTotal: b.discountTotal,
        taxTotal: b.taxTotal,
        tipTotal: b.tipTotal,
        total: b.total,
        amountPaid: b.amountPaid,
        due: b.due,
        payments: b.payments
          .filter((p) => p.status === 'SUCCEEDED')
          .map((p) => ({ id: p.id, amount: p.amount, tipAmount: p.tipAmount, createdAt: p.createdAt })),
      })),
    };
  }

  // ───────── Pagar ─────────

  /** Crea (o retoma) el cobro de Stripe por el monto que eligió el cliente. */
  async intent(token: string, dto: TablePayIntentDto) {
    const session = await this.session(token);
    if (session.status !== 'OPEN' && session.status !== 'BILL_REQUESTED') throw new ConflictException('Esta mesa ya cerró su cuenta');
    if (!this.stripe.configured || !this.stripe.publishableKey) throw new ServiceUnavailableException('El pago con el celular no está disponible');
    this.limiter.assertAllowed(`pay:${session.id}`);
    this.limiter.fail(`pay:${session.id}`); // cuenta cada intento (no es un error)

    const existing = await this.prisma.payment.findUnique({ where: { clientRequestId: dto.clientRequestId } });
    if (existing?.stripePaymentIntentId) {
      const intent = await this.stripe.retrievePaymentIntent(existing.stripePaymentIntentId);
      if (existing.billId !== dto.billId) throw new BadRequestException('Ese pago es de otra cuenta');
      return { paymentId: existing.id, clientSecret: intent.client_secret, amount: fromCents(intent.amount) };
    }

    const bill = await this.billing.view(dto.billId);
    if (bill.session?.id !== session.id) throw new NotFoundException('Cuenta no encontrada');
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada');
    const amount = D(dto.amount).toDecimalPlaces(2);
    if (amount.gt(bill.due.plus(0.001))) throw new BadRequestException(`Quedan $${bill.due.toFixed(2)} por pagar: el monto es mayor`);
    const tip = D(dto.tip ?? 0).toDecimalPlaces(2);
    const cents = toCents(amount.plus(tip));
    if (cents < 50) throw new BadRequestException('El mínimo para pagar con tarjeta es $0.50');

    const settings = await this.settings.get();
    const intent = await this.stripe.createPaymentIntent(
      {
        amount: cents,
        currency: settings.currency.toLowerCase(),
        automatic_payment_methods: { enabled: true },
        receipt_email: dto.email || undefined,
        description: `${settings.name} · Mesa ${session.table.label}`,
        metadata: { kind: 'table_qr', billId: bill.id, tableSessionId: session.id, tipCents: String(toCents(tip)) },
      },
      `tablepay-${dto.clientRequestId}`,
    );
    const shift = await this.prisma.cashShift.findFirst({ where: { closedAt: null }, orderBy: { openedAt: 'desc' } });
    try {
      const payment = await this.prisma.payment.create({
        data: {
          billId: bill.id,
          method: 'CARD_QR',
          status: 'PENDING',
          amount: amount.plus(tip),
          tipAmount: tip,
          stripePaymentIntentId: intent.id,
          clientRequestId: dto.clientRequestId,
          cashShiftId: shift?.id ?? null,
        },
      });
      return { paymentId: payment.id, clientSecret: intent.client_secret, amount: amount.plus(tip) };
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
      const again = await this.prisma.payment.findUniqueOrThrow({ where: { clientRequestId: dto.clientRequestId } });
      return { paymentId: again.id, clientSecret: intent.client_secret, amount: amount.plus(tip) };
    }
  }

  /** La web avisa que el cliente terminó de pagar: se consulta a Stripe y se aplica. */
  async confirm(token: string, dto: TablePayConfirmDto) {
    const session = await this.session(token);
    const payment = await this.prisma.payment.findUnique({
      where: { stripePaymentIntentId: dto.paymentIntentId },
      include: { bill: { select: { tableSessionId: true } } },
    });
    if (!payment || payment.method !== 'CARD_QR' || payment.bill.tableSessionId !== session.id) {
      throw new NotFoundException('Pago no encontrado');
    }
    const intent = await this.stripe.retrievePaymentIntent(dto.paymentIntentId);
    await this.applyIntent(intent);
    const status = intent.status === 'succeeded' ? 'succeeded' : intent.status === 'canceled' ? 'failed' : 'pending';
    return { status, view: await this.view(token) };
  }

  // ───────── Internos ─────────

  private async session(token: string) {
    const sessionId = verifyTablePay(token, this.env.jwtAccessSecret);
    const session = sessionId
      ? await this.prisma.tableSession.findUnique({ where: { id: sessionId }, include: { table: true } })
      : null;
    if (!session) throw new NotFoundException('Este enlace de pago no es válido');
    const open = session.status === 'OPEN' || session.status === 'BILL_REQUESTED';
    if (!open && (!session.closedAt || Date.now() - session.closedAt.getTime() > CLOSED_GRACE_MS)) {
      throw new NotFoundException('Esta mesa ya cerró su cuenta');
    }
    return session;
  }

  private async bills(sessionId: string): Promise<BillView[]> {
    const rows = await this.prisma.bill.findMany({
      where: { tableSessionId: sessionId, status: { not: 'VOID' }, items: { some: { status: 'ACTIVE' } } },
      select: { id: true },
      orderBy: { createdAt: 'asc' },
    });
    return Promise.all(rows.map((r) => this.billing.view(r.id)));
  }

  /** Aplica el resultado de Stripe una sola vez (webhook y web pueden llegar a la vez). */
  async applyIntent(intent: Stripe.PaymentIntent): Promise<void> {
    if (intent.status === 'canceled') {
      await this.prisma.payment.updateMany({ where: { stripePaymentIntentId: intent.id, status: 'PENDING' }, data: { status: 'CANCELLED' } });
      return;
    }
    if (intent.status !== 'succeeded') return;
    const received = fromCents(intent.amount_received);
    const tip = fromCents(Number(intent.metadata?.tipCents ?? 0) || 0);
    const card = await this.cardLabel(intent);
    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.payment.findUnique({ where: { stripePaymentIntentId: intent.id } });
      if (!payment) return null;
      const before = await tx.bill.findUniqueOrThrow({ where: { id: payment.billId } });
      const updated = await tx.payment.updateMany({
        where: { id: payment.id, status: 'PENDING' },
        data: { status: 'SUCCEEDED', amount: received, tipAmount: tip, reference: card },
      });
      if (updated.count === 0) return null;
      if (tip.gt(0)) await tx.bill.update({ where: { id: payment.billId }, data: { tipTotal: { increment: tip } } });
      await this.billing.settle(tx, payment.billId);
      // Dos personas pagaron lo mismo a la vez: el dinero ya entró, la caja debe devolver la diferencia.
      const overpaid = before.amountPaid.plus(received).minus(before.total.plus(tip));
      return { billId: payment.billId, overpaid: overpaid.gt(0.009) ? overpaid : null };
    });
    if (!result) return;
    await this.audit.log('system', 'payment.table_qr', 'bill', result.billId, {
      amount: received.toString(),
      tip: tip.toString(),
      card,
    });
    if (result.overpaid) {
      this.logger.warn(`Cuenta ${result.billId}: se pagaron $${result.overpaid.toFixed(2)} de más desde la mesa (devolver).`);
      await this.audit.log('system', 'payment.overpaid', 'bill', result.billId, { extra: result.overpaid.toString() });
    }
    await this.billing.afterChange('system', result.billId);
  }

  /** "Visa •••• 4242 · Apple Pay" para el historial de la cuenta. */
  private async cardLabel(intent: Stripe.PaymentIntent): Promise<string | null> {
    try {
      const id = typeof intent.latest_charge === 'string' ? intent.latest_charge : intent.latest_charge?.id;
      if (!id) return 'Celular del cliente';
      const charge = await this.stripe.api.charges.retrieve(id);
      const c = charge.payment_method_details?.card;
      if (!c) return `Celular · ${charge.payment_method_details?.type ?? 'otro'}`.slice(0, 60);
      const brand = c.brand ? c.brand[0].toUpperCase() + c.brand.slice(1) : 'Tarjeta';
      const wallet = c.wallet?.type ? ` · ${c.wallet.type === 'apple_pay' ? 'Apple Pay' : c.wallet.type === 'google_pay' ? 'Google Pay' : c.wallet.type}` : '';
      return `${brand} •••• ${c.last4 ?? '????'}${wallet} · QR`.slice(0, 60);
    } catch {
      return 'Celular del cliente';
    }
  }
}
