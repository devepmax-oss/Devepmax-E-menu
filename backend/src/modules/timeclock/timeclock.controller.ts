import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { DeviceActor, EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import {
  CopyWeekDto,
  DeleteEntryDto,
  EntriesQueryDto,
  ManagerPunchDto,
  PinDto,
  PunchDto,
  SaveEntryDto,
  SaveShiftDto,
  TimeclockSettingsDto,
  WeekQueryDto,
} from './dto/timeclock.dto';
import { TimeclockService } from './timeclock.service';

/** La tablet de reloj checador: el empleado escribe su PIN y marca. */
@ApiTags('timeclock')
@ApiBearerAuth()
@AllowActors('device')
@RequirePermissions('timeclock.punch')
@Controller('timeclock/device')
export class TimeclockDeviceController {
  constructor(private readonly timeclock: TimeclockService) {}

  /** Solo consulta: responde 200. */
  @Post('lookup')
  @HttpCode(200)
  lookup(@CurrentActor() device: DeviceActor, @Body() dto: PinDto) {
    return this.timeclock.lookup(device, dto.pin);
  }

  @Post('punch')
  punch(@CurrentActor() device: DeviceActor, @Body() dto: PunchDto) {
    return this.timeclock.punch(device, dto.pin, dto.action);
  }
}

/** Asistencia y horarios para el gerente. */
@ApiTags('timeclock')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('employees.manage')
@Controller()
export class TimeclockController {
  constructor(private readonly timeclock: TimeclockService) {}

  @Get('timeclock/now')
  now() {
    return this.timeclock.now();
  }

  @Get('timeclock/entries')
  entries(@Query() query: EntriesQueryDto) {
    return this.timeclock.entries(query);
  }

  @Post('timeclock/entries')
  createEntry(@CurrentActor() actor: EmployeeActor, @Body() dto: SaveEntryDto) {
    return this.timeclock.createEntry(actor, dto);
  }

  @Put('timeclock/entries/:id')
  updateEntry(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SaveEntryDto) {
    return this.timeclock.updateEntry(actor, id, dto);
  }

  @Delete('timeclock/entries/:id')
  deleteEntry(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: DeleteEntryDto) {
    return this.timeclock.deleteEntry(actor, id, dto.reason);
  }

  @Post('timeclock/employees/:id/punch')
  managerPunch(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: ManagerPunchDto) {
    return this.timeclock.managerPunch(actor, id, dto.action, dto.reason);
  }

  @Get('timeclock/settings')
  settings() {
    return this.timeclock.getSettings();
  }

  @Patch('timeclock/settings')
  updateSettings(@CurrentActor() actor: EmployeeActor, @Body() dto: TimeclockSettingsDto) {
    return this.timeclock.updateSettings(actor, dto);
  }

  @Get('schedule')
  week(@Query() query: WeekQueryDto) {
    return this.timeclock.week(query.week);
  }

  @Post('schedule/shifts')
  createShift(@CurrentActor() actor: EmployeeActor, @Body() dto: SaveShiftDto) {
    return this.timeclock.saveShift(actor, null, dto);
  }

  @Put('schedule/shifts/:id')
  updateShift(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SaveShiftDto) {
    return this.timeclock.saveShift(actor, id, dto);
  }

  @Delete('schedule/shifts/:id')
  deleteShift(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.timeclock.deleteShift(actor, id);
  }

  @Post('schedule/copy-week')
  copyWeek(@CurrentActor() actor: EmployeeActor, @Body() dto: CopyWeekDto) {
    return this.timeclock.copyWeek(actor, dto);
  }
}
