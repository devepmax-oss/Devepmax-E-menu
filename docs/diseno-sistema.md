# Devepmax E-Menu — Diseño del sistema v1

> Producto: **Devepmax E-Menu**. Primer restaurante: **Picadera** (`gopicadera.online`).
> Basado en el prompt del proyecto, las decisiones tomadas y la evaluación del código existente (Gopicadera).

---

## 0. Decisiones confirmadas
- **Una instalación independiente por restaurante** (no SaaS multi-tenant). Mismo código; marca, menú y reglas en la base de datos.
- **Nube primero**, sin modo offline completo en v1 (reconexión, resync e idempotencia sí).
- **País: Estados Unidos** (USD, sales tax, zona horaria configurable, por defecto America/New_York).
- **Tablets: Android** (modo kiosco nativo).
- **Apps en Flutter; web pública en Next.js; backend en NestJS** (port de Gopicaderabackend).
- **WooCommerce descartado.** Delivery con repartidores propios.
- El sistema anterior **no está en uso** → sin migración de datos.

---

## 1. Principios

1. **Un producto, una instalación por restaurante.** Todo lo que cambia entre restaurantes (marca, menú, impuestos, horarios, estaciones, canales activos) vive en la base de datos y se edita desde el panel admin. Nunca forks.
2. **Un solo motor de órdenes.** Tablet de mesa, POS, mesero y web entran por el mismo servicio, con las mismas reglas.
3. **El servidor manda.** Precios, impuestos, totales, numeración y transiciones de estado se calculan y validan en el backend. Los clientes solo proponen.
4. **Nube primero, resiliente.** Reconexión automática, resincronización al reconectar, idempotencia en cada envío y nada se pierde si se cae la señal.
5. **Reutilizar lo que sirve.** Se portan el modelo y la lógica de Gopicaderabackend, la web Next.js y las apps Flutter; se rehace la estructura donde hace falta.

---

## 2. Arquitectura

```
                         ┌──────────────────────────────────────────┐
                         │          BACKEND (NestJS + Prisma)       │
  Web pública (Next.js)  │                                          │
  gopicadera.online ────►│  REST API  /api/v1/...   (OpenAPI)       │
                         │  Realtime  Socket.IO gateway (rooms)     │
  App E-Menu (Flutter)   │                                          │
  tablets en mesas ─────►│  Módulos: auth · settings · menu ·       │
                         │  tables · devices · orders (motor) ·     │──► PostgreSQL
  App Staff (Flutter)    │  kitchen · bills · payments · cash ·     │
  POS · KDS · Mesero ───►│  customers · delivery · notifications ·  │──► Almacenamiento de imágenes
  · Admin                │  reports · audit                         │    (Supabase Storage / S3)
                         │                                          │
  App Repartidor ───────►│  Integraciones: Stripe (online +         │──► Stripe · FCM · Google Maps
  (Flutter)              │  Terminal) · Firebase FCM · Maps         │
                         └──────────────────────────────────────────┘
```

### Piezas

| Pieza | Tecnología | Base existente |
|---|---|---|
| Backend | NestJS, Prisma, PostgreSQL, Socket.IO, zod/class-validator | Port de `Gopicaderabackend` (Express) |
| Web pública | Next.js 16, React 19, Tailwind 4, Stripe Elements | `web-client` → `web/` |
| App E-Menu (tablets Android de mesa, modo kiosco) | Flutter | Nueva (reusa UI de menú/modificadores) |
| App Staff: modos **POS, KDS, Mesero, Admin** | Flutter (Android/Windows/web) | `restaurant_app` → `apps/staff` |
| App Repartidor | Flutter | `driver_app` → `apps/driver` |

**¿Por qué 3 apps Flutter y no 1?** La E-Menu la usan clientes en tablets bloqueadas: se autentica como *dispositivo de mesa*, sin código de staff dentro. Staff (POS/KDS/mesero/admin) comparte login, permisos y pantallas → una app con modos según rol/dispositivo. Repartidor corre en teléfonos personales con GPS → app aparte. Las tres comparten paquetes (modelos, cliente API, sockets, tema).

### Contratos compartidos
El backend publica **OpenAPI**. De ahí se generan el cliente **Dart** (3 apps) y el cliente **TypeScript** (web). Así rutas y modelos nunca se desincronizan.

### Estructura del repositorio (monorepo `devepmax-oss/Devepmax-E-menu`)

```
devepmax-emenu/
├── backend/                     NestJS
│   ├── prisma/                  schema.prisma, migraciones, seed
│   └── src/
│       ├── common/              guards, decoradores, filtros, idempotencia, audit
│       ├── realtime/            gateway Socket.IO, rooms, eventos
│       └── modules/
│           ├── auth/  settings/  menu/  tables/  devices/
│           ├── orders/  kitchen/  bills/  payments/  cash/
│           ├── customers/  delivery/  notifications/  reports/  audit/
├── web/                         Next.js (web pública)
├── apps/                        Flutter
│   ├── emenu/                   tablets de mesa
│   ├── staff/                   POS · KDS · Mesero · Admin
│   ├── driver/                  repartidores
│   └── packages/
│       ├── core/                modelos + cliente API generado + socket + auth
│       └── ui/                  tema dinámico desde la marca del restaurante
├── infra/                       docker-compose, scripts de instalación/actualización
└── docs/
```

### Despliegue por restaurante
- `infra/` trae un `docker-compose` (backend + web; PostgreSQL gestionado o en contenedor) y un script de alta: crea la base, corre migraciones, siembra roles y un usuario dueño, y pide los datos de marca.
- Variables por instancia: dominio, llaves de Stripe del restaurante, proyecto Firebase/FCM, storage.
- Actualizar = nueva imagen + `prisma migrate deploy`. Backups diarios por instancia.
- Primera instancia: **Picadera → `gopicadera.online`**.

---

## 3. Modelo de datos

Cambios clave respecto a Gopicaderabackend:
- **Empleados, roles y permisos reales**; dispositivos con su propia identidad.
- **Mesas, áreas y sesiones de mesa.**
- **Estaciones de cocina** y **tickets por estación**.
- **Modificadores elegidos guardados en la orden** (snapshot de nombres y precios).
- **Grupos de modificadores reutilizables** entre productos.
- **Cuenta (`Bill`) separada de la orden**: una mesa envía varias rondas y paga una o varias cuentas. Dividir cuenta = mover ítems a otra cuenta.
- Idempotencia (`clientRequestId`), numeración diaria, bitácora de auditoría.
- Marca del restaurante y textos traducibles (es/en).

### Esquema Prisma (borrador)

```prisma
// ───────────── Configuración ─────────────
model RestaurantSettings {
  id                    Int      @id @default(1)   // fila única
  name                  String
  legalName             String?
  logoUrl               String?
  primaryColor          String   @default("#111111")
  accentColor           String   @default("#FACC15")
  phone                 String?
  whatsapp              String?
  email                 String?
  addressLine           String?
  city                  String?
  state                 String?
  zipCode               String?
  lat                   Float?
  lng                   Float?
  socialLinks           Json?                       // { instagram, tiktok, ... }
  timezone              String   @default("America/New_York")
  currency              String   @default("USD")
  locales               String[] @default(["es", "en"])
  acceptsDineIn         Boolean  @default(true)
  acceptsPickup         Boolean  @default(true)
  acceptsDelivery       Boolean  @default(true)
  onlineOrderingPaused  Boolean  @default(false)
  requireWaiterApproval Boolean  @default(false)    // órdenes de tablet esperan OK del mesero
  prepTimeMinutes       Int      @default(20)
  tipPresets            Int[]    @default([15, 18, 20])
  receiptFooter         String?
  maintenanceMode       Boolean  @default(false)
  updatedAt             DateTime @updatedAt
}

model OpeningHour {
  id        String @id @default(cuid())
  dayOfWeek Int                      // 0 = domingo
  opensAt   String                   // "10:30"
  closesAt  String                   // "01:00" (puede cruzar medianoche)
}

model TaxRate {
  id        String    @id @default(cuid())
  name      String
  rate      Decimal   @db.Decimal(6, 4)
  isDefault Boolean   @default(false)
  products  Product[]
}

// ───────────── Personas y acceso ─────────────
model Role {
  id          String     @id @default(cuid())
  name        String     @unique     // Admin, Gerente, Cajero, Mesero, Cocina, Repartidor
  permissions String[]               // códigos, ver sección 5
  isSystem    Boolean    @default(false)
  employees   Employee[]
}

model Employee {
  id            String         @id @default(cuid())
  name          String
  email         String?        @unique
  phone         String?
  passwordHash  String?                    // login completo (admin, gerente, repartidor)
  pinHash       String?                    // login rápido en POS/KDS
  roleId        String
  isActive      Boolean        @default(true)
  createdAt     DateTime       @default(now())
  updatedAt     DateTime       @updatedAt
  role          Role           @relation(fields: [roleId], references: [id])
  driverProfile DriverProfile?
}

model AuthSession {               // refresh tokens revocables
  id         String    @id @default(cuid())
  subject    String               // "employee:<id>" | "customer:<id>" | "device:<id>"
  tokenHash  String    @unique
  userAgent  String?
  expiresAt  DateTime
  revokedAt  DateTime?
  createdAt  DateTime  @default(now())
}

model Customer {
  id             String            @id @default(cuid())
  name           String
  phone          String?           @unique
  email          String?           @unique
  passwordHash   String?
  marketingOptIn Boolean           @default(false)
  createdAt      DateTime          @default(now())
  addresses      CustomerAddress[]
  orders         Order[]
}

model CustomerAddress {
  id           String   @id @default(cuid())
  customerId   String
  label        String?
  street       String
  city         String
  state        String
  zipCode      String
  instructions String?
  lat          Float?
  lng          Float?
  customer     Customer @relation(fields: [customerId], references: [id], onDelete: Cascade)
}

// ───────────── Sala y dispositivos ─────────────
enum TableStatus { AVAILABLE OCCUPIED RESERVED CLEANING }
enum DeviceType  { EMENU POS KDS WAITER }
enum SessionStatus { OPEN BILL_REQUESTED CLOSED }

model DiningArea {
  id        String        @id @default(cuid())
  name      String                       // Salón, Terraza
  sortOrder Int           @default(0)
  tables    DiningTable[]
}

model DiningTable {
  id       String         @id @default(cuid())
  label    String         @unique        // "12"
  areaId   String
  seats    Int            @default(4)
  status   TableStatus    @default(AVAILABLE)
  posX     Int?                           // plano visual
  posY     Int?
  isActive Boolean        @default(true)
  area     DiningArea     @relation(fields: [areaId], references: [id])
  devices  Device[]
  sessions TableSession[]
}

model Device {
  id               String          @id @default(cuid())
  name             String
  type             DeviceType
  tableId          String?                     // EMENU
  stationId        String?                     // KDS
  tokenHash        String?         @unique     // credencial del dispositivo (revocable)
  pairingCode      String?         @unique     // código de 6 dígitos para vincular
  pairingExpiresAt DateTime?
  appVersion       String?
  lastSeenAt       DateTime?
  isActive         Boolean         @default(true)
  table            DiningTable?    @relation(fields: [tableId], references: [id])
  station          KitchenStation? @relation(fields: [stationId], references: [id])
}

model TableSession {                      // "la mesa está abierta"
  id              String           @id @default(cuid())
  tableId         String
  status          SessionStatus    @default(OPEN)
  guestCount      Int?
  waiterId        String?
  openedAt        DateTime         @default(now())
  closedAt        DateTime?
  table           DiningTable      @relation(fields: [tableId], references: [id])
  orders          Order[]
  bills           Bill[]
  serviceRequests ServiceRequest[]
}

enum ServiceRequestType   { CALL_WAITER REQUEST_BILL ASSISTANCE }
enum ServiceRequestStatus { OPEN ACKNOWLEDGED DONE }

model ServiceRequest {                    // botón "llamar mesero" / "pedir cuenta"
  id             String               @id @default(cuid())
  tableSessionId String
  type           ServiceRequestType
  status         ServiceRequestStatus @default(OPEN)
  createdAt      DateTime             @default(now())
  resolvedById   String?
  resolvedAt     DateTime?
  tableSession   TableSession         @relation(fields: [tableSessionId], references: [id])
}

// ───────────── Menú ─────────────
enum SelectionType { SINGLE MULTIPLE }

model KitchenStation {
  id        String          @id @default(cuid())
  name      String                       // Cocina caliente, Bebidas, Postres
  color     String?
  sortOrder Int             @default(0)
  isActive  Boolean         @default(true)
  products  Product[]
  tickets   KitchenTicket[]
  devices   Device[]
}

model Category {
  id            String    @id @default(cuid())
  name          String
  translations  Json?                     // { en: { name } }
  imageUrl      String?
  sortOrder     Int       @default(0)
  isActive      Boolean   @default(true)
  visibleDineIn Boolean   @default(true)
  visibleOnline Boolean   @default(true)
  products      Product[]
}

model Product {
  id              String                 @id @default(cuid())
  categoryId      String
  name            String
  description     String?
  translations    Json?                  // { en: { name, description } }
  price           Decimal                @db.Decimal(10, 2)
  imageUrl        String?
  stationId       String?                // a qué estación va
  taxRateId       String?                // null = impuesto por defecto
  sortOrder       Int                    @default(0)
  isActive        Boolean                @default(true)   // existe en el menú
  isAvailable     Boolean                @default(true)   // agotado hoy (86)
  visibleDineIn   Boolean                @default(true)
  visibleOnline   Boolean                @default(true)
  allergens       String[]
  prepTimeMinutes Int?
  createdAt       DateTime               @default(now())
  updatedAt       DateTime               @updatedAt
  category        Category               @relation(fields: [categoryId], references: [id])
  station         KitchenStation?        @relation(fields: [stationId], references: [id])
  taxRate         TaxRate?               @relation(fields: [taxRateId], references: [id])
  modifierGroups  ProductModifierGroup[]
}

model ModifierGroup {
  id            String                 @id @default(cuid())
  name          String                 // "Tamaño", "Extras", "Quitar ingredientes"
  translations  Json?
  selectionType SelectionType
  minSelect     Int                    @default(0)
  maxSelect     Int                    @default(1)
  isActive      Boolean                @default(true)
  options       ModifierOption[]
  products      ProductModifierGroup[]
}

model ProductModifierGroup {             // grupos reutilizables
  productId       String
  modifierGroupId String
  sortOrder       Int           @default(0)
  product         Product       @relation(fields: [productId], references: [id], onDelete: Cascade)
  modifierGroup   ModifierGroup @relation(fields: [modifierGroupId], references: [id], onDelete: Cascade)
  @@id([productId, modifierGroupId])
}

model ModifierOption {
  id              String        @id @default(cuid())
  groupId         String
  name            String
  translations    Json?
  priceAdjustment Decimal       @default(0) @db.Decimal(10, 2)
  isDefault       Boolean       @default(false)
  isAvailable     Boolean       @default(true)
  sortOrder       Int           @default(0)
  group           ModifierGroup @relation(fields: [groupId], references: [id], onDelete: Cascade)
}

// ───────────── Órdenes y cocina ─────────────
enum OrderChannel    { TABLET POS WAITER ONLINE }
enum FulfillmentType { DINE_IN TAKEOUT PICKUP DELIVERY }
enum OrderStatus {
  PENDING_PAYMENT     // online prepago esperando Stripe
  PENDING_APPROVAL    // tablet esperando OK del mesero (si está activado)
  PLACED              // recibida, enviada a cocina
  ACCEPTED
  PREPARING
  READY
  OUT_FOR_DELIVERY
  COMPLETED
  CANCELLED
}
enum TicketStatus { NEW ACCEPTED PREPARING READY COMPLETED CANCELLED }
enum ItemStatus   { ACTIVE VOIDED }

model Order {
  id                   String           @id @default(cuid())
  businessDate         DateTime         @db.Date
  number               Int                           // 1, 2, 3… se reinicia cada día
  publicCode           String           @unique      // para seguimiento online
  clientRequestId      String           @unique      // idempotencia
  channel              OrderChannel
  fulfillmentType      FulfillmentType
  status               OrderStatus
  tableSessionId       String?
  billId               String
  customerId           String?
  deviceId             String?
  createdById          String?                       // empleado
  customerName         String?
  customerPhone        String?
  customerEmail        String?
  deliveryAddress      Json?                         // snapshot de la dirección
  deliveryInstructions String?
  deliveryZoneId       String?
  scheduledFor         DateTime?
  notes                String?
  estimatedReadyAt     DateTime?
  placedAt             DateTime?
  acceptedAt           DateTime?
  readyAt              DateTime?
  completedAt          DateTime?
  cancelledAt          DateTime?
  cancelReason         String?
  cancelledById        String?
  createdAt            DateTime         @default(now())
  updatedAt            DateTime         @updatedAt
  tableSession         TableSession?    @relation(fields: [tableSessionId], references: [id])
  bill                 Bill             @relation(fields: [billId], references: [id])
  customer             Customer?        @relation(fields: [customerId], references: [id])
  items                OrderItem[]
  tickets              KitchenTicket[]
  deliveryAssignment   DeliveryAssignment?
  @@unique([businessDate, number])
  @@index([status])
}

model OrderItem {
  id             String              @id @default(cuid())
  orderId        String
  billId         String                         // cambia al dividir la cuenta
  ticketId       String?
  productId      String?
  stationId      String?
  nameSnapshot   String
  unitPrice      Decimal             @db.Decimal(10, 2)   // precio base
  modifiersTotal Decimal             @default(0) @db.Decimal(10, 2)
  quantity       Int
  lineTotal      Decimal             @db.Decimal(10, 2)
  taxRate        Decimal             @db.Decimal(6, 4)    // snapshot
  notes          String?
  seat           Int?                                     // para dividir por asiento
  status         ItemStatus          @default(ACTIVE)
  voidReason     String?
  voidedById     String?
  voidedAt       DateTime?
  order          Order               @relation(fields: [orderId], references: [id], onDelete: Cascade)
  bill           Bill                @relation(fields: [billId], references: [id])
  ticket         KitchenTicket?      @relation(fields: [ticketId], references: [id])
  modifiers      OrderItemModifier[]
}

model OrderItemModifier {                 // lo que eligió el cliente, congelado
  id                 String    @id @default(cuid())
  orderItemId        String
  modifierOptionId   String?
  groupNameSnapshot  String
  optionNameSnapshot String
  priceAdjustment    Decimal   @db.Decimal(10, 2)
  orderItem          OrderItem @relation(fields: [orderItemId], references: [id], onDelete: Cascade)
}

model KitchenTicket {                     // una orden genera un ticket por estación
  id          String         @id @default(cuid())
  orderId     String
  stationId   String
  status      TicketStatus   @default(NEW)
  createdAt   DateTime       @default(now())
  acceptedAt  DateTime?
  startedAt   DateTime?
  readyAt     DateTime?
  completedAt DateTime?
  order       Order          @relation(fields: [orderId], references: [id], onDelete: Cascade)
  station     KitchenStation @relation(fields: [stationId], references: [id])
  items       OrderItem[]
  @@index([stationId, status])
}

model DailyCounter {                      // numeración diaria segura
  businessDate    DateTime @id @db.Date
  lastOrderNumber Int      @default(0)
}

// ───────────── Cuentas, pagos y caja ─────────────
enum BillStatus    { UNPAID PARTIALLY_PAID PAID REFUNDED VOID }
enum PaymentMethod { CASH CARD_TERMINAL CARD_ONLINE CARD_QR OTHER }
enum PaymentStatus { PENDING SUCCEEDED FAILED CANCELLED REFUNDED PARTIALLY_REFUNDED }
enum DiscountType  { PERCENT AMOUNT }
enum CashMovementType { PAY_IN PAY_OUT DROP }

model Bill {
  id             String        @id @default(cuid())
  tableSessionId String?
  status         BillStatus    @default(UNPAID)
  subtotal       Decimal       @default(0) @db.Decimal(10, 2)
  discountTotal  Decimal       @default(0) @db.Decimal(10, 2)
  taxTotal       Decimal       @default(0) @db.Decimal(10, 2)
  deliveryFee    Decimal       @default(0) @db.Decimal(10, 2)
  tipTotal       Decimal       @default(0) @db.Decimal(10, 2)
  total          Decimal       @default(0) @db.Decimal(10, 2)
  amountPaid     Decimal       @default(0) @db.Decimal(10, 2)
  closedAt       DateTime?
  createdAt      DateTime      @default(now())
  updatedAt      DateTime      @updatedAt
  tableSession   TableSession? @relation(fields: [tableSessionId], references: [id])
  orders         Order[]
  items          OrderItem[]
  payments       Payment[]
  discounts      Discount[]
}

model Discount {
  id             String       @id @default(cuid())
  billId         String
  orderItemId    String?                    // null = a toda la cuenta
  type           DiscountType
  value          Decimal      @db.Decimal(10, 2)
  amount         Decimal      @db.Decimal(10, 2)   // calculado
  reason         String
  appliedById    String
  authorizedById String?                    // gerente que puso el PIN
  createdAt      DateTime     @default(now())
  bill           Bill         @relation(fields: [billId], references: [id])
}

model Payment {
  id                    String        @id @default(cuid())
  billId                String
  method                PaymentMethod
  status                PaymentStatus @default(PENDING)
  amount                Decimal       @db.Decimal(10, 2)
  tipAmount             Decimal       @default(0) @db.Decimal(10, 2)
  cashTendered          Decimal?      @db.Decimal(10, 2)
  changeGiven           Decimal?      @db.Decimal(10, 2)
  stripePaymentIntentId String?       @unique
  employeeId            String?
  cashShiftId           String?
  createdAt             DateTime      @default(now())
  bill                  Bill          @relation(fields: [billId], references: [id])
  cashShift             CashShift?    @relation(fields: [cashShiftId], references: [id])
  refunds               Refund[]
}

model Refund {
  id             String   @id @default(cuid())
  paymentId      String
  amount         Decimal  @db.Decimal(10, 2)
  reason         String
  stripeRefundId String?  @unique
  employeeId     String
  createdAt      DateTime @default(now())
  payment        Payment  @relation(fields: [paymentId], references: [id])
}

model CashShift {                         // apertura y cierre de caja
  id           String         @id @default(cuid())
  deviceId     String?
  openedById   String
  closedById   String?
  openedAt     DateTime       @default(now())
  closedAt     DateTime?
  openingCash  Decimal        @db.Decimal(10, 2)
  expectedCash Decimal?       @db.Decimal(10, 2)
  countedCash  Decimal?       @db.Decimal(10, 2)
  difference   Decimal?       @db.Decimal(10, 2)
  notes        String?
  payments     Payment[]
  movements    CashMovement[]
}

model CashMovement {
  id         String           @id @default(cuid())
  shiftId    String
  type       CashMovementType
  amount     Decimal          @db.Decimal(10, 2)
  reason     String
  employeeId String
  createdAt  DateTime         @default(now())
  shift      CashShift        @relation(fields: [shiftId], references: [id])
}

// ───────────── Delivery (port de Gopicadera) ─────────────
enum DriverStatus { OFFLINE AVAILABLE BUSY SUSPENDED }
enum DeliveryAssignmentStatus { PENDING ACCEPTED PICKED_UP DELIVERED CANCELLED }

model DeliveryZone {
  id          String   @id @default(cuid())
  name        String
  polygon     Json?                       // GeoJSON; o radio
  radiusKm    Decimal? @db.Decimal(6, 2)
  fee         Decimal  @db.Decimal(10, 2)
  minOrder    Decimal  @default(0) @db.Decimal(10, 2)
  etaMinutes  Int      @default(30)
  isActive    Boolean  @default(true)
}

model DriverProfile {
  id           String               @id @default(cuid())
  employeeId   String               @unique
  photoUrl     String?
  vehicleType  String?
  vehiclePlate String?
  vehicleColor String?
  status       DriverStatus         @default(OFFLINE)
  lastLat      Float?
  lastLng      Float?
  lastSeenAt   DateTime?
  employee     Employee             @relation(fields: [employeeId], references: [id])
  assignments  DeliveryAssignment[]
}

model DeliveryAssignment {
  id          String                   @id @default(cuid())
  orderId     String                   @unique
  driverId    String
  status      DeliveryAssignmentStatus @default(PENDING)
  acceptedAt  DateTime?
  pickedUpAt  DateTime?
  deliveredAt DateTime?
  cancelledAt DateTime?
  createdAt   DateTime                 @default(now())
  order       Order                    @relation(fields: [orderId], references: [id], onDelete: Cascade)
  driver      DriverProfile            @relation(fields: [driverId], references: [id])
}

// ───────────── Sistema ─────────────
model NotificationToken {
  id         String   @id @default(cuid())
  token      String   @unique
  platform   String?
  subject    String               // "employee:<id>" | "customer:<id>" | "device:<id>"
  isActive   Boolean  @default(true)
  lastSeenAt DateTime @default(now())
  @@index([subject, isActive])
}

model AuditLog {
  id         String   @id @default(cuid())
  actor      String               // "employee:<id>" | "device:<id>" | "customer:<id>" | "system"
  action     String               // "order.cancel", "item.void", "discount.apply", "price.change"…
  entityType String
  entityId   String
  data       Json?
  createdAt  DateTime @default(now())
  @@index([entityType, entityId])
  @@index([createdAt])
}

model IdempotencyKey {
  key        String   @id
  endpoint   String
  response   Json
  createdAt  DateTime @default(now())
}
```

> Inventario (Fase 6) se añade después: `InventoryItem`, `Recipe` (producto → ingredientes), `StockMovement`. Por ahora `Product.isAvailable` cubre el "agotado".

### Promociones (Fase 2; cupones en Fase 5)

Tipos en la v1 (decididos): **descuento % o $** en productos o categorías, **2x1 / lleva X paga Y**, **combos a precio fijo** y **cupones para la web**. Horarios especiales (happy hour) quedan para después; el modelo ya trae fechas de vigencia y se le pueden sumar franjas horarias.

```prisma
enum PromotionType {
  PERCENT_OFF   // 15 % en hamburguesas
  AMOUNT_OFF    // $2 menos en bebidas
  BUY_X_GET_Y   // 2x1 = compra 1, lleva 1 gratis (el más barato sale gratis)
  COMBO_PRICE   // hamburguesa + acompañamiento + bebida = $15
}

model Promotion {
  id             String          @id @default(cuid())
  name           String          // "2x1 en tacos"
  description    String?
  translations   Json?
  type           PromotionType
  value          Decimal?        @db.Decimal(10, 2) // % o $ según el tipo
  buyQuantity    Int?            // BUY_X_GET_Y
  getQuantity    Int?
  comboPrice     Decimal?        @db.Decimal(10, 2) // COMBO_PRICE
  appliesDineIn  Boolean         @default(true)
  appliesOnline  Boolean         @default(true)
  requiresCoupon Boolean         @default(false)
  startsAt       DateTime?
  endsAt         DateTime?
  priority       Int             @default(0)
  isActive       Boolean         @default(true)
  targets        PromotionTarget[]   // productos o categorías que participan
  comboSlots     PromotionComboSlot[] // "elige 1 hamburguesa", "elige 1 bebida"
  coupons        Coupon[]
}

model PromotionTarget {
  id          String  @id @default(cuid())
  promotionId String
  productId   String?
  categoryId  String?
}

model PromotionComboSlot {        // cada "hueco" del combo y qué productos lo llenan
  id          String @id @default(cuid())
  promotionId String
  name        String // "Bebida"
  quantity    Int    @default(1)
  productIds  String[]
  categoryIds String[]
}

model Coupon {
  id                 String    @id @default(cuid())
  code               String    @unique // BIENVENIDO10 (se guarda en mayúsculas)
  promotionId        String
  maxUses            Int?
  maxUsesPerCustomer Int?
  usesCount          Int       @default(0)
  minOrderTotal      Decimal?  @db.Decimal(10, 2)
  startsAt           DateTime?
  endsAt             DateTime?
  isActive           Boolean   @default(true)
}

model CouponRedemption {
  id         String   @id @default(cuid())
  couponId   String
  orderId    String
  customerId String?
  createdAt  DateTime @default(now())
}
```

**Reglas del motor de precios** (siempre en el servidor):
- Al crear o modificar una orden se evalúan las promociones activas y vigentes para su canal; el resultado se guarda como `Discount` con `promotionId` (y `couponId` si aplica), así queda el detalle en la cuenta, el recibo y los reportes.
- Una línea recibe como máximo una promoción automática (la de mayor ahorro; empate → mayor `priority`). Las promociones no se acumulan salvo un cupón sobre el total.
- **Combos**: los productos siguen siendo líneas separadas (cada uno va a su estación de cocina); el descuento es la diferencia entre la suma de las líneas y `comboPrice`.
- **2x1**: se descuenta el artículo más barato de cada grupo que cumple la regla.
- Los descuentos manuales del cajero (con PIN de gerente) siguen existiendo aparte.
- Toda creación o cambio de promoción y cupón queda en `AuditLog`.

### Estadísticas de ventas e ingresos (Fase 6)
Pantalla única en la app Staff (rol con `reports.view`): ventas e ingresos por día, semana y mes con comparación contra el periodo anterior; ingresos por canal (mesa, POS, online, delivery); productos y categorías más vendidos; horas pico; ticket promedio (global y por mesa); tiempo promedio de preparación por estación; cancelaciones y descuentos (manuales, promociones y cupones, con su costo); propinas; métodos de pago. Filtros por rango de fechas y exportación a CSV/Excel.

---

## 4. Flujos de órdenes

### 4.1 Máquinas de estado

**Orden (vista general):**
```
PENDING_PAYMENT ─(Stripe ok)─┐
PENDING_APPROVAL ─(mesero OK)┤
                             ▼
                          PLACED → ACCEPTED → PREPARING → READY ─┬─► COMPLETED   (mesa / pickup)
                                                                 └─► OUT_FOR_DELIVERY → COMPLETED
   (cualquier estado antes de COMPLETED) ──► CANCELLED  (con reglas y permisos)
```
- El estado de la orden se **deriva de sus tickets**: ACCEPTED cuando el primer ticket se acepta, PREPARING cuando alguno está en preparación, READY cuando **todos** están listos.
- **Ticket de cocina (KDS):** NEW → ACCEPTED → PREPARING → READY → COMPLETED (un toque por paso; se puede deshacer el último paso por 10 s).
- **Cuenta (pago):** UNPAID → PARTIALLY_PAID → PAID → (REFUNDED). Independiente de la preparación.
- **Mesa:** AVAILABLE → OCCUPIED (al abrir sesión) → CLEANING (al cerrar la cuenta) → AVAILABLE.

### 4.2 Orden desde la mesa (tablet E-Menu)
1. La tablet está vinculada a la mesa (dispositivo `EMENU` con token).
2. El cliente arma el carrito **en la tablet** y toca "Enviar". La app genera `clientRequestId`.
3. `POST /orders` → el backend, en **una transacción**:
   - abre `TableSession` + `Bill` si la mesa no tiene una abierta;
   - valida productos, disponibilidad y modificadores (min/max, requeridos);
   - recalcula precios e impuestos desde la base de datos;
   - asigna número diario (`DailyCounter`), crea `Order`, `OrderItem`, `OrderItemModifier`;
   - agrupa ítems por estación y crea un `KitchenTicket` por estación;
   - actualiza totales de la `Bill`;
   - registra `clientRequestId` (si llega repetido, devuelve la misma orden).
4. Emite eventos: POS (`order.created`), cada estación (`ticket.created`), meseros, y la tablet (`order.updated` → "¡Recibido!").
5. Si `requireWaiterApproval` está activo, la orden queda en `PENDING_APPROVAL` hasta que el mesero la confirme.
6. La tablet muestra el progreso en vivo y permite pedir otra ronda (nueva orden, misma cuenta).

### 4.3 Orden desde POS o mesero
Mismo endpoint. Canal `POS`/`WAITER`, tipo `DINE_IN` (con mesa) o `TAKEOUT` (mostrador, sin mesa: se crea una `Bill` suelta).

### 4.4 Orden online (web)
1. Carrito en el servidor por sesión → checkout con datos, tipo (pickup/delivery), zona de delivery, propina, horario programado opcional.
2. El backend crea la orden en `PENDING_PAYMENT` y un PaymentIntent de Stripe.
3. Webhook `payment_intent.succeeded` → `Payment` SUCCEEDED, `Bill` PAID, orden `PLACED` → cocina. (Pago en tienda para pickup opcional: entra directo como `PLACED` con `Bill` UNPAID.)
4. Página de seguimiento en vivo (`/order/[publicCode]`): estados, tiempo estimado y, en delivery, mapa del repartidor.
5. Si `onlineOrderingPaused` o la tienda está cerrada, el checkout se bloquea con mensaje.

### 4.5 Cocina → servicio
- Cada pantalla KDS está vinculada a una estación y solo ve sus tickets, ordenados por antigüedad, con temporizador y colores (verde / amarillo / rojo según tiempo).
- Ticket READY → si todos los tickets de la orden están listos: orden READY →
  - **mesa:** aviso al mesero (push + app); la tablet muestra "en camino";
  - **pickup:** aviso al cliente (web/push/SMS opcional);
  - **delivery:** se publica a repartidores disponibles.
- Órdenes programadas aparecen en cocina X minutos antes de la hora.

### 4.6 Cobro en mesa
1. El cliente toca "Pedir la cuenta" (o el mesero lo hace) → `ServiceRequest REQUEST_BILL`, sesión `BILL_REQUESTED`.
2. En POS (o app del mesero): ver la cuenta, **dividir** (por ítems, por asiento, en partes iguales o por monto), descuentos (con PIN de gerente si el rol lo exige), propina.
3. Formas de pago: **efectivo** (calcula cambio, va al turno de caja), **Stripe Terminal**, o **QR en la tablet** → el cliente paga desde su teléfono.
4. Cuando todas las cuentas de la sesión están pagadas → sesión `CLOSED`, mesa `CLEANING`, tablet vuelve a la bienvenida. Recibo impreso o por email/SMS.

### 4.7 Cancelaciones y anulaciones
| Momento | Quién | Requisito |
|---|---|---|
| Antes de que cocina acepte | Cajero, mesero, gerente | Motivo |
| Después de aceptada / en preparación | Gerente (o cajero con PIN de gerente) | Motivo; se avisa a la estación |
| Orden pagada online | Gerente | Reembolso Stripe total o parcial |

Toda cancelación, anulación de ítem, descuento, reembolso y cambio de precio queda en `AuditLog`.

### 4.8 Tiempo real
- **Rooms de Socket.IO:** `pos`, `waiters`, `kitchen:<stationId>`, `table:<tableId>`, `order:<publicCode>`, `drivers`, `driver:<id>`, `admin`.
- **Eventos:** `order.created`, `order.updated`, `ticket.created`, `ticket.updated`, `bill.updated`, `payment.succeeded`, `table.updated`, `service_request.created`, `product.availability`, `driver.location`, `settings.updated`.
- Cada evento lleva `updatedAt`; el cliente ignora eventos más viejos que lo que ya tiene.
- **Al reconectar**, cada app pide una foto completa de su ámbito (`GET /sync/kitchen?stationId=…`, `/sync/pos`, `/sync/table/:id`) y reemplaza su estado.
- El socket se autentica con el mismo token que la API; el servidor decide a qué rooms se une cada quien.

---

## 5. Roles y permisos

### Tipos de identidad
| Identidad | Cómo entra | Uso |
|---|---|---|
| Empleado (admin, gerente, repartidor) | Email/teléfono + contraseña → JWT de acceso (15 min) + refresh revocable | Panel admin, app repartidor |
| Empleado en dispositivo compartido | **PIN de 4–6 dígitos** en un dispositivo POS/KDS registrado | Cambiar de cajero/mesero rápido |
| Dispositivo | Código de vinculación de 6 dígitos generado en admin → token propio | Tablets E-Menu, pantallas KDS |
| Cliente | Invitado, o cuenta con email/teléfono | Web pública |

### Permisos por rol (configurables; estos son los de fábrica)

| Permiso | Admin | Gerente | Cajero | Mesero | Cocina | Repartidor |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `settings.manage` (marca, impuestos, horarios, canales) | ✓ | | | | | |
| `employees.manage` / `roles.manage` | ✓ | ✓¹ | | | | |
| `menu.manage` (productos, precios, modificadores) | ✓ | ✓ | | | | |
| `product.toggle_availability` (agotado) | ✓ | ✓ | ✓ | ✓ | ✓ | |
| `tables.manage` / `devices.manage` | ✓ | ✓ | | | | |
| `tables.operate` (abrir, mover, unir, liberar) | ✓ | ✓ | ✓ | ✓ | | |
| `orders.create` | ✓ | ✓ | ✓ | ✓ | | |
| `orders.approve` (órdenes de tablet) | ✓ | ✓ | ✓ | ✓ | | |
| `orders.cancel` (antes de cocina) | ✓ | ✓ | ✓ | ✓ | | |
| `orders.void_after_kitchen` | ✓ | ✓ | PIN² | PIN² | | |
| `kitchen.operate` (cambiar estado de tickets) | ✓ | ✓ | | | ✓ | |
| `bills.discount` | ✓ | ✓ | PIN² | | | |
| `payments.take` | ✓ | ✓ | ✓ | ✓³ | | |
| `payments.refund` | ✓ | ✓ | | | | |
| `cash.shift` (abrir/cerrar caja, movimientos) | ✓ | ✓ | ✓ | | | |
| `delivery.dispatch` (asignar repartidor) | ✓ | ✓ | ✓ | | | |
| `delivery.own` (sus entregas, ubicación) | | | | | | ✓ |
| `reports.view` | ✓ | ✓ | | | | |
| `audit.view` | ✓ | ✓ | | | | |

¹ No puede crear ni editar administradores. ² Requiere PIN de un gerente en el momento (queda registrado quién autorizó). ³ Activable en ajustes.

**Dispositivo E-Menu:** solo puede leer el menú, crear órdenes **para su mesa**, ver su sesión/cuenta, crear `ServiceRequest` y generar el QR de pago de su cuenta.
**Dispositivo KDS:** solo ve y opera tickets de su estación.

---

## 6. Plan de desarrollo por fases

| Fase | Contenido | Resultado |
|---|---|---|
| **0. Preparación** | Monorepo `Devepmax-E-menu` con apps y web copiadas (respaldo en git). Esqueleto de backend NestJS, paquetes Flutter compartidos, Docker con PostgreSQL local, CI. | Base de trabajo ordenada |
| **1. Fundamentos** | NestJS + Prisma con el esquema nuevo. Auth (empleados, roles, permisos, PIN, dispositivos con vinculación). Ajustes + marca. Auditoría. OpenAPI → clientes Dart y TS. Menú: categorías, productos, modificadores reutilizables, estaciones, imágenes, agotado. Admin de menú en app Staff (portado). Renombrar apps (`com.devepmax.emenu.*`) y configuración Firebase por instancia. | Sistema central seguro con menú administrable |
| **2. Motor de órdenes + canal online** | Órdenes, ítems con modificadores, tickets por estación, máquina de estados, idempotencia, numeración diaria, cuentas. **Motor de precios con promociones** (descuento %/$, 2x1, combos) y pantalla de promociones en la app Staff. Gateway Socket.IO con rooms y resync. Port de carrito, checkout Stripe y repartidores. Web apuntando a la API nueva en **gopicadera.online**. | Pedidos online de punta a punta sobre el motor nuevo |
| **3. Sala: E-Menu, KDS y meseros** | Áreas, mesas, plano visual, sesiones. App E-Menu (kiosco Android, bilingüe, fotos, modificadores, seguimiento, llamar mesero, pedir cuenta). KDS por estación con temporizadores y alertas. Modo mesero. | Las mesas piden solas y cocina opera por estaciones |
| **4. POS y caja** | Mesas, órdenes manuales, cuentas, dividir, descuentos con PIN, propinas, efectivo, **Stripe Terminal**, **pago por QR desde la mesa**, recibos impresos (ESC/POS) y digitales, reembolsos, turnos y cierre de caja. | **Piloto en el restaurante** |
| **5. Online+** | **Cupones para la web**, seguimiento en vivo en la web, cuentas de cliente, historial y "repetir pedido", zonas y costos de delivery, pausar pedidos online, órdenes programadas, marca y contenido desde la API, SEO por producto, reseñas desde Google. | Experiencia online superior a la competencia |
| **6. Estadísticas e inventario** | **Pantalla de estadísticas de ventas e ingresos** (ver sección 3): por día/semana/mes, por canal, por producto, más vendidos, horas pico, ticket promedio por mesa, tiempo de preparación por estación, cancelaciones, costo de promociones y cupones, propinas, métodos de pago, exportación. Inventario básico. | Dueño decide con datos |
| **7. Endurecimiento y lanzamiento** | Pruebas de carga y concurrencia, pruebas de desconexión, revisión de seguridad, monitoreo, backups probados, script de instalación para nuevos restaurantes, publicación en tiendas. | Listo para vender a más restaurantes |

Pruebas, seguridad y revisión de UX se hacen **en cada fase**, no solo en la 7.

---

## 7. Diferenciadores frente a la competencia
- Pago desde la mesa (QR o terminal) con división de cuenta por el propio cliente.
- Menú bilingüe con fotos grandes, alérgenos y sugerencias de acompañamientos.
- Seguimiento en vivo en mesa, web y delivery con tiempos reales de cocina.
- Llamar mesero / pedir cuenta con un toque.
- KDS por estaciones con tiempos y alertas; analítica de cuellos de botella.
- Delivery propio con repartidores y mapa en vivo (sin comisiones de terceros).
- Marca del restaurante en todo (tablet, web, recibos) sin tocar código.

---

## 8. Pendiente de decidir
- **Lector Stripe Terminal** (p. ej. WisePOS E o S700) — antes de la Fase 4.
- **Hosting:** seguir en Railway o mover; PostgreSQL en Supabase o gestionado — antes de la Fase 2.
- **Happy hour** (promociones por día y hora): fuera de la v1; el modelo de promociones lo admite después.
