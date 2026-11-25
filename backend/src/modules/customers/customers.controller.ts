import { Body, Controller, Delete, ForbiddenException, Get, Headers, HttpCode, Ip, Param, Patch, Post, Query, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { CUSTOMER_TOKEN_HEADER, CustomerAuthService } from './customer-auth.service';
import { CustomersService } from './customers.service';
import {
  AddressDto,
  AttachCustomerDto,
  CreateCustomerDto,
  CustomersQueryDto,
  GoogleSignInDto,
  LookupDto,
  RequestCodeDto,
  UpdateCustomerDto,
  UpdateMeDto,
  VerifyCodeDto,
} from './dto/customers.dto';

/** Entrar a la cuenta de cliente con un código (web). */
@ApiTags('cuenta de cliente')
@Controller('customer-auth')
export class CustomerAuthController {
  constructor(
    private readonly auth: CustomerAuthService,
    private readonly customers: CustomersService,
  ) {}

  @Public()
  @Post('request')
  @HttpCode(200)
  request(@Body() dto: RequestCodeDto, @Ip() ip: string) {
    return this.auth.requestCode(dto.target, ip, dto.lang);
  }

  @Public()
  @Post('verify')
  @HttpCode(200)
  async verify(@Body() dto: VerifyCodeDto, @Ip() ip: string) {
    const { token } = await this.auth.verify(dto.target, dto.code, ip);
    const customer = await this.auth.resolve(token);
    return { token, customer: await this.customers.profile(customer!) };
  }

  @Public()
  @Get('options')
  options() {
    return this.auth.options();
  }

  @Public()
  @Post('google')
  @HttpCode(200)
  async google(@Body() dto: GoogleSignInDto, @Ip() ip: string) {
    const { token } = await this.auth.google(dto.credential, ip);
    const customer = await this.auth.resolve(token);
    return { token, customer: await this.customers.profile(customer!) };
  }

  @Public()
  @Post('logout')
  @HttpCode(204)
  async logout(@Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    await this.auth.logout(token);
  }
}

/** La cuenta del cliente: datos, direcciones y pedidos. Se identifica con el encabezado x-customer-token. */
@ApiTags('cuenta de cliente')
@Controller('me')
export class MeController {
  constructor(
    private readonly auth: CustomerAuthService,
    private readonly customers: CustomersService,
  ) {}

  private async me(token?: string) {
    const customer = await this.auth.resolve(token);
    if (!customer) throw new UnauthorizedException('Entra a tu cuenta');
    return customer;
  }

  @Public()
  @Get()
  async profile(@Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.profile(await this.me(token));
  }

  @Public()
  @Patch()
  async update(@Body() dto: UpdateMeDto, @Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.updateMe(await this.me(token), dto);
  }

  @Public()
  @Post('addresses')
  async addAddress(@Body() dto: AddressDto, @Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.addAddress(await this.me(token), dto);
  }

  @Public()
  @Patch('addresses/:id')
  async updateAddress(@Param('id') id: string, @Body() dto: AddressDto, @Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.updateAddress(await this.me(token), id, dto);
  }

  @Public()
  @Delete('addresses/:id')
  async removeAddress(@Param('id') id: string, @Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.removeAddress(await this.me(token), id);
  }

  @Public()
  @Get('orders')
  async orders(@Headers(CUSTOMER_TOKEN_HEADER) token?: string) {
    return this.customers.history((await this.me(token)).id);
  }
}

/** Clientes para el personal. */
@ApiTags('clientes')
@ApiBearerAuth()
@AllowActors('employee')
@Controller()
export class CustomersController {
  constructor(private readonly customers: CustomersService) {}

  /** Buscar o dar de alta un cliente basta con atender mesas, tomar pedidos o cobrar. */
  private assertFrontOfHouse(actor: EmployeeActor) {
    const p = actor.permissions;
    if (!p.has('orders.create') && !p.has('payments.take') && !p.has('tables.operate')) {
      throw new ForbiddenException('Permiso requerido: orders.create');
    }
  }

  @RequirePermissions('customers.manage')
  @Get('customers')
  list(@Query() query: CustomersQueryDto) {
    return this.customers.list(query);
  }

  @Get('customers/lookup')
  lookup(@CurrentActor() actor: EmployeeActor, @Query() query: LookupDto) {
    this.assertFrontOfHouse(actor);
    return this.customers.lookup(query.phone);
  }

  @Post('customers')
  create(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateCustomerDto) {
    this.assertFrontOfHouse(actor);
    return this.customers.create(actor, dto);
  }

  @RequirePermissions('customers.manage')
  @Get('customers/:id')
  detail(@Param('id') id: string) {
    return this.customers.detail(id);
  }

  @RequirePermissions('customers.manage')
  @Patch('customers/:id')
  update(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateCustomerDto) {
    return this.customers.update(actor, id, dto);
  }

  @Patch('tables/:id/customer')
  attachToTable(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: AttachCustomerDto) {
    this.assertFrontOfHouse(actor);
    return this.customers.attachToTable(actor, id, dto.customerId);
  }

  @Patch('billing/bills/:id/customer')
  attach(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: AttachCustomerDto) {
    this.assertFrontOfHouse(actor);
    return this.customers.attach(actor, id, dto.customerId);
  }
}
