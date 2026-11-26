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
import { NewOrder, OrdersService } from '../orders/orders.service';
import { PricingService } from '../orders/pricing.service';
import { toPublicOrderView } from '../orders/public-order.view';
import { DeliveryService } from '../delivery/delivery.service';
import { PaymentsService } from '../payments/payments.service';
import { StripeService } from '../payments/stripe.service';
import { PromotionsService } from '../promotions/promotions.service';
import { toE164 } from '../../common/phone';
import { CouponsService } from '../coupons/coupons.service';
import { CustomerAuthService } from '../customers/customer-auth.service';
import { CustomersService } from '../customers/customers.service';
import { SettingsService } from '../settings/settings.service';
import { CreateOnlineOrderDto, OnlineQuoteDto } from './dto/online.dto';
import { isOpenAt } from './opening-hours';
import { SCHEDULE_DAYS, isOfferedSlot, scheduleSlots } from './schedule.rules';

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
    private readonly customerAuth: CustomerAuthService,
    private readonly customers: CustomersService,
    private readonly coupons: CouponsService,
  ) {}

  /** Todo lo que la web necesita para arrancar: marca, horario, canales, envío y pagos. */
  async config() {
    const [pub, zone, settings] = await Promise.all([this.settings.getPublic(), this.deliveryZone(), this.settings.get()]);
    return {
      ...pub,
      isOpenNow: isOpenAt(pub.openingHours, pub.timezone),
      scheduling: { enabled: settings.scheduledOrdersEnabled, maxDays: SCHEDULE_DAYS },
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

  /**
   * Horas para programar (próximos 7 días, cada 15 min, dentro del horario). Para recoger se
   * deja el tiempo de preparación desde que abre; para delivery, el tiempo de entrega.
   */
  async slots(fulfillmentType: 'PICKUP' | 'DELIVERY') {
    const settings = await this.settings.get();
    const hours = await this.prisma.openingHour.findMany();
    const asap = isOpenAt(hours, settings.timezone);
    if (!settings.scheduledOrdersEnabled) return { enabled: false, asap, days: [] };
    const lead = await this.leadMinutes(settings, fulfillmentType);
    return { enabled: true, asap, leadMinutes: lead, days: scheduleSlots(hours, settings.timezone, new Date(), lead) };
  }

  /** Cotiza el carrito: precios, promociones, impuesto, envío, propina y total. */
  async quote(dto: OnlineQuoteDto, customerToken?: string) {
    const settings = await this.settings.get();
    this.assertFulfillment(settings, dto.fulfillmentType);
    const zone = dto.fulfillmentType === 'DELIVERY' ? await this.deliveryZone() : null;

    const lines = await this.pricing.priceLines(this.prisma, 'online', dto.items);
    const allocations = await this.promotions.applyToLines('online', lines);
    const perLine = new Map<number, Prisma.Decimal>();
    for (const a of allocations) {
      for (const [line, amount] of a.perLine) perLine.set(line, (perLine.get(line) ?? new Prisma.Decimal(0)).plus(amount));
    }
    let deliveryFee = zone?.fee ?? new Prisma.Decimal(0);
    // Cupón: se muestra el descuento o por qué no aplica (sin impedir la cotización).
    let coupon: { code: string; name: string; amount: Prisma.Decimal; freeDelivery: boolean; saved: Prisma.Decimal } | null = null;
    let couponError: string | null = null;
    if (dto.couponCode?.trim()) {
      const subtotal = lines.reduce((s, l) => s.plus(l.lineTotal), new Prisma.Decimal(0));
      const promos = [...perLine.values()].reduce((s, v) => s.plus(v), new Prisma.Decimal(0));
      const customer = await this.customerAuth.resolve(customerToken);
      try {
        const r = await this.coupons.check(dto.couponCode, {
          channel: 'online',
          base: subtotal.minus(promos),
          deliveryFee,
          customerId: customer?.id ?? null,
          phone: dto.phone ?? customer?.phone ?? null,
        });
        coupon = { code: r.coupon.code, name: r.label, amount: r.amount, freeDelivery: r.freeDelivery, saved: r.saved };
        if (r.freeDelivery) deliveryFee = new Prisma.Decimal(0);
      } catch (e) {
        couponError = e instanceof BadRequestException ? (e.message as string) : 'Ese cupón no se puede usar';
      }
    }
    const totals = computeTotals(
      lines.map((l, i) => ({ lineTotal: l.lineTotal, taxRate: l.taxRate, discount: perLine.get(i) })),
      { deliveryFee, tipTotal: dto.tipAmount ?? 0, billDiscount: coupon?.amount ?? 0 },
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
      coupon,
      couponError,
      totals,
      minOrder,
      meetsMinimum: totals.subtotal.gte(minOrder),
    };
  }

  /**
   * Crea el pedido. Con tarjeta queda "esperando pago" (no va a cocina hasta que Stripe
   * confirme); pagando al recoger va a cocina de inmediato.
   */
  async createOrder(dto: CreateOnlineOrderDto, ip: string, customerToken?: string) {
    this.limiter.assertAllowed(ip);
    this.limiter.fail(ip); // cuenta pedidos, no solo errores

    const settings = await this.settings.get();
    if (settings.maintenanceMode || settings.onlineOrderingPaused) {
      throw new ServiceUnavailableException('Ahora mismo no estamos recibiendo pedidos en línea');
    }
    this.assertFulfillment(settings, dto.fulfillmentType);
    const hours = await this.prisma.openingHour.findMany();
    // Programado: tiene que ser una de las horas ofrecidas (también con el restaurante cerrado).
    let scheduledFor: Date | undefined;
    let releaseAt: Date | undefined;
    if (dto.scheduledFor) {
      if (!settings.scheduledOrdersEnabled) throw new BadRequestException('Ahora no estamos aceptando pedidos programados');
      const lead = await this.leadMinutes(settings, dto.fulfillmentType);
      const at = new Date(dto.scheduledFor);
      if (!isOfferedSlot(scheduleSlots(hours, settings.timezone, new Date(), lead), at)) {
        throw new BadRequestException('Esa hora ya no está disponible; elige otra');
      }
      scheduledFor = at;
      releaseAt = new Date(at.getTime() - lead * 60_000);
    } else if (!isOpenAt(hours, settings.timezone)) {
      throw new BadRequestException(
        settings.scheduledOrdersEnabled
          ? 'El restaurante está cerrado en este momento; puedes programar tu pedido para cuando abramos'
          : 'El restaurante está cerrado en este momento',
      );
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
    // Con sesión de cliente, el pedido queda en su historial.
    const customer = await this.customerAuth.resolve(customerToken);

    // Cupón: se valida de nuevo con el teléfono del pedido (límites por cliente y primer pedido).
    let coupon: NewOrder['coupon'];
    let deliveryFee = zone?.fee;
    if (dto.couponCode?.trim()) {
      const lines = await this.pricing.priceLines(this.prisma, 'online', dto.items);
      const allocations = await this.promotions.applyToLines('online', lines);
      const subtotal = lines.reduce((s, l) => s.plus(l.lineTotal), new Prisma.Decimal(0));
      const promos = allocations.reduce((s, a) => s.plus(a.amount), new Prisma.Decimal(0));
      const r = await this.coupons.check(dto.couponCode, {
        channel: 'online',
        base: subtotal.minus(promos),
        deliveryFee: zone?.fee ?? 0,
        customerId: customer?.id ?? null,
        phone: dto.customer.phone,
      });
      coupon = {
        id: r.coupon.id,
        type: r.coupon.type,
        value: r.coupon.value,
        amount: r.amount,
        saved: r.saved,
        label: r.label,
        customerPhone: toE164(dto.customer.phone),
      };
      if (r.freeDelivery) deliveryFee = new Prisma.Decimal(0);
    }
    const order = await this.orders.createOrder(
      {
        clientRequestId: dto.clientRequestId,
        channel: 'ONLINE',
        fulfillmentType: dto.fulfillmentType,
        status: dto.paymentMethod === 'card' ? 'PENDING_PAYMENT' : scheduledFor ? 'SCHEDULED' : 'PLACED',
        scheduledFor,
        releaseAt,
        customerName: dto.customer.name,
        customerPhone: dto.customer.phone,
        customerEmail: dto.customer.email,
        customerId: customer?.id ?? null,
        deliveryAddress: delivery && address
          ? { street: address.street, city: address.city, state: address.state, zipCode: address.zipCode }
          : undefined,
        deliveryInstructions: address?.instructions,
        notes: dto.notes,
        items: dto.items,
        pricingChannel: 'online',
        deliveryFee,
        tipTotal: dto.tipAmount ? new Prisma.Decimal(dto.tipAmount) : undefined,
        coupon,
      },
      'system',
    );

    if (customer) {
      if (customer.name.trim().length < 2) {
        await this.prisma.customer.update({ where: { id: customer.id }, data: { name: dto.customer.name.trim() } }).catch(() => undefined);
      }
      if (delivery && address && dto.saveAddress) await this.customers.addAddress(customer, address).catch(() => undefined);
    }

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

  /** Minutos antes de la hora pedida en que el pedido pasa a cocina. */
  private async leadMinutes(settings: RestaurantSettings, type: 'PICKUP' | 'DELIVERY') {
    if (type === 'PICKUP') return settings.prepTimeMinutes;
    const zone = await this.deliveryZone();
    return zone?.etaMinutes ?? settings.prepTimeMinutes + 20;
  }

  private deliveryZone() {
    return this.prisma.deliveryZone.findFirst({ where: { isActive: true }, orderBy: { fee: 'asc' } });
  }
}
