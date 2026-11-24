import { Module } from '@nestjs/common';
import { EmenuController } from './emenu.controller';
import { EmenuService } from './emenu.service';
import { TablesController } from './tables.controller';
import { TablesService } from './tables.service';

@Module({
  controllers: [TablesController, EmenuController],
  providers: [TablesService, EmenuService],
  exports: [TablesService],
})
export class TablesModule {}
