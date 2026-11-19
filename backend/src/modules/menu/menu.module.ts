import { Module } from '@nestjs/common';
import { CategoriesService } from './categories.service';
import { MenuSetupController } from './menu-setup.controller';
import { MenuController } from './menu.controller';
import { MenuService } from './menu.service';
import { ModifiersService } from './modifiers.service';
import { ProductsService } from './products.service';
import { StationsService } from './stations.service';
import { TaxRatesService } from './tax-rates.service';

@Module({
  controllers: [MenuController, MenuSetupController],
  providers: [MenuService, CategoriesService, ProductsService, ModifiersService, StationsService, TaxRatesService],
  exports: [MenuService],
})
export class MenuModule {}
