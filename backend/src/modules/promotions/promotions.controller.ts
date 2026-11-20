import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { CreatePromotionDto, PublicPromotionsQueryDto, UpdatePromotionDto } from './dto/promotion.dto';
import { PromotionsService } from './promotions.service';

@ApiTags('promotions')
@Controller('promotions')
export class PromotionsController {
  constructor(private readonly promotions: PromotionsService) {}

  /** Promociones vigentes (para mostrarlas en tablets y web). */
  @Public()
  @Get('public')
  listPublic(@Query() query: PublicPromotionsQueryDto) {
    return this.promotions.listPublic(query.channel ?? 'online');
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get()
  list() {
    return this.promotions.list();
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post()
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreatePromotionDto) {
    return this.promotions.create(actor, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch(':id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdatePromotionDto) {
    return this.promotions.update(actor, id, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete(':id')
  @HttpCode(204)
  remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.promotions.remove(actor, id);
  }
}
