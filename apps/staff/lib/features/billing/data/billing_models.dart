import '../../../core/ui/feedback.dart';

typedef BJson = Map<String, dynamic>;

const paymentMethodLabels = <String, String>{
  'CASH': 'Efectivo',
  'CARD_TERMINAL': 'Tarjeta',
  'CARD_ONLINE': 'Tarjeta en línea',
  'CARD_QR': 'QR en la mesa',
  'OTHER': 'Otro',
};

const billKindLabels = <String, String>{
  'TABLE': 'Mesa',
  'COUNTER': 'Mostrador',
  'PICKUP': 'Pickup',
  'DELIVERY': 'Delivery',
};

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();

class BillItem {
  const BillItem({
    required this.id,
    required this.orderNumber,
    required this.name,
    required this.quantity,
    required this.lineTotal,
    required this.discount,
    required this.modifiers,
    this.notes,
  });
  final String id;
  final int orderNumber;
  final String name;
  final int quantity;
  final double lineTotal;
  final double discount;
  final List<String> modifiers;
  final String? notes;

  factory BillItem.fromJson(BJson j) => BillItem(
        id: j['id'] as String,
        orderNumber: (j['orderNumber'] as num).toInt(),
        name: j['name'] as String,
        quantity: (j['quantity'] as num).toInt(),
        lineTotal: parseMoney(j['lineTotal']),
        discount: parseMoney(j['discount']),
        modifiers: [for (final m in j['modifiers'] as List? ?? const []) '$m'],
        notes: j['notes'] as String?,
      );
}

class BillDiscount {
  const BillDiscount({required this.id, required this.type, required this.value, required this.amount, required this.reason, this.itemName, this.authorizedBy});
  final String id;
  final String type;
  final double value;
  final double amount;
  final String reason;
  final String? itemName;
  final String? authorizedBy;

  String get label => type == 'PERCENT' ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%' : formatMoney(value);

  factory BillDiscount.fromJson(BJson j) => BillDiscount(
        id: j['id'] as String,
        type: j['type'] as String,
        value: parseMoney(j['value']),
        amount: parseMoney(j['amount']),
        reason: j['reason'] as String,
        itemName: j['itemName'] as String?,
        authorizedBy: j['authorizedBy'] as String?,
      );
}

class BillPayment {
  const BillPayment({
    required this.id,
    required this.method,
    required this.status,
    required this.amount,
    required this.tipAmount,
    this.changeGiven,
    this.reference,
    required this.createdAt,
    this.employee,
  });
  final String id;
  final String method;
  final String status;
  final double amount;
  final double tipAmount;
  final double? changeGiven;
  final String? reference;
  final DateTime createdAt;
  final String? employee;

  factory BillPayment.fromJson(BJson j) => BillPayment(
        id: j['id'] as String,
        method: j['method'] as String,
        status: j['status'] as String,
        amount: parseMoney(j['amount']),
        tipAmount: parseMoney(j['tipAmount']),
        changeGiven: j['changeGiven'] == null ? null : parseMoney(j['changeGiven']),
        reference: j['reference'] as String?,
        createdAt: _date(j['createdAt']),
        employee: j['employee'] as String?,
      );
}

class BillOrderRef {
  const BillOrderRef({required this.id, required this.number, required this.status, this.customerName});
  final String id;
  final int number;
  final String status;
  final String? customerName;

  factory BillOrderRef.fromJson(BJson j) => BillOrderRef(
        id: j['id'] as String,
        number: (j['number'] as num).toInt(),
        status: j['status'] as String,
        customerName: j['customerName'] as String?,
      );
}

class BillView {
  const BillView({
    required this.id,
    required this.status,
    required this.kind,
    required this.label,
    this.tableId,
    this.tableLabel,
    this.sessionId,
    this.guestCount,
    required this.billRequested,
    required this.openedAt,
    required this.orders,
    required this.items,
    required this.discounts,
    required this.payments,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.deliveryFee,
    required this.tipTotal,
    required this.total,
    required this.amountPaid,
    required this.due,
  });

  final String id;
  final String status;
  final String kind;
  final String label;
  final String? tableId;
  final String? tableLabel;
  final String? sessionId;
  final int? guestCount;
  final bool billRequested;
  final DateTime openedAt;
  final List<BillOrderRef> orders;
  final List<BillItem> items;
  final List<BillDiscount> discounts;
  final List<BillPayment> payments;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double deliveryFee;
  final double tipTotal;
  final double total;
  final double amountPaid;
  final double due;

  bool get isOpen => status == 'UNPAID' || status == 'PARTIALLY_PAID';
  bool get hasPayments => payments.any((p) => p.status == 'SUCCEEDED');
  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  factory BillView.fromJson(BJson j) {
    final table = j['table'] as BJson?;
    final session = j['session'] as BJson?;
    return BillView(
      id: j['id'] as String,
      status: j['status'] as String,
      kind: j['kind'] as String,
      label: j['label'] as String,
      tableId: table?['id'] as String?,
      tableLabel: table?['label'] as String?,
      sessionId: session?['id'] as String?,
      guestCount: (session?['guestCount'] as num?)?.toInt(),
      billRequested: j['billRequested'] as bool? ?? false,
      openedAt: _date(j['openedAt']),
      orders: [for (final o in j['orders'] as List? ?? const []) BillOrderRef.fromJson(o as BJson)],
      items: [for (final i in j['items'] as List? ?? const []) BillItem.fromJson(i as BJson)],
      discounts: [for (final d in j['discounts'] as List? ?? const []) BillDiscount.fromJson(d as BJson)],
      payments: [for (final p in j['payments'] as List? ?? const []) BillPayment.fromJson(p as BJson)],
      subtotal: parseMoney(j['subtotal']),
      discountTotal: parseMoney(j['discountTotal']),
      taxTotal: parseMoney(j['taxTotal']),
      deliveryFee: parseMoney(j['deliveryFee']),
      tipTotal: parseMoney(j['tipTotal']),
      total: parseMoney(j['total']),
      amountPaid: parseMoney(j['amountPaid']),
      due: parseMoney(j['due']),
    );
  }
}

class ShiftSale {
  const ShiftSale({required this.method, required this.count, required this.amount, required this.tips});
  final String method;
  final int count;
  final double amount;
  final double tips;
}

class ShiftMovement {
  const ShiftMovement({required this.type, required this.amount, required this.reason, required this.createdAt});
  final String type;
  final double amount;
  final String reason;
  final DateTime createdAt;
}

class CashShiftView {
  const CashShiftView({
    required this.id,
    required this.openedAt,
    this.closedAt,
    this.openedBy,
    required this.openingCash,
    required this.sales,
    required this.totalSales,
    required this.totalTips,
    required this.movements,
    required this.expectedCash,
    this.countedCash,
    this.difference,
  });
  final String id;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? openedBy;
  final double openingCash;
  final List<ShiftSale> sales;
  final double totalSales;
  final double totalTips;
  final List<ShiftMovement> movements;
  final double expectedCash;
  final double? countedCash;
  final double? difference;

  factory CashShiftView.fromJson(BJson j) => CashShiftView(
        id: j['id'] as String,
        openedAt: _date(j['openedAt']),
        closedAt: j['closedAt'] == null ? null : _date(j['closedAt']),
        openedBy: j['openedBy'] as String?,
        openingCash: parseMoney(j['openingCash']),
        sales: [
          for (final s in j['sales'] as List? ?? const [])
            ShiftSale(
              method: (s as BJson)['method'] as String,
              count: (s['count'] as num).toInt(),
              amount: parseMoney(s['amount']),
              tips: parseMoney(s['tips']),
            ),
        ],
        totalSales: parseMoney(j['totalSales']),
        totalTips: parseMoney(j['totalTips']),
        movements: [
          for (final m in j['movements'] as List? ?? const [])
            ShiftMovement(
              type: (m as BJson)['type'] as String,
              amount: parseMoney(m['amount']),
              reason: m['reason'] as String,
              createdAt: _date(m['createdAt']),
            ),
        ],
        expectedCash: parseMoney(j['expectedCash']),
        countedCash: j['countedCash'] == null ? null : parseMoney(j['countedCash']),
        difference: j['difference'] == null ? null : parseMoney(j['difference']),
      );
}
