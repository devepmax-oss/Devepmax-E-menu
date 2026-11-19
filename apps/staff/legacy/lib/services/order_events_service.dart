import 'dart:async';

class OrderEventsService {
  OrderEventsService._();

  static final OrderEventsService instance = OrderEventsService._();

  final StreamController<Map<String, dynamic>> _orderUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get orderUpdatedStream =>
      _orderUpdatedController.stream;

  void emitOrderUpdated(Map<String, dynamic> order) {
    if (order.isEmpty || _orderUpdatedController.isClosed) return;
    _orderUpdatedController.add(order);
  }

  void dispose() {
    _orderUpdatedController.close();
  }
}
