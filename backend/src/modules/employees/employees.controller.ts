import { Body, Controller, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto';
import { EmployeesService } from './employees.service';

@ApiTags('employees')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('employees.manage')
@Controller()
export class EmployeesController {
  constructor(private readonly employees: EmployeesService) {}

  @Get('employees')
  list() {
    return this.employees.list();
  }

  @Post('employees')
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateEmployeeDto) {
    return this.employees.create(actor, dto);
  }

  @Patch('employees/:id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateEmployeeDto) {
    return this.employees.update(actor, id, dto);
  }

  @Get('roles')
  roles() {
    return this.employees.listRoles();
  }
}
