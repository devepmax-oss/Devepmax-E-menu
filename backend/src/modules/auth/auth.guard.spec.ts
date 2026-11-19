import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Actor } from '../../common/auth/actor';
import { ACTOR_KINDS_KEY, IS_PUBLIC_KEY, PERMISSIONS_KEY } from '../../common/auth/decorators';
import { AuthGuard } from './auth.guard';
import { AuthService } from './auth.service';

const cashier: Actor = {
  kind: 'employee',
  id: 'e1',
  name: 'Ana',
  roleId: 'r1',
  roleName: 'Cajero',
  permissions: new Set(['orders.create']),
  deviceId: null,
};

function setup(metadata: Record<string, unknown>, authorization?: string, actor: Actor = cashier) {
  const reflector = { getAllAndOverride: (key: string) => metadata[key] } as unknown as Reflector;
  const resolveActor = jest.fn(async () => actor);
  const guard = new AuthGuard(reflector, { resolveActor } as unknown as AuthService);
  const request: Record<string, unknown> = { headers: authorization ? { authorization } : {} };
  const context = {
    getType: () => 'http',
    getHandler: () => undefined,
    getClass: () => undefined,
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { guard, context, request, resolveActor };
}

describe('AuthGuard', () => {
  it('deja pasar rutas públicas sin token', async () => {
    const { guard, context } = setup({ [IS_PUBLIC_KEY]: true });
    await expect(guard.canActivate(context)).resolves.toBe(true);
  });

  it('exige token en rutas privadas', async () => {
    const { guard, context } = setup({});
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('adjunta la identidad cuando el permiso alcanza', async () => {
    const { guard, context, request } = setup({ [PERMISSIONS_KEY]: ['orders.create'] }, 'Bearer abc');
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.actor).toBe(cashier);
  });

  it('rechaza si falta un permiso', async () => {
    const { guard, context } = setup({ [PERMISSIONS_KEY]: ['payments.refund'] }, 'Bearer abc');
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rechaza el tipo de identidad no permitido', async () => {
    const { guard, context } = setup({ [ACTOR_KINDS_KEY]: ['device'] }, 'Bearer abc');
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('en rutas públicas ignora un token inválido', async () => {
    const { guard, context, resolveActor } = setup({ [IS_PUBLIC_KEY]: true }, 'Bearer malo');
    resolveActor.mockRejectedValueOnce(new UnauthorizedException());
    await expect(guard.canActivate(context)).resolves.toBe(true);
  });
});
