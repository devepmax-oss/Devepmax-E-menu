import { IsBoolean, IsIn, IsInt, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class UpdateDriverMeDto {
  /** Disponible para recibir entregas, o desconectado. */
  @IsOptional() @IsIn(['AVAILABLE', 'OFFLINE']) status?: 'AVAILABLE' | 'OFFLINE';
  @IsOptional() @IsString() @MaxLength(30) vehicleType?: string;
  @IsOptional() @IsString() @MaxLength(30) vehicleColor?: string;
  @IsOptional() @IsString() @MaxLength(15) vehiclePlate?: string;
}

export class DriverLocationDto {
  @IsLatitude() lat: number;
  @IsLongitude() lng: number;
}

export class AssignDriverDto {
  @IsString() driverId: string;
}

export class DeliveryZoneDto {
  @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(100) fee: number;
  @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1000) minOrder: number;
  @IsInt() @Min(5) @Max(240) etaMinutes: number;
  @IsOptional() @IsBoolean() autoAssign?: boolean;
  @IsOptional() @IsInt() @Min(30) @Max(300) offerSeconds?: number;
}
