import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { AssignDriverDto, DeliveryZoneDto, DriverLocationDto, UpdateDriverMeDto } from './dto/delivery.dto';
import { DeliveryService } from './delivery.service';

@ApiTags('delivery')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('delivery')
export class DeliveryController {
  constructor(private readonly delivery: DeliveryService) {}

  // ───────── App del repartidor ─────────

  @RequirePermissions('delivery.own')
  @Get('me')
  me(@CurrentActor() actor: EmployeeActor) {
    return this.delivery.me(actor);
  }

  @RequirePermissions('delivery.own')
  @Patch('me')
  updateMe(@CurrentActor() actor: EmployeeActor, @Body() dto: UpdateDriverMeDto) {
    return this.delivery.updateMe(actor, dto);
  }

  @RequirePermissions('delivery.own')
  @Get('me/deliveries')
  myDeliveries(@CurrentActor() actor: EmployeeActor) {
    return this.delivery.myDeliveries(actor);
  }

  @RequirePermissions('delivery.own')
  @Post('me/location')
  @HttpCode(200)
  location(@CurrentActor() actor: EmployeeActor, @Body() dto: DriverLocationDto) {
    return this.delivery.location(actor, dto);
  }

  @RequirePermissions('delivery.own')
  @Post('assignments/:id/accept')
  @HttpCode(200)
  accept(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.delivery.accept(actor, id);
  }

  @RequirePermissions('delivery.own')
  @Post('assignments/:id/decline')
  @HttpCode(200)
  decline(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.delivery.decline(actor, id);
  }

  @RequirePermissions('delivery.own')
  @Post('assignments/:id/picked-up')
  @HttpCode(200)
  pickedUp(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.delivery.pickedUp(actor, id);
  }

  @RequirePermissions('delivery.own')
  @Post('assignments/:id/delivered')
  @HttpCode(200)
  delivered(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.delivery.delivered(actor, id);
  }

  // ───────── Despacho ─────────

  @RequirePermissions('delivery.dispatch')
  @Get('drivers')
  drivers() {
    return this.delivery.drivers();
  }

  @RequirePermissions('delivery.dispatch')
  @Post('orders/:orderId/assign')
  @HttpCode(200)
  assign(@CurrentActor() actor: EmployeeActor, @Param('orderId') orderId: string, @Body() dto: AssignDriverDto) {
    return this.delivery.assign(actor, orderId, dto.driverId);
  }

  @RequirePermissions('delivery.dispatch')
  @Delete('orders/:orderId/assign')
  unassign(@CurrentActor() actor: EmployeeActor, @Param('orderId') orderId: string) {
    return this.delivery.unassign(actor, orderId);
  }

  // ───────── Zona ─────────

  @RequirePermissions('delivery.dispatch')
  @Get('zone')
  zone() {
    return this.delivery.zone();
  }

  @RequirePermissions('settings.manage')
  @Put('zone')
  saveZone(@CurrentActor() actor: EmployeeActor, @Body() dto: DeliveryZoneDto) {
    return this.delivery.saveZone(actor, dto);
  }
}
