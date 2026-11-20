import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsDateString,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import type { PromotionType } from '../promotion.engine';

export const PROMOTION_TYPES: PromotionType[] = ['PERCENT_OFF', 'AMOUNT_OFF', 'BUY_X_GET_Y', 'COMBO_PRICE'];

export class ComboSlotDto {
  /** Ej. "Hamburguesa", "Bebida". */
  @IsString() @MinLength(1) @MaxLength(60) name: string;
  @IsInt() @Min(1) @Max(10) quantity: number;
  @IsArray() @ArrayUnique() @ArrayMaxSize(200) @IsString({ each: true }) productIds: string[];
  @IsArray() @ArrayUnique() @ArrayMaxSize(50) @IsString({ each: true }) categoryIds: string[];
}

class PromotionFieldsDto {
  @IsOptional() @IsBoolean() appliesDineIn?: boolean;
  @IsOptional() @IsBoolean() appliesOnline?: boolean;
  @IsOptional() @IsInt() @Min(0) @Max(100) priority?: number;
  @IsOptional() @IsBoolean() isActive?: boolean;

  /** PERCENT_OFF: 1–100. AMOUNT_OFF: dólares por unidad. */
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(10000) value?: number | null;
  /** BUY_X_GET_Y: compra X… */
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) @Max(20) buyQuantity?: number | null;
  /** …lleva Y gratis. */
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) @Max(20) getQuantity?: number | null;
  /** COMBO_PRICE: precio del combo completo. */
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(10000) comboPrice?: number | null;

  /** Productos y categorías a los que aplica (descuentos y 2x1). */
  @IsOptional() @IsArray() @ArrayUnique() @ArrayMaxSize(500) @IsString({ each: true }) productIds?: string[];
  @IsOptional() @IsArray() @ArrayUnique() @ArrayMaxSize(100) @IsString({ each: true }) categoryIds?: string[];

  /** Partes del combo. */
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(8)
  @ValidateNested({ each: true })
  @Type(() => ComboSlotDto)
  comboSlots?: ComboSlotDto[];
}

export class CreatePromotionDto extends PromotionFieldsDto {
  @IsString() @MinLength(1) @MaxLength(80) name: string;
  @IsOptional() @IsString() @MaxLength(300) description?: string;
  @IsOptional() @IsObject() translations?: Record<string, Record<string, unknown>>;
  @IsIn(PROMOTION_TYPES) type: PromotionType;
  @IsOptional() @IsDateString() startsAt?: string;
  @IsOptional() @IsDateString() endsAt?: string;
}

export class UpdatePromotionDto extends PromotionFieldsDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(300) description?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsObject() translations?: Record<string, Record<string, unknown>> | null;
  @IsOptional() @IsIn(PROMOTION_TYPES) type?: PromotionType;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString() startsAt?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString() endsAt?: string | null;
}

export class PublicPromotionsQueryDto {
  @IsOptional() @IsIn(['dine_in', 'online']) channel?: 'dine_in' | 'online';
}
