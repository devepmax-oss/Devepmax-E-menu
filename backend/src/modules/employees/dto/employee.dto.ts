import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsEmail,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
import { Type } from 'class-transformer';
import { PERMISSIONS } from '../../../common/permissions';

const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** Datos de la ficha. En la edición, null borra el dato. */
class EmployeeProfileDto {
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(80)
  jobTitle?: string | null;

  /** Fecha de ingreso (AAAA-MM-DD). */
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @Matches(DATE, { message: 'La fecha de ingreso debe ser AAAA-MM-DD' })
  hireDate?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(200)
  address?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(100)
  emergencyName?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(30)
  emergencyPhone?: string | null;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(2000)
  notes?: string | null;
}

export class CreateEmployeeDto extends EmployeeProfileDto {
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

export class UpdateEmployeeDto extends EmployeeProfileDto {
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

  /** false = dar de baja (cierra sus sesiones; su historial se conserva). true = reactivar. */
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  /** Motivo de la baja (solo con isActive: false). */
  @IsOptional()
  @IsString()
  @MaxLength(300)
  terminationReason?: string;

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

export class EmployeeHistoryQueryDto {
  /** all = todo; about = cambios a su ficha y accesos; actions = lo que hizo. */
  @IsOptional()
  @IsIn(['all', 'about', 'actions'])
  scope?: 'all' | 'about' | 'actions';

  @IsOptional()
  @IsString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  take?: number;
}

export class SaveRoleDto {
  @IsString()
  @MinLength(1)
  @MaxLength(40)
  name: string;

  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsString()
  @MaxLength(200)
  description?: string | null;

  @IsArray()
  @ArrayUnique()
  @ArrayMaxSize(PERMISSIONS.length)
  @IsIn(PERMISSIONS as unknown as string[], { each: true, message: 'Permiso desconocido' })
  permissions: string[];
}
