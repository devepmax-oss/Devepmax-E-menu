import '../../../core/ui/feedback.dart';

/// Respuesta JSON de la API.
typedef OrderJson = Map<String, dynamic>;

/// Estados de una orden, en el orden en que avanzan.
const finishedStatuses = {'COMPLETED', 'CANCELLED'};

const orderStatusLabels = <String, String>{
  'PENDING_PAYMENT': 'Esperando pago',
  'PENDING_APPROVAL': 'Por aprobar',
  'PLACED': 'Recibida',
  'ACCEPTED': 'Aceptada',
  'PREPARING': 'Preparando',
  'READY': 'Lista',
  'OUT_FOR_DELIVERY': 'En camino',
  'COMPLETED': 'Entregada',
  'CANCELLED': 'Cancelada',
};

const ticketStatusLabels = <String, String>{
  'NEW': 'Nuevo',
  'ACCEPTED': 'Aceptado',
  'PREPARING': 'Preparando',
  'READY': 'Listo',
  'COMPLETED': 'Entregado',
  'CANCELLED': 'Cancelado',
};

const channelLabels = <String, String>{
  'TABLET': 'Mesa',
  'POS': 'Caja',
  'WAITER': 'Mesero',
  'ONLINE': 'Web',
};

const fulfillmentLabels = <String, String>{
  'DINE_IN': 'En el local',
  'TAKEOUT': 'Para llevar',
  'PICKUP': 'Pickup',
  'DELIVERY': 'Delivery',
};

class OrderModifier {
  const OrderModifier(this.group, this.option);
  final String group;
  final String option;
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.lineTotal,
    required this.discount,
    required this.status,
    this.notes,
    required this.modifiers,
  });

  final String id;
  final String name;
  final int quantity;
  final double lineTotal;
  final double discount;
  final String status;
  final String? notes;
  final List<OrderModifier> modifiers;

  bool get isActive => status == 'ACTIVE';

  factory OrderItem.fromJson(OrderJson j) => OrderItem(
        id: j['id'] as String,
        name: j['name'] as String,
        quantity: j['quantity'] as int,
        lineTotal: parseMoney(j['lineTotal']),
        discount: parseMoney(j['discount']),
        status: j['status'] as String? ?? 'ACTIVE',
        notes: j['notes'] as String?,
        modifiers: ((j['modifiers'] as List?) ?? const [])
            .map((m) => OrderModifier((m as OrderJson)['group'] as String, m['option'] as String))
            .toList(),
      );
}

class OrderTicket {
  const OrderTicket({required this.id, required this.status, required this.stationName, this.stationColor});
  final String id;
  final String status;
  final String stationName;
  final String? stationColor;

  factory OrderTicket.fromJson(OrderJson j) {
    final station = (j['station'] as OrderJson?) ?? const {};
    return OrderTicket(
      id: j['id'] as String,
      status: j['status'] as String,
      stationName: station['name'] as String? ?? 'Cocina',
      stationColor: station['color'] as String?,
    );
  }
}

const deliveryStatusLabels = <String, String>{
  'PENDING': 'Esperando que acepte',
  'ACCEPTED': 'Aceptó',
  'PICKED_UP': 'En camino',
  'DELIVERED': 'Entregado',
};

/// Repartidor asignado a un pedido de delivery.
class OrderDelivery {
  const OrderDelivery({required this.status, required this.driverId, required this.driverName, this.driverPhone});
  final String status;
  final String driverId;
  final String driverName;
  final String? driverPhone;

  static OrderDelivery? fromJson(Object? json) {
    if (json is! Map) return null;
    final driver = (json['driver'] as Map?) ?? const {};
    return OrderDelivery(
      status: json['status'] as String? ?? 'PENDING',
      driverId: driver['id'] as String? ?? '',
      driverName: driver['name'] as String? ?? 'Repartidor',
      driverPhone: driver['phone'] as String?,
    );
  }
}

/// Repartidor para el diálogo de asignar.
class DriverOption {
  const DriverOption({required this.id, required this.name, required this.status, required this.activeDeliveries, this.phone});
  final String id;
  final String name;
  final String status;
  final int activeDeliveries;
  final String? phone;

  bool get available => status == 'AVAILABLE';

  factory DriverOption.fromJson(OrderJson j) => DriverOption(
        id: j['id'] as String,
        name: j['name'] as String,
        status: j['status'] as String? ?? 'OFFLINE',
        activeDeliveries: j['activeDeliveries'] as int? ?? 0,
        phone: j['phone'] as String?,
      );
}

class OrderPromotion {
  const OrderPromotion(this.name, this.amount);
  final String name;
  final double amount;
}

class OrderView {
  const OrderView({
    required this.id,
    required this.number,
    required this.publicCode,
    required this.channel,
    required this.fulfillmentType,
    required this.status,
    required this.updatedAt,
    required this.createdAt,
    this.placedAt,
    this.readyAt,
    this.tableLabel,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.deliveryAddress,
    this.deliveryInstructions,
    this.delivery,
    this.notes,
    this.cancelReason,
    required this.items,
    required this.tickets,
    required this.promotions,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.deliveryFee,
    required this.tipTotal,
    required this.amountPaid,
    required this.billStatus,
    this.billId,
  });

  final String id;
  final int number;
  final String publicCode;
  final String channel;
  final String fulfillmentType;
  final String status;

  /// Versión para tiempo real: se ignora un aviso más viejo que lo que ya se tiene.
  final DateTime updatedAt;
  final DateTime createdAt;
  final DateTime? placedAt;
  final DateTime? readyAt;
  final String? tableLabel;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;

  /// Dirección de entrega (delivery): street, city, state, zipCode.
  final Map<String, dynamic>? deliveryAddress;
  final String? deliveryInstructions;
  final OrderDelivery? delivery;
  final String? notes;
  final String? cancelReason;
  final List<OrderItem> items;
  final List<OrderTicket> tickets;
  final List<OrderPromotion> promotions;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double deliveryFee;
  final double tipTotal;
  final double amountPaid;
  final String billStatus;

  /// Cuenta de la orden (para cobrarla en Caja).
  final String? billId;

  bool get isPaid => billStatus == 'PAID';

  /// "123 Main St, Miami, FL 33101"
  String? get addressText {
    final a = deliveryAddress;
    if (a == null) return null;
    final line2 = [a['state'], a['zipCode']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final parts = [a['street'], a['city'], line2].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  bool get isFinished => finishedStatuses.contains(status);
  List<OrderItem> get activeItems => items.where((i) => i.isActive).toList();
  int get itemCount => activeItems.fold(0, (sum, i) => sum + i.quantity);

  /// Productos que se pidieron (en una cancelada, los que tenía antes de anularse).
  int get orderedCount => (status == 'CANCELLED' ? items : activeItems).fold(0, (sum, i) => sum + i.quantity);

  /// "Mesa 7", "Para llevar · Luis", "Delivery"…
  String get where {
    if (tableLabel != null) return 'Mesa $tableLabel';
    final kind = fulfillmentLabels[fulfillmentType] ?? fulfillmentType;
    final name = customerName?.trim();
    return name == null || name.isEmpty ? kind : '$kind · $name';
  }

  /// Desde que la cocina recibió la orden (o desde que se creó).
  DateTime get startedAt => placedAt ?? createdAt;

  factory OrderView.fromJson(OrderJson j) {
    final bill = (j['bill'] as OrderJson?) ?? const {};
    final table = j['table'] as OrderJson?;
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    return OrderView(
      id: j['id'] as String,
      number: j['number'] as int,
      publicCode: j['publicCode'] as String? ?? '',
      channel: j['channel'] as String,
      fulfillmentType: j['fulfillmentType'] as String,
      status: j['status'] as String,
      updatedAt: date(j['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdAt: date(j['createdAt']) ?? DateTime.now(),
      placedAt: date(j['placedAt']),
      readyAt: date(j['readyAt']),
      tableLabel: table?['label'] as String?,
      customerName: j['customerName'] as String?,
      customerPhone: j['customerPhone'] as String?,
      customerEmail: j['customerEmail'] as String?,
      deliveryAddress: j['deliveryAddress'] is Map ? Map<String, dynamic>.from(j['deliveryAddress'] as Map) : null,
      deliveryInstructions: j['deliveryInstructions'] as String?,
      delivery: OrderDelivery.fromJson(j['delivery']),
      notes: j['notes'] as String?,
      cancelReason: j['cancelReason'] as String?,
      items: ((j['items'] as List?) ?? const []).map((i) => OrderItem.fromJson(i as OrderJson)).toList(),
      tickets: ((j['tickets'] as List?) ?? const []).map((t) => OrderTicket.fromJson(t as OrderJson)).toList(),
      promotions: ((j['promotions'] as List?) ?? const [])
          .map((p) => OrderPromotion((p as OrderJson)['name'] as String? ?? 'Promoción', parseMoney(p['amount'])))
          .toList(),
      subtotal: parseMoney(bill['subtotal']),
      discountTotal: parseMoney(bill['discountTotal']),
      taxTotal: parseMoney(bill['taxTotal']),
      total: parseMoney(bill['total']),
      deliveryFee: parseMoney(bill['deliveryFee']),
      tipTotal: parseMoney(bill['tipTotal']),
      amountPaid: parseMoney(bill['amountPaid']),
      billStatus: bill['status'] as String? ?? 'OPEN',
      billId: bill['id'] as String?,
    );
  }
}
