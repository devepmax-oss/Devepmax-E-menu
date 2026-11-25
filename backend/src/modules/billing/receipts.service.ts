import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { signReceipt, signTablePay, verifyReceipt } from '../../common/pay-token';
import { loadEnv } from '../../config/env';
import { toE164 } from '../../common/phone';
import { AuditService } from '../audit/audit.service';
import { SettingsService } from '../settings/settings.service';
import { BillingService, BillView } from './billing.service';
import { SendReceiptDto } from './dto/billing.dto';

const METHOD_LABEL: Record<string, string> = {
  CASH: 'Efectivo',
  CARD_TERMINAL: 'Tarjeta',
  CARD_ONLINE: 'Tarjeta en línea',
  CARD_QR: 'Celular (QR)',
  OTHER: 'Otro',
};

const money = (v: Prisma.Decimal.Value, currency: string) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(new Prisma.Decimal(v).toNumber());

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export { toE164 };

/**
 * Recibos: una página con el recibo (enlace firmado), y el envío por email o SMS. El ticket
 * impreso lleva un QR al mismo enlace.
 */
@Injectable()
export class ReceiptsService {
  private readonly logger = new Logger(ReceiptsService.name);
  private readonly env = loadEnv();

  constructor(
    private readonly billing: BillingService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
  ) {}

  config() {
    const r = this.env.receipts;
    return { email: !!(r.resendApiKey && r.emailFrom), sms: !!(r.twilioAccountSid && r.twilioAuthToken && r.smsFrom) };
  }

  url(billId: string): string {
    return `${this.env.webUrl}/recibo/${signReceipt(billId, this.env.jwtAccessSecret)}`;
  }

  /** El recibo para el cliente (sin datos internos). Solo existe si ya se cobró algo. */
  async publicView(token: string) {
    const billId = verifyReceipt(token, this.env.jwtAccessSecret);
    if (!billId) throw new NotFoundException('Recibo no encontrado');
    const bill = await this.billing.view(billId).catch(() => null);
    if (!bill || !this.hasPayments(bill)) throw new NotFoundException('Recibo no encontrado');
    return this.toReceipt(bill);
  }

  /** Lo mismo, para la caja (imprimir el ticket del pago). */
  async forStaff(billId: string) {
    return { ...(await this.toReceipt(await this.paidBill(billId))), url: this.url(billId) };
  }

  /**
   * La cuenta antes de pagar (pre-cuenta): lo pedido y el total, propinas sugeridas y, en una
   * mesa, el QR para pagar con el celular. No es un comprobante de pago.
   */
  async check(billId: string) {
    const bill = await this.billing.view(billId);
    if (bill.status !== 'UNPAID' && bill.status !== 'PARTIALLY_PAID') throw new ConflictException('Esta cuenta ya está pagada: imprime el recibo');
    const s = await this.settings.get();
    const base = bill.due.toNumber();
    const stripeReady = !!(this.env.stripe.secretKey && this.env.stripe.publishableKey);
    return {
      ...(await this.toReceipt(bill)),
      tips: s.tipPresets.map((percent) => ({ percent, amount: Math.round(base * percent) / 100 })),
      payUrl: stripeReady && bill.session ? `${this.env.webUrl}/cuenta/${signTablePay(bill.session.id, this.env.jwtAccessSecret)}` : null,
    };
  }

  /** Las cuentas por pagar de la visita en curso de una mesa. */
  async tableChecks(tableId: string) {
    const bills = (await this.billing.list(tableId)).filter((b) => b.status === 'UNPAID' || b.status === 'PARTIALLY_PAID');
    return Promise.all(bills.map((b) => this.check(b.id)));
  }

  async send(actor: EmployeeActor, billId: string, dto: SendReceiptDto) {
    if (!dto.email && !dto.phone) throw new BadRequestException('Escribe un email o un teléfono');
    const receipt = await this.toReceipt(await this.paidBill(billId));
    const url = this.url(billId);
    const sent: string[] = [];
    if (dto.email) {
      await this.sendEmail(dto.email.trim(), receipt, url);
      sent.push('email');
    }
    if (dto.phone) {
      const to = toE164(dto.phone);
      if (!to) throw new BadRequestException('Revisa el teléfono (10 dígitos)');
      await this.sendSms(to, receipt, url);
      sent.push('sms');
    }
    await this.audit.log(actor, 'receipt.send', 'bill', billId, { channels: sent });
    return { sent, url };
  }

  private hasPayments(bill: BillView) {
    return bill.payments.some((p) => p.status === 'SUCCEEDED');
  }

  /** El recibo es el comprobante de un pago: sin cobro no hay recibo (para eso está la cuenta). */
  private async paidBill(billId: string) {
    const bill = await this.billing.view(billId);
    if (!this.hasPayments(bill)) throw new ConflictException('Todavía no hay pagos: el recibo se da después de cobrar. Para mostrar el total, imprime la cuenta.');
    return bill;
  }

  private async toReceipt(bill: BillView) {
    const s = await this.settings.get();
    const succeeded = bill.payments.filter((p) => p.status === 'SUCCEEDED');
    return {
      restaurant: {
        name: s.name,
        legalName: s.legalName,
        logoUrl: s.logoUrl,
        phone: s.phone,
        email: s.email,
        address: [s.addressLine, [s.city, [s.state, s.zipCode].filter(Boolean).join(' ')].filter(Boolean).join(', ')].filter(Boolean),
        footer: s.receiptFooter,
      },
      currency: s.currency,
      timezone: s.timezone,
      id: bill.id,
      status: bill.status,
      kind: bill.kind,
      label: bill.label,
      orderNumbers: bill.orders.filter((o) => o.status !== 'CANCELLED').map((o) => o.number),
      date: (bill.payments.at(-1)?.createdAt ?? bill.openedAt).toISOString(),
      items: bill.items.map((i) => ({
        id: i.id,
        name: i.name,
        quantity: i.quantity,
        lineTotal: i.lineTotal,
        discount: i.discount,
        modifiers: i.modifiers,
      })),
      discounts: bill.discounts.map((d) => ({ id: d.id, reason: d.reason, amount: d.amount, item: d.itemName })),
      subtotal: bill.subtotal,
      discountTotal: bill.discountTotal,
      taxTotal: bill.taxTotal,
      deliveryFee: bill.deliveryFee,
      tipTotal: bill.tipTotal,
      total: bill.total,
      amountPaid: bill.amountPaid,
      due: bill.due,
      refundedTotal: bill.refundedTotal,
      payments: succeeded.map((p) => ({
        id: p.id,
        method: METHOD_LABEL[p.method] ?? p.method,
        reference: p.reference,
        amount: p.amount,
        tipAmount: p.tipAmount,
        cashTendered: p.cashTendered,
        changeGiven: p.changeGiven,
        createdAt: p.createdAt,
      })),
      refunds: succeeded.flatMap((p) => p.refunds.map((r) => ({ id: r.id, amount: r.amount, createdAt: r.createdAt, method: METHOD_LABEL[p.method] ?? p.method }))),
    };
  }

  // ───────── Envío ─────────

  private async sendEmail(to: string, receipt: Awaited<ReturnType<ReceiptsService['toReceipt']>>, url: string) {
    const { resendApiKey, emailFrom } = this.env.receipts;
    if (!resendApiKey || !emailFrom) throw new ServiceUnavailableException('El envío por email no está configurado');
    const c = receipt.currency;
    const name = escapeHtml(receipt.restaurant.name);
    const rows = receipt.items
      .map(
        (i) =>
          `<tr><td style="padding:4px 0">${i.quantity}× ${escapeHtml(i.name)}${i.modifiers.length ? `<br><span style="color:#888;font-size:12px">${escapeHtml(i.modifiers.join(', '))}</span>` : ''}</td><td style="padding:4px 0;text-align:right">${money(i.lineTotal, c)}</td></tr>`,
      )
      .join('');
    const line = (label: string, value: string, bold = false) =>
      `<tr><td style="padding:2px 0;${bold ? 'font-weight:700;font-size:16px' : 'color:#555'}">${label}</td><td style="padding:2px 0;text-align:right;${bold ? 'font-weight:700;font-size:16px' : 'color:#555'}">${value}</td></tr>`;
    const html = `<!doctype html><html><body style="margin:0;background:#f4f1ec;font-family:-apple-system,Segoe UI,Roboto,sans-serif;color:#1d150e">
<div style="max-width:480px;margin:0 auto;padding:24px">
<div style="background:#fff;border-radius:16px;padding:24px">
<h1 style="margin:0 0 4px;font-size:22px">${name}</h1>
<p style="margin:0 0 16px;color:#777">Gracias por tu visita · ${escapeHtml(receipt.label)}</p>
<table style="width:100%;border-collapse:collapse;font-size:14px">${rows}</table>
<hr style="border:0;border-top:1px solid #eee;margin:12px 0">
<table style="width:100%;border-collapse:collapse;font-size:14px">
${line('Subtotal', money(receipt.subtotal, c))}
${Number(receipt.discountTotal) > 0 ? line('Descuentos', `−${money(receipt.discountTotal, c)}`) : ''}
${line('Impuestos', money(receipt.taxTotal, c))}
${Number(receipt.tipTotal) > 0 ? line('Propina', money(receipt.tipTotal, c)) : ''}
${line('Total', money(receipt.total, c), true)}
${Number(receipt.refundedTotal) > 0 ? line('Reembolsado', `−${money(receipt.refundedTotal, c)}`) : ''}
</table>
<p style="margin:20px 0 0;text-align:center"><a href="${url}" style="display:inline-block;background:#1d150e;color:#fff;text-decoration:none;padding:12px 22px;border-radius:999px;font-weight:700">Ver recibo completo</a></p>
${receipt.restaurant.footer ? `<p style="margin:18px 0 0;text-align:center;color:#888;font-size:13px">${escapeHtml(receipt.restaurant.footer)}</p>` : ''}
</div></div></body></html>`;
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: emailFrom,
        to: [to],
        subject: `Tu recibo de ${receipt.restaurant.name} · ${money(receipt.total, c)}`,
        html,
        text: `${receipt.restaurant.name}\nTotal: ${money(receipt.total, c)}\nRecibo: ${url}`,
      }),
    }).catch((e: unknown) => {
      this.logger.error(`Email: ${String(e)}`);
      return null;
    });
    if (!response?.ok) {
      const detail = response ? await response.text().catch(() => '') : '';
      this.logger.error(`Resend respondió ${response?.status}: ${detail.slice(0, 300)}`);
      throw new ServiceUnavailableException('No se pudo enviar el email. Intenta de nuevo.');
    }
  }

  private async sendSms(to: string, receipt: Awaited<ReturnType<ReceiptsService['toReceipt']>>, url: string) {
    const { twilioAccountSid: sid, twilioAuthToken: token, smsFrom } = this.env.receipts;
    if (!sid || !token || !smsFrom) throw new ServiceUnavailableException('El envío por SMS no está configurado');
    const body = `${receipt.restaurant.name}: gracias por tu visita. Tu recibo (${money(receipt.total, receipt.currency)}): ${url}`;
    const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: to, From: smsFrom, Body: body }).toString(),
    }).catch((e: unknown) => {
      this.logger.error(`SMS: ${String(e)}`);
      return null;
    });
    if (!response?.ok) {
      const detail = response ? await response.text().catch(() => '') : '';
      this.logger.error(`Twilio respondió ${response?.status}: ${detail.slice(0, 300)}`);
      throw new ServiceUnavailableException('No se pudo enviar el SMS. Revisa el número e intenta de nuevo.');
    }
  }
}
