import { IsEmail, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class LoginDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  password: string;
}

export class RefreshDto {
  @IsString()
  @MinLength(10)
  @MaxLength(200)
  refreshToken: string;
}

export class PinLoginDto {
  /** PIN de 4 a 6 dígitos. */
  @Matches(/^\d{4,6}$/, { message: 'El PIN debe tener entre 4 y 6 dígitos' })
  pin: string;
}

export class PairDeviceDto {
  /** Código de 6 dígitos generado en el panel admin. */
  @Matches(/^\d{6}$/, { message: 'El código debe tener 6 dígitos' })
  code: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;
}
