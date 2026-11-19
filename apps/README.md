# Apps Flutter

| Carpeta | App | Origen |
|---|---|---|
| `staff/` | Restaurante: POS · KDS · Mesero · Admin | Reescrita en Fase 1 (código anterior en `staff/legacy`) |
| `driver/` | Repartidores | `driver_app` (copiada tal cual en Fase 0) |
| `emenu/` | Tablets de mesa | Nueva (Fase 3) |
| `packages/core` | Modelos, cliente API, sockets, auth | Nuevo |
| `packages/ui` | Tema de marca y componentes | Nuevo |

> `driver` todavía apunta al backend viejo de Gopicadera; se migra en la Fase 2.

## Probar la app Staff

Con el backend corriendo (`backend/`: `npm run start:dev`):

```bash
cd apps/staff
flutter pub get
flutter run -d chrome --web-port 5000     # el puerto 5000 está permitido en CORS_ORIGINS
```

Otro servidor: `--dart-define=API_BASE_URL=https://api.ejemplo.com/api/v1`.
