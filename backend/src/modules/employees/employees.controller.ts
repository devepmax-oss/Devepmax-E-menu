import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { PERMISSIONS } from '../../common/permissions';
import { MAX_IMAGE_BYTES } from '../../storage/image.service';
import { CreateEmployeeDto, EmployeeHistoryQueryDto, SaveRoleDto, UpdateEmployeeDto } from './dto/employee.dto';
import { EmployeesService } from './employees.service';

@ApiTags('employees')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('employees.manage')
@Controller('employees')
export class EmployeesController {
  constructor(private readonly employees: EmployeesService) {}

  @Get()
  list() {
    return this.employees.list();
  }

  @Post()
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateEmployeeDto) {
    return this.employees.create(actor, dto);
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.employees.detail(id);
  }

  @Patch(':id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateEmployeeDto) {
    return this.employees.update(actor, id, dto);
  }

  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @Post(':id/photo')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1 } }))
  setPhoto(
    @CurrentActor() actor: EmployeeActor,
    @Param('id') id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('Falta la foto (campo "file")');
    return this.employees.setPhoto(actor, id, file);
  }

  @Delete(':id/photo')
  removePhoto(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.employees.removePhoto(actor, id);
  }

  @Post(':id/logout-all')
  logoutAll(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.employees.logoutAll(actor, id);
  }

  @RequirePermissions('employees.manage', 'audit.view')
  @Get(':id/history')
  history(@Param('id') id: string, @Query() query: EmployeeHistoryQueryDto) {
    return this.employees.history(id, query);
  }
}

@ApiTags('employees')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('roles.manage')
@Controller('roles')
export class RolesController {
  constructor(private readonly employees: EmployeesService) {}

  /** Lo usan quienes administran empleados (para elegir rol) o roles. */
  @RequirePermissions()
  @Get()
  list(@CurrentActor() actor: EmployeeActor) {
    if (!actor.permissions.has('employees.manage') && !actor.permissions.has('roles.manage')) {
      throw new ForbiddenException('Permiso requerido: employees.manage o roles.manage');
    }
    return this.employees.listRoles();
  }

  @Get('permissions')
  permissions() {
    return PERMISSIONS;
  }

  @Post()
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: SaveRoleDto) {
    return this.employees.createRole(actor, dto);
  }

  @Patch(':id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SaveRoleDto) {
    return this.employees.updateRole(actor, id, dto);
  }

  @Delete(':id')
  remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.employees.deleteRole(actor, id);
  }
}
