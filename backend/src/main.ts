import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { resolve } from 'node:path';
import { loadEnv } from './config/env';
import { LOCAL_UPLOADS_ROUTE } from './storage/local.driver';

async function bootstrap(): Promise<void> {
  const env = loadEnv();
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.enableCors({ origin: env.corsOrigins, credentials: true });
  app.enableShutdownHooks();

  // En desarrollo las imágenes se sirven desde el propio backend.
  if (env.storage.driver === 'local') {
    app.useStaticAssets(resolve(env.storage.localDir), {
      prefix: `/${LOCAL_UPLOADS_ROUTE}/`,
      maxAge: '7d',
      immutable: true,
    });
  }

  // Documentación y contrato OpenAPI (de aquí se generan los clientes Dart y TS).
  const openApi = SwaggerModule.createDocument(
    app,
    new DocumentBuilder()
      .setTitle('Devepmax E-Menu API')
      .setVersion('1.0')
      .addBearerAuth()
      .build(),
  );
  SwaggerModule.setup('api/docs', app, openApi, { jsonDocumentUrl: 'api/openapi.json' });

  await app.listen(env.port);
  console.log(`Devepmax E-Menu backend escuchando en http://localhost:${env.port}/api/v1`);
  console.log(`Documentación: http://localhost:${env.port}/api/docs`);
}

void bootstrap();
