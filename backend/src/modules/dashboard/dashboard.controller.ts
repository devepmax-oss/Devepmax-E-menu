import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AllowActors, RequirePermissions } from '../../common/auth/decorators';
import { DashboardService } from './dashboard.service';

@ApiTags('dashboard')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('reports.view')
@Controller('dashboard')
export class DashboardController {
  constructor(private readonly dashboard: DashboardService) {}

  /** Cómo va hoy, qué pasa ahora y las alertas. */
  @Get('today')
  today() {
    return this.dashboard.today();
  }
}
