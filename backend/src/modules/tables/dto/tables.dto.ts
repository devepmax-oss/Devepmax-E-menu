import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export class AreaDto {
  @IsString() @MinLength(1) @MaxLength(40) name: string;
  @IsOptional() @IsInt() @Min(0) @Max(999) sortOrder?: number;
}

export class UpdateAreaDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(40) name?: string;
  @IsOptional() @IsInt() @Min(0) @Max(999) sortOrder?: number;
}

export class CreateTableDto {
  @Matches(/^[A-Za-z0-9 -]{1,10}$/, { message: 'Nombre de mesa: hasta 10 letras o números' }) label: string;
  @IsString() areaId: string;
  @IsInt() @Min(1) @Max(30) seats: number;
  @IsOptional() @IsInt() @Min(0) @Max(39) posX?: number;
  @IsOptional() @IsInt() @Min(0) @Max(39) posY?: number;
}

export class UpdateTableDto {
  @IsOptional() @Matches(/^[A-Za-z0-9 -]{1,10}$/, { message: 'Nombre de mesa: hasta 10 letras o números' }) label?: string;
  @IsOptional() @IsString() areaId?: string;
  @IsOptional() @IsInt() @Min(1) @Max(30) seats?: number;
  @IsOptional() @IsInt() @Min(0) @Max(39) posX?: number;
  @IsOptional() @IsInt() @Min(0) @Max(39) posY?: number;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

/** Crear varias mesas de una vez: 1, 2, 3… */
export class BulkTablesDto {
  @IsString() areaId: string;
  @IsInt() @Min(1) @Max(999) from: number;
  @IsInt() @Min(1) @Max(50) count: number;
  @IsInt() @Min(1) @Max(30) seats: number;
}

class TablePositionDto {
  @IsString() id: string;
  @IsInt() @Min(0) @Max(39) posX: number;
  @IsInt() @Min(0) @Max(39) posY: number;
}

export class LayoutDto {
  @IsArray() @ArrayMaxSize(300) @ValidateNested({ each: true }) @Type(() => TablePositionDto) positions: TablePositionDto[];
}

export class TableStatusDto {
  @IsIn(['AVAILABLE', 'RESERVED', 'CLEANING']) status: 'AVAILABLE' | 'RESERVED' | 'CLEANING';
}

export class OpenTableDto {
  @IsOptional() @IsInt() @Min(1) @Max(50) guestCount?: number;
}

export class CloseTableDto {
  /** Cerrar aunque la cuenta tenga saldo (mientras no exista el cobro en caja). */
  @IsOptional() @IsBoolean() force?: boolean;
}

export class ServiceRequestDto {
  @IsIn(['CALL_WAITER', 'REQUEST_BILL']) type: 'CALL_WAITER' | 'REQUEST_BILL';
}

export class ResolveRequestDto {
  @IsIn(['ACKNOWLEDGED', 'DONE']) status: 'ACKNOWLEDGED' | 'DONE';
}
