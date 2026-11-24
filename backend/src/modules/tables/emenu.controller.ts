import { Body, Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { DeviceActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { ServiceRequestDto } from './dto/tables.dto';
import { EmenuService } from './emenu.service';

/** Endpoints de la tablet de mesa (con su token de dispositivo). */
@ApiTags('emenu')
@ApiBearerAuth()
@AllowActors('device')
@Controller('emenu')
export class EmenuController {
  constructor(private readonly emenu: EmenuService) {}

  @RequirePermissions('table.view_bill')
  @Get('table')
  table(@CurrentActor() device: DeviceActor) {
    return this.emenu.table(device);
  }

  @RequirePermissions('table.service_request')
  @Post('requests')
  request(@CurrentActor() device: DeviceActor, @Body() dto: ServiceRequestDto) {
    return this.emenu.createRequest(device, dto.type);
  }

  @RequirePermissions('table.service_request')
  @Post('requests/:id/cancel')
  @HttpCode(200)
  cancel(@CurrentActor() device: DeviceActor, @Param('id') id: string) {
    return this.emenu.cancelRequest(device, id);
  }
}
