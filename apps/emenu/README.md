# App E-Menu (tablets de mesa)

App Flutter para las tablets de las mesas (Android, horizontal, pantalla completa).

- **Vincular**: en la app Staff → Dispositivos → Tablet de mesa → *Generar código*.
  La tablet escanea el QR (o se escribe el código de 6 dígitos).
- **El cliente**: ve el menú, arma su pedido y lo envía a cocina; sigue el estado,
  ve su cuenta, llama al mesero o pide la cuenta.
- **Personal**: mantener presionado el logo 3 segundos → PIN → recargar, volver a la
  bienvenida o desvincular.

## Correr en desarrollo

```
flutter pub get
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

En Chrome: `flutter run -d chrome --web-port 5002` (agregar `http://localhost:5002` a `CORS_ORIGINS`).
