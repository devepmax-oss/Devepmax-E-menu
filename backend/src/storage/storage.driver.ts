/** Contrato común para guardar archivos (disco local en desarrollo, S3/R2 en producción). */
export interface StorageDriver {
  /** Guarda el archivo y devuelve su URL pública. */
  put(key: string, body: Buffer, contentType: string): Promise<string>;
  delete(key: string): Promise<void>;
  /** Devuelve la clave interna si la URL pertenece a este almacenamiento. */
  keyFromUrl(url: string): string | null;
}

export const STORAGE_DRIVER = Symbol('STORAGE_DRIVER');

export function keyFromPublicUrl(baseUrl: string, url: string): string | null {
  const prefix = `${baseUrl}/`;
  if (!url.startsWith(prefix)) return null;
  const key = decodeURIComponent(url.slice(prefix.length));
  return key && !key.includes('..') ? key : null;
}
