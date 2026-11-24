import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { BillingService } from './billing.service';
import { CashService } from './cash.service';
import { ReceiptsService } from './receipts.service';
import { TablePayService } from './table-pay.service';
import { TerminalService } from './terminal.service';
import {
  BillsQueryDto,
  CashMovementDto,
  CloseShiftDto,
  DiscountDto,
  MergeDto,
  OpenShiftDto,
  PaymentDto,
  RefundDto,
  RegisterReaderDto,
  RemoveDiscountDto,
  SendReceiptDto,
  SimulateTapDto,
  SplitDto,
  TablePayConfirmDto,
  TablePayIntentDto,
  TapToPayDto,
  TerminalChargeDto,
} from './dto/billing.dto';

@ApiTags('billing')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('billing')
export class BillingController {
  constructor(
    private readonly billing: BillingService,
    private readonly terminal: TerminalService,
    private readonly receipts: ReceiptsService,
  ) {}

  /** Qué formas de enviar el recibo están configuradas (email, SMS). */
  @RequirePermissions('payments.take')
  @Get('receipts/config')
  receiptConfig() {
    return this.receipts.config();
  }

  /** La cuenta antes de pagar (pre-cuenta) para imprimir o mostrar, con el QR de pago de la mesa. */
  @RequirePermissions('payments.take')
  @Get('bills/:id/check')
  check(@Param('id') id: string) {
    return this.receipts.check(id);
  }

  /** El recibo para imprimir el ticket (con el enlace del QR). */
  @RequirePermissions('payments.take')
  @Get('bills/:id/receipt')
  receipt(@Param('id') id: string) {
    return this.receipts.forStaff(id);
  }

  @RequirePermissions('payments.take')
  @Post('bills/:id/receipt')
  @HttpCode(200)
  sendReceipt(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SendReceiptDto) {
    return this.receipts.send(actor, id, dto);
  }

  /** Cobro con el lector: manda el monto; el cliente paga en el lector. */
  @RequirePermissions('payments.take')
  @Post('bills/:id/terminal')
  charge(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: TerminalChargeDto) {
    return this.terminal.charge(actor, id, dto);
  }

  /** Tap to Pay: crea el cobro para que este aparato lo cobre con su NFC. */
  @RequirePermissions('payments.take')
  @Post('bills/:id/tap-to-pay')
  tapToPay(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: TapToPayDto) {
    return this.terminal.tapToPay(actor, id, dto);
  }

  @RequirePermissions('payments.take')
  @Get('terminal/:paymentId')
  terminalStatus(@CurrentActor() actor: EmployeeActor, @Param('paymentId') paymentId: string) {
    return this.terminal.status(actor, paymentId);
  }

  @RequirePermissions('payments.take')
  @Post('terminal/:paymentId/cancel')
  @HttpCode(200)
  cancelTerminal(@CurrentActor() actor: EmployeeActor, @Param('paymentId') paymentId: string) {
    return this.terminal.cancel(actor, paymentId);
  }

  /** Modo prueba: simula la tarjeta en el lector de prueba. */
  @RequirePermissions('payments.take')
  @Post('terminal/:paymentId/simulate')
  @HttpCode(200)
  simulate(@Param('paymentId') paymentId: string, @Body() dto: SimulateTapDto) {
    return this.terminal.simulate(paymentId, dto.tip, dto.declined);
  }

  @RequirePermissions('payments.take')
  @Get('bills')
  list(@Query() query: BillsQueryDto) {
    return this.billing.list(query.tableId, query.scope);
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

  /** Reembolso: permiso payments.refund, o PIN de un gerente. */
  @RequirePermissions('payments.take')
  @Post('payments/:id/refunds')
  refund(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: RefundDto) {
    return this.billing.refund(actor, id, dto);
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

@ApiTags('terminal')
@ApiBearerAuth()
@AllowActors('employee')
@Controller('terminal')
export class TerminalController {
  constructor(private readonly terminal: TerminalService) {}

  @RequirePermissions('payments.take')
  @Get('config')
  config() {
    return this.terminal.config();
  }

  /** Tap to Pay: token de conexión para el SDK de Stripe en el aparato. */
  @RequirePermissions('payments.take')
  @Post('connection-token')
  @HttpCode(200)
  connectionToken() {
    return this.terminal.connectionToken();
  }

  @RequirePermissions('payments.take')
  @Get('readers')
  readers() {
    return this.terminal.readers();
  }

  @RequirePermissions('devices.manage')
  @Post('readers')
  register(@CurrentActor() actor: EmployeeActor, @Body() dto: RegisterReaderDto) {
    return this.terminal.register(actor, dto.registrationCode, dto.label);
  }

  @RequirePermissions('devices.manage')
  @Delete('readers/:id')
  remove(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.terminal.remove(actor, id);
  }
}

/**
 * Pagar desde la mesa: lo abre el cliente en su celular al escanear el QR de la tablet.
 * Público: el enlace firmado de la visita es la llave, y deja de servir al cerrar la mesa.
 */
@ApiTags('table-pay')
@Public()
@Controller('pay')
export class TablePayController {
  constructor(private readonly tablePay: TablePayService) {}

  @Get(':token')
  view(@Param('token') token: string) {
    return this.tablePay.view(token);
  }

  @Post(':token/intent')
  @HttpCode(200)
  intent(@Param('token') token: string, @Body() dto: TablePayIntentDto) {
    return this.tablePay.intent(token, dto);
  }

  @Post(':token/confirm')
  @HttpCode(200)
  confirm(@Param('token') token: string, @Body() dto: TablePayConfirmDto) {
    return this.tablePay.confirm(token, dto);
  }
}

/** Recibo digital: lo abre el cliente desde el email, el SMS o el QR del ticket. */
@ApiTags('receipts')
@Public()
@Controller('receipts')
export class ReceiptsController {
  constructor(private readonly receipts: ReceiptsService) {}

  @Get(':token')
  view(@Param('token') token: string) {
    return this.receipts.publicView(token);
  }
}
