import { Body, Controller, Delete, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { Actor, actorRef } from '../../common/auth/actor';
import { CurrentActor } from '../../common/auth/decorators';
import { PushService } from './push.service';

class TokenDto {
  @IsString() @MaxLength(4096) token: string;
  @IsOptional() @IsIn(['web', 'android', 'ios']) platform?: string;
}

/** Cada app registra aquí su token para recibir notificaciones push. */
@ApiTags('notifications')
@ApiBearerAuth()
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly push: PushService) {}

  @Post('token')
  @HttpCode(200)
  register(@CurrentActor() actor: Actor, @Body() dto: TokenDto) {
    return this.push.register(actorRef(actor), dto.token, dto.platform);
  }

  @Delete('token')
  unregister(@Body() dto: TokenDto) {
    return this.push.unregister(dto.token);
  }
}
