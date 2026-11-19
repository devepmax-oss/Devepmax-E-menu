import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Actor, EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { ImageService } from '../../storage/image.service';
import { AuditService } from '../audit/audit.service';
import { CreateProductDto, UpdateProductDto } from './dto/menu.dto';
import { found, TRANSLATION_FIELDS, translationsInput } from './menu.helpers';

type UploadedImage = { buffer: Buffer; mimetype: string; size: number };

export const PRODUCT_ADMIN_INCLUDE = {
  modifierGroups: {
    orderBy: { sortOrder: 'asc' },
    include: { modifierGroup: { include: { options: { orderBy: { sortOrder: 'asc' } } } } },
  },
} satisfies Prisma.ProductInclude;

@Injectable()
export class ProductsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly images: ImageService,
  ) {}

  async get(id: string) {
    return found(
      await this.prisma.product.findUnique({ where: { id }, include: PRODUCT_ADMIN_INCLUDE }),
      'Producto no encontrado',
    );
  }

  async create(actor: EmployeeActor, dto: CreateProductDto) {
    await this.assertReferences(dto);
    const { modifierGroupIds, translations, ...fields } = dto;
    const last = await this.prisma.product.aggregate({
      where: { categoryId: dto.categoryId },
      _max: { sortOrder: true },
    });

    const product = await this.prisma.product.create({
      data: {
        ...fields,
        name: dto.name.trim(),
        description: dto.description?.trim(),
        translations: translationsInput(translations, TRANSLATION_FIELDS.product),
        sortOrder: (last._max.sortOrder ?? -1) + 1,
        modifierGroups: modifierGroupIds?.length
          ? { create: modifierGroupIds.map((modifierGroupId, sortOrder) => ({ modifierGroupId, sortOrder })) }
          : undefined,
      },
      include: PRODUCT_ADMIN_INCLUDE,
    });
    await this.audit.log(actor, 'product.create', 'product', product.id, {
      name: product.name,
      price: dto.price,
    });
    return product;
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateProductDto) {
    const current = found(await this.prisma.product.findUnique({ where: { id } }), 'Producto no encontrado');
    await this.assertReferences(dto);
    const { modifierGroupIds, translations, ...fields } = dto;

    const product = await this.prisma.$transaction(async (tx) => {
      if (modifierGroupIds) {
        await tx.productModifierGroup.deleteMany({ where: { productId: id } });
        if (modifierGroupIds.length) {
          await tx.productModifierGroup.createMany({
            data: modifierGroupIds.map((modifierGroupId, sortOrder) => ({ productId: id, modifierGroupId, sortOrder })),
          });
        }
      }
      return tx.product.update({
        where: { id },
        data: {
          ...fields,
          name: dto.name?.trim(),
          description: dto.description === null ? null : dto.description?.trim(),
          translations: translationsInput(translations, TRANSLATION_FIELDS.product),
        },
        include: PRODUCT_ADMIN_INCLUDE,
      });
    });

    const priceChanged = dto.price !== undefined && !current.price.equals(dto.price);
    await this.audit.log(actor, priceChanged ? 'product.price_change' : 'product.update', 'product', id, {
      fields: Object.keys(dto),
      ...(priceChanged ? { from: current.price.toString(), to: dto.price } : {}),
    });
    return product;
  }

  /** Borra el producto. Las órdenes pasadas conservan nombre y precio (snapshot). */
  async remove(actor: EmployeeActor, id: string) {
    const product = found(await this.prisma.product.findUnique({ where: { id } }), 'Producto no encontrado');
    await this.prisma.product.delete({ where: { id } });
    await this.images.remove(product.imageUrl);
    await this.audit.log(actor, 'product.delete', 'product', id, { name: product.name });
  }

  /** "Agotado" del día. Lo pueden usar meseros, cajeros, cocina y pantallas KDS. */
  async setAvailability(actor: Actor, id: string, isAvailable: boolean) {
    found(await this.prisma.product.findUnique({ where: { id } }), 'Producto no encontrado');
    const product = await this.prisma.product.update({ where: { id }, data: { isAvailable } });
    await this.audit.log(actor, isAvailable ? 'product.available' : 'product.sold_out', 'product', id);
    return { id: product.id, isAvailable: product.isAvailable };
  }

  async reorder(actor: EmployeeActor, categoryId: string, ids: string[]) {
    const count = await this.prisma.product.count({ where: { id: { in: ids }, categoryId } });
    if (count !== ids.length) throw new BadRequestException('Algún producto no pertenece a la categoría');
    await this.prisma.$transaction(
      ids.map((id, index) => this.prisma.product.update({ where: { id }, data: { sortOrder: index } })),
    );
    await this.audit.log(actor, 'product.reorder', 'category', categoryId, { count: ids.length });
  }

  async setImage(actor: EmployeeActor, id: string, file: UploadedImage) {
    const current = found(await this.prisma.product.findUnique({ where: { id } }), 'Producto no encontrado');
    const imageUrl = await this.images.save(`products/${id}`, file);
    const product = await this.prisma.product.update({
      where: { id },
      data: { imageUrl },
      include: PRODUCT_ADMIN_INCLUDE,
    });
    await this.images.remove(current.imageUrl);
    await this.audit.log(actor, 'product.image', 'product', id);
    return product;
  }

  async removeImage(actor: EmployeeActor, id: string) {
    const current = found(await this.prisma.product.findUnique({ where: { id } }), 'Producto no encontrado');
    const product = await this.prisma.product.update({
      where: { id },
      data: { imageUrl: null },
      include: PRODUCT_ADMIN_INCLUDE,
    });
    await this.images.remove(current.imageUrl);
    await this.audit.log(actor, 'product.image_removed', 'product', id);
    return product;
  }

  private async assertReferences(dto: {
    categoryId?: string;
    stationId?: string | null;
    taxRateId?: string | null;
    modifierGroupIds?: string[];
  }): Promise<void> {
    if (dto.categoryId && !(await this.prisma.category.findUnique({ where: { id: dto.categoryId } }))) {
      throw new BadRequestException('Categoría no encontrada');
    }
    if (dto.stationId && !(await this.prisma.kitchenStation.findUnique({ where: { id: dto.stationId } }))) {
      throw new BadRequestException('Estación no encontrada');
    }
    if (dto.taxRateId && !(await this.prisma.taxRate.findUnique({ where: { id: dto.taxRateId } }))) {
      throw new BadRequestException('Impuesto no encontrado');
    }
    if (dto.modifierGroupIds?.length) {
      const count = await this.prisma.modifierGroup.count({ where: { id: { in: dto.modifierGroupIds } } });
      if (count !== dto.modifierGroupIds.length) throw new BadRequestException('Algún grupo de modificadores no existe');
    }
  }
}
