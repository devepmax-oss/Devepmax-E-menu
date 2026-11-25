import { CouponsModule } from '../coupons/coupons.module';
import { CustomersModule } from '../customers/customers.module';
import { Module } from '@nestjs/common';
import { DeliveryModule } from '../delivery/delivery.module';
import { OrdersModule } from '../orders/orders.module';
import { PaymentsModule } from '../payments/payments.module';
import { PromotionsModule } from '../promotions/promotions.module';
import { SettingsModule } from '../settings/settings.module';
import { OnlineController } from './online.controller';
import { OnlineService } from './online.service';

@Module({
  imports: [CouponsModule, CustomersModule, DeliveryModule, OrdersModule, PaymentsModule, PromotionsModule, SettingsModule],
  controllers: [OnlineController],
  providers: [OnlineService],
})
export class OnlineModule {}
