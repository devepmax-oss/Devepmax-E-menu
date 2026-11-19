class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.roleName,
    required this.permissions,
  });

  final String id;
  final String name;
  final String? email;
  final String roleName;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String?,
        roleName: (json['role'] as Map<String, dynamic>)['name'] as String,
        permissions: (json['permissions'] as List).cast<String>().toSet(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': {'name': roleName},
        'permissions': permissions.toList(),
      };
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.employee,
  });

  final String accessToken;
  final String refreshToken;
  final Employee employee;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        employee: Employee.fromJson(json['employee'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'employee': employee.toJson(),
      };
}
