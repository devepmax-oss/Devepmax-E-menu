import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { Actor, ActorKind } from '../../common/auth/actor';
import { ACTOR_KINDS_KEY, IS_PUBLIC_KEY, PERMISSIONS_KEY } from '../../common/auth/decorators';
import { AuthService } from './auth.service';

type RequestWithActor = Request & { actor?: Actor };

export function extractBearerToken(request: Request): string | undefined {
  const header = request.headers.authorization;
  if (!header) return undefined;
  const [scheme, token] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' && token ? token.trim() : undefined;
}

/** Guard global: autentica (empleado o dispositivo) y verifica permisos. Todo es privado salvo @Public(). */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly auth: AuthService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;

    const targets = [context.getHandler(), context.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, targets) ?? false;
    const request = context.switchToHttp().getRequest<RequestWithActor>();
    const token = extractBearerToken(request);

    if (isPublic) {
      if (token) {
        request.actor = await this.auth.resolveActor(token).catch(() => undefined);
      }
      return true;
    }

    if (!token) throw new UnauthorizedException('Autenticación requerida');
    const actor = await this.auth.resolveActor(token);
    request.actor = actor;

    const kinds = this.reflector.getAllAndOverride<ActorKind[]>(ACTOR_KINDS_KEY, targets);
    if (kinds && !kinds.includes(actor.kind)) {
      throw new ForbiddenException('Esta acción no está permitida para este tipo de usuario');
    }

    const required = this.reflector.getAllAndOverride<string[]>(PERMISSIONS_KEY, targets) ?? [];
    const missing = required.filter((permission) => !actor.permissions.has(permission));
    if (missing.length > 0) {
      throw new ForbiddenException(`Permiso requerido: ${missing.join(', ')}`);
    }
    return true;
  }
}
