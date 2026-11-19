# Devepmax E-Menu

Plataforma para restaurantes: **menú electrónico en mesas (E-Menu), POS, pantalla de cocina (KDS), pedidos online y delivery propio**, todo conectado a un único motor de órdenes en tiempo real.

Cada restaurante tiene su **propia instalación** del mismo producto, adaptada a su marca y menú desde la configuración. Primer restaurante: **Picadera** — `gopicadera.online`.

## Estructura

```
backend/            API NestJS + Prisma + PostgreSQL + Socket.IO
web/                Web pública de pedidos online (Next.js)
apps/staff/         App Flutter del restaurante (POS · KDS · Mesero · Admin)
apps/driver/        App Flutter de repartidores
apps/emenu/         App Flutter para tablets de mesa (Fase 3)
apps/packages/      Paquetes Flutter compartidos (core, ui)
infra/              Docker y scripts de instalación
docs/               Diseño del sistema y decisiones
```

El diseño completo (arquitectura, modelo de datos, flujos, permisos y fases) está en [`docs/diseno-sistema.md`](docs/diseno-sistema.md).

## Requisitos

- Git
- Node.js 20 o superior
- Flutter (canal stable)
- Docker Desktop

## Arranque local

```bash
# 1. Base de datos
docker compose -f infra/docker-compose.yml up -d

# 2. Backend
cd backend
cp .env.example .env
npm install
npm run start:dev          # http://localhost:3000/api/v1/health

# 3. Web
cd ../web
npm install
npm run dev -- -p 3001     # requiere NEXT_PUBLIC_API_URL en web/.env.local

# 4. Apps Flutter
cd ../apps/staff
flutter pub get
flutter run
```

## Estado

**Fase 0 — Preparación.** Las apps `staff` y `driver` y la `web` son copias del sistema anterior (Gopicadera) y todavía apuntan a su backend en Railway. Se migran al backend nuevo a partir de la Fase 1.

## Reglas del repo

- Nunca subir secretos: `.env`, llaves de Stripe, cuentas de servicio de Firebase.
- Nada específico de un restaurante en el código: va en la base de datos / configuración.
- Precios, impuestos y estados se calculan en el backend.
