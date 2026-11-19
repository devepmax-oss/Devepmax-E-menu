import { SelectionType } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsEnum,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import { ALLERGENS } from '../menu.rules';

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
const MONEY = { maxDecimalPlaces: 2 } as const;

/** Traducciones por idioma, p. ej. { en: { name: "…", description: "…" } } */
type Translations = Record<string, Record<string, unknown>>;

// ───────── Estaciones de cocina ─────────

export class CreateStationDto {
  @IsString() @MinLength(1) @MaxLength(60) name: string;
  @IsOptional() @Matches(HEX_COLOR, { message: 'Color en formato #RRGGBB' }) color?: string;
  @IsOptional() @IsInt() @Min(0) sortOrder?: number;
}

export class UpdateStationDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(60) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @Matches(HEX_COLOR) color?: string | null;
  @IsOptional() @IsInt() @Min(0) sortOrder?: number;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

// ───────── Impuestos ─────────

export class CreateTaxRateDto {
  @IsString() @MinLength(1) @MaxLength(60) name: string;
  /** Fracción: 0.08875 = 8.875 % */
  @IsNumber({ maxDecimalPlaces: 4 }) @Min(0) @Max(1) rate: number;
  @IsOptional() @IsBoolean() isDefault?: boolean;
}

export class UpdateTaxRateDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(60) name?: string;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 4 }) @Min(0) @Max(1) rate?: number;
  @IsOptional() @IsBoolean() isDefault?: boolean;
}

// ───────── Categorías ─────────

export class CreateCategoryDto {
  @IsString() @MinLength(1) @MaxLength(80) name: string;
  @IsOptional() @IsObject() translations?: Translations;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional() @IsBoolean() visibleDineIn?: boolean;
  @IsOptional() @IsBoolean() visibleOnline?: boolean;
}

export class UpdateCategoryDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsObject() translations?: Translations | null;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional() @IsBoolean() visibleDineIn?: boolean;
  @IsOptional() @IsBoolean() visibleOnline?: boolean;
}

export class ReorderDto {
  /** IDs en el orden deseado. */
  @IsArray() @ArrayUnique() @ArrayMaxSize(500) @IsString({ each: true }) ids: string[];
}

// ───────── Productos ─────────

export class CreateProductDto {
  @IsString() categoryId: string;
  @IsString() @MinLength(1) @MaxLength(120) name: string;
  @IsOptional() @IsString() @MaxLength(1000) description?: string;
  @IsOptional() @IsObject() translations?: Translations;
  @IsNumber(MONEY) @Min(0) @Max(100000) price: number;
  @IsOptional() @IsString() stationId?: string;
  /** Sin valor = impuesto por defecto del restaurante. */
  @IsOptional() @IsString() taxRateId?: string;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional() @IsBoolean() isAvailable?: boolean;
  @IsOptional() @IsBoolean() visibleDineIn?: boolean;
  @IsOptional() @IsBoolean() visibleOnline?: boolean;
  @IsOptional() @IsArray() @ArrayUnique() @IsIn(ALLERGENS, { each: true }) allergens?: string[];
  @IsOptional() @IsInt() @Min(0) @Max(240) prepTimeMinutes?: number;
  /** Grupos de modificadores en el orden en que se muestran. */
  @IsOptional() @IsArray() @ArrayUnique() @ArrayMaxSize(30) @IsString({ each: true }) modifierGroupIds?: string[];
}

export class UpdateProductDto {
  @IsOptional() @IsString() categoryId?: string;
  @IsOptional() @IsString() @MinLength(1) @MaxLength(120) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(1000) description?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsObject() translations?: Translations | null;
  @IsOptional() @IsNumber(MONEY) @Min(0) @Max(100000) price?: number;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() stationId?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() taxRateId?: string | null;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional() @IsBoolean() isAvailable?: boolean;
  @IsOptional() @IsBoolean() visibleDineIn?: boolean;
  @IsOptional() @IsBoolean() visibleOnline?: boolean;
  @IsOptional() @IsArray() @ArrayUnique() @IsIn(ALLERGENS, { each: true }) allergens?: string[];
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(0) @Max(240) prepTimeMinutes?: number | null;
  @IsOptional() @IsArray() @ArrayUnique() @ArrayMaxSize(30) @IsString({ each: true }) modifierGroupIds?: string[];
}

export class AvailabilityDto {
  @IsBoolean() isAvailable: boolean;
}

// ───────── Modificadores ─────────

export class CreateModifierOptionDto {
  @IsString() @MinLength(1) @MaxLength(80) name: string;
  @IsOptional() @IsObject() translations?: Translations;
  /** Puede ser negativo (p. ej. "sin queso -$0.50"). */
  @IsOptional() @IsNumber(MONEY) @Min(-1000) @Max(1000) priceAdjustment?: number;
  @IsOptional() @IsBoolean() isDefault?: boolean;
  @IsOptional() @IsBoolean() isAvailable?: boolean;
  @IsOptional() @IsInt() @Min(0) sortOrder?: number;
}

export class UpdateModifierOptionDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsObject() translations?: Translations | null;
  @IsOptional() @IsNumber(MONEY) @Min(-1000) @Max(1000) priceAdjustment?: number;
  @IsOptional() @IsBoolean() isDefault?: boolean;
  @IsOptional() @IsBoolean() isAvailable?: boolean;
  @IsOptional() @IsInt() @Min(0) sortOrder?: number;
}

export class CreateModifierGroupDto {
  @IsString() @MinLength(1) @MaxLength(80) name: string;
  @IsOptional() @IsObject() translations?: Translations;
  @IsEnum(SelectionType) selectionType: SelectionType;
  @IsInt() @Min(0) @Max(50) minSelect: number;
  @IsInt() @Min(1) @Max(50) maxSelect: number;
  @IsOptional() @IsBoolean() isActive?: boolean;
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => CreateModifierOptionDto)
  options?: CreateModifierOptionDto[];
}

export class UpdateModifierGroupDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsObject() translations?: Translations | null;
  @IsOptional() @IsEnum(SelectionType) selectionType?: SelectionType;
  @IsOptional() @IsInt() @Min(0) @Max(50) minSelect?: number;
  @IsOptional() @IsInt() @Min(1) @Max(50) maxSelect?: number;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

// ───────── Menú público ─────────

export class MenuQueryDto {
  /** dine_in = tablets y POS; online = web pública. */
  @IsOptional() @IsIn(['dine_in', 'online']) channel?: 'dine_in' | 'online';
}
