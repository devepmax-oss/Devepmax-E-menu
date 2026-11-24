import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { TablesModule } from '../tables/tables.module';
import { BillingController, CashController } from './billing.controller';
import { BillingService } from './billing.service';
import { CashService } from './cash.service';

@Module({
  imports: [OrdersModule, TablesModule],
  controllers: [BillingController, CashController],
  providers: [BillingService, CashService],
  exports: [BillingService],
})
export class BillingModule {}
