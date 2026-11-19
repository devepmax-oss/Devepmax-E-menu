import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { ImageService } from '../../storage/image.service';
import { AuditService } from '../audit/audit.service';
import { CreateCategoryDto, UpdateCategoryDto } from './dto/menu.dto';
import { found, TRANSLATION_FIELDS, translationsInput } from './menu.helpers';

type UploadedImage = { buffer: Buffer; mimetype: string; size: number };

@Injectable()
export class CategoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly images: ImageService,
  ) {}

  async create(actor: EmployeeActor, dto: CreateCategoryDto) {
    const last = await this.prisma.category.aggregate({ _max: { sortOrder: true } });
    const category = await this.prisma.category.create({
      data: {
        ...dto,
        name: dto.name.trim(),
        translations: translationsInput(dto.translations, TRANSLATION_FIELDS.category),
        sortOrder: (last._max.sortOrder ?? -1) + 1,
      },
    });
    await this.audit.log(actor, 'category.create', 'category', category.id, { name: category.name });
    return category;
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateCategoryDto) {
    found(await this.prisma.category.findUnique({ where: { id } }), 'Categoría no encontrada');
    const category = await this.prisma.category.update({
      where: { id },
      data: {
        ...dto,
        name: dto.name?.trim(),
        translations: translationsInput(dto.translations, TRANSLATION_FIELDS.category),
      },
    });
    await this.audit.log(actor, 'category.update', 'category', id, { fields: Object.keys(dto) });
    return category;
  }

  async remove(actor: EmployeeActor, id: string) {
    const category = found(
      await this.prisma.category.findUnique({ where: { id }, include: { _count: { select: { products: true } } } }),
      'Categoría no encontrada',
    );
    if (category._count.products > 0) {
      throw new ConflictException('La categoría tiene productos. Muévelos o desactívala.');
    }
    await this.prisma.category.delete({ where: { id } });
    await this.images.remove(category.imageUrl);
    await this.audit.log(actor, 'category.delete', 'category', id, { name: category.name });
  }

  async reorder(actor: EmployeeActor, ids: string[]) {
    const count = await this.prisma.category.count({ where: { id: { in: ids } } });
    if (count !== ids.length) throw new BadRequestException('Alguna categoría no existe');
    await this.prisma.$transaction(
      ids.map((id, index) => this.prisma.category.update({ where: { id }, data: { sortOrder: index } })),
    );
    await this.audit.log(actor, 'category.reorder', 'category', '*', { count: ids.length });
  }

  async setImage(actor: EmployeeActor, id: string, file: UploadedImage) {
    const current = found(await this.prisma.category.findUnique({ where: { id } }), 'Categoría no encontrada');
    const imageUrl = await this.images.save(`categories/${id}`, file);
    const category = await this.prisma.category.update({ where: { id }, data: { imageUrl } });
    await this.images.remove(current.imageUrl);
    await this.audit.log(actor, 'category.image', 'category', id);
    return category;
  }

  async removeImage(actor: EmployeeActor, id: string) {
    const current = found(await this.prisma.category.findUnique({ where: { id } }), 'Categoría no encontrada');
    const category = await this.prisma.category.update({ where: { id }, data: { imageUrl: null } });
    await this.images.remove(current.imageUrl);
    await this.audit.log(actor, 'category.image_removed', 'category', id);
    return category;
  }
}
