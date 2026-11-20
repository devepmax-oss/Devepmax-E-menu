import { Body, Controller, ForbiddenException, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Actor } from '../../common/auth/actor';
import { CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import {
  CancelOrderDto,
  CreateOrderDto,
  KitchenQueryDto,
  OrdersQueryDto,
  QuoteOrderDto,
  UpdateTicketDto,
} from './dto/order.dto';
import { KitchenService } from './kitchen.service';
import { OrdersService } from './orders.service';

@ApiTags('orders')
@ApiBearerAuth()
@Controller('orders')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  /**
   * Crea una orden (POS, mesero o tablet de mesa). Idempotente por clientRequestId:
   * si la app reenvía la misma orden, se devuelve la ya creada.
   */
  @Post()
  create(@CurrentActor() actor: Actor, @Body() dto: CreateOrderDto) {
    // Empleados: orders.create. Tablets de mesa: se valida en el servicio (table.order).
    if (actor.kind === 'employee' && !actor.permissions.has('orders.create')) {
      throw new ForbiddenException('Permiso requerido: orders.create');
    }
    return this.orders.create(actor, dto);
  }

  /** Precios, promociones y totales de un carrito, sin crear la orden. */
  @Post('quote')
  @HttpCode(200)
  quote(@CurrentActor() actor: Actor, @Body() dto: QuoteOrderDto) {
    if (actor.kind === 'employee' && !actor.permissions.has('orders.create')) {
      throw new ForbiddenException('Permiso requerido: orders.create');
    }
    return this.orders.quote(dto);
  }

  @RequirePermissions('orders.create')
  @Get()
  list(@Query() query: OrdersQueryDto) {
    return this.orders.list(query.scope ?? 'active');
  }

  @RequirePermissions('orders.create')
  @Get(':id')
  get(@Param('id') id: string) {
    return this.orders.getView(id);
  }

  @RequirePermissions('orders.approve')
  @Post(':id/approve')
  @HttpCode(200)
  approve(@CurrentActor() actor: Actor, @Param('id') id: string) {
    return this.orders.approve(actor, id);
  }

  @RequirePermissions('orders.create')
  @Post(':id/complete')
  @HttpCode(200)
  complete(@CurrentActor() actor: Actor, @Param('id') id: string) {
    return this.orders.complete(actor, id);
  }

  @RequirePermissions('orders.cancel')
  @Post(':id/cancel')
  @HttpCode(200)
  cancel(@CurrentActor() actor: Actor, @Param('id') id: string, @Body() dto: CancelOrderDto) {
    return this.orders.cancel(actor, id, dto.reason.trim());
  }
}

@ApiTags('kitchen')
@ApiBearerAuth()
@Controller('kitchen')
export class KitchenController {
  constructor(private readonly kitchen: KitchenService) {}

  /** Tickets en curso. Las pantallas de cocina reciben solo los de su estación. */
  @RequirePermissions('kitchen.operate')
  @Get('tickets')
  list(@CurrentActor() actor: Actor, @Query() query: KitchenQueryDto) {
    return this.kitchen.list(actor, query.stationId);
  }

  @RequirePermissions('kitchen.operate')
  @Patch('tickets/:id')
  updateStatus(@CurrentActor() actor: Actor, @Param('id') id: string, @Body() dto: UpdateTicketDto) {
    return this.kitchen.updateStatus(actor, id, dto.status);
  }
}
