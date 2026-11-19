import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Actor, EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import {
  AvailabilityDto,
  CreateModifierGroupDto,
  CreateModifierOptionDto,
  CreateStationDto,
  CreateTaxRateDto,
  UpdateModifierGroupDto,
  UpdateModifierOptionDto,
  UpdateStationDto,
  UpdateTaxRateDto,
} from './dto/menu.dto';
import { ModifiersService } from './modifiers.service';
import { StationsService } from './stations.service';
import { TaxRatesService } from './tax-rates.service';

/** Estaciones de cocina, impuestos y grupos de modificadores. */
@ApiTags('menu')
@ApiBearerAuth()
@Controller('menu')
export class MenuSetupController {
  constructor(
    private readonly stations: StationsService,
    private readonly taxRates: TaxRatesService,
    private readonly modifiers: ModifiersService,
  ) {}

  // ───────── Estaciones ─────────

  /** También la usan las pantallas KDS para mostrar su estación. */
  @Get('stations')
  listStations() {
    return this.stations.list();
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('stations')
  createStation(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateStationDto) {
    return this.stations.create(actor, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch('stations/:id')
  updateStation(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateStationDto) {
    return this.stations.update(actor, id, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('stations/:id')
  @HttpCode(204)
  removeStation(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.stations.remove(actor, id);
  }

  // ───────── Impuestos ─────────

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get('tax-rates')
  listTaxRates() {
    return this.taxRates.list();
  }

  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Post('tax-rates')
  createTaxRate(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateTaxRateDto) {
    return this.taxRates.create(actor, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Patch('tax-rates/:id')
  updateTaxRate(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateTaxRateDto) {
    return this.taxRates.update(actor, id, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Delete('tax-rates/:id')
  @HttpCode(204)
  removeTaxRate(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.taxRates.remove(actor, id);
  }

  // ───────── Grupos de modificadores ─────────

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get('modifier-groups')
  listModifierGroups() {
    return this.modifiers.list();
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get('modifier-groups/:id')
  getModifierGroup(@Param('id') id: string) {
    return this.modifiers.get(id);
  }

  /** Crea un grupo reutilizable (p. ej. "Tamaño", "Extras") con sus opciones. */
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('modifier-groups')
  createModifierGroup(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateModifierGroupDto) {
    return this.modifiers.create(actor, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch('modifier-groups/:id')
  updateModifierGroup(
    @CurrentActor() actor: EmployeeActor,
    @Param('id') id: string,
    @Body() dto: UpdateModifierGroupDto,
  ) {
    return this.modifiers.update(actor, id, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('modifier-groups/:id')
  @HttpCode(204)
  removeModifierGroup(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.modifiers.remove(actor, id);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('modifier-groups/:id/options')
  addOption(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: CreateModifierOptionDto) {
    return this.modifiers.addOption(actor, id, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch('modifier-options/:id')
  updateOption(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateModifierOptionDto) {
    return this.modifiers.updateOption(actor, id, dto);
  }

  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('modifier-options/:id')
  @HttpCode(204)
  removeOption(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.modifiers.removeOption(actor, id);
  }

  /** Opción agotada (p. ej. "sin aguacate hoy"). */
  @RequirePermissions('product.toggle_availability')
  @Patch('modifier-options/:id/availability')
  setOptionAvailability(@CurrentActor() actor: Actor, @Param('id') id: string, @Body() dto: AvailabilityDto) {
    return this.modifiers.setOptionAvailability(actor, id, dto.isAvailable);
  }
}
