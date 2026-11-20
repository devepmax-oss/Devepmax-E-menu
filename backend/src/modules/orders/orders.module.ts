import { Module } from '@nestjs/common';
import { PromotionsModule } from '../promotions/promotions.module';
import { SettingsModule } from '../settings/settings.module';
import { KitchenController, OrdersController } from './orders.controller';
import { KitchenService } from './kitchen.service';
import { OrdersService } from './orders.service';
import { PricingService } from './pricing.service';

@Module({
  imports: [SettingsModule, PromotionsModule],
  controllers: [OrdersController, KitchenController],
  providers: [OrdersService, PricingService, KitchenService],
  exports: [OrdersService, PricingService],
})
export class OrdersModule {}
