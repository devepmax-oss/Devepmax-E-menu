import { Global, Module } from '@nestjs/common';
import { loadEnv } from '../config/env';
import { ImageService } from './image.service';
import { LocalStorageDriver } from './local.driver';
import { S3StorageDriver } from './s3.driver';
import { STORAGE_DRIVER, StorageDriver } from './storage.driver';

@Global()
@Module({
  providers: [
    {
      provide: STORAGE_DRIVER,
      useFactory: (): StorageDriver => {
        const { storage } = loadEnv();
        return storage.driver === 's3' && storage.s3
          ? new S3StorageDriver(storage.s3)
          : new LocalStorageDriver(storage.localDir, storage.localPublicBaseUrl);
      },
    },
    ImageService,
  ],
  exports: [STORAGE_DRIVER, ImageService],
})
export class StorageModule {}
