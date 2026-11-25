import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { CouponsService } from './coupons.service';
import { ApplyCouponDto, CouponDto } from './dto/coupons.dto';

@ApiTags('cupones')
@ApiBearerAuth()
@AllowActors('employee')
@Controller()
export class CouponsController {
  constructor(private readonly coupons: CouponsService) {}

  @RequirePermissions('menu.manage')
  @Get('coupons')
  list() {
    return this.coupons.list();
  }

  @RequirePermissions('menu.manage')
  @Get('coupons/suggest-code')
  suggest() {
    return this.coupons.suggestCode();
  }

  @RequirePermissions('menu.manage')
  @Post('coupons')
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CouponDto) {
    return this.coupons.create(actor, dto);
  }

  @RequirePermissions('menu.manage')
  @Patch('coupons/:id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: CouponDto) {
    return this.coupons.update(actor, id, dto);
  }

  @RequirePermissions('menu.manage')
  @Delete('coupons/:id')
  @HttpCode(204)
  async remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    await this.coupons.remove(actor, id);
  }

  /** Cupón en una cuenta de la caja (ya autorizado: no hace falta PIN de gerente). */
  @RequirePermissions('payments.take')
  @Post('billing/bills/:id/coupon')
  @HttpCode(200)
  apply(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: ApplyCouponDto) {
    return this.coupons.applyToBill(actor, id, dto.code);
  }

  @RequirePermissions('payments.take')
  @Delete('billing/bills/:id/coupon')
  removeFromBill(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.coupons.removeFromBill(actor, id);
  }
}
