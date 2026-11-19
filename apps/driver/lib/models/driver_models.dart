class DriverProfile {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? photoUrl;
  final String? vehicleType;
  final String? vehiclePlate;
  final String? vehicleColor;
  final String status;
  final bool isActive;
  final double? lastLat;
  final double? lastLng;
  final DateTime? lastSeenAt;

  const DriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.photoUrl,
    this.vehicleType,
    this.vehiclePlate,
    this.vehicleColor,
    required this.status,
    required this.isActive,
    this.lastLat,
    this.lastLng,
    this.lastSeenAt,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    return DriverProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Driver',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      vehicleType: json['vehicleType']?.toString(),
      vehiclePlate: json['vehiclePlate']?.toString(),
      vehicleColor: json['vehicleColor']?.toString(),
      status: json['status']?.toString() ?? 'offline',
      isActive: json['isActive'] != false,
      lastLat: _toDouble(json['lastLat']),
      lastLng: _toDouble(json['lastLng']),
      lastSeenAt: _toDate(json['lastSeenAt']),
    );
  }
  bool get hasLocation => lastLat != null && lastLng != null;

  String get updatedKey =>
      '${name}_${phone}_${email}_${photoUrl}_${vehicleType}_${vehiclePlate}_${vehicleColor}_${status}_${lastLat}_${lastLng}_${lastSeenAt?.toIso8601String()}';
  DriverProfile copyWith({
    String? name,
    String? phone,
    String? email,
    String? photoUrl,
    String? vehicleType,
    String? vehiclePlate,
    String? vehicleColor,
    String? status,
    double? lastLat,
    double? lastLng,
    DateTime? lastSeenAt,
  }) {
    return DriverProfile(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      vehicleType: vehicleType ?? this.vehicleType,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      status: status ?? this.status,
      isActive: isActive,
      lastLat: lastLat ?? this.lastLat,
      lastLng: lastLng ?? this.lastLng,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

class DriverOrder {
  final String id;
  final String publicCode;
  final String orderType;
  final String orderStatus;
  final String customerName;
  final String customerPhone;
  final String? deliveryStreet;
  final String? deliveryCity;
  final String? deliveryState;
  final String? deliveryZipCode;
  final String? deliveryInstructions;
  final String? notes;
  final double subtotal;
  final double tax;
  final double deliveryFee;
  final double tip;
  final double total;
  final List<DriverOrderItem> items;

  const DriverOrder({
    required this.id,
    required this.publicCode,
    required this.orderType,
    required this.orderStatus,
    required this.customerName,
    required this.customerPhone,
    this.deliveryStreet,
    this.deliveryCity,
    this.deliveryState,
    this.deliveryZipCode,
    this.deliveryInstructions,
    this.notes,
    required this.subtotal,
    required this.tax,
    required this.deliveryFee,
    required this.tip,
    required this.total,
    required this.items,
  });

  factory DriverOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DriverOrder(
      id: json['id']?.toString() ?? '',
      publicCode:
          json['publicCode']?.toString() ?? json['code']?.toString() ?? '',
      orderType: json['orderType']?.toString() ??
          json['type']?.toString() ??
          'delivery',
      orderStatus:
          json['orderStatus']?.toString() ?? json['status']?.toString() ?? '',
      customerName: json['customerName']?.toString() ??
          json['customer']?.toString() ??
          'Cliente',
      customerPhone:
          json['customerPhone']?.toString() ?? json['phone']?.toString() ?? '',
      deliveryStreet: json['deliveryStreet']?.toString(),
      deliveryCity: json['deliveryCity']?.toString(),
      deliveryState: json['deliveryState']?.toString(),
      deliveryZipCode: json['deliveryZipCode']?.toString(),
      deliveryInstructions: json['deliveryInstructions']?.toString(),
      notes: json['notes']?.toString(),
      subtotal: _toDouble(json['subtotal']) ?? 0,
      tax: _toDouble(json['tax']) ?? 0,
      deliveryFee: _toDouble(json['deliveryFee']) ?? 0,
      tip: _toDouble(json['tip']) ?? 0,
      total: _toDouble(json['total']) ?? 0,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                  (e) => DriverOrderItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  String get deliveryAddress {
    final parts = [deliveryStreet, deliveryCity, deliveryState, deliveryZipCode]
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toList();
    return parts.isEmpty ? 'Dirección no disponible' : parts.join(', ');
  }
}

class DriverOrderItem {
  final String name;
  final int quantity;
  final double totalPrice;
  final String? notes;

  const DriverOrderItem({
    required this.name,
    required this.quantity,
    required this.totalPrice,
    this.notes,
  });

  factory DriverOrderItem.fromJson(Map<String, dynamic> json) {
    return DriverOrderItem(
      name: json['nameSnapshot']?.toString() ??
          json['name']?.toString() ??
          'Producto',
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 1,
      totalPrice: _toDouble(json['totalPrice']) ?? 0,
      notes: json['notes']?.toString(),
    );
  }
}

class DriverAssignment {
  final String id;
  final String orderId;
  final String driverId;
  final String status;
  final DriverOrder? order;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  const DriverAssignment({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.status,
    this.order,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  factory DriverAssignment.fromJson(Map<String, dynamic> json) {
    final orderJson = json['order'];
    return DriverAssignment(
      id: json['id']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? '',
      driverId: json['driverId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      order: orderJson is Map
          ? DriverOrder.fromJson(Map<String, dynamic>.from(orderJson))
          : null,
      acceptedAt: _toDate(json['acceptedAt']),
      pickedUpAt: _toDate(json['pickedUpAt']),
      deliveredAt: _toDate(json['deliveredAt']),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isPickedUp => status == 'picked_up';
  bool get isDelivered => status == 'delivered';
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
