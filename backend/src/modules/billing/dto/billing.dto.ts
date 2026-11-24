import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';

const money = { maxDecimalPlaces: 2 } as const;

export class BillsQueryDto {
  /** Solo las cuentas de esta mesa (también las ya pagadas de la visita en curso). */
  @IsOptional() @IsString() tableId?: string;
}

export class PaymentDto {
  @Matches(/^[A-Za-z0-9_-]{8,64}$/, { message: 'clientRequestId inválido' })
  clientRequestId: string;

  @IsIn(['CASH', 'CARD_TERMINAL', 'OTHER'])
  method: 'CASH' | 'CARD_TERMINAL' | 'OTHER';

  /** Lo que se abona a la cuenta (sin la propina). */
  @Type(() => Number) @IsNumber(money) @Min(0.01) @Max(100000) amount: number;

  @IsOptional() @Type(() => Number) @IsNumber(money) @Min(0) @Max(10000) tip?: number;

  /** Efectivo: con cuánto pagó el cliente (para calcular el cambio). */
  @IsOptional() @Type(() => Number) @IsNumber(money) @Min(0) @Max(100000) cashTendered?: number;

  @IsOptional() @IsString() @MaxLength(60) reference?: string;
}

export class DiscountDto {
  @IsIn(['PERCENT', 'AMOUNT']) type: 'PERCENT' | 'AMOUNT';
  @Type(() => Number) @IsNumber(money) @Min(0.01) @Max(100000) value: number;
  @IsString() @MinLength(3) @MaxLength(200) reason: string;
  /** Solo a un artículo (si falta, a toda la cuenta). */
  @IsOptional() @IsString() itemId?: string;
  /** PIN de un gerente, si quien aplica no tiene permiso de descuentos. */
  @IsOptional() @Matches(/^\d{4,6}$/, { message: 'PIN inválido' }) managerPin?: string;
}

export class RemoveDiscountDto {
  @IsOptional() @Matches(/^\d{4,6}$/, { message: 'PIN inválido' }) managerPin?: string;
}

export class SplitDto {
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(200) @IsString({ each: true }) itemIds: string[];
}

export class MergeDto {
  @IsString() targetBillId: string;
}

export class OpenShiftDto {
  @Type(() => Number) @IsNumber(money) @Min(0) @Max(100000) openingCash: number;
}

export class CashMovementDto {
  @IsIn(['PAY_IN', 'PAY_OUT', 'DROP']) type: 'PAY_IN' | 'PAY_OUT' | 'DROP';
  @Type(() => Number) @IsNumber(money) @Min(0.01) @Max(100000) amount: number;
  @IsString() @MinLength(3) @MaxLength(200) reason: string;
}

export class CloseShiftDto {
  @Type(() => Number) @IsNumber(money) @Min(0) @Max(1000000) countedCash: number;
  @IsOptional() @IsString() @MaxLength(500) notes?: string;
}

export class TerminalChargeDto {
  @Matches(/^[A-Za-z0-9_-]{8,64}$/, { message: 'clientRequestId inválido' })
  clientRequestId: string;

  @IsString() @Matches(/^tmr_/, { message: 'Lector inválido' }) readerId: string;

  /** Lo que se abona a la cuenta; la propina la elige el cliente en el lector. */
  @Type(() => Number) @IsNumber(money) @Min(0.5) @Max(100000) amount: number;

  @IsOptional() @IsBoolean() tipOnReader?: boolean;
}

export class RegisterReaderDto {
  @IsString() @MinLength(3) @MaxLength(60) registrationCode: string;
  @IsString() @MinLength(2) @MaxLength(40) label: string;
}

export class SimulateTapDto {
  @IsOptional() @Type(() => Number) @IsNumber(money) @Min(0) @Max(10000) tip?: number;
  /** Simular una tarjeta rechazada. */
  @IsOptional() @IsBoolean() declined?: boolean;
}
