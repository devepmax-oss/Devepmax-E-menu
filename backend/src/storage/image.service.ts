import { BadRequestException, Inject, Injectable, Logger } from '@nestjs/common';
import { generateToken } from '../common/crypto';
import { STORAGE_DRIVER, StorageDriver } from './storage.driver';

export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
export const ACCEPTED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
const MAX_WIDTH = 1600;

/** Optimiza (WebP, máx. 1600 px) y guarda imágenes del menú. */
@Injectable()
export class ImageService {
  private readonly logger = new Logger(ImageService.name);

  constructor(@Inject(STORAGE_DRIVER) private readonly storage: StorageDriver) {}

  async save(folder: string, file: { buffer: Buffer; mimetype: string; size: number }): Promise<string> {
    if (!ACCEPTED_IMAGE_TYPES.includes(file.mimetype)) {
      throw new BadRequestException('Formato no admitido. Usa JPG, PNG, WebP o AVIF.');
    }
    if (file.size > MAX_IMAGE_BYTES) {
      throw new BadRequestException('La imagen supera 8 MB.');
    }

    const { default: sharp } = await import('sharp');
    let optimized: Buffer;
    try {
      optimized = await sharp(file.buffer)
        .rotate()
        .resize({ width: MAX_WIDTH, withoutEnlargement: true })
        .webp({ quality: 82 })
        .toBuffer();
    } catch {
      throw new BadRequestException('El archivo no es una imagen válida.');
    }

    const key = `${folder}/${Date.now()}-${generateToken(8)}.webp`;
    return this.storage.put(key, optimized, 'image/webp');
  }

  /** Borra una imagen previa. Nunca falla la operación principal por esto. */
  async remove(url: string | null | undefined): Promise<void> {
    if (!url) return;
    const key = this.storage.keyFromUrl(url);
    if (!key) return;
    try {
      await this.storage.delete(key);
    } catch (error) {
      this.logger.warn(`No se pudo borrar la imagen ${key}: ${String(error)}`);
    }
  }
}
