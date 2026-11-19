import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import type { AnyPermission } from '../permissions';
import type { Actor, ActorKind } from './actor';

export const IS_PUBLIC_KEY = 'auth:isPublic';
export const PERMISSIONS_KEY = 'auth:permissions';
export const ACTOR_KINDS_KEY = 'auth:actorKinds';

/** Ruta accesible sin autenticación. */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

/** Exige todos los permisos indicados. */
export const RequirePermissions = (...permissions: AnyPermission[]) =>
  SetMetadata(PERMISSIONS_KEY, permissions);

/** Restringe el tipo de identidad (empleado o dispositivo). */
export const AllowActors = (...kinds: ActorKind[]) => SetMetadata(ACTOR_KINDS_KEY, kinds);

/** Inyecta la identidad autenticada en el handler. */
export const CurrentActor = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): Actor | undefined => ctx.switchToHttp().getRequest().actor,
);
