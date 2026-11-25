import { BadRequestException, ConflictException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { Customer, Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { signPayload, signReceipt, verifyPayload } from '../../common/pay-token';
import { buildXlsx, Cell } from '../../common/xlsx';
import { toE164 } from '../../common/phone';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { BillingService } from '../billing/billing.service';
import { AddressDto, CreateCustomerDto, CustomersQueryDto, ExportCustomersDto, UpdateCustomerDto, UpdateMeDto } from './dto/customers.dto';
import { SettingsService } from '../settings/settings.service';

const MAX_ADDRESSES = 10;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Visitas que cuentan: cuentas no anuladas con algún pedido real (no la web sin pagar ni cancelado). */
const COUNTED_BILL: Prisma.BillWhereInput = {
  status: { not: 'VOID' },
  orders: { some: { status: { notIn: ['PENDING_PAYMENT', 'CANCELLED'] } } },
};

const HISTORY_INCLUDE = {
  orders: {
    orderBy: { createdAt: 'asc' },
    select: { id: true, number: true, publicCode: true, channel: true, fulfillmentType: true, status: true, createdAt: true },
  },
  items: { where: { status: 'ACTIVE' }, orderBy: { id: 'asc' }, include: { modifiers: true } },
  payments: { where: { status: 'SUCCEEDED' }, select: { id: true } },
  tableSession: { include: { table: { select: { label: true } } } },
} satisfies Prisma.BillInclude;

type HistoryBill = Prisma.BillGetPayload<{ include: typeof HISTORY_INCLUDE }>;

/**
 * Clientes: su cuenta (datos, direcciones, historial) y, para el personal, la lista de
 * clientes con sus visitas y el cliente de cada cuenta (caja o mesa).
 */
@Injectable()
export class CustomersService {
  private readonly env = loadEnv();

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly billing: BillingService,
    private readonly settings: SettingsService,
  ) {}

  // ───────── El cliente ─────────

  async profile(customer: Customer) {
    const addresses = await this.prisma.customerAddress.findMany({ where: { customerId: customer.id }, orderBy: { createdAt: 'asc' } });
    return {
      id: customer.id,
      name: customer.name,
      needsName: customer.name.trim().length < 2,
      phone: customer.phone,
      email: customer.email,
      marketingOptIn: customer.marketingOptIn,
      lang: customer.lang,
      addresses: addresses.map((a) => ({
        id: a.id,
        label: a.label,
        street: a.street,
        city: a.city,
        state: a.state,
        zipCode: a.zipCode,
        instructions: a.instructions,
      })),
    };
  }

  async updateMe(customer: Customer, dto: UpdateMeDto) {
    const updated = await this.prisma.customer.update({
      where: { id: customer.id },
      data: {
        ...(dto.name !== undefined ? { name: dto.name.trim() } : {}),
        ...(dto.marketingOptIn !== undefined ? { marketingOptIn: dto.marketingOptIn } : {}),
        ...(dto.lang !== undefined ? { lang: dto.lang } : {}),
      },
    });
    return this.profile(updated);
  }

  async addAddress(customer: Customer, dto: AddressDto) {
    const count = await this.prisma.customerAddress.count({ where: { customerId: customer.id } });
    if (count >= MAX_ADDRESSES) throw new BadRequestException(`Puedes guardar hasta ${MAX_ADDRESSES} direcciones`);
    const clean = this.cleanAddress(dto);
    // La misma dirección no se guarda dos veces.
    const same = await this.prisma.customerAddress.findFirst({
      where: { customerId: customer.id, street: { equals: clean.street, mode: 'insensitive' }, zipCode: clean.zipCode },
    });
    if (same) await this.prisma.customerAddress.update({ where: { id: same.id }, data: clean });
    else await this.prisma.customerAddress.create({ data: { ...clean, customerId: customer.id } });
    return this.profile(customer);
  }

  async updateAddress(customer: Customer, id: string, dto: AddressDto) {
    await this.ownAddress(customer, id);
    await this.prisma.customerAddress.update({ where: { id }, data: this.cleanAddress(dto) });
    return this.profile(customer);
  }

  async removeAddress(customer: Customer, id: string) {
    await this.ownAddress(customer, id);
    await this.prisma.customerAddress.delete({ where: { id } });
    return this.profile(customer);
  }

  /** Lo que el cliente ve en "Mis pedidos": cada visita o pedido con lo que llevó. */
  async history(customerId: string, take = 30) {
    const bills = await this.prisma.bill.findMany({
      where: { ...COUNTED_BILL, OR: [{ customerId }, { orders: { some: { customerId } } }] },
      include: HISTORY_INCLUDE,
      orderBy: { createdAt: 'desc' },
      take,
    });
    return bills.map((b) => this.historyEntry(b));
  }

  // ───────── El personal ─────────

  async list(query: CustomersQueryDto) {
    const where = this.whereFor(query.q, query.filter);
    const sort = query.sort ?? 'recent';
    const skip = query.offset ?? 0;
    const take = query.limit ?? 50;
    const total = await this.prisma.customer.count({ where });

    let customers: Customer[];
    if (sort === 'visits' || sort === 'spent' || sort === 'lastVisit') {
      // Los que más vienen / más gastan / vinieron hace menos (solo quienes tienen visitas).
      const groups = await this.prisma.bill.groupBy({
        by: ['customerId'],
        where: { ...COUNTED_BILL, customerId: { not: null }, customer: { is: where } },
        _count: { customerId: true },
        _sum: { amountPaid: true },
        _max: { createdAt: true },
        orderBy:
          sort === 'spent' ? { _sum: { amountPaid: 'desc' } } : sort === 'visits' ? { _count: { customerId: 'desc' } } : { _max: { createdAt: 'desc' } },
        skip,
        take,
      });
      const ids = groups.map((g) => g.customerId!).filter(Boolean);
      const rows = await this.prisma.customer.findMany({ where: { id: { in: ids } } });
      const byId = new Map(rows.map((c) => [c.id, c]));
      customers = ids.map((id) => byId.get(id)).filter((c): c is Customer => !!c);
    } else {
      customers = await this.prisma.customer.findMany({
        where,
        orderBy: sort === 'name' ? { name: 'asc' } : { createdAt: 'desc' },
        skip,
        take,
      });
    }
    const stats = await this.statsFor(customers.map((c) => c.id));
    return {
      total,
      customers: customers.map((c) => ({ ...this.summary(c), ...(stats.get(c.id) ?? this.emptyStats()) })),
    };
  }

  /** Enlace de descarga (10 min) de la lista en Excel, con la misma búsqueda y filtro. */
  exportLink(dto: ExportCustomersDto) {
    const expires = Date.now() + 10 * 60_000;
    const payload = JSON.stringify({ q: dto.q?.trim() || undefined, f: dto.filter ?? 'all', e: expires });
    const token = signPayload('customers-export:v1', payload, this.env.jwtAccessSecret);
    return { url: `${this.env.publicApiUrl}/customers/export/${token}`, expiresAt: new Date(expires).toISOString() };
  }

  async exportFromToken(token: string) {
    const raw = verifyPayload('customers-export:v1', token, this.env.jwtAccessSecret);
    let payload: { q?: string; f?: ExportCustomersDto['filter']; e?: number } | null = null;
    try {
      payload = raw ? JSON.parse(raw) : null;
    } catch {
      payload = null;
    }
    if (!payload || !(Number(payload.e) > Date.now())) throw new UnauthorizedException('El enlace venció: vuelve a exportar desde la app');
    const tz = (await this.settings.get()).timezone;
    const customers = await this.prisma.customer.findMany({ where: this.whereFor(payload.q, payload.f), orderBy: { name: 'asc' }, take: 20_000 });
    const stats = await this.statsFor(customers.map((c) => c.id));
    const day = (d: Date | null) => (d ? new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(d) : '');
    const rows: Cell[][] = [
      ['Nombre', 'Teléfono', 'Email', 'Acepta promociones', 'Cuenta web', 'Visitas', 'Gastado', 'Promedio', 'Última visita', 'Cliente desde', 'Notas'],
      ...customers.map((c): Cell[] => {
        const s = stats.get(c.id) ?? this.emptyStats();
        return [
          c.name,
          c.phone ?? '',
          c.email ?? '',
          c.marketingOptIn ? 'Sí' : 'No',
          c.lastLoginAt ? 'Sí' : 'No',
          s.visits,
          { money: s.spent.toNumber() },
          s.visits ? { money: s.spent.div(s.visits).toNumber() } : '',
          day(s.lastVisitAt),
          day(c.createdAt),
          c.notes ?? '',
        ];
      }),
    ];
    const buffer = buildXlsx([{ name: 'Clientes', rows, widths: [26, 16, 28, 12, 10, 9, 12, 12, 13, 13, 40] }]);
    return { name: `clientes-${day(new Date())}.xlsx`, buffer };
  }

  async detail(id: string) {
    const customer = await this.prisma.customer.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException('Cliente no encontrado');
    const [profile, stats, history] = await Promise.all([this.profile(customer), this.statsFor([id]), this.history(id, 50)]);
    return {
      ...profile,
      notes: customer.notes,
      createdAt: customer.createdAt,
      hasAccount: !!customer.lastLoginAt,
      lastLoginAt: customer.lastLoginAt,
      ...(stats.get(id) ?? this.emptyStats()),
      history,
    };
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateCustomerDto) {
    const customer = await this.prisma.customer.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException('Cliente no encontrado');
    let phone: string | null | undefined;
    if (dto.phone !== undefined) {
      phone = dto.phone === null || !dto.phone.trim() ? null : toE164(dto.phone);
      if (phone === null && dto.phone?.trim()) throw new BadRequestException('Escribe un teléfono de 10 dígitos');
      if (phone && phone !== customer.phone && (await this.prisma.customer.findUnique({ where: { phone } }))) {
        throw new ConflictException('Ese teléfono ya es de otro cliente. Si es la misma persona, júntalos.');
      }
    }
    let email: string | null | undefined;
    if (dto.email !== undefined) {
      email = dto.email?.trim().toLowerCase() || null;
      if (email && !EMAIL.test(email)) throw new BadRequestException('Revisa el email');
      if (email && email !== customer.email && (await this.prisma.customer.findUnique({ where: { email } }))) {
        throw new ConflictException('Ese email ya es de otro cliente. Si es la misma persona, júntalos.');
      }
    }
    // Sin teléfono ni email el cliente ya no podría entrar a su cuenta.
    const nextPhone = phone !== undefined ? phone : customer.phone;
    const nextEmail = email !== undefined ? email : customer.email;
    if (!nextPhone && !nextEmail && !customer.googleId) throw new BadRequestException('El cliente necesita un teléfono o un email');
    await this.prisma.customer.update({
      where: { id },
      data: {
        ...(dto.name !== undefined ? { name: dto.name.trim() } : {}),
        ...(phone !== undefined ? { phone } : {}),
        ...(email !== undefined ? { email } : {}),
        ...(dto.notes !== undefined ? { notes: dto.notes?.trim() || null } : {}),
        ...(dto.marketingOptIn !== undefined ? { marketingOptIn: dto.marketingOptIn } : {}),
      },
    });
    await this.audit.log(actor, 'customer.update', 'customer', id, { fields: Object.keys(dto) });
    return this.detail(id);
  }

  /**
   * Borra al cliente (por ejemplo, si pide que se borren sus datos). Sus pedidos y cuentas se
   * quedan para los reportes, sin el vínculo; sus direcciones y sesiones se borran.
   */
  async remove(actor: EmployeeActor, id: string) {
    const customer = await this.prisma.customer.findUnique({ where: { id } });
    if (!customer) throw new NotFoundException('Cliente no encontrado');
    await this.prisma.$transaction([
      this.prisma.order.updateMany({ where: { customerId: id }, data: { customerId: null } }),
      this.prisma.bill.updateMany({ where: { customerId: id }, data: { customerId: null } }),
      this.prisma.couponRedemption.updateMany({ where: { customerId: id }, data: { customerId: null, customerPhone: null } }),
      this.prisma.customer.delete({ where: { id } }),
    ]);
    await this.audit.log(actor, 'customer.delete', 'customer', id);
  }

  /** Junta dos fichas de la misma persona: todo pasa a [id] y la otra se borra. */
  async merge(actor: EmployeeActor, id: string, fromId: string) {
    if (id === fromId) throw new BadRequestException('Elige otro cliente');
    const [target, source] = await Promise.all([
      this.prisma.customer.findUnique({ where: { id } }),
      this.prisma.customer.findUnique({ where: { id: fromId }, include: { addresses: true } }),
    ]);
    if (!target || !source) throw new NotFoundException('Cliente no encontrado');
    const targetAddresses = await this.prisma.customerAddress.findMany({ where: { customerId: id } });
    const duplicated = source.addresses.filter((a) =>
      targetAddresses.some((t) => t.street.toLowerCase() === a.street.toLowerCase() && t.zipCode === a.zipCode),
    );
    const notes = [target.notes, source.notes].filter((n) => n?.trim()).join('\n') || null;
    await this.prisma.$transaction([
      this.prisma.order.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      this.prisma.bill.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      this.prisma.customerAddress.deleteMany({ where: { id: { in: duplicated.map((a) => a.id) } } }),
      this.prisma.customerAddress.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      this.prisma.customerSession.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      this.prisma.coupon.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      this.prisma.couponRedemption.updateMany({ where: { customerId: fromId }, data: { customerId: id } }),
      // Primero se borra la ficha vieja para liberar su teléfono, email y Google.
      this.prisma.customer.delete({ where: { id: fromId } }),
      this.prisma.customer.update({
        where: { id },
        data: {
          name: target.name.trim() ? target.name : source.name,
          phone: target.phone ?? source.phone,
          email: target.email ?? source.email,
          googleId: target.googleId ?? source.googleId,
          marketingOptIn: target.marketingOptIn || source.marketingOptIn,
          lang: target.lang ?? source.lang,
          notes,
          lastLoginAt:
            target.lastLoginAt && source.lastLoginAt
              ? new Date(Math.max(target.lastLoginAt.getTime(), source.lastLoginAt.getTime()))
              : (target.lastLoginAt ?? source.lastLoginAt),
          createdAt: target.createdAt < source.createdAt ? target.createdAt : source.createdAt,
        },
      }),
    ]);
    await this.audit.log(actor, 'customer.merge', 'customer', id, { fromId });
    return this.detail(id);
  }

  /** Buscar por teléfono en la caja o la mesa. */
  async lookup(phone: string) {
    const e164 = toE164(phone);
    if (!e164) throw new BadRequestException('Escribe un teléfono de 10 dígitos');
    const customer = await this.prisma.customer.findUnique({ where: { phone: e164 } });
    if (!customer) return { customer: null };
    const stats = (await this.statsFor([customer.id])).get(customer.id) ?? this.emptyStats();
    return { customer: { ...this.summary(customer), ...stats } };
  }

  /** Alta rápida (nombre y teléfono). Si el teléfono ya es de un cliente, se usa ese. */
  async create(actor: EmployeeActor, dto: CreateCustomerDto) {
    const phone = toE164(dto.phone);
    if (!phone) throw new BadRequestException('Escribe un teléfono de 10 dígitos');
    const email = dto.email?.trim().toLowerCase() || null;
    if (email && !EMAIL.test(email)) throw new BadRequestException('Revisa el email');
    const existing = await this.prisma.customer.findUnique({ where: { phone } });
    if (existing) {
      if (!existing.name.trim()) await this.prisma.customer.update({ where: { id: existing.id }, data: { name: dto.name.trim() } });
      return { existing: true, customer: (await this.lookup(phone)).customer! };
    }
    if (email && (await this.prisma.customer.findUnique({ where: { email } }))) {
      throw new ConflictException('Ese email ya es de otro cliente');
    }
    const created = await this.prisma.customer.create({ data: { name: dto.name.trim(), phone, email } });
    await this.audit.log(actor, 'customer.create', 'customer', created.id);
    return { existing: false, customer: { ...this.summary(created), ...this.emptyStats() } };
  }

  /** Liga (o quita) el cliente de una cuenta: sus pedidos pasan a su historial. */
  async attach(actor: EmployeeActor, billId: string, customerId: string | null) {
    const bill = await this.prisma.bill.findUnique({ where: { id: billId }, select: { id: true, status: true } });
    if (!bill) throw new NotFoundException('Cuenta no encontrada');
    if (bill.status === 'VOID') throw new ConflictException('La cuenta está anulada');
    if (customerId && !(await this.prisma.customer.findUnique({ where: { id: customerId }, select: { id: true } }))) {
      throw new NotFoundException('Cliente no encontrado');
    }
    await this.prisma.$transaction([
      this.prisma.bill.update({ where: { id: billId }, data: { customerId } }),
      // Los pedidos web siguen con su cuenta de cliente; los demás toman el de la cuenta.
      this.prisma.order.updateMany({ where: { billId, channel: { not: 'ONLINE' } }, data: { customerId } }),
    ]);
    await this.audit.log(actor, customerId ? 'bill.customer_attach' : 'bill.customer_detach', 'bill', billId, customerId ? { customerId } : undefined);
    return this.billing.afterChange(actor, billId);
  }

  /** Liga (o quita) el cliente de la visita en curso de una mesa: sus cuentas y lo que pida después. */
  async attachToTable(actor: EmployeeActor, tableId: string, customerId: string | null) {
    const session = await this.prisma.tableSession.findFirst({
      where: { tableId, status: { in: ['OPEN', 'BILL_REQUESTED'] } },
      orderBy: { openedAt: 'desc' },
      include: { bills: { where: { status: { not: 'VOID' } }, select: { id: true } } },
    });
    if (!session || !session.bills.length) throw new BadRequestException('La mesa todavía no tiene cuenta: toma el primer pedido');
    for (const b of session.bills) await this.attach(actor, b.id, customerId);
    return { customer: customerId ? (await this.prisma.customer.findUnique({ where: { id: customerId }, select: { id: true, name: true } })) : null };
  }

  // ───────── Ayudantes ─────────

  private whereFor(q?: string, filter?: CustomersQueryDto['filter']): Prisma.CustomerWhereInput {
    const text = q?.trim();
    const digits = text?.replace(/\D/g, '') ?? '';
    return {
      name: { not: '' },
      ...(filter === 'optIn' ? { marketingOptIn: true } : {}),
      ...(filter === 'account' ? { lastLoginAt: { not: null } } : {}),
      ...(filter === 'noVisits' ? { bills: { none: COUNTED_BILL } } : {}),
      ...(text
        ? {
            OR: [
              { name: { contains: text, mode: 'insensitive' } },
              { email: { contains: text, mode: 'insensitive' } },
              ...(digits.length >= 3 ? [{ phone: { contains: digits } }] : []),
            ],
          }
        : {}),
    };
  }

  private summary(c: Customer) {
    return {
      id: c.id,
      name: c.name,
      phone: c.phone,
      email: c.email,
      marketingOptIn: c.marketingOptIn,
      hasAccount: !!c.lastLoginAt,
      createdAt: c.createdAt,
    };
  }

  private emptyStats() {
    return { visits: 0, spent: new Prisma.Decimal(0), lastVisitAt: null as Date | null };
  }

  private async statsFor(ids: string[]) {
    const map = new Map<string, { visits: number; spent: Prisma.Decimal; lastVisitAt: Date | null }>();
    if (!ids.length) return map;
    const rows = await this.prisma.bill.groupBy({
      by: ['customerId'],
      where: { ...COUNTED_BILL, customerId: { in: ids } },
      _count: { _all: true },
      _sum: { amountPaid: true },
      _max: { createdAt: true },
    });
    for (const r of rows) {
      if (!r.customerId) continue;
      map.set(r.customerId, { visits: r._count._all, spent: r._sum.amountPaid ?? new Prisma.Decimal(0), lastVisitAt: r._max.createdAt });
    }
    return map;
  }

  private historyEntry(b: HistoryBill) {
    const real = b.orders.filter((o) => o.status !== 'PENDING_PAYMENT');
    const online = real.find((o) => o.channel === 'ONLINE');
    const types = real.map((o) => o.fulfillmentType);
    const kind = b.tableSessionId ? 'TABLE' : types.includes('DELIVERY') ? 'DELIVERY' : types.includes('PICKUP') ? 'PICKUP' : 'COUNTER';
    const cancelled = real.length > 0 && real.every((o) => o.status === 'CANCELLED');
    return {
      id: b.id,
      date: b.createdAt,
      kind,
      table: b.tableSession?.table.label ?? null,
      orderNumbers: real.filter((o) => o.status !== 'CANCELLED').map((o) => o.number),
      status: cancelled ? 'CANCELLED' : b.status,
      trackingCode: online?.publicCode ?? null,
      total: b.total,
      items: b.items.map((i) => ({
        productId: i.productId,
        name: i.nameSnapshot,
        quantity: i.quantity,
        lineTotal: i.lineTotal,
        notes: i.notes,
        options: i.modifiers.map((m) => ({ id: m.modifierOptionId, name: m.optionNameSnapshot })),
      })),
      receiptUrl: b.payments.length ? `${this.env.webUrl}/recibo/${signReceipt(b.id, this.env.jwtAccessSecret)}` : null,
    };
  }

  private cleanAddress(dto: AddressDto) {
    return {
      label: dto.label?.trim() || null,
      street: dto.street.trim(),
      city: dto.city.trim(),
      state: dto.state.trim().toUpperCase(),
      zipCode: dto.zipCode.trim(),
      instructions: dto.instructions?.trim() || null,
    };
  }

  private async ownAddress(customer: Customer, id: string) {
    const address = await this.prisma.customerAddress.findUnique({ where: { id } });
    if (!address || address.customerId !== customer.id) throw new NotFoundException('Dirección no encontrada');
    return address;
  }
}
