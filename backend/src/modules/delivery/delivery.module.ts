import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { SettingsModule } from '../settings/settings.module';
import { DeliveryController } from './delivery.controller';
import { DeliveryService } from './delivery.service';
import { GeocodingService } from './geocoding.service';

@Module({
  imports: [OrdersModule, SettingsModule],
  controllers: [DeliveryController],
  providers: [DeliveryService, GeocodingService],
  exports: [DeliveryService],
})
export class DeliveryModule {}
