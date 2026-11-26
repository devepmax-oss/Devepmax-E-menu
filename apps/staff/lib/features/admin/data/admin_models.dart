typedef Json = Map<String, dynamic>;

class Role {
  const Role({
    required this.id,
    required this.name,
    required this.permissions,
    this.description,
    this.isSystem = false,
    this.employeeCount = 0,
  });
  final String id;
  final String name;
  final List<String> permissions;
  final String? description;
  final bool isSystem;
  final int employeeCount;

  bool get isAdmin => name == 'Admin';

  factory Role.fromJson(Json j) => Role(
        id: j['id'] as String,
        name: j['name'] as String,
        permissions: ((j['permissions'] as List?) ?? const []).cast<String>(),
        description: j['description'] as String?,
        isSystem: j['isSystem'] as bool? ?? false,
        employeeCount: (j['employeeCount'] as num?)?.toInt() ?? 0,
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
    this.jobTitle,
    this.photoUrl,
    this.hireDate,
    this.address,
    this.emergencyName,
    this.emergencyPhone,
    this.notes,
    this.terminatedAt,
    this.terminationReason,
    this.activeSessions,
    this.lastLoginAt,
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
  final String? jobTitle;
  final String? photoUrl;

  /// Fecha de ingreso (AAAA-MM-DD).
  final String? hireDate;
  final String? address;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? notes;
  final DateTime? terminatedAt;
  final String? terminationReason;

  /// Solo en la ficha (GET /employees/:id).
  final int? activeSessions;
  final DateTime? lastLoginAt;

  factory EmployeeView.fromJson(Json j) {
    final role = j['role'] as Json;
    final access = j['access'] as Json?;
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
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
      jobTitle: j['jobTitle'] as String?,
      photoUrl: j['photoUrl'] as String?,
      hireDate: j['hireDate'] as String?,
      address: j['address'] as String?,
      emergencyName: j['emergencyName'] as String?,
      emergencyPhone: j['emergencyPhone'] as String?,
      notes: j['notes'] as String?,
      terminatedAt: date(j['terminatedAt']),
      terminationReason: j['terminationReason'] as String?,
      activeSessions: (access?['activeSessions'] as num?)?.toInt(),
      lastLoginAt: date(access?['lastLoginAt']),
    );
  }
}

/// Una línea del historial de un empleado.
class EmployeeEvent {
  const EmployeeEvent({
    required this.id,
    required this.at,
    required this.action,
    required this.entityType,
    required this.about,
    required this.byThisEmployee,
    this.actorName,
    this.data,
  });
  final String id;
  final DateTime at;
  final String action;
  final String entityType;

  /// Cambio a su ficha o acceso (lo hizo otro o el sistema).
  final bool about;

  /// Lo hizo él mismo.
  final bool byThisEmployee;
  final String? actorName;
  final Json? data;

  factory EmployeeEvent.fromJson(Json j) => EmployeeEvent(
        id: j['id'] as String,
        at: DateTime.parse(j['at'] as String).toLocal(),
        action: j['action'] as String,
        entityType: j['entityType'] as String,
        about: j['about'] as bool? ?? false,
        byThisEmployee: j['byThisEmployee'] as bool? ?? false,
        actorName: j['actorName'] as String?,
        data: j['data'] is Map ? (j['data'] as Map).cast<String, dynamic>() : null,
      );
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
