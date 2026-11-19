export interface Env {
  port: number;
  nodeEnv: string;
  corsOrigins: string[];
  jwtAccessSecret: string;
  pinPepper: string;
  accessTokenTtlSeconds: number;
  refreshTokenDays: number;
}

let cached: Env | undefined;

function requiredSecret(name: string): string {
  const value = process.env[name]?.trim();
  if (!value || value.length < 32) {
    throw new Error(`La variable ${name} es obligatoria y debe tener al menos 32 caracteres.`);
  }
  return value;
}

/** Lee y valida la configuración una sola vez. Falla al arrancar si falta algo crítico. */
export function loadEnv(): Env {
  if (cached) return cached;

  try {
    process.loadEnvFile();
  } catch {
    // Sin archivo .env: se usan las variables del sistema (producción).
  }

  cached = {
    port: Number(process.env.PORT) || 3000,
    nodeEnv: process.env.NODE_ENV ?? 'development',
    corsOrigins: (process.env.CORS_ORIGINS ?? '')
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    jwtAccessSecret: requiredSecret('JWT_ACCESS_SECRET'),
    pinPepper: requiredSecret('PIN_PEPPER'),
    accessTokenTtlSeconds: Number(process.env.ACCESS_TOKEN_TTL_SECONDS) || 900,
    refreshTokenDays: Number(process.env.REFRESH_TOKEN_DAYS) || 30,
  };
  return cached;
}
