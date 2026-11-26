import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';
import { SettingsService } from '../settings/settings.service';
import { CountDto, InventorySettingsDto, ItemDto, MovementsQueryDto, ReceiptDto, RecipeDto, SupplierDto, WasteDto } from './dto/inventory.dto';
import { canMake, plateCost, weightedCost } from './inventory.rules';

const dec = (v: Prisma.Decimal.Value) => new Prisma.Decimal(v);
const ZERO = dec(0);
/** Órdenes que todavía no van a cocina o se cancelaron: no gastan ingredientes. */
const NOT_COUNTED = ['PENDING_PAYMENT', 'PENDING_APPROVAL', 'CANCELLED'];

/**
 * Inventario por ingredientes: cada venta descuenta su receta cuando la orden entra a cocina y
 * lo devuelve si se anula. Entradas de mercancía (con costo promedio), conteos físicos, mermas,
 * proveedores, costo y margen por plato, y agotar/reactivar platos según la existencia.
 */
@Injectable()
export class InventoryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger('Inventario');
  private unsubscribe?: () => void;
  private readonly queue = new Map<string, Promise<void>>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly events: DomainEventsService,
    private readonly settings: SettingsService,
    private readonly audit: AuditService,
  ) {}

  onModuleInit() {
    this.unsubscribe = this.events.subscribe((e) => {
      if (e.name !== 'order.created' && e.name !== 'order.updated') return;
      const orderId = (e.payload as { id?: string }).id;
      if (orderId) void this.enqueue(orderId);
    });
  }

  onModuleDestroy() {
    this.unsubscribe?.();
  }

  enqueue(orderId: string): Promise<void> {
    const previous = this.queue.get(orderId) ?? Promise.resolve();
    const next = previous
      .then(() => this.syncOrder(orderId))
      .catch((e) => this.logger.error(`No se pudo descontar el inventario de la orden ${orderId}: ${String(e)}`))
      .finally(() => {
        if (this.queue.get(orderId) === next) this.queue.delete(orderId);
      });
    this.queue.set(orderId, next);
    return next;
  }

  /** Deja los movimientos de venta de la orden como deben ser. */
  async syncOrder(orderId: string) {
    const s = await this.settings.get();
    if (!s.inventoryEnabled) return;
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      select: { status: true, number: true, items: { select: { id: true, productId: true, quantity: true, status: true } } },
    });
    if (!order) return;
    const counted = !NOT_COUNTED.includes(order.status);
    const touched = new Set<string>();
    for (const item of order.items) {
      const moves = await this.prisma.stockMovement.findMany({ where: { orderItemId: item.id, type: 'SALE' } });
      if (counted && item.status === 'ACTIVE') {
        if (moves.length || !item.productId) continue; // ya se descontó (con la receta de ese momento)
        const recipe = await this.prisma.recipeLine.findMany({
          where: { productId: item.productId },
          include: { item: { select: { costPerUnit: true } } },
        });
        for (const line of recipe) {
          const qty = line.quantity.times(item.quantity);
          await this.prisma.$transaction([
            this.prisma.stockMovement.create({
              data: {
                itemId: line.itemId,
                type: 'SALE',
                quantity: qty.negated(),
                unitCost: line.item.costPerUnit,
                orderItemId: item.id,
                reason: `Orden #${order.number}`,
              },
            }),
            this.prisma.inventoryItem.update({ where: { id: line.itemId }, data: { onHand: { decrement: qty } } }),
          ]);
          touched.add(line.itemId);
        }
      } else {
        // Anulado o cancelado: se devuelve lo que se había descontado.
        const byItem = new Map<string, Prisma.Decimal>();
        for (const m of moves) byItem.set(m.itemId, (byItem.get(m.itemId) ?? ZERO).plus(m.quantity));
        for (const [itemId, net] of byItem) {
          if (net.isZero()) continue;
          await this.prisma.$transaction([
            this.prisma.stockMovement.create({
              data: { itemId, type: 'SALE', quantity: net.negated(), orderItemId: item.id, reason: `Devolución · orden #${order.number}` },
            }),
            this.prisma.inventoryItem.update({ where: { id: itemId }, data: { onHand: { increment: net.negated() } } }),
          ]);
          touched.add(itemId);
        }
      }
    }
    if (touched.size) await this.refreshAvailability([...touched]);
  }

  /** Agota los platos que ya no se pueden hacer y reactiva los que el inventario había agotado. */
  async refreshAvailability(itemIds: string[]) {
    const s = await this.settings.get();
    if (!s.inventoryEnabled || !s.inventoryAutoSoldOut || !itemIds.length) return;
    const products = await this.prisma.product.findMany({
      where: { recipe: { some: { itemId: { in: itemIds } } } },
      include: { recipe: { include: { item: { select: { onHand: true, isActive: true } } } } },
    });
    for (const p of products) {
      const possible = canMake(p.recipe.filter((l) => l.item.isActive).map((l) => ({ quantity: l.quantity, onHand: l.item.onHand })));
      let change: { isAvailable: boolean; soldOutByStock: boolean } | null = null;
      if (!possible && p.isAvailable) change = { isAvailable: false, soldOutByStock: true };
      else if (possible && !p.isAvailable && p.soldOutByStock) change = { isAvailable: true, soldOutByStock: false };
      if (!change) continue;
      const updated = await this.prisma.product.update({ where: { id: p.id }, data: change });
      this.events.emit('product.availability', { id: updated.id, isAvailable: updated.isAvailable, updatedAt: updated.updatedAt });
      this.logger.log(`${updated.name}: ${updated.isAvailable ? 'disponible otra vez' : 'agotado por inventario'}`);
    }
  }

  // ───────── Resumen y ajustes ─────────

  async summary() {
    const s = await this.settings.get();
    const items = await this.prisma.inventoryItem.findMany({ where: { isActive: true } });
    const value = items.reduce((sum, i) => sum.plus(i.onHand.gt(0) ? i.onHand.times(i.costPerUnit) : 0), ZERO);
    const low = items.filter((i) => i.minLevel !== null && i.onHand.lte(i.minLevel)).length;
    const since = new Date(Date.now() - 7 * 86_400_000);
    const moves = await this.prisma.stockMovement.findMany({
      where: { createdAt: { gte: since }, type: { in: ['SALE', 'WASTE'] } },
      include: { item: { select: { costPerUnit: true } } },
    });
    const costOf = (type: string) =>
      moves.filter((m) => m.type === type).reduce((sum, m) => sum.plus(m.quantity.negated().times(m.unitCost ?? m.item.costPerUnit)), ZERO);
    const soldOut = await this.prisma.product.count({ where: { soldOutByStock: true, isAvailable: false } });
    return {
      enabled: s.inventoryEnabled,
      autoSoldOut: s.inventoryAutoSoldOut,
      items: items.length,
      low,
      value: value.toDecimalPlaces(2),
      usedLast7Days: costOf('SALE').toDecimalPlaces(2),
      wasteLast7Days: costOf('WASTE').toDecimalPlaces(2),
      soldOutByStock: soldOut,
    };
  }

  async updateSettings(actor: EmployeeActor, dto: InventorySettingsDto) {
    await this.settings.update(actor, {
      ...(dto.enabled !== undefined ? { inventoryEnabled: dto.enabled } : {}),
      ...(dto.autoSoldOut !== undefined ? { inventoryAutoSoldOut: dto.autoSoldOut } : {}),
    });
    if (dto.enabled || dto.autoSoldOut) {
      const all = await this.prisma.inventoryItem.findMany({ select: { id: true } });
      await this.refreshAvailability(all.map((i) => i.id));
    }
    return this.summary();
  }

  // ───────── Ingredientes ─────────

  async items() {
    const items = await this.prisma.inventoryItem.findMany({
      include: { supplier: { select: { id: true, name: true } }, _count: { select: { recipeLines: true } } },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
    });
    return items.map((i) => this.itemView(i));
  }

  async createItem(actor: EmployeeActor, dto: ItemDto) {
    const item = await this.prisma.inventoryItem.create({
      data: {
        name: dto.name.trim(),
        unit: dto.unit,
        minLevel: dto.minLevel ?? null,
        costPerUnit: dto.costPerUnit ?? 0,
        supplierId: dto.supplierId ?? null,
        sku: dto.sku?.trim() || null,
        isActive: dto.isActive ?? true,
        onHand: dto.onHand ?? 0,
      },
    });
    if (dto.onHand && dto.onHand > 0) {
      await this.prisma.stockMovement.create({
        data: { itemId: item.id, type: 'COUNT', quantity: dto.onHand, unitCost: item.costPerUnit, reason: 'Existencia inicial', employeeId: actor.id },
      });
    }
    await this.audit.log(actor, 'inventory.item_create', 'inventory_item', item.id, { name: item.name });
    return this.item(item.id);
  }

  async updateItem(actor: EmployeeActor, id: string, dto: ItemDto) {
    await this.mustItem(id);
    await this.prisma.inventoryItem.update({
      where: { id },
      data: {
        name: dto.name.trim(),
        unit: dto.unit,
        minLevel: dto.minLevel ?? null,
        ...(dto.costPerUnit !== undefined ? { costPerUnit: dto.costPerUnit } : {}),
        supplierId: dto.supplierId ?? null,
        sku: dto.sku?.trim() || null,
        ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
      },
    });
    await this.audit.log(actor, 'inventory.item_update', 'inventory_item', id);
    await this.refreshAvailability([id]);
    return this.item(id);
  }

  /** Solo si nunca tuvo movimientos; si no, se desactiva. */
  async removeItem(actor: EmployeeActor, id: string) {
    await this.mustItem(id);
    if (await this.prisma.stockMovement.count({ where: { itemId: id } })) {
      throw new ConflictException('Este ingrediente ya tiene movimientos: desactívalo en vez de borrarlo');
    }
    await this.prisma.inventoryItem.delete({ where: { id } });
    await this.audit.log(actor, 'inventory.item_delete', 'inventory_item', id);
  }

  /** Conteo físico: la existencia pasa a ser lo contado (se guarda la diferencia). */
  async count(actor: EmployeeActor, id: string, dto: CountDto) {
    const item = await this.mustItem(id);
    const delta = dec(dto.onHand).minus(item.onHand);
    if (!delta.isZero()) {
      await this.prisma.$transaction([
        this.prisma.stockMovement.create({
          data: { itemId: id, type: 'COUNT', quantity: delta, unitCost: item.costPerUnit, reason: dto.reason?.trim() || 'Conteo físico', employeeId: actor.id },
        }),
        this.prisma.inventoryItem.update({ where: { id }, data: { onHand: dto.onHand } }),
      ]);
    }
    await this.audit.log(actor, 'inventory.count', 'inventory_item', id, { onHand: dto.onHand, delta: delta.toString() });
    await this.refreshAvailability([id]);
    return this.item(id);
  }

  async waste(actor: EmployeeActor, id: string, dto: WasteDto) {
    const item = await this.mustItem(id);
    await this.prisma.$transaction([
      this.prisma.stockMovement.create({
        data: { itemId: id, type: 'WASTE', quantity: -dto.quantity, unitCost: item.costPerUnit, reason: dto.reason.trim(), employeeId: actor.id },
      }),
      this.prisma.inventoryItem.update({ where: { id }, data: { onHand: { decrement: dto.quantity } } }),
    ]);
    await this.audit.log(actor, 'inventory.waste', 'inventory_item', id, { quantity: dto.quantity, reason: dto.reason });
    await this.refreshAvailability([id]);
    return this.item(id);
  }

  async movements(q: MovementsQueryDto) {
    const moves = await this.prisma.stockMovement.findMany({
      where: { ...(q.itemId ? { itemId: q.itemId } : {}), ...(q.type ? { type: q.type } : {}) },
      include: { item: { select: { name: true, unit: true, costPerUnit: true } } },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    const ids = [...new Set(moves.map((m) => m.employeeId).filter((x): x is string => !!x))];
    const people = ids.length ? await this.prisma.employee.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } }) : [];
    const names = new Map(people.map((p) => [p.id, p.name]));
    return moves.map((m) => ({
      id: m.id,
      itemId: m.itemId,
      item: m.item.name,
      unit: m.item.unit,
      type: m.type,
      quantity: m.quantity,
      cost: m.quantity.abs().times(m.unitCost ?? m.item.costPerUnit).toDecimalPlaces(2),
      reason: m.reason,
      employee: m.employeeId ? (names.get(m.employeeId) ?? null) : null,
      createdAt: m.createdAt,
    }));
  }

  // ───────── Entradas de mercancía ─────────

  async receipts() {
    const list = await this.prisma.stockReceipt.findMany({
      include: { supplier: { select: { name: true } }, movements: { include: { item: { select: { name: true, unit: true } } } } },
      orderBy: { receivedAt: 'desc' },
      take: 100,
    });
    return list.map((r) => ({
      id: r.id,
      supplier: r.supplier?.name ?? null,
      reference: r.reference,
      notes: r.notes,
      total: r.total,
      receivedAt: r.receivedAt,
      lines: r.movements.map((m) => ({ itemId: m.itemId, item: m.item.name, unit: m.item.unit, quantity: m.quantity, unitCost: m.unitCost })),
    }));
  }

  /** Registra una compra: sube la existencia y actualiza el costo promedio de cada ingrediente. */
  async receive(actor: EmployeeActor, dto: ReceiptDto) {
    const ids = [...new Set(dto.lines.map((l) => l.itemId))];
    const items = await this.prisma.inventoryItem.findMany({ where: { id: { in: ids } } });
    if (items.length !== ids.length) throw new BadRequestException('Algún ingrediente no existe');
    if (dto.supplierId && !(await this.prisma.supplier.findUnique({ where: { id: dto.supplierId } }))) {
      throw new BadRequestException('Proveedor no encontrado');
    }
    const total = dto.lines.reduce((s, l) => s.plus(dec(l.quantity).times(l.unitCost)), ZERO).toDecimalPlaces(2);
    const receipt = await this.prisma.$transaction(async (tx) => {
      const r = await tx.stockReceipt.create({
        data: { supplierId: dto.supplierId ?? null, reference: dto.reference?.trim() || null, notes: dto.notes?.trim() || null, total, employeeId: actor.id },
      });
      for (const line of dto.lines) {
        const item = await tx.inventoryItem.findUniqueOrThrow({ where: { id: line.itemId } });
        await tx.stockMovement.create({
          data: { itemId: line.itemId, type: 'RECEIPT', quantity: line.quantity, unitCost: line.unitCost, receiptId: r.id, employeeId: actor.id },
        });
        await tx.inventoryItem.update({
          where: { id: line.itemId },
          data: {
            onHand: { increment: line.quantity },
            costPerUnit: weightedCost(item.onHand, item.costPerUnit, line.quantity, line.unitCost),
            ...(dto.supplierId && !item.supplierId ? { supplierId: dto.supplierId } : {}),
          },
        });
      }
      return r;
    });
    await this.audit.log(actor, 'inventory.receipt', 'stock_receipt', receipt.id, { lines: dto.lines.length, total: total.toString() });
    await this.refreshAvailability(ids);
    return (await this.receipts()).find((r) => r.id === receipt.id);
  }

  // ───────── Proveedores ─────────

  async suppliers() {
    const list = await this.prisma.supplier.findMany({
      include: { _count: { select: { items: true, receipts: true } } },
      orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
    });
    return list.map((s) => ({
      id: s.id,
      name: s.name,
      contactName: s.contactName,
      phone: s.phone,
      email: s.email,
      notes: s.notes,
      isActive: s.isActive,
      items: s._count.items,
      receipts: s._count.receipts,
    }));
  }

  async saveSupplier(actor: EmployeeActor, id: string | null, dto: SupplierDto) {
    const data = {
      name: dto.name.trim(),
      contactName: dto.contactName?.trim() || null,
      phone: dto.phone?.trim() || null,
      email: dto.email?.trim() || null,
      notes: dto.notes?.trim() || null,
      isActive: dto.isActive ?? true,
    };
    const supplier = id
      ? await this.prisma.supplier.update({ where: { id }, data }).catch(() => {
          throw new NotFoundException('Proveedor no encontrado');
        })
      : await this.prisma.supplier.create({ data });
    await this.audit.log(actor, id ? 'supplier.update' : 'supplier.create', 'supplier', supplier.id);
    return (await this.suppliers()).find((s) => s.id === supplier.id);
  }

  async removeSupplier(actor: EmployeeActor, id: string) {
    const s = await this.prisma.supplier.findUnique({ where: { id }, include: { _count: { select: { receipts: true } } } });
    if (!s) throw new NotFoundException('Proveedor no encontrado');
    if (s._count.receipts) throw new ConflictException('Este proveedor tiene compras registradas: desactívalo en vez de borrarlo');
    await this.prisma.supplier.delete({ where: { id } });
    await this.audit.log(actor, 'supplier.delete', 'supplier', id);
  }

  // ───────── Recetas, costo y margen ─────────

  async recipes() {
    const products = await this.prisma.product.findMany({
      where: { isActive: true },
      include: {
        category: { select: { name: true, sortOrder: true } },
        recipe: { include: { item: { select: { id: true, name: true, unit: true, costPerUnit: true, onHand: true } } } },
      },
      orderBy: [{ category: { sortOrder: 'asc' } }, { sortOrder: 'asc' }],
    });
    return products.map((p) => {
      const lines = p.recipe.map((l) => ({
        itemId: l.itemId,
        item: l.item.name,
        unit: l.item.unit,
        quantity: l.quantity,
        cost: l.quantity.times(l.item.costPerUnit).toDecimalPlaces(2),
      }));
      const totals = plateCost(p.price, p.recipe.map((l) => ({ quantity: l.quantity, costPerUnit: l.item.costPerUnit })));
      return {
        productId: p.id,
        name: p.name,
        category: p.category.name,
        price: p.price,
        isAvailable: p.isAvailable,
        soldOutByStock: p.soldOutByStock,
        lines,
        ...totals,
      };
    });
  }

  async saveRecipe(actor: EmployeeActor, productId: string, dto: RecipeDto) {
    const product = await this.prisma.product.findUnique({ where: { id: productId } });
    if (!product) throw new NotFoundException('Producto no encontrado');
    const ids = dto.lines.map((l) => l.itemId);
    if (new Set(ids).size !== ids.length) throw new BadRequestException('Un ingrediente aparece dos veces');
    if (ids.length && (await this.prisma.inventoryItem.count({ where: { id: { in: ids } } })) !== ids.length) {
      throw new BadRequestException('Algún ingrediente no existe');
    }
    const before = await this.prisma.recipeLine.findMany({ where: { productId }, select: { itemId: true } });
    await this.prisma.$transaction([
      this.prisma.recipeLine.deleteMany({ where: { productId } }),
      ...dto.lines.map((l) => this.prisma.recipeLine.create({ data: { productId, itemId: l.itemId, quantity: l.quantity } })),
    ]);
    await this.audit.log(actor, 'inventory.recipe', 'product', productId, { lines: dto.lines.length });
    // Si la receta ya no deja hacerlo (o ahora sí), se agota o reactiva.
    await this.refreshAvailability([...new Set([...ids, ...before.map((b) => b.itemId)])]);
    if (!dto.lines.length && product.soldOutByStock) {
      const updated = await this.prisma.product.update({ where: { id: productId }, data: { isAvailable: true, soldOutByStock: false } });
      this.events.emit('product.availability', { id: updated.id, isAvailable: true, updatedAt: updated.updatedAt });
    }
    return (await this.recipes()).find((r) => r.productId === productId);
  }

  // ───────── Ayudantes ─────────

  private async mustItem(id: string) {
    const item = await this.prisma.inventoryItem.findUnique({ where: { id } });
    if (!item) throw new NotFoundException('Ingrediente no encontrado');
    return item;
  }

  private async item(id: string) {
    const i = await this.prisma.inventoryItem.findUniqueOrThrow({
      where: { id },
      include: { supplier: { select: { id: true, name: true } }, _count: { select: { recipeLines: true } } },
    });
    return this.itemView(i);
  }

  private itemView(i: Prisma.InventoryItemGetPayload<{ include: { supplier: { select: { id: true; name: true } }; _count: { select: { recipeLines: true } } } }>) {
    return {
      id: i.id,
      name: i.name,
      unit: i.unit,
      onHand: i.onHand,
      minLevel: i.minLevel,
      low: i.minLevel !== null && i.onHand.lte(i.minLevel),
      costPerUnit: i.costPerUnit,
      value: (i.onHand.gt(0) ? i.onHand.times(i.costPerUnit) : ZERO).toDecimalPlaces(2),
      supplier: i.supplier,
      sku: i.sku,
      isActive: i.isActive,
      usedIn: i._count.recipeLines,
    };
  }
}
