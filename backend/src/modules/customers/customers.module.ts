import { Module } from '@nestjs/common';
import { BillingModule } from '../billing/billing.module';
import { LoyaltyModule } from '../loyalty/loyalty.module';
import { SettingsModule } from '../settings/settings.module';
import { CustomerAuthService } from './customer-auth.service';
import { CustomerAuthController, CustomersController, MeController } from './customers.controller';
import { CustomersService } from './customers.service';

@Module({
  imports: [SettingsModule, BillingModule, LoyaltyModule],
  controllers: [CustomerAuthController, MeController, CustomersController],
  providers: [CustomerAuthService, CustomersService],
  exports: [CustomerAuthService, CustomersService],
})
export class CustomersModule {}
