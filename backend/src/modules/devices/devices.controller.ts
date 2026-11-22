import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { DevicesService } from './devices.service';
import { CreateDeviceDto, UpdateDeviceDto } from './dto/device.dto';

@ApiTags('devices')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('devices.manage')
@Controller('devices')
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Get()
  list() {
    return this.devices.list();
  }

  /** Crea el dispositivo y devuelve un código de vinculación válido por 15 minutos. */
  @Post()
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateDeviceDto) {
    return this.devices.create(actor, dto);
  }

  @Patch(':id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateDeviceDto) {
    return this.devices.update(actor, id, dto);
  }

  @Post(':id/pairing-code')
  @HttpCode(200)
  pairingCode(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.devices.regeneratePairingCode(actor, id);
  }

  @Post(':id/revoke')
  @HttpCode(200)
  revoke(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.devices.revoke(actor, id);
  }

  @Delete(':id')
  @HttpCode(204)
  remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.devices.remove(actor, id);
  }
}
