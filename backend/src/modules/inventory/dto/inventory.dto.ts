import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import { UNITS } from '../inventory.rules';

export class InventorySettingsDto {
  @IsOptional() @IsBoolean() enabled?: boolean;
  @IsOptional() @IsBoolean() autoSoldOut?: boolean;
}

export class ItemDto {
  @IsString() @MinLength(2) @MaxLength(80) name: string;
  @IsIn(UNITS) unit: (typeof UNITS)[number];
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) minLevel?: number | null;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 4 }) @Min(0) costPerUnit?: number;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(40) supplierId?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(40) sku?: string | null;
  @IsOptional() @IsBoolean() isActive?: boolean;
  /** Solo al crear: lo que hay ahora. */
  @IsOptional() @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) onHand?: number;
}

export class CountDto {
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) onHand: number;
  @IsOptional() @IsString() @MaxLength(200) reason?: string;
}

export class WasteDto {
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
  @IsString() @MinLength(3) @MaxLength(200) reason: string;
}

export class ReceiptLineDto {
  @IsString() @MaxLength(40) itemId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
  /** Costo por unidad del ingrediente (por g, por lb…). */
  @IsNumber({ maxDecimalPlaces: 4 }) @Min(0) unitCost: number;
}

export class ReceiptDto {
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(40) supplierId?: string | null;
  @IsOptional() @IsString() @MaxLength(60) reference?: string;
  @IsOptional() @IsString() @MaxLength(300) notes?: string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(200) @ValidateNested({ each: true }) @Type(() => ReceiptLineDto) lines: ReceiptLineDto[];
}

export class SupplierDto {
  @IsString() @MinLength(2) @MaxLength(80) name: string;
  @IsOptional() @IsString() @MaxLength(80) contactName?: string;
  @IsOptional() @IsString() @MaxLength(30) phone?: string;
  @IsOptional() @ValidateIf((_, v) => v !== '' && v !== null) @IsEmail() email?: string;
  @IsOptional() @IsString() @MaxLength(500) notes?: string;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

export class RecipeLineDto {
  @IsString() @MaxLength(40) itemId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) quantity: number;
}

export class RecipeDto {
  @IsArray() @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => RecipeLineDto) lines: RecipeLineDto[];
}

export class MovementsQueryDto {
  @IsOptional() @IsString() @MaxLength(40) itemId?: string;
  @IsOptional() @IsIn(['SALE', 'RECEIPT', 'COUNT', 'WASTE', 'ADJUST']) type?: 'SALE' | 'RECEIPT' | 'COUNT' | 'WASTE' | 'ADJUST';
}
