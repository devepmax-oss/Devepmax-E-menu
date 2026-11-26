import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { PayrollQueryDto, PayrollSettingsDto, PerformanceQueryDto, SetRateDto } from './dto/payroll.dto';
import { PayrollService } from './payroll.service';

@ApiTags('payroll')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('payroll.manage')
@Controller()
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('payroll')
  summary(@Query() query: PayrollQueryDto) {
    return this.payroll.payroll(query.week, query.weeks ?? 1);
  }

  @Post('payroll/export-link')
  @HttpCode(200)
  exportLink(@Body() body: PayrollQueryDto) {
    return this.payroll.exportLink(body.week, body.weeks ?? 1);
  }

  /** Descarga del Excel con el enlace firmado (se abre en el navegador, sin sesión). */
  @Public()
  @Get('payroll/export/:token')
  async exportFile(@Param('token') token: string, @Res() res: Response) {
    const { name, buffer } = await this.payroll.exportFromToken(token);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
    res.setHeader('Cache-Control', 'no-store');
    res.send(buffer);
  }

  @Get('payroll/settings')
  settings() {
    return this.payroll.getSettings();
  }

  @Patch('payroll/settings')
  updateSettings(@CurrentActor() actor: EmployeeActor, @Body() dto: PayrollSettingsDto) {
    return this.payroll.updateSettings(actor, dto);
  }

  @Get('payroll/rates')
  rates() {
    return this.payroll.rates();
  }

  @Put('payroll/rates/:employeeId')
  setRate(@CurrentActor() actor: EmployeeActor, @Param('employeeId') employeeId: string, @Body() dto: SetRateDto) {
    return this.payroll.setRate(actor, employeeId, dto);
  }

  @Delete('payroll/rates/:id')
  deleteRate(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.payroll.deleteRate(actor, id);
  }

  @Get('performance')
  performance(@Query() query: PerformanceQueryDto) {
    return this.payroll.performance(query.from, query.to);
  }
}
