import { Module } from '@nestjs/common';
import { SettingsModule } from '../settings/settings.module';
import { TimeclockController, TimeclockDeviceController } from './timeclock.controller';
import { TimeclockService } from './timeclock.service';

@Module({
  imports: [SettingsModule],
  controllers: [TimeclockDeviceController, TimeclockController],
  providers: [TimeclockService],
  exports: [TimeclockService],
})
export class TimeclockModule {}
