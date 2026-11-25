import '../../../core/ui/feedback.dart';

typedef TJson = Map<String, dynamic>;

/// Estados de una mesa, con el texto que ve el personal.
const tableStatusLabels = <String, String>{
  'AVAILABLE': 'Libre',
  'OCCUPIED': 'Ocupada',
  'RESERVED': 'Reservada',
  'CLEANING': 'Por limpiar',
};

const serviceRequestLabels = <String, String>{
  'CALL_WAITER': 'Llama al mesero',
  'REQUEST_BILL': 'Pide la cuenta',
  'ASSISTANCE': 'Necesita ayuda',
};

class ServiceRequestView {
  const ServiceRequestView({required this.id, required this.type, required this.status, required this.createdAt});
  final String id;
  final String type;
  final String status;
  final DateTime createdAt;

  factory ServiceRequestView.fromJson(TJson j) => ServiceRequestView(
        id: j['id'] as String,
        type: j['type'] as String,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

/// La visita en curso: cuántos son, desde cuándo, pedidos y cuenta.
class TableSessionView {
  const TableSessionView({
    required this.id,
    required this.status,
    this.guestCount,
    required this.openedAt,
    required this.orderCount,
    required this.activeOrders,
    required this.total,
    required this.paid,
    required this.due,
    required this.requests,
    this.readyOrders = 0,
    this.waiterId,
    this.waiterName,
    this.customerId,
    this.customerName,
  });

  final String id;
  final String status;
  final int? guestCount;
  final DateTime openedAt;
  final int orderCount;
  final int activeOrders;
  final double total;
  final double paid;
  final double due;
  final List<ServiceRequestView> requests;

  /// Pedidos que la cocina ya terminó y el mesero tiene que llevar.
  final int readyOrders;

  /// Quién atiende la mesa.
  final String? waiterId;
  final String? waiterName;

  /// Cliente identificado en la mesa.
  final String? customerId;
  final String? customerName;

  bool get billRequested => status == 'BILL_REQUESTED' || requests.any((r) => r.type == 'REQUEST_BILL');
  bool get calling => requests.any((r) => r.type == 'CALL_WAITER' && r.status == 'OPEN');

  factory TableSessionView.fromJson(TJson j) => TableSessionView(
        id: j['id'] as String,
        status: j['status'] as String,
        guestCount: (j['guestCount'] as num?)?.toInt(),
        openedAt: DateTime.parse(j['openedAt'] as String).toLocal(),
        orderCount: (j['orderCount'] as num?)?.toInt() ?? 0,
        activeOrders: (j['activeOrders'] as num?)?.toInt() ?? 0,
        total: parseMoney(j['total']),
        paid: parseMoney(j['paid']),
        due: parseMoney(j['due']),
        requests: [for (final r in (j['requests'] as List? ?? const [])) ServiceRequestView.fromJson(r as TJson)],
        readyOrders: (j['readyOrders'] as num?)?.toInt() ?? 0,
        waiterId: (j['waiter'] as TJson?)?['id'] as String?,
        waiterName: (j['waiter'] as TJson?)?['name'] as String?,
        customerId: (j['customer'] as TJson?)?['id'] as String?,
        customerName: (j['customer'] as TJson?)?['name'] as String?,
      );
}

class TabletView {
  const TabletView({required this.id, required this.name, this.lastSeenAt});
  final String id;
  final String name;
  final DateTime? lastSeenAt;

  factory TabletView.fromJson(TJson j) => TabletView(
        id: j['id'] as String,
        name: j['name'] as String,
        lastSeenAt: j['lastSeenAt'] == null ? null : DateTime.parse(j['lastSeenAt'] as String).toLocal(),
      );
}

class TableView {
  const TableView({
    required this.id,
    required this.label,
    required this.areaId,
    required this.seats,
    required this.status,
    required this.posX,
    required this.posY,
    required this.tablets,
    this.session,
  });

  final String id;
  final String label;
  final String areaId;
  final int seats;
  final String status;
  final int posX;
  final int posY;
  final List<TabletView> tablets;
  final TableSessionView? session;

  bool get isOccupied => session != null || status == 'OCCUPIED';
  bool get hasRequests => session?.requests.isNotEmpty ?? false;

  /// Estado que se muestra: si hay clientes sentados, siempre "Ocupada".
  String get displayStatus => session != null ? 'OCCUPIED' : status;

  TableView moved(int x, int y) => TableView(
        id: id,
        label: label,
        areaId: areaId,
        seats: seats,
        status: status,
        posX: x,
        posY: y,
        tablets: tablets,
        session: session,
      );

  factory TableView.fromJson(TJson j) => TableView(
        id: j['id'] as String,
        label: j['label'] as String,
        areaId: j['areaId'] as String,
        seats: (j['seats'] as num?)?.toInt() ?? 4,
        status: j['status'] as String,
        posX: (j['posX'] as num?)?.toInt() ?? 0,
        posY: (j['posY'] as num?)?.toInt() ?? 0,
        tablets: [for (final d in (j['tablets'] as List? ?? const [])) TabletView.fromJson(d as TJson)],
        session: j['session'] == null ? null : TableSessionView.fromJson(j['session'] as TJson),
      );
}

class AreaView {
  const AreaView({required this.id, required this.name, required this.sortOrder, required this.tables});
  final String id;
  final String name;
  final int sortOrder;
  final List<TableView> tables;

  AreaView withTables(List<TableView> next) => AreaView(id: id, name: name, sortOrder: sortOrder, tables: next);

  factory AreaView.fromJson(TJson j) => AreaView(
        id: j['id'] as String,
        name: j['name'] as String,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        tables: [for (final t in (j['tables'] as List? ?? const [])) TableView.fromJson(t as TJson)],
      );
}
