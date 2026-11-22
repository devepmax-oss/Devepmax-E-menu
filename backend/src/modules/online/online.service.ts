import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma, RestaurantSettings } from '@prisma/client';
import { AttemptLimiter } from '../../common/attempt-limiter';
import { PrismaService } from '../../prisma/prisma.service';
import { computeTotals } from '../orders/order.rules';
import { OrdersService } from '../orders/orders.service';
import { PricingService } from '../orders/pricing.service';
import { toPublicOrderView } from '../orders/public-order.view';
import { DeliveryService } from '../delivery/delivery.service';
import { PaymentsService } from '../payments/payments.service';
import { StripeService } from '../payments/stripe.service';
import { PromotionsService } from '../promotions/promotions.service';
import { SettingsService } from '../settings/settings.service';
import { CreateOnlineOrderDto, OnlineQuoteDto } from './dto/online.dto';
import { isOpenAt } from './opening-hours';

const PUBLIC_CODE = /^[A-Z0-9]{6,12}$/;

/** Pedidos desde la web: sin cuenta de empleado, con reglas propias del canal online. */
@Injectable()
export class OnlineService {
  // Freno ante abuso: pedidos creados por IP en 15 minutos.
  private readonly limiter = new AttemptLimiter(30, 15 * 60_000);

  constructor(
    private readonly prisma: PrismaService,
    private readonly settings: SettingsService,
    private readonly pricing: PricingService,
    private readonly promotions: PromotionsService,
    private readonly orders: OrdersService,
    private readonly payments: PaymentsService,
    private readonly stripe: StripeService,
    private readonly delivery: DeliveryService,
  ) {}

  /** Todo lo que la web necesita para arrancar: marca, horario, canales, envío y pagos. */
  async config() {
    const [pub, zone] = await Promise.all([this.settings.getPublic(), this.deliveryZone()]);
    return {
      ...pub,
      isOpenNow: isOpenAt(pub.openingHours, pub.timezone),
      delivery: {
        fee: zone?.fee ?? new Prisma.Decimal(0),
        minOrder: zone?.minOrder ?? new Prisma.Decimal(0),
        etaMinutes: zone?.etaMinutes ?? pub.prepTimeMinutes + 20,
      },
      payments: {
        card: this.stripe.configured,
        payAtPickup: true,
        publishableKey: this.stripe.publishableKey,
      },
    };
  }

  /** Cotiza el carrito: precios, promociones, impuesto, envío, propina y total. */
  async quote(dto: OnlineQuoteDto) {
    const settings = await this.settings.get();
    this.assertFulfillment(settings, dto.fulfillmentType);
    const zone = dto.fulfillmentType === 'DELIVERY' ? await this.deliveryZone() : null;

    const lines = await this.pricing.priceLines(this.prisma, 'online', dto.items);
    const allocations = await this.promotions.applyToLines('online', lines);
    const perLine = new Map<number, Prisma.Decimal>();
    for (const a of allocations) {
      for (const [line, amount] of a.perLine) perLine.set(line, (perLine.get(line) ?? new Prisma.Decimal(0)).plus(amount));
    }
    const deliveryFee = zone?.fee ?? new Prisma.Decimal(0);
    const totals = computeTotals(
      lines.map((l, i) => ({ lineTotal: l.lineTotal, taxRate: l.taxRate, discount: perLine.get(i) })),
      { deliveryFee, tipTotal: dto.tipAmount ?? 0 },
    );
    const minOrder = zone?.minOrder ?? new Prisma.Decimal(0);
    return {
      lines: lines.map((l, i) => ({
        productId: l.productId,
        name: l.nameSnapshot,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        modifiersTotal: l.modifiersTotal,
        lineTotal: l.lineTotal,
        discount: perLine.get(i) ?? new Prisma.Decimal(0),
        modifiers: l.modifiers.map((m) => ({ group: m.groupNameSnapshot, option: m.optionNameSnapshot })),
      })),
      promotions: allocations.map((a) => ({ promotionId: a.promotionId, name: a.name, amount: a.amount })),
      totals,
      minOrder,
      meetsMinimum: totals.subtotal.gte(minOrder),
    };
  }

  /**
   * Crea el pedido. Con tarjeta queda "esperando pago" (no va a cocina hasta que Stripe
   * confirme); pagando al recoger va a cocina de inmediato.
   */
  async createOrder(dto: CreateOnlineOrderDto, ip: string) {
    this.limiter.assertAllowed(ip);
    this.limiter.fail(ip); // cuenta pedidos, no solo errores

    const settings = await this.settings.get();
    if (settings.maintenanceMode || settings.onlineOrderingPaused) {
      throw new ServiceUnavailableException('Ahora mismo no estamos recibiendo pedidos en línea');
    }
    this.assertFulfillment(settings, dto.fulfillmentType);
    const hours = await this.prisma.openingHour.findMany();
    if (!isOpenAt(hours, settings.timezone)) {
      throw new BadRequestException('El restaurante está cerrado en este momento');
    }
    const delivery = dto.fulfillmentType === 'DELIVERY';
    if (delivery && !dto.deliveryAddress) throw new BadRequestException('Falta la dirección de entrega');
    if (delivery && dto.paymentMethod === 'pay_at_pickup') {
      throw new BadRequestException('El delivery se paga en línea con tarjeta');
    }
    if (dto.paymentMethod === 'card' && !this.stripe.configured) {
      throw new ServiceUnavailableException('El pago con tarjeta no está disponible; elige pagar al recoger');
    }

    const zone = delivery ? await this.deliveryZone() : null;
    if (zone && zone.minOrder.gt(0)) {
      const lines = await this.pricing.priceLines(this.prisma, 'online', dto.items);
      const subtotal = lines.reduce((sum, l) => sum.plus(l.lineTotal), new Prisma.Decimal(0));
      if (subtotal.lt(zone.minOrder)) {
        throw new BadRequestException(`El pedido mínimo para delivery es de $${zone.minOrder.toFixed(2)}`);
      }
    }

    const address = dto.deliveryAddress;
    const order = await this.orders.createOrder(
      {
        clientRequestId: dto.clientRequestId,
        channel: 'ONLINE',
        fulfillmentType: dto.fulfillmentType,
        status: dto.paymentMethod === 'card' ? 'PENDING_PAYMENT' : 'PLACED',
        customerName: dto.customer.name,
        customerPhone: dto.customer.phone,
        customerEmail: dto.customer.email,
        deliveryAddress: delivery && address
          ? { street: address.street, city: address.city, state: address.state, zipCode: address.zipCode }
          : undefined,
        deliveryInstructions: address?.instructions,
        notes: dto.notes,
        items: dto.items,
        pricingChannel: 'online',
        deliveryFee: zone?.fee,
        tipTotal: dto.tipAmount ? new Prisma.Decimal(dto.tipAmount) : undefined,
      },
      'system',
    );

    // Ubicar la dirección en el mapa en segundo plano (no retrasa el pedido).
    if (delivery && address) {
      void this.delivery
        .locateOrder(order.id, { street: address.street, city: address.city, state: address.state, zipCode: address.zipCode })
        .catch(() => undefined);
    }

    const payment =
      order.status === 'PENDING_PAYMENT'
        ? await this.payments.startOnlinePayment(order, dto.customer.email)
        : null;
    return {
      order: toPublicOrderView(order),
      payment: payment ? { clientSecret: payment.clientSecret, publishableKey: this.stripe.publishableKey } : null,
    };
  }

  /** Seguimiento público por código (lo que el cliente ve en su teléfono). */
  async getPublic(code: string) {
    return toPublicOrderView(await this.findByCode(code));
  }

  /**
   * La web llama aquí al volver de Stripe: se consulta el cobro y, si está pagado,
   * el pedido pasa a cocina. (El webhook hace lo mismo; lo que llegue primero gana.)
   */
  async confirmPayment(code: string) {
    const order = await this.findByCode(code);
    if (order.status === 'PENDING_PAYMENT') {
      const payment = await this.prisma.payment.findFirst({
        where: { billId: order.bill.id, method: 'CARD_ONLINE', stripePaymentIntentId: { not: null } },
        orderBy: { createdAt: 'desc' },
      });
      if (payment?.stripePaymentIntentId) await this.payments.syncPaymentIntent(payment.stripePaymentIntentId);
    }
    return this.getPublic(code);
  }

  private async findByCode(code: string) {
    const normalized = code.trim().toUpperCase();
    if (!PUBLIC_CODE.test(normalized)) throw new NotFoundException('Pedido no encontrado');
    const order = await this.orders.findByPublicCode(normalized);
    if (!order || order.channel !== 'ONLINE') throw new NotFoundException('Pedido no encontrado');
    return order;
  }

  private assertFulfillment(settings: RestaurantSettings, type: 'PICKUP' | 'DELIVERY') {
    if (type === 'PICKUP' && !settings.acceptsPickup) throw new BadRequestException('Pickup no está disponible');
    if (type === 'DELIVERY' && !settings.acceptsDelivery) throw new BadRequestException('Delivery no está disponible');
  }

  private deliveryZone() {
    return this.prisma.deliveryZone.findFirst({ where: { isActive: true }, orderBy: { fee: 'asc' } });
  }
}
