import { IsBoolean, IsIn, IsInt, IsISO8601, IsNumber, IsOptional, IsString, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';

export class CouponDto {
  @IsString() @MinLength(3) @MaxLength(30) code: string;
  @IsOptional() @IsString() @MaxLength(80) name?: string;
  @IsIn(['PERCENT', 'AMOUNT', 'FREE_DELIVERY']) type: 'PERCENT' | 'AMOUNT' | 'FREE_DELIVERY';
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) value?: number | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) maxDiscount?: number | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) minOrderTotal?: number | null;
  @IsOptional() @IsBoolean() appliesOnline?: boolean;
  @IsOptional() @IsBoolean() appliesInStore?: boolean;
  @IsOptional() @IsBoolean() firstOrderOnly?: boolean;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) maxUses?: number | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) maxUsesPerCustomer?: number | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsISO8601() startsAt?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsISO8601() endsAt?: string | null;
  /** Cupón personal: solo ese cliente. */
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(40) customerId?: string | null;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

export class ApplyCouponDto {
  @IsString() @MinLength(3) @MaxLength(30) code: string;
}
