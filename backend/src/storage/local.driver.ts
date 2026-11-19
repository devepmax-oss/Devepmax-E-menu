import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { keyFromPublicUrl, StorageDriver } from './storage.driver';

export const LOCAL_UPLOADS_ROUTE = 'uploads';

export class LocalStorageDriver implements StorageDriver {
  private readonly root: string;
  private readonly baseUrl: string;

  constructor(directory: string, publicBaseUrl: string) {
    this.root = resolve(directory);
    this.baseUrl = `${publicBaseUrl}/${LOCAL_UPLOADS_ROUTE}`;
  }

  async put(key: string, body: Buffer): Promise<string> {
    const path = this.pathFor(key);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, body);
    return `${this.baseUrl}/${key}`;
  }

  async delete(key: string): Promise<void> {
    await rm(this.pathFor(key), { force: true });
  }

  keyFromUrl(url: string): string | null {
    return keyFromPublicUrl(this.baseUrl, url);
  }

  private pathFor(key: string): string {
    const path = resolve(join(this.root, key));
    if (!path.startsWith(this.root)) throw new Error('Ruta de archivo inválida');
    return path;
  }
}
