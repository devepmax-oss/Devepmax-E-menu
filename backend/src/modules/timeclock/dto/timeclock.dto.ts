import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
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

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DAY_MSG = { message: 'La fecha debe ser AAAA-MM-DD' };
const TIME_MSG = { message: 'La hora debe ser HH:MM (24 h)' };
export const CLOCK_ACTIONS = ['IN', 'BREAK_START', 'BREAK_END', 'OUT'] as const;

export class PinDto {
  @Matches(/^\d{4,8}$/, { message: 'PIN inválido' })
  pin: string;
}

export class PunchDto extends PinDto {
  @IsIn(CLOCK_ACTIONS as unknown as string[])
  action: (typeof CLOCK_ACTIONS)[number];
}

/** El gerente marca por un empleado (olvidó marcar, no hay tablet). */
export class ManagerPunchDto {
  @IsIn(CLOCK_ACTIONS as unknown as string[])
  action: (typeof CLOCK_ACTIONS)[number];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

export class EntriesQueryDto {
  @IsOptional() @Matches(DAY, DAY_MSG) from?: string;
  @IsOptional() @Matches(DAY, DAY_MSG) to?: string;
  @IsOptional() @IsString() employeeId?: string;
}

class BreakTimesDto {
  @Matches(TIME, TIME_MSG) start: string;
  @IsOptional() @Matches(TIME, TIME_MSG) end?: string;
}

/**
 * Jornada escrita a mano por el gerente. Las horas son locales del restaurante; una hora
 * antes de la entrada se entiende como del día siguiente (turno de noche).
 */
export class SaveEntryDto {
  @IsString() employeeId: string;
  @Matches(DAY, DAY_MSG) day: string;
  @Matches(TIME, TIME_MSG) clockIn: string;
  @IsOptional() @Matches(TIME, TIME_MSG) clockOut?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @ValidateNested({ each: true })
  @Type(() => BreakTimesDto)
  breaks?: BreakTimesDto[];

  /** Por qué se agrega o corrige (queda en el historial). */
  @IsString()
  @MinLength(3, { message: 'Escribe el motivo de la corrección' })
  @MaxLength(200)
  reason: string;
}

export class DeleteEntryDto {
  @IsString()
  @MinLength(3, { message: 'Escribe el motivo' })
  @MaxLength(200)
  reason: string;
}

export class WeekQueryDto {
  /** Cualquier día de la semana; se usa su lunes. Sin fecha: esta semana. */
  @IsOptional() @Matches(DAY, DAY_MSG) week?: string;
}

export class SaveShiftDto {
  @IsString() employeeId: string;
  @Matches(DAY, DAY_MSG) day: string;
  @Matches(TIME, TIME_MSG) start: string;
  /** Si es igual o anterior al inicio, termina al día siguiente. */
  @Matches(TIME, TIME_MSG) end: string;
  @IsOptional() @IsString() @MaxLength(40) position?: string;
  @IsOptional() @IsString() @MaxLength(200) note?: string;
}

export class CopyWeekDto {
  @Matches(DAY, DAY_MSG) fromWeek: string;
  @Matches(DAY, DAY_MSG) toWeek: string;
  /** Solo los turnos de este empleado (sin él: los de todos). */
  @IsOptional() @IsString() employeeId?: string;
}

export class TimeclockSettingsDto {
  /** 0 = ningún descanso se paga; 1440 = todos; N = los de hasta N minutos. */
  @IsOptional() @IsInt() @Min(0) @Max(1440) paidBreakMinutes?: number;
  @IsOptional() @IsInt() @Min(0) @Max(60) clockGraceMinutes?: number;
}
