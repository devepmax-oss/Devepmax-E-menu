import { ConflictException, Injectable } from '@nestjs/common';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateTaxRateDto, UpdateTaxRateDto } from './dto/menu.dto';
import { found } from './menu.helpers';

@Injectable()
export class TaxRatesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  list() {
    return this.prisma.taxRate.findMany({ orderBy: [{ isDefault: 'desc' }, { name: 'asc' }] });
  }

  async create(actor: EmployeeActor, dto: CreateTaxRateDto) {
    const isFirst = (await this.prisma.taxRate.count()) === 0;
    const isDefault = dto.isDefault ?? isFirst;
    const taxRate = await this.prisma.$transaction(async (tx) => {
      if (isDefault) await tx.taxRate.updateMany({ data: { isDefault: false } });
      return tx.taxRate.create({ data: { name: dto.name.trim(), rate: dto.rate, isDefault } });
    });
    await this.audit.log(actor, 'tax_rate.create', 'tax_rate', taxRate.id, {
      name: taxRate.name,
      rate: dto.rate,
    });
    return taxRate;
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateTaxRateDto) {
    const current = found(await this.prisma.taxRate.findUnique({ where: { id } }), 'Impuesto no encontrado');
    if (dto.isDefault === false && current.isDefault) {
      throw new ConflictException('Marca otro impuesto como predeterminado en lugar de quitar este');
    }
    const taxRate = await this.prisma.$transaction(async (tx) => {
      if (dto.isDefault) await tx.taxRate.updateMany({ where: { id: { not: id } }, data: { isDefault: false } });
      return tx.taxRate.update({ where: { id }, data: { ...dto, name: dto.name?.trim() } });
    });
    await this.audit.log(actor, 'tax_rate.update', 'tax_rate', id, {
      fields: Object.keys(dto),
      rate: dto.rate,
    });
    return taxRate;
  }

  async remove(actor: EmployeeActor, id: string) {
    const taxRate = found(
      await this.prisma.taxRate.findUnique({ where: { id }, include: { _count: { select: { products: true } } } }),
      'Impuesto no encontrado',
    );
    if (taxRate.isDefault) throw new ConflictException('No se puede borrar el impuesto predeterminado');
    if (taxRate._count.products > 0) {
      throw new ConflictException('Hay productos que usan este impuesto');
    }
    await this.prisma.taxRate.delete({ where: { id } });
    await this.audit.log(actor, 'tax_rate.delete', 'tax_rate', id, { name: taxRate.name });
  }
}
