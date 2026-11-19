import { Injectable } from '@nestjs/common';
import { Actor, EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import {
  CreateModifierGroupDto,
  CreateModifierOptionDto,
  UpdateModifierGroupDto,
  UpdateModifierOptionDto,
} from './dto/menu.dto';
import { found, TRANSLATION_FIELDS, translationsInput } from './menu.helpers';
import { assertModifierGroupRules } from './menu.rules';

const GROUP_INCLUDE = {
  options: { orderBy: { sortOrder: 'asc' as const } },
  _count: { select: { products: true } },
};

function optionData(option: CreateModifierOptionDto | UpdateModifierOptionDto) {
  return {
    ...option,
    name: option.name?.trim(),
    translations: translationsInput(option.translations, TRANSLATION_FIELDS.modifierOption),
  };
}

@Injectable()
export class ModifiersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  list() {
    return this.prisma.modifierGroup.findMany({ include: GROUP_INCLUDE, orderBy: { name: 'asc' } });
  }

  async get(id: string) {
    return found(
      await this.prisma.modifierGroup.findUnique({ where: { id }, include: GROUP_INCLUDE }),
      'Grupo de modificadores no encontrado',
    );
  }

  async create(actor: EmployeeActor, dto: CreateModifierGroupDto) {
    const options = dto.options ?? [];
    assertModifierGroupRules(dto, options.filter((o) => o.isDefault).length);

    const group = await this.prisma.modifierGroup.create({
      data: {
        name: dto.name.trim(),
        translations: translationsInput(dto.translations, TRANSLATION_FIELDS.modifierGroup),
        selectionType: dto.selectionType,
        minSelect: dto.minSelect,
        maxSelect: dto.maxSelect,
        isActive: dto.isActive,
        options: {
          create: options.map((option, index) => {
            const data = optionData(option);
            return { ...data, name: data.name ?? option.name, sortOrder: option.sortOrder ?? index };
          }),
        },
      },
      include: GROUP_INCLUDE,
    });
    await this.audit.log(actor, 'modifier_group.create', 'modifier_group', group.id, { name: group.name });
    return group;
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateModifierGroupDto) {
    const current = await this.get(id);
    assertModifierGroupRules(
      {
        selectionType: dto.selectionType ?? current.selectionType,
        minSelect: dto.minSelect ?? current.minSelect,
        maxSelect: dto.maxSelect ?? current.maxSelect,
      },
      current.options.filter((o) => o.isDefault).length,
    );
    const group = await this.prisma.modifierGroup.update({
      where: { id },
      data: {
        ...dto,
        name: dto.name?.trim(),
        translations: translationsInput(dto.translations, TRANSLATION_FIELDS.modifierGroup),
      },
      include: GROUP_INCLUDE,
    });
    await this.audit.log(actor, 'modifier_group.update', 'modifier_group', id, { fields: Object.keys(dto) });
    return group;
  }

  /** Al borrar el grupo se quita de todos los productos que lo usan. */
  async remove(actor: EmployeeActor, id: string) {
    const group = await this.get(id);
    await this.prisma.modifierGroup.delete({ where: { id } });
    await this.audit.log(actor, 'modifier_group.delete', 'modifier_group', id, {
      name: group.name,
      products: group._count.products,
    });
  }

  async addOption(actor: EmployeeActor, groupId: string, dto: CreateModifierOptionDto) {
    const group = await this.get(groupId);
    assertModifierGroupRules(group, group.options.filter((o) => o.isDefault).length + (dto.isDefault ? 1 : 0));
    const data = optionData(dto);
    const option = await this.prisma.modifierOption.create({
      data: {
        ...data,
        name: dto.name.trim(),
        groupId,
        sortOrder: dto.sortOrder ?? group.options.length,
      },
    });
    await this.audit.log(actor, 'modifier_option.create', 'modifier_option', option.id, {
      groupId,
      name: option.name,
    });
    return option;
  }

  async updateOption(actor: EmployeeActor, id: string, dto: UpdateModifierOptionDto) {
    const option = found(
      await this.prisma.modifierOption.findUnique({ where: { id } }),
      'Opción no encontrada',
    );
    if (dto.isDefault === true && !option.isDefault) {
      const group = await this.get(option.groupId);
      assertModifierGroupRules(group, group.options.filter((o) => o.isDefault).length + 1);
    }
    const updated = await this.prisma.modifierOption.update({ where: { id }, data: optionData(dto) });
    await this.audit.log(actor, 'modifier_option.update', 'modifier_option', id, { fields: Object.keys(dto) });
    return updated;
  }

  async removeOption(actor: EmployeeActor, id: string) {
    const option = found(
      await this.prisma.modifierOption.findUnique({ where: { id } }),
      'Opción no encontrada',
    );
    await this.prisma.modifierOption.delete({ where: { id } });
    await this.audit.log(actor, 'modifier_option.delete', 'modifier_option', id, {
      groupId: option.groupId,
      name: option.name,
    });
  }

  async setOptionAvailability(actor: Actor, id: string, isAvailable: boolean) {
    found(await this.prisma.modifierOption.findUnique({ where: { id } }), 'Opción no encontrada');
    const option = await this.prisma.modifierOption.update({ where: { id }, data: { isAvailable } });
    await this.audit.log(
      actor,
      isAvailable ? 'modifier_option.available' : 'modifier_option.sold_out',
      'modifier_option',
      id,
    );
    return { id: option.id, isAvailable: option.isAvailable };
  }
}
