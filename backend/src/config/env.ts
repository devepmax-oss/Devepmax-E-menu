export interface S3StorageConfig {
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  publicBaseUrl: string;
}

export interface StorageConfig {
  driver: 'local' | 's3';
  /** Carpeta de archivos cuando driver = local. */
  localDir: string;
  /** URL pública base de los archivos locales (normalmente la del backend). */
  localPublicBaseUrl: string;
  s3?: S3StorageConfig;
}

export interface Env {
  port: number;
  nodeEnv: string;
  corsOrigins: string[];
  jwtAccessSecret: string;
  pinPepper: string;
  accessTokenTtlSeconds: number;
  refreshTokenDays: number;
  storage: StorageConfig;
  /** Pagos en línea. Sin STRIPE_SECRET_KEY la web solo ofrece pagar al recoger. */
  stripe: StripeConfig;
  /** Notificaciones push (Firebase). Sin archivo, no se envían y todo lo demás sigue igual. */
  firebaseServiceAccountPath?: string;
}

export interface StripeConfig {
  secretKey?: string;
  publishableKey?: string;
  webhookSecret?: string;
}

let cached: Env | undefined;

function requiredSecret(name: string): string {
  const value = process.env[name]?.trim();
  if (!value || value.length < 32) {
    throw new Error(`La variable ${name} es obligatoria y debe tener al menos 32 caracteres.`);
  }
  return value;
}

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`La variable ${name} es obligatoria.`);
  return value;
}

function stripTrailingSlash(url: string): string {
  return url.replace(/\/+$/, '');
}

function loadStorage(port: number): StorageConfig {
  const driver = (process.env.STORAGE_DRIVER ?? 'local').trim().toLowerCase();
  if (driver !== 'local' && driver !== 's3') {
    throw new Error('STORAGE_DRIVER debe ser "local" o "s3".');
  }
  const config: StorageConfig = {
    driver,
    localDir: process.env.STORAGE_LOCAL_DIR?.trim() || 'uploads',
    localPublicBaseUrl: stripTrailingSlash(
      process.env.PUBLIC_BASE_URL?.trim() || `http://localhost:${port}`,
    ),
  };
  if (driver === 's3') {
    config.s3 = {
      endpoint: required('S3_ENDPOINT'),
      region: process.env.S3_REGION?.trim() || 'auto',
      bucket: required('S3_BUCKET'),
      accessKeyId: required('S3_ACCESS_KEY_ID'),
      secretAccessKey: required('S3_SECRET_ACCESS_KEY'),
      publicBaseUrl: stripTrailingSlash(required('S3_PUBLIC_BASE_URL')),
    };
  }
  return config;
}

/** Lee y valida la configuración una sola vez. Falla al arrancar si falta algo crítico. */
export function loadEnv(): Env {
  if (cached) return cached;

  try {
    process.loadEnvFile();
  } catch {
    // Sin archivo .env: se usan las variables del sistema (producción).
  }

  const port = Number(process.env.PORT) || 3000;
  cached = {
    port,
    nodeEnv: process.env.NODE_ENV ?? 'development',
    corsOrigins: (process.env.CORS_ORIGINS ?? '')
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    jwtAccessSecret: requiredSecret('JWT_ACCESS_SECRET'),
    pinPepper: requiredSecret('PIN_PEPPER'),
    accessTokenTtlSeconds: Number(process.env.ACCESS_TOKEN_TTL_SECONDS) || 900,
    refreshTokenDays: Number(process.env.REFRESH_TOKEN_DAYS) || 30,
    storage: loadStorage(port),
    firebaseServiceAccountPath: process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim() || undefined,
    stripe: {
      secretKey: process.env.STRIPE_SECRET_KEY?.trim() || undefined,
      publishableKey: process.env.STRIPE_PUBLISHABLE_KEY?.trim() || undefined,
      webhookSecret: process.env.STRIPE_WEBHOOK_SECRET?.trim() || undefined,
    },
  };
  return cached;
}
