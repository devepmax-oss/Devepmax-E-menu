import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Device } from '@prisma/client';
import { EmployeeActor } from '../../common/auth/actor';
import { generatePairingCode } from '../../common/crypto';
import { isUniqueViolation } from '../../prisma/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { DomainEventsService } from '../../realtime/domain-events.service';
import { AuditService } from '../audit/audit.service';

const PAIRING_CODE_TTL_MS = 15 * 60_000;

export function toDeviceView(device: Device) {
  return {
    id: device.id,
    name: device.name,
    type: device.type,
    tableId: device.tableId,
    stationId: device.stationId,
    isActive: device.isActive,
    isPaired: !!device.tokenHash,
    pairingCode: device.pairingCode,
    pairingExpiresAt: device.pairingExpiresAt,
    appVersion: device.appVersion,
    lastSeenAt: device.lastSeenAt,
  };
}

@Injectable()
export class DevicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly events: DomainEventsService,
  ) {}

  async list() {
    const devices = await this.prisma.device.findMany({ orderBy: [{ type: 'asc' }, { name: 'asc' }] });
    return devices.map(toDeviceView);
  }

  async create(actor: EmployeeActor, dto: { name: string; type: Device['type']; tableId?: string; stationId?: string }) {
    await this.assertLinks(dto.tableId, dto.stationId);
    const device = await this.withUniquePairingCode((pairing) =>
      this.prisma.device.create({
        data: {
          name: dto.name.trim(),
          type: dto.type,
          tableId: dto.tableId,
          stationId: dto.stationId,
          ...pairing,
        },
      }),
    );
    await this.audit.log(actor, 'device.create', 'device', device.id, { name: device.name, type: device.type });
    return toDeviceView(device);
  }

  async update(
    actor: EmployeeActor,
    id: string,
    dto: { name?: string; tableId?: string | null; stationId?: string | null; isActive?: boolean },
  ) {
    await this.findOrFail(id);
    await this.assertLinks(dto.tableId ?? undefined, dto.stationId ?? undefined);
    const device = await this.prisma.device.update({
      where: { id },
      data: {
        name: dto.name?.trim(),
        tableId: dto.tableId,
        stationId: dto.stationId,
        isActive: dto.isActive,
        ...(dto.isActive === false ? { tokenHash: null, pairingCode: null, pairingExpiresAt: null } : {}),
      },
    });
    await this.audit.log(actor, 'device.update', 'device', id, { fields: Object.keys(dto) });
    // Mesa, estación o estado cambiaron: el dispositivo se reconecta con sus rooms nuevas.
    this.events.emit('device.changed', { deviceId: id });
    return toDeviceView(device);
  }

  /** Genera un código nuevo. El dispositivo actual queda desvinculado hasta usarlo. */
  async regeneratePairingCode(actor: EmployeeActor, id: string) {
    const current = await this.findOrFail(id);
    if (!current.isActive) throw new BadRequestException('El dispositivo está desactivado');
    const device = await this.withUniquePairingCode((pairing) =>
      this.prisma.device.update({ where: { id }, data: { tokenHash: null, ...pairing } }),
    );
    await this.audit.log(actor, 'device.pairing_code', 'device', id);
    this.events.emit('device.changed', { deviceId: id });
    return toDeviceView(device);
  }

  async revoke(actor: EmployeeActor, id: string) {
    await this.findOrFail(id);
    const device = await this.prisma.device.update({
      where: { id },
      data: { tokenHash: null, pairingCode: null, pairingExpiresAt: null },
    });
    await this.audit.log(actor, 'device.revoke', 'device', id);
    this.events.emit('device.changed', { deviceId: id });
    return toDeviceView(device);
  }

  /** Borra un dispositivo que ya no se usa. Las órdenes que creó conservan su historial. */
  async remove(actor: EmployeeActor, id: string): Promise<void> {
    const device = await this.findOrFail(id);
    await this.prisma.device.delete({ where: { id } });
    await this.audit.log(actor, 'device.delete', 'device', id, { name: device.name, type: device.type });
    this.events.emit('device.changed', { deviceId: id });
  }

  private async findOrFail(id: string): Promise<Device> {
    const device = await this.prisma.device.findUnique({ where: { id } });
    if (!device) throw new NotFoundException('Dispositivo no encontrado');
    return device;
  }

  private async assertLinks(tableId?: string, stationId?: string): Promise<void> {
    if (tableId && !(await this.prisma.diningTable.findUnique({ where: { id: tableId } }))) {
      throw new BadRequestException('Mesa no encontrada');
    }
    if (stationId && !(await this.prisma.kitchenStation.findUnique({ where: { id: stationId } }))) {
      throw new BadRequestException('Estación no encontrada');
    }
  }

  private async withUniquePairingCode(
    write: (pairing: { pairingCode: string; pairingExpiresAt: Date }) => Promise<Device>,
  ): Promise<Device> {
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        return await write({
          pairingCode: generatePairingCode(),
          pairingExpiresAt: new Date(Date.now() + PAIRING_CODE_TTL_MS),
        });
      } catch (error) {
        if (!isUniqueViolation(error)) throw error;
      }
    }
    throw new Error('No se pudo generar un código de vinculación único');
  }
}
