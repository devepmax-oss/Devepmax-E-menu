import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { Actor, actorRef } from '../../common/auth/actor';

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  /** Registra una acción importante. Nunca guardar contraseñas, PINs ni tokens en `data`. */
  async log(
    actor: Actor | 'system',
    action: string,
    entityType: string,
    entityId: string,
    data?: Prisma.InputJsonValue,
  ): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        actor: actor === 'system' ? 'system' : actorRef(actor),
        action,
        entityType,
        entityId,
        data,
      },
    });
  }

  list(params: { entityType?: string; entityId?: string; take: number; cursor?: string }) {
    return this.prisma.auditLog.findMany({
      where: { entityType: params.entityType, entityId: params.entityId },
      orderBy: { createdAt: 'desc' },
      take: params.take,
      ...(params.cursor ? { skip: 1, cursor: { id: params.cursor } } : {}),
    });
  }
}
