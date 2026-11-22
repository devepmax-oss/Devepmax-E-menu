import { Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';

/** AuthService y DomainEventsService vienen de módulos globales. */
@Module({ providers: [RealtimeGateway] })
export class RealtimeModule {}
