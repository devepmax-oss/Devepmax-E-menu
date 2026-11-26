import { TablesModule } from './modules/tables/tables.module';
import { BillingModule } from './modules/billing/billing.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { DeliveryModule } from './modules/delivery/delivery.module';
import { OnlineModule } from './modules/online/online.module';
import { CustomersModule } from './modules/customers/customers.module';
import { CouponsModule } from './modules/coupons/coupons.module';
import { InventoryModule } from './modules/inventory/inventory.module';
import { TimeclockModule } from './modules/timeclock/timeclock.module';
import { PayrollModule } from './modules/payroll/payroll.module';
import { PaymentsModule } from './modules/payments/payments.module';
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
import { RealtimeModule } from './realtime/realtime.module';
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
    RealtimeModule,
    PaymentsModule,
    NotificationsModule,
    TablesModule,
    BillingModule,
    DeliveryModule,
    OnlineModule,
    CustomersModule,
    CouponsModule,
    InventoryModule,
    TimeclockModule,
    PayrollModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
