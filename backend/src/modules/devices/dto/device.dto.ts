import { DeviceType } from '@prisma/client';
import { IsBoolean, IsEnum, IsOptional, IsString, MaxLength, MinLength, ValidateIf } from 'class-validator';

export class CreateDeviceDto {
  @IsString()
  @MinLength(1)
  @MaxLength(60)
  name: string;

  @IsEnum(DeviceType)
  type: DeviceType;

  /** Mesa (tablets E-Menu). */
  @IsOptional()
  @IsString()
  tableId?: string;

  /** Estación de cocina (pantallas KDS). */
  @IsOptional()
  @IsString()
  stationId?: string;
}

export class UpdateDeviceDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(60)
  name?: string;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  tableId?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  stationId?: string | null;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
