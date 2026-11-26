import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { OrdersService } from './orders.service';

/** Cada 30 segundos pasa a cocina los pedidos programados a los que ya les toca. */
@Injectable()
export class ScheduledOrdersService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ScheduledOrdersService.name);
  private timer?: NodeJS.Timeout;
  private running = false;

  constructor(private readonly orders: OrdersService) {}

  onModuleInit() {
    if (process.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => void this.tick(), 30_000);
    this.timer.unref?.();
    setTimeout(() => void this.tick(), 5_000).unref?.();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  async tick() {
    if (this.running) return;
    this.running = true;
    try {
      for (const { id } of await this.orders.dueScheduled()) {
        try {
          await this.orders.releaseScheduled('system', id);
        } catch (error) {
          this.logger.error(`No se pudo pasar a cocina el pedido programado ${id}: ${String(error)}`);
        }
      }
    } catch (error) {
      this.logger.error(`Revisión de pedidos programados: ${String(error)}`);
    } finally {
      this.running = false;
    }
  }
}
