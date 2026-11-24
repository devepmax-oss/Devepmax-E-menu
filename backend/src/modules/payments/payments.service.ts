import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type Stripe from 'stripe';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { OrdersService, OrderView } from '../orders/orders.service';
import { SettingsService } from '../settings/settings.service';
import { StripeService } from './stripe.service';

const toCents = (amount: Prisma.Decimal.Value) => new Prisma.Decimal(amount).times(100).toDecimalPlaces(0).toNumber();

export type PaymentOutcome = 'succeeded' | 'pending' | 'failed';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly stripe: StripeService,
    private readonly orders: OrdersService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
    private readonly events: DomainEventsService,
  ) {}

  /**
   * Inicia el cobro con tarjeta de una orden online, o retoma el que ya estaba pendiente
   * (si el cliente recarga la página no se crea un segundo cobro).
   */
  async startOnlinePayment(order: OrderView, receiptEmail?: string | null) {
    const amount = toCents(order.bill.total);
    if (amount < 50) throw new BadRequestException('El total es muy bajo para pagar con tarjeta');

    const pending = await this.prisma.payment.findFirst({
      where: { billId: order.bill.id, method: 'CARD_ONLINE', status: 'PENDING' },
      orderBy: { createdAt: 'desc' },
    });
    if (pending?.stripePaymentIntentId) {
      const current = await this.stripe.retrievePaymentIntent(pending.stripePaymentIntentId);
      if (current.amount === amount && current.client_secret && current.status !== 'canceled') {
        return { clientSecret: current.client_secret, paymentIntentId: current.id };
      }
    }

    const settings = await this.settings.get();
    const intent = await this.stripe.createPaymentIntent(
      {
        amount,
        currency: settings.currency.toLowerCase(),
        automatic_payment_methods: { enabled: true },
        receipt_email: receiptEmail || undefined,
        description: `${settings.name} · Pedido #${order.number}`,
        metadata: { orderId: order.id, billId: order.bill.id, publicCode: order.publicCode },
      },
      `order-${order.id}-${amount}`,
    );
    try {
      await this.prisma.payment.create({
        data: {
          billId: order.bill.id,
          method: 'CARD_ONLINE',
          status: 'PENDING',
          amount: order.bill.total,
          tipAmount: order.bill.tipTotal,
          stripePaymentIntentId: intent.id,
        },
      });
    } catch (error) {
      // Dos pedidos simultáneos con la misma clave: Stripe devolvió el mismo cobro y ya está guardado.
      if (!isUniqueViolation(error)) throw error;
    }
    if (!intent.client_secret) throw new BadRequestException('Stripe no devolvió el cobro');
    return { clientSecret: intent.client_secret, paymentIntentId: intent.id };
  }

  /** Pregunta a Stripe el estado real del cobro y lo aplica. Seguro de llamar varias veces. */
  async syncPaymentIntent(paymentIntentId: string): Promise<PaymentOutcome> {
    return this.applyPaymentIntent(await this.stripe.retrievePaymentIntent(paymentIntentId));
  }

  /** Aplica un cobro de Stripe (desde el webhook o desde la confirmación de la web). */
  async applyPaymentIntent(intent: Stripe.PaymentIntent): Promise<PaymentOutcome> {
    if (intent.metadata?.kind === 'terminal' || intent.metadata?.kind === 'table_qr') {
      this.events.emit(intent.metadata.kind === 'terminal' ? 'payment.terminal_intent' : 'payment.bill_intent', intent);
      return intent.status === 'succeeded' ? 'succeeded' : intent.status === 'canceled' ? 'failed' : 'pending';
    }
    if (intent.status === 'succeeded') {
      await this.markSucceeded(intent.id, intent.amount_received);
      return 'succeeded';
    }
    if (intent.status === 'canceled') {
      await this.prisma.payment.updateMany({
        where: { stripePaymentIntentId: intent.id, status: 'PENDING' },
        data: { status: 'CANCELLED' },
      });
      return 'failed';
    }
    return 'pending';
  }

  private async markSucceeded(paymentIntentId: string, amountReceivedCents: number): Promise<void> {
    const received = new Prisma.Decimal(amountReceivedCents).div(100);
    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await tx.payment.findUnique({ where: { stripePaymentIntentId: paymentIntentId } });
      if (!payment) return null; // un cobro que no es de este sistema
      // Solo la primera confirmación suma el pago (webhook y web pueden llegar a la vez).
      const updated = await tx.payment.updateMany({
        where: { id: payment.id, status: 'PENDING' },
        data: { status: 'SUCCEEDED', amount: received },
      });
      if (updated.count === 0) return { billId: payment.billId, first: false };
      const bill = await tx.bill.findUniqueOrThrow({ where: { id: payment.billId } });
      const amountPaid = bill.amountPaid.plus(received);
      const fullyPaid = amountPaid.gte(bill.total);
      await tx.bill.update({
        where: { id: bill.id },
        data: { amountPaid, status: fullyPaid ? 'PAID' : 'PARTIALLY_PAID', closedAt: fullyPaid ? new Date() : null },
      });
      return { billId: payment.billId, first: true };
    });
    if (!result) return;
    if (result.first) {
      await this.audit.log('system', 'payment.succeeded', 'bill', result.billId, {
        paymentIntentId,
        amount: received.toString(),
      });
    }

    // Pagada: la orden pasa a cocina.
    const orders = await this.prisma.order.findMany({
      where: { billId: result.billId },
      select: { id: true, status: true, number: true },
    });
    for (const order of orders) {
      if (order.status === 'PENDING_PAYMENT') await this.orders.placeAfterPayment(order.id);
      else if (order.status === 'CANCELLED') {
        this.logger.warn(`El pedido #${order.number} se pagó pero estaba cancelado: requiere reembolso.`);
      }
    }
  }
}
