import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { loadEnv } from './config/env';

async function bootstrap(): Promise<void> {
  const env = loadEnv();
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.enableCors({ origin: env.corsOrigins, credentials: true });
  app.enableShutdownHooks();

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
