import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUrl,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
export const SUPPORTED_LOCALES = ['es', 'en'] as const;

export class UpdateSettingsDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(100) name?: string;
  @IsOptional() @IsString() @MaxLength(150) legalName?: string;
  @IsOptional() @IsUrl() logoUrl?: string;
  @IsOptional() @Matches(HEX_COLOR, { message: 'Color en formato #RRGGBB' }) primaryColor?: string;
  @IsOptional() @Matches(HEX_COLOR, { message: 'Color en formato #RRGGBB' }) accentColor?: string;
  @IsOptional() @IsString() @MaxLength(30) phone?: string;
  @IsOptional() @IsString() @MaxLength(30) whatsapp?: string;
  @IsOptional() @IsEmail() email?: string;
  @IsOptional() @IsString() @MaxLength(200) addressLine?: string;
  @IsOptional() @IsString() @MaxLength(100) city?: string;
  @IsOptional() @IsString() @MaxLength(50) state?: string;
  @IsOptional() @IsString() @MaxLength(15) zipCode?: string;
  @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number;
  /** { instagram: "https://…", tiktok: "https://…" } */
  @IsOptional() @IsObject() socialLinks?: Record<string, string>;
  /** Zona horaria IANA, p. ej. America/New_York. */
  @IsOptional() @IsString() @MaxLength(60) timezone?: string;
  @IsOptional() @IsString() @Length(3, 3) currency?: string;
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @IsIn(SUPPORTED_LOCALES, { each: true })
  locales?: string[];
  @IsOptional() @IsBoolean() acceptsDineIn?: boolean;
  @IsOptional() @IsBoolean() acceptsPickup?: boolean;
  @IsOptional() @IsBoolean() acceptsDelivery?: boolean;
  @IsOptional() @IsBoolean() onlineOrderingPaused?: boolean;
  @IsOptional() @IsBoolean() requireWaiterApproval?: boolean;
  @IsOptional() @IsInt() @Min(1) @Max(240) prepTimeMinutes?: number;
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5)
  @IsInt({ each: true })
  @Min(0, { each: true })
  @Max(100, { each: true })
  tipPresets?: number[];
  @IsOptional() @IsString() @MaxLength(300) receiptFooter?: string;
  @IsOptional() @IsBoolean() maintenanceMode?: boolean;
}

export class OpeningHourDto {
  /** 0 = domingo … 6 = sábado */
  @IsInt() @Min(0) @Max(6) dayOfWeek: number;
  @Matches(TIME, { message: 'Hora en formato HH:MM' }) opensAt: string;
  /** Puede ser menor que opensAt si cierra después de medianoche. */
  @Matches(TIME, { message: 'Hora en formato HH:MM' }) closesAt: string;
}

export class ReplaceOpeningHoursDto {
  @IsArray()
  @ArrayMaxSize(21)
  @ValidateNested({ each: true })
  @Type(() => OpeningHourDto)
  hours: OpeningHourDto[];
}
