import { Body, Controller, Get, HttpCode, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { Actor, DeviceActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public } from '../../common/auth/decorators';
import { AuthService } from './auth.service';
import { LoginDto, PairDeviceDto, PinLoginDto, RefreshDto } from './dto/auth.dto';

function clientIp(request: Request): string {
  return request.ip ?? request.socket.remoteAddress ?? 'unknown';
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  /** Ingreso de empleados con email y contraseña (panel admin, app de repartidor). */
  @Public()
  @Post('login')
  @HttpCode(200)
  login(@Body() dto: LoginDto, @Req() request: Request) {
    return this.auth.login(dto.email, dto.password, clientIp(request), request.get('user-agent'));
  }

  /** Renueva la sesión. El refresh token anterior queda invalidado. */
  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto, @Req() request: Request) {
    return this.auth.refresh(dto.refreshToken, request.get('user-agent'));
  }

  @Public()
  @Post('logout')
  @HttpCode(204)
  async logout(@Body() dto: RefreshDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  /** Ingreso rápido con PIN desde un dispositivo POS/KDS/mesero ya vinculado. */
  @ApiBearerAuth()
  @AllowActors('device')
  @Post('pin')
  @HttpCode(200)
  pin(@CurrentActor() device: DeviceActor, @Body() dto: PinLoginDto) {
    return this.auth.loginWithPin(device, dto.pin);
  }

  /** Tablet de mesa: el personal abre el menú oculto con su PIN (no inicia sesión). */
  @ApiBearerAuth()
  @AllowActors('device')
  @Post('device/staff-check')
  @HttpCode(200)
  staffCheck(@CurrentActor() device: DeviceActor, @Body() dto: PinLoginDto) {
    return this.auth.verifyStaffPin(device, dto.pin);
  }

  /** Vincula un dispositivo con el código de 6 dígitos generado en el panel. */
  @Public()
  @Post('device/pair')
  @HttpCode(200)
  pair(@Body() dto: PairDeviceDto, @Req() request: Request) {
    return this.auth.pairDevice(dto.code, clientIp(request), dto.appVersion);
  }

  /** Identidad actual (empleado o dispositivo) con sus permisos. */
  @ApiBearerAuth()
  @Get('me')
  me(@CurrentActor() actor: Actor) {
    return { ...actor, permissions: [...actor.permissions].sort() };
  }
}
