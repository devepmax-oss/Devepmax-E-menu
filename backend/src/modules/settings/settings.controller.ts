import { Body, Controller, Get, Patch, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { ReplaceOpeningHoursDto, UpdateSettingsDto } from './dto/settings.dto';
import { SettingsService } from './settings.service';

@ApiTags('settings')
@Controller('settings')
export class SettingsController {
  constructor(private readonly settings: SettingsService) {}

  /** Marca, canales y horarios para la web pública y las apps. */
  @Public()
  @Get('public')
  getPublic() {
    return this.settings.getPublic();
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Get()
  get() {
    return this.settings.get();
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Patch()
  update(@CurrentActor() actor: EmployeeActor, @Body() dto: UpdateSettingsDto) {
    return this.settings.update(actor, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('settings.manage')
  @Put('opening-hours')
  replaceOpeningHours(@CurrentActor() actor: EmployeeActor, @Body() dto: ReplaceOpeningHoursDto) {
    return this.settings.replaceOpeningHours(actor, dto);
  }
}
