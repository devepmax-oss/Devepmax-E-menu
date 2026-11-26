import { Module } from '@nestjs/common';
import { EmployeesController, RolesController } from './employees.controller';
import { EmployeesService } from './employees.service';

@Module({
  controllers: [EmployeesController, RolesController],
  providers: [EmployeesService],
})
export class EmployeesModule {}
