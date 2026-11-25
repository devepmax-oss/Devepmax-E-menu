import { Body, Controller, Get, Headers, HttpCode, Ip, Param, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/auth/decorators';
import { CUSTOMER_TOKEN_HEADER } from '../customers/customer-auth.service';
import { CreateOnlineOrderDto, OnlineQuoteDto } from './dto/online.dto';
import { OnlineService } from './online.service';

/** API pública de la web de pedidos (gopicadera.online). No requiere sesión. */
@ApiTags('online')
@Public()
@Controller('online')
export class OnlineController {
  constructor(private readonly online: OnlineService) {}

  @Get('config')
  config() {
    return this.online.config();
  }

  @Post('quote')
  @HttpCode(200)
  quote(@Body() dto: OnlineQuoteDto) {
    return this.online.quote(dto);
  }

  @Post('orders')
  create(@Body() dto: CreateOnlineOrderDto, @Ip() ip: string, @Headers(CUSTOMER_TOKEN_HEADER) customerToken?: string) {
    return this.online.createOrder(dto, ip, customerToken);
  }

  @Get('orders/:code')
  get(@Param('code') code: string) {
    return this.online.getPublic(code);
  }

  @Post('orders/:code/confirm-payment')
  @HttpCode(200)
  confirmPayment(@Param('code') code: string) {
    return this.online.confirmPayment(code);
  }
}
