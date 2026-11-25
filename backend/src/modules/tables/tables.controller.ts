import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import {
  AssignWaiterDto,
  AreaDto,
  BulkTablesDto,
  CloseTableDto,
  CreateTableDto,
  LayoutDto,
  OpenTableDto,
  ResolveRequestDto,
  TableStatusDto,
  UpdateAreaDto,
  UpdateTableDto,
} from './dto/tables.dto';
import { EmenuService } from './emenu.service';
import { TablesService } from './tables.service';

@ApiTags('tables')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('tables')
export class TablesController {
  constructor(
    private readonly tables: TablesService,
    private readonly emenu: EmenuService,
  ) {}

  /** Atender un llamado de la tablet: "Voy" (ACKNOWLEDGED) o "Listo" (DONE). */
  @RequirePermissions('tables.operate')
  @Patch('requests/:id')
  resolveRequest(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: ResolveRequestDto) {
    return this.emenu.resolveRequest(actor, id, dto.status);
  }

  // ───────── Salón (meseros y caja) ─────────

  @RequirePermissions('tables.operate')
  @Get('floor')
  floor() {
    return this.tables.floor();
  }

  @RequirePermissions('tables.operate')
  @Get(':id')
  view(@Param('id') id: string) {
    return this.tables.view(id);
  }

  @RequirePermissions('tables.operate')
  @Post(':id/open')
  @HttpCode(200)
  open(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: OpenTableDto) {
    return this.tables.open(actor, id, dto.guestCount);
  }

  @RequirePermissions('tables.operate')
  @Post(':id/close')
  @HttpCode(200)
  close(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: CloseTableDto) {
    return this.tables.close(actor, id, dto.force);
  }

  /** "Tomar esta mesa" (sin waiterId) o asignarla a otro mesero (gerente). */
  @RequirePermissions('tables.operate')
  @Patch(':id/waiter')
  assignWaiter(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: AssignWaiterDto) {
    return this.tables.assignWaiter(actor, id, dto.waiterId);
  }

  @RequirePermissions('tables.operate')
  @Patch(':id/status')
  status(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: TableStatusDto) {
    return this.tables.setStatus(actor, id, dto.status);
  }

  // ───────── Configuración del plano ─────────

  @RequirePermissions('tables.manage')
  @Post('areas')
  createArea(@CurrentActor() actor: EmployeeActor, @Body() dto: AreaDto) {
    return this.tables.createArea(actor, dto);
  }

  @RequirePermissions('tables.manage')
  @Patch('areas/:id')
  updateArea(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateAreaDto) {
    return this.tables.updateArea(actor, id, dto);
  }

  @RequirePermissions('tables.manage')
  @Delete('areas/:id')
  deleteArea(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.tables.deleteArea(actor, id);
  }

  @RequirePermissions('tables.manage')
  @Post()
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateTableDto) {
    return this.tables.createTable(actor, dto);
  }

  @RequirePermissions('tables.manage')
  @Post('bulk')
  bulk(@CurrentActor() actor: EmployeeActor, @Body() dto: BulkTablesDto) {
    return this.tables.bulkCreate(actor, dto);
  }

  @RequirePermissions('tables.manage')
  @Put('layout')
  layout(@CurrentActor() actor: EmployeeActor, @Body() dto: LayoutDto) {
    return this.tables.saveLayout(actor, dto);
  }

  @RequirePermissions('tables.manage')
  @Patch(':id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateTableDto) {
    return this.tables.updateTable(actor, id, dto);
  }

  @RequirePermissions('tables.manage')
  @Delete(':id')
  remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.tables.removeTable(actor, id);
  }
}
