import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Length, Matches, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';

/** Teléfono o email con el que el cliente entra a su cuenta. */
export class RequestCodeDto {
  @IsString() @MinLength(5) @MaxLength(120) target: string;
  @IsOptional() @IsIn(['es', 'en']) lang?: 'es' | 'en';
}

export class VerifyCodeDto {
  @IsString() @MinLength(5) @MaxLength(120) target: string;
  @Matches(/^\s*\d{6}\s*$/, { message: 'El código tiene 6 dígitos' }) code: string;
}

export class UpdateMeDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) name?: string;
  @IsOptional() @IsBoolean() marketingOptIn?: boolean;
  @IsOptional() @IsIn(['es', 'en']) lang?: 'es' | 'en';
}

export class AddressDto {
  @IsOptional() @IsString() @MaxLength(40) label?: string;
  @IsString() @MinLength(3) @MaxLength(200) street: string;
  @IsString() @MinLength(2) @MaxLength(100) city: string;
  @IsString() @Length(2, 50) state: string;
  @Matches(/^\d{5}(-\d{4})?$/, { message: 'Código postal inválido' }) zipCode: string;
  @IsOptional() @IsString() @MaxLength(300) instructions?: string;
}

export class CustomersQueryDto {
  @IsOptional() @IsString() @MaxLength(80) q?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
}

export class LookupDto {
  @IsString() @MinLength(7) @MaxLength(20) phone: string;
}

/** Alta rápida desde la caja o la mesa. */
export class CreateCustomerDto {
  @IsString() @MinLength(2) @MaxLength(80) name: string;
  @Matches(/^[0-9+()\-.\s]{7,20}$/, { message: 'Teléfono inválido' }) phone: string;
  @IsOptional() @IsString() @MaxLength(120) email?: string;
}

export class UpdateCustomerDto {
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) name?: string;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(1000) notes?: string | null;
  @IsOptional() @IsBoolean() marketingOptIn?: boolean;
}

export class AttachCustomerDto {
  /** null = quitar el cliente de la cuenta. */
  @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(40) customerId: string | null;
}
