import { Module } from '@nestjs/common';
import { SettingsModule } from '../settings/settings.module';
import { LoyaltyService } from './loyalty.service';

@Module({
  imports: [SettingsModule],
  providers: [LoyaltyService],
  exports: [LoyaltyService],
})
export class LoyaltyModule {}
