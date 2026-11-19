typedef Json = Map<String, dynamic>;

class Role {
  const Role({required this.id, required this.name, required this.permissions});
  final String id;
  final String name;
  final List<String> permissions;

  factory Role.fromJson(Json j) => Role(
        id: j['id'] as String,
        name: j['name'] as String,
        permissions: ((j['permissions'] as List?) ?? const []).cast<String>(),
      );
}

class EmployeeView {
  const EmployeeView({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.isActive,
    required this.hasPassword,
    required this.hasPin,
    required this.roleId,
    required this.roleName,
  });
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final bool isActive;
  final bool hasPassword;
  final bool hasPin;
  final String roleId;
  final String roleName;

  factory EmployeeView.fromJson(Json j) {
    final role = j['role'] as Json;
    return EmployeeView(
      id: j['id'] as String,
      name: j['name'] as String,
      email: j['email'] as String?,
      phone: j['phone'] as String?,
      isActive: j['isActive'] as bool? ?? true,
      hasPassword: j['hasPassword'] as bool? ?? false,
      hasPin: j['hasPin'] as bool? ?? false,
      roleId: role['id'] as String,
      roleName: role['name'] as String,
    );
  }
}

/// Tipos de dispositivo y su nombre para mostrar.
const deviceTypeLabels = <String, String>{
  'EMENU': 'Tablet de mesa',
  'POS': 'Caja (POS)',
  'KDS': 'Pantalla de cocina',
  'WAITER': 'Mesero',
};

class DeviceView {
  const DeviceView({
    required this.id,
    required this.name,
    required this.type,
    this.tableId,
    this.stationId,
    required this.isActive,
    required this.isPaired,
    this.pairingCode,
    this.pairingExpiresAt,
    this.appVersion,
    this.lastSeenAt,
  });
  final String id;
  final String name;
  final String type;
  final String? tableId;
  final String? stationId;
  final bool isActive;
  final bool isPaired;
  final String? pairingCode;
  final DateTime? pairingExpiresAt;
  final String? appVersion;
  final DateTime? lastSeenAt;

  bool get hasValidCode =>
      pairingCode != null && pairingExpiresAt != null && pairingExpiresAt!.isAfter(DateTime.now());

  factory DeviceView.fromJson(Json j) => DeviceView(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        tableId: j['tableId'] as String?,
        stationId: j['stationId'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        isPaired: j['isPaired'] as bool? ?? false,
        pairingCode: j['pairingCode'] as String?,
        pairingExpiresAt: DateTime.tryParse(j['pairingExpiresAt'] as String? ?? '')?.toLocal(),
        appVersion: j['appVersion'] as String?,
        lastSeenAt: DateTime.tryParse(j['lastSeenAt'] as String? ?? '')?.toLocal(),
      );
}

class OpeningHour {
  const OpeningHour({required this.dayOfWeek, required this.opensAt, required this.closesAt});
  final int dayOfWeek;
  final String opensAt;
  final String closesAt;

  factory OpeningHour.fromJson(Json j) => OpeningHour(
        dayOfWeek: j['dayOfWeek'] as int,
        opensAt: j['opensAt'] as String,
        closesAt: j['closesAt'] as String,
      );

  Json toJson() => {'dayOfWeek': dayOfWeek, 'opensAt': opensAt, 'closesAt': closesAt};
}
