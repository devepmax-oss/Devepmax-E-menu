import { ConflictException, Injectable } from '@nestjs/common';
import { EmployeeActor } from '../../common/auth/actor';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import { CreateStationDto, UpdateStationDto } from './dto/menu.dto';
import { found } from './menu.helpers';

@Injectable()
export class StationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  list() {
    return this.prisma.kitchenStation.findMany({ orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] });
  }

  async create(actor: EmployeeActor, dto: CreateStationDto) {
    const station = await this.prisma.kitchenStation.create({ data: { ...dto, name: dto.name.trim() } });
    await this.audit.log(actor, 'station.create', 'station', station.id, { name: station.name });
    return station;
  }

  async update(actor: EmployeeActor, id: string, dto: UpdateStationDto) {
    found(await this.prisma.kitchenStation.findUnique({ where: { id } }), 'Estación no encontrada');
    const station = await this.prisma.kitchenStation.update({
      where: { id },
      data: { ...dto, name: dto.name?.trim() },
    });
    await this.audit.log(actor, 'station.update', 'station', id, { fields: Object.keys(dto) });
    return station;
  }

  /** Solo se borra si nada la usa; si no, hay que desactivarla. */
  async remove(actor: EmployeeActor, id: string) {
    const station = found(
      await this.prisma.kitchenStation.findUnique({
        where: { id },
        include: { _count: { select: { products: true, devices: true, tickets: true } } },
      }),
      'Estación no encontrada',
    );
    const { products, devices, tickets } = station._count;
    if (products + devices + tickets > 0) {
      throw new ConflictException('La estación tiene productos, pantallas u órdenes. Desactívala en lugar de borrarla.');
    }
    await this.prisma.kitchenStation.delete({ where: { id } });
    await this.audit.log(actor, 'station.delete', 'station', id, { name: station.name });
  }
}
