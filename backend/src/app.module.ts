import { Module } from '@nestjs/common';
import { HealthController } from './health/health.controller';
import { AuditModule } from './modules/audit/audit.module';
import { AuthModule } from './modules/auth/auth.module';
import { DevicesModule } from './modules/devices/devices.module';
import { EmployeesModule } from './modules/employees/employees.module';
import { MenuModule } from './modules/menu/menu.module';
import { OrdersModule } from './modules/orders/orders.module';
import { PromotionsModule } from './modules/promotions/promotions.module';
import { SettingsModule } from './modules/settings/settings.module';
import { PrismaModule } from './prisma/prisma.module';
import { DomainEventsModule } from './realtime/domain-events.service';
import { StorageModule } from './storage/storage.module';

@Module({
  imports: [
    PrismaModule,
    DomainEventsModule,
    StorageModule,
    AuditModule,
    AuthModule,
    EmployeesModule,
    DevicesModule,
    SettingsModule,
    MenuModule,
    OrdersModule,
    PromotionsModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
