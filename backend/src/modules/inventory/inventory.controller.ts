import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, RequirePermissions } from '../../common/auth/decorators';
import { CountDto, InventorySettingsDto, ItemDto, MovementsQueryDto, ReceiptDto, RecipeDto, SupplierDto, WasteDto } from './dto/inventory.dto';
import { InventoryService } from './inventory.service';

@ApiTags('inventario')
@ApiBearerAuth()
@AllowActors('employee')
@RequirePermissions('inventory.manage')
@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventory: InventoryService) {}

  @Get('summary')
  summary() {
    return this.inventory.summary();
  }

  @Patch('settings')
  settings(@CurrentActor() actor: EmployeeActor, @Body() dto: InventorySettingsDto) {
    return this.inventory.updateSettings(actor, dto);
  }

  @Get('items')
  items() {
    return this.inventory.items();
  }

  @Post('items')
  createItem(@CurrentActor() actor: EmployeeActor, @Body() dto: ItemDto) {
    return this.inventory.createItem(actor, dto);
  }

  @Patch('items/:id')
  updateItem(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: ItemDto) {
    return this.inventory.updateItem(actor, id, dto);
  }

  @Delete('items/:id')
  @HttpCode(204)
  async removeItem(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    await this.inventory.removeItem(actor, id);
  }

  @Post('items/:id/count')
  @HttpCode(200)
  count(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: CountDto) {
    return this.inventory.count(actor, id, dto);
  }

  @Post('items/:id/waste')
  @HttpCode(200)
  waste(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: WasteDto) {
    return this.inventory.waste(actor, id, dto);
  }

  @Get('movements')
  movements(@Query() q: MovementsQueryDto) {
    return this.inventory.movements(q);
  }

  @Get('receipts')
  receipts() {
    return this.inventory.receipts();
  }

  @Post('receipts')
  receive(@CurrentActor() actor: EmployeeActor, @Body() dto: ReceiptDto) {
    return this.inventory.receive(actor, dto);
  }

  @Get('suppliers')
  suppliers() {
    return this.inventory.suppliers();
  }

  @Post('suppliers')
  createSupplier(@CurrentActor() actor: EmployeeActor, @Body() dto: SupplierDto) {
    return this.inventory.saveSupplier(actor, null, dto);
  }

  @Patch('suppliers/:id')
  updateSupplier(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: SupplierDto) {
    return this.inventory.saveSupplier(actor, id, dto);
  }

  @Delete('suppliers/:id')
  @HttpCode(204)
  async removeSupplier(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    await this.inventory.removeSupplier(actor, id);
  }

  @Get('recipes')
  recipes() {
    return this.inventory.recipes();
  }

  @Put('recipes/:productId')
  saveRecipe(@CurrentActor() actor: EmployeeActor, @Param('productId') productId: string, @Body() dto: RecipeDto) {
    return this.inventory.saveRecipe(actor, productId, dto);
  }
}
