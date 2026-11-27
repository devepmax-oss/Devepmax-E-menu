import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AllowActors, RequirePermissions } from '../../common/auth/decorators';
import { DashboardService } from './dashboard.service';
import { MenuInsightsService } from './menu-insights.service';

@ApiTags('dashboard')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('reports.view')
@Controller('dashboard')
export class DashboardController {
  constructor(
    private readonly dashboard: DashboardService,
    private readonly menuInsights: MenuInsightsService,
  ) {}

  /** Cómo va hoy, qué pasa ahora y las alertas. */
  @Get('today')
  today() {
    return this.dashboard.today();
  }

  /** Platos y promociones de un período: ?from=AAAA-MM-DD&to=AAAA-MM-DD (hasta 400 días). */
  @Get('menu')
  menu(@Query('from') from?: string, @Query('to') to?: string) {
    return this.menuInsights.menu(from, to);
  }
}
