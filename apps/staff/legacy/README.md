# Código heredado (Gopicadera)

Pantallas y servicios de la app anterior, conectados al backend viejo. **No se compilan.**
Se conservan como referencia para portarlos al backend nuevo:

| Archivo | Se porta en |
|---|---|
| `screens/orders_dashboard_screen.dart`, `history_screen.dart` | Fase 2–3 (órdenes y KDS) |
| `screens/delivery_screen.dart` | Fase 2 (delivery) |
| `services/printer_service.dart` (ESC/POS) | Fase 4 (recibos y tickets) |
| `services/notification_service.dart`, `socket_service.dart` | Fase 2 (tiempo real y push) |
| `firebase_options.dart` | Fase 2 (configuración Firebase por instalación) |
