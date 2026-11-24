import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { PaymentsModule } from '../payments/payments.module';
import { SettingsModule } from '../settings/settings.module';
import { TablesModule } from '../tables/tables.module';
import { BillingController, CashController, TablePayController, TerminalController } from './billing.controller';
import { BillingService } from './billing.service';
import { CashService } from './cash.service';
import { TablePayService } from './table-pay.service';
import { TerminalService } from './terminal.service';

@Module({
  imports: [OrdersModule, TablesModule, PaymentsModule, SettingsModule],
  controllers: [BillingController, CashController, TerminalController, TablePayController],
  providers: [BillingService, CashService, TerminalService, TablePayService],
  exports: [BillingService],
})
export class BillingModule {}
