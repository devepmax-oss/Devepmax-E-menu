import {
  IsBoolean,
  IsEmail,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  ValidateIf,
} from 'class-validator';

export class CreateEmployeeDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  phone?: string;

  @IsString()
  roleId: string;

  /** Necesaria para entrar al panel o a la app de repartidor. */
  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(200)
  password?: string;

  /** Genera un PIN de 6 dígitos para entrar rápido en POS/KDS. Se devuelve una sola vez. */
  @IsOptional()
  @IsBoolean()
  generatePin?: boolean;
}

export class UpdateEmployeeDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name?: string;

  /** null para quitar el email. */
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsEmail()
  email?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(30)
  phone?: string | null;

  @IsOptional()
  @IsString()
  roleId?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(200)
  password?: string;

  /** Genera un PIN nuevo (el anterior deja de funcionar). Se devuelve una sola vez. */
  @IsOptional()
  @IsBoolean()
  regeneratePin?: boolean;

  @IsOptional()
  @IsBoolean()
  removePin?: boolean;
}
