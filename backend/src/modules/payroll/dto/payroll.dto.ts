import { Type } from 'class-transformer';
import { IsIn, IsInt, IsNumber, IsOptional, Matches, Max, Min } from 'class-validator';

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MSG = { message: 'La fecha debe ser AAAA-MM-DD' };

export class PayrollQueryDto {
  /** Cualquier día de la primera semana; se usa su lunes. Sin fecha: esta semana. */
  @IsOptional() @Matches(DAY, DAY_MSG) week?: string;

  @IsOptional()
  @Type(() => Number)
  @IsIn([1, 2])
  weeks?: 1 | 2;
}

export class PerformanceQueryDto {
  @IsOptional() @Matches(DAY, DAY_MSG) from?: string;
  @IsOptional() @Matches(DAY, DAY_MSG) to?: string;
}

export class SetRateDto {
  /** Dólares por hora. */
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  @Max(500)
  hourlyRate: number;

  /** Desde qué día vale (sin fecha: hoy). Sirve para registrar un aumento con fecha. */
  @IsOptional() @Matches(DAY, DAY_MSG) effectiveFrom?: string;
}

export class PayrollSettingsDto {
  @IsOptional() @IsInt() @Min(0) @Max(80) weeklyHours?: number;
  @IsOptional() @IsInt() @Min(0) @Max(24) dailyHours?: number;
  @IsOptional() @IsInt() @Min(0) @Max(24) doubleDailyHours?: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(1) @Max(5) overtimeMultiplier?: number;
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(1) @Max(5) doubleMultiplier?: number;
}
