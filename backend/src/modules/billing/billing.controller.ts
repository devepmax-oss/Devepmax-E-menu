import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { BillingService } from './billing.service';
import { CashService } from './cash.service';
import {
  BillsQueryDto,
  CashMovementDto,
  CloseShiftDto,
  DiscountDto,
  MergeDto,
  OpenShiftDto,
  PaymentDto,
  RemoveDiscountDto,
  SplitDto,
} from './dto/billing.dto';

@ApiTags('billing')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('billing')
export class BillingController {
  constructor(private readonly billing: BillingService) {}

  @RequirePermissions('payments.take')
  @Get('bills')
  list(@Query() query: BillsQueryDto) {
    return this.billing.list(query.tableId);
  }

  @RequirePermissions('payments.take')
  @Get('bills/:id')
  view(@Param('id') id: string) {
    return this.billing.view(id);
  }

  @RequirePermissions('payments.take')
  @Post('bills/:id/payments')
  pay(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: PaymentDto) {
    return this.billing.pay(actor, id, dto);
  }

  /** Descuento manual: permiso bills.discount, o PIN de un gerente. */
  @RequirePermissions('payments.take')
  @Post('bills/:id/discounts')
  discount(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: DiscountDto) {
    return this.billing.addDiscount(actor, id, dto);
  }

  @RequirePermissions('payments.take')
  @Delete('discounts/:id')
  removeDiscount(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: RemoveDiscountDto) {
    return this.billing.removeDiscount(actor, id, dto?.managerPin);
  }

  @RequirePermissions('payments.take')
  @Post('bills/:id/split')
  split(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SplitDto) {
    return this.billing.split(actor, id, dto.itemIds);
  }

  @RequirePermissions('payments.take')
  @Post('bills/:id/merge')
  @HttpCode(200)
  merge(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: MergeDto) {
    return this.billing.merge(actor, id, dto.targetBillId);
  }
}

@ApiTags('cash')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('cash')
export class CashController {
  constructor(private readonly cash: CashService) {}

  @RequirePermissions('payments.take')
  @Get('shift')
  async current() {
    return { shift: await this.cash.current() };
  }

  @RequirePermissions('cash.shift')
  @Get('shifts')
  history() {
    return this.cash.history();
  }

  @RequirePermissions('cash.shift')
  @Post('shift/open')
  open(@CurrentActor() actor: EmployeeActor, @Body() dto: OpenShiftDto) {
    return this.cash.open(actor, dto.openingCash);
  }

  @RequirePermissions('cash.shift')
  @Post('shift/movements')
  movement(@CurrentActor() actor: EmployeeActor, @Body() dto: CashMovementDto) {
    return this.cash.movement(actor, dto);
  }

  @RequirePermissions('cash.shift')
  @Post('shift/close')
  @HttpCode(200)
  close(@CurrentActor() actor: EmployeeActor, @Body() dto: CloseShiftDto) {
    return this.cash.close(actor, dto.countedCash, dto.notes);
  }
}
