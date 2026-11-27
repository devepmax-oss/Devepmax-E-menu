import { Module } from '@nestjs/common';
import { SettingsModule } from '../settings/settings.module';
import { DashboardController } from './dashboard.controller';
import { DashboardService } from './dashboard.service';
import { KitchenInsightsService } from './kitchen-insights.service';
import { MenuInsightsService } from './menu-insights.service';

@Module({
  imports: [SettingsModule],
  controllers: [DashboardController],
  providers: [DashboardService, MenuInsightsService, KitchenInsightsService],
  exports: [DashboardService, MenuInsightsService, KitchenInsightsService],
})
export class DashboardModule {}
