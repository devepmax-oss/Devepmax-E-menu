import { Global, Injectable, Logger, Module } from '@nestjs/common';
import { EventEmitter } from 'node:events';

/** Eventos del dominio que se difunden en tiempo real (el gateway de Socket.IO se suscribe). */
export type DomainEventName =
  | 'order.created'
  | 'order.updated'
  | 'ticket.created'
  | 'ticket.updated'
  | 'bill.updated'
  | 'product.availability'
  | 'option.availability'
  // Repartidores: su lista de entregas y la ubicación en vivo.
  | 'delivery.updated'
  | 'delivery.removed'
  | 'driver.location'
  // Salón: estado de cada mesa (sesión, cuenta, llamados).
  | 'table.updated'
  // Llamados desde la tablet: "llama al mesero", "pide la cuenta".
  | 'service_request.created'
  | 'service_request.updated'
  // Internos: no se difunden; el gateway desconecta los sockets afectados
  // para que vuelvan a entrar con sus permisos y rooms actualizados.
  | 'device.changed'
  // Interno: Stripe confirmó o canceló un cobro del lector (lo aplica la caja).
  | 'payment.terminal_intent'
  | 'employee.changed';

export interface DomainEvent<T = unknown> {
  name: DomainEventName;
  payload: T;
  /** Para que los clientes descarten eventos viejos. */
  at: string;
}

@Injectable()
export class DomainEventsService {
  private readonly logger = new Logger(DomainEventsService.name);
  private readonly emitter = new EventEmitter();

  emit<T>(name: DomainEventName, payload: T): void {
    const event: DomainEvent<T> = { name, payload, at: new Date().toISOString() };
    try {
      this.emitter.emit('event', event);
    } catch (error) {
      // Un suscriptor con error nunca debe romper la operación que generó el evento.
      this.logger.error(`Error al difundir ${name}: ${String(error)}`);
    }
  }

  subscribe(listener: (event: DomainEvent) => void): () => void {
    this.emitter.on('event', listener);
    return () => this.emitter.off('event', listener);
  }
}

@Global()
@Module({
  providers: [DomainEventsService],
  exports: [DomainEventsService],
})
export class DomainEventsModule {}
