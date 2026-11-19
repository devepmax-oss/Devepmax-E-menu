import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Actor, EmployeeActor } from '../../common/auth/actor';
import { AllowActors, CurrentActor, Public, RequirePermissions } from '../../common/auth/decorators';
import { MAX_IMAGE_BYTES } from '../../storage/image.service';
import { CategoriesService } from './categories.service';
import {
  AvailabilityDto,
  CreateCategoryDto,
  CreateProductDto,
  MenuQueryDto,
  ReorderDto,
  UpdateCategoryDto,
  UpdateProductDto,
} from './dto/menu.dto';
import { MenuService } from './menu.service';
import { ProductsService } from './products.service';

const imageUpload = FileInterceptor('file', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1 } });
const imageBody = {
  schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } }, required: ['file'] },
};

function requireFile(file: Express.Multer.File | undefined): Express.Multer.File {
  if (!file) throw new BadRequestException('Falta la imagen (campo "file")');
  return file;
}

@ApiTags('menu')
@Controller('menu')
export class MenuController {
  constructor(
    private readonly menu: MenuService,
    private readonly categories: CategoriesService,
    private readonly products: ProductsService,
  ) {}

  // ───────── Lectura ─────────

  /** Menú para clientes. Las tablets usan dine_in; la web, online. */
  @Public()
  @Get()
  getMenu(@Query() query: MenuQueryDto, @CurrentActor() actor?: Actor) {
    const channel = query.channel ?? (actor ? 'dine_in' : 'online');
    return this.menu.getPublicMenu(channel);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get('admin')
  getAdmin() {
    return this.menu.getAdminMenu();
  }

  // ───────── Categorías ─────────

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('categories')
  createCategory(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateCategoryDto) {
    return this.categories.create(actor, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Put('categories/order')
  @HttpCode(204)
  reorderCategories(@CurrentActor() actor: EmployeeActor, @Body() dto: ReorderDto) {
    return this.categories.reorder(actor, dto.ids);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch('categories/:id')
  updateCategory(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateCategoryDto) {
    return this.categories.update(actor, id, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('categories/:id')
  @HttpCode(204)
  removeCategory(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.categories.remove(actor, id);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Put('categories/:id/products/order')
  @HttpCode(204)
  reorderProducts(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: ReorderDto) {
    return this.products.reorder(actor, id, dto.ids);
  }

  @ApiBearerAuth()
  @ApiConsumes('multipart/form-data')
  @ApiBody(imageBody)
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('categories/:id/image')
  @UseInterceptors(imageUpload)
  setCategoryImage(
    @CurrentActor() actor: EmployeeActor,
    @Param('id') id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.categories.setImage(actor, id, requireFile(file));
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('categories/:id/image')
  removeCategoryImage(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.categories.removeImage(actor, id);
  }

  // ───────── Productos ─────────

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Get('products/:id')
  getProduct(@Param('id') id: string) {
    return this.products.get(id);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('products')
  createProduct(@CurrentActor() actor: EmployeeActor, @Body() dto: CreateProductDto) {
    return this.products.create(actor, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Patch('products/:id')
  updateProduct(@CurrentActor() actor: EmployeeActor, @Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.products.update(actor, id, dto);
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('products/:id')
  @HttpCode(204)
  removeProduct(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.products.remove(actor, id);
  }

  /** Marcar agotado / disponible. Empleados con permiso o pantallas KDS. */
  @ApiBearerAuth()
  @RequirePermissions('product.toggle_availability')
  @Patch('products/:id/availability')
  setAvailability(@CurrentActor() actor: Actor, @Param('id') id: string, @Body() dto: AvailabilityDto) {
    return this.products.setAvailability(actor, id, dto.isAvailable);
  }

  @ApiBearerAuth()
  @ApiConsumes('multipart/form-data')
  @ApiBody(imageBody)
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Post('products/:id/image')
  @UseInterceptors(imageUpload)
  setProductImage(
    @CurrentActor() actor: EmployeeActor,
    @Param('id') id: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    return this.products.setImage(actor, id, requireFile(file));
  }

  @ApiBearerAuth()
  @AllowActors('employee')
  @RequirePermissions('menu.manage')
  @Delete('products/:id/image')
  removeProductImage(@CurrentActor() actor: EmployeeActor, @Param('id') id: string) {
    return this.products.removeImage(actor, id);
  }
}
