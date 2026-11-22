import '../../../core/ui/feedback.dart';

typedef Json = Map<String, dynamic>;

/// Estado de una entrega para el repartidor.
const deliveryStatusLabels = <String, String>{
  'PENDING': 'Nueva',
  'ACCEPTED': 'Aceptada',
  'PICKED_UP': 'En camino',
  'DELIVERED': 'Entregada',
  'CANCELLED': 'Cancelada',
};

/// Estado de la cocina, para saber si ya se puede recoger.
const kitchenLabels = <String, String>{
  'PENDING_PAYMENT': 'Esperando pago',
  'PENDING_APPROVAL': 'Por aprobar',
  'PLACED': 'Recibido en cocina',
  'ACCEPTED': 'En cocina',
  'PREPARING': 'Preparando',
  'READY': 'Listo para recoger',
  'OUT_FOR_DELIVERY': 'Contigo',
  'COMPLETED': 'Entregado',
  'CANCELLED': 'Cancelado',
};

class DriverMe {
  const DriverMe({required this.name, required this.status, this.phone, this.vehicleType, this.vehicleColor, this.vehiclePlate});
  final String name;
  final String status;
  final String? phone;
  final String? vehicleType;
  final String? vehicleColor;
  final String? vehiclePlate;

  bool get available => status == 'AVAILABLE';
  String get vehicle => [vehicleType, vehicleColor, vehiclePlate].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  factory DriverMe.fromJson(Json j) => DriverMe(
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? 'OFFLINE',
        phone: j['phone'] as String?,
        vehicleType: j['vehicleType'] as String?,
        vehicleColor: j['vehicleColor'] as String?,
        vehiclePlate: j['vehiclePlate'] as String?,
      );
}

class DeliveryItem {
  const DeliveryItem({required this.name, required this.quantity, required this.modifiers, this.notes});
  final String name;
  final int quantity;
  final List<String> modifiers;
  final String? notes;
}

class Delivery {
  const Delivery({
    required this.assignmentId,
    required this.status,
    required this.active,
    required this.orderId,
    required this.number,
    required this.publicCode,
    required this.orderStatus,
    required this.items,
    required this.total,
    required this.tip,
    required this.paid,
    required this.amountDue,
    required this.updatedAt,
    this.customerName,
    this.customerPhone,
    this.address,
    this.instructions,
    this.notes,
    this.readyAt,
    this.estimatedReadyAt,
  });

  final String assignmentId;
  final String status;
  final bool active;
  final String orderId;
  final int number;
  final String publicCode;
  final String orderStatus;
  final List<DeliveryItem> items;
  final double total;
  final double tip;
  final bool paid;
  final double amountDue;
  final DateTime updatedAt;
  final String? customerName;
  final String? customerPhone;
  final Json? address;
  final String? instructions;
  final String? notes;
  final DateTime? readyAt;
  final DateTime? estimatedReadyAt;

  bool get readyToPickUp => orderStatus == 'READY';
  int get itemCount => items.fold(0, (n, i) => n + i.quantity);

  /// "123 Main St"
  String get street => (address?['street'] as String?) ?? 'Sin dirección';

  /// "Yonkers, NY 10701"
  String get cityLine {
    final a = address;
    if (a == null) return '';
    final stateZip = [a['state'], a['zipCode']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return [a['city'], stateZip].whereType<String>().where((s) => s.isNotEmpty).join(', ');
  }

  String get fullAddress => [street, cityLine].where((s) => s.isNotEmpty).join(', ');

  /// Orden en la lista: primero lo que va en camino, luego lo aceptado, luego lo nuevo.
  int get sortRank => switch (status) { 'PICKED_UP' => 0, 'ACCEPTED' => 1, _ => 2 };

  factory Delivery.fromJson(Json j) {
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    return Delivery(
      assignmentId: j['assignmentId'] as String,
      status: j['status'] as String,
      active: j['active'] as bool? ?? true,
      orderId: j['orderId'] as String,
      number: j['number'] as int,
      publicCode: j['publicCode'] as String? ?? '',
      orderStatus: j['orderStatus'] as String? ?? '',
      customerName: j['customerName'] as String?,
      customerPhone: j['customerPhone'] as String?,
      address: j['address'] is Map ? Map<String, dynamic>.from(j['address'] as Map) : null,
      instructions: j['instructions'] as String?,
      notes: j['notes'] as String?,
      items: ((j['items'] as List?) ?? const [])
          .map((i) => i as Map)
          .map((i) => DeliveryItem(
                name: i['name'] as String,
                quantity: i['quantity'] as int,
                modifiers: ((i['modifiers'] as List?) ?? const []).cast<String>(),
                notes: i['notes'] as String?,
              ))
          .toList(),
      total: parseMoney(j['total']),
      tip: parseMoney(j['tip']),
      paid: j['paid'] as bool? ?? false,
      amountDue: parseMoney(j['amountDue']),
      readyAt: date(j['readyAt']),
      estimatedReadyAt: date(j['estimatedReadyAt']),
      updatedAt: date(j['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
