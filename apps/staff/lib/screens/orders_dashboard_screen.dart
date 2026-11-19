import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:gopicadera/core/config/app_config.dart';

import '../services/notification_service.dart';
import '../services/order_events_service.dart';
import '../services/printer_service.dart';
import '../services/socket_service.dart';

class OrdersDashboardScreen extends StatefulWidget {
  const OrdersDashboardScreen({super.key});

  @override
  State<OrdersDashboardScreen> createState() => _OrdersDashboardScreenState();
}

class _OrdersDashboardScreenState extends State<OrdersDashboardScreen> {
  final List<AppOrder> _orders = [];
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _orderUpdatedSubscription;

  bool _loading = true;
  bool _hasError = false;
  bool _syncing = false;

  String _selectedFilter = 'Nuevos';
  String _searchQuery = '';
  AppOrder? _selectedOrder;

  final String baseUrl = AppConfig.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _initSocketListeners();
    _initInternalOrderEvents();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
        _ensureSelection();
      });
    });
  }

  @override
  void dispose() {
    _orderUpdatedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initInternalOrderEvents() {
    _orderUpdatedSubscription?.cancel();
    _orderUpdatedSubscription =
        OrderEventsService.instance.orderUpdatedStream.listen((data) {
      try {
        final updated = AppOrder.fromJson(Map<String, dynamic>.from(data));
        if (!mounted) return;

        setState(() {
          updated.needsAttention = false;
          _upsertOrder(updated, preserveAttention: false);

          if (updated.status == 'preparing') {
            _selectedFilter = 'Preparando';
          } else {
            _selectedFilter = _filterForStatus(
              updated.status,
              updated.fulfillmentType,
            );
          }

          _ensureSelection(preferId: updated.id);
        });
      } catch (e) {
        debugPrint('Error applying internal order update: $e');
      }
    });
  }

  void _initSocketListeners() {
    final socketService = SocketService.instance;
    socketService.init();

    socketService.on('new_order', (data) async {
      try {
        final incoming = AppOrder.fromJson(Map<String, dynamic>.from(data));
        if (!mounted) return;

        setState(() {
          incoming.needsAttention = true;
          _upsertOrder(incoming);
          _ensureSelection(preferId: incoming.id);
        });

        if (PrinterService.instance.autoPrintNewOrders) {
          await PrinterService.instance.printOrder(incoming);
        }
      } catch (e) {
        debugPrint('Error parsing new_order in dashboard: $e');
      }
    });

    socketService.on('order_updated', (data) {
      try {
        final updated = AppOrder.fromJson(Map<String, dynamic>.from(data));
        if (!mounted) return;

        setState(() {
          _upsertOrder(updated, preserveAttention: true);
          if (_selectedOrder?.id == updated.id) {
            _selectedOrder = updated;
          }
          _ensureSelection(preferId: updated.id);
        });
      } catch (e) {
        debugPrint('Error parsing order_updated in dashboard: $e');
      }
    });
  }

  void _upsertOrder(AppOrder order, {bool preserveAttention = false}) {
    final index = _orders.indexWhere((o) => o.id == order.id);

    if (index >= 0) {
      if (preserveAttention) {
        order.needsAttention = _orders[index].needsAttention;
      }
      _orders[index] = order;
    } else {
      _orders.insert(0, order);
    }

    _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _ensureSelection({String? preferId}) {
    final visible = _filteredOrders;
    if (visible.isEmpty) {
      _selectedOrder = null;
      return;
    }

    final currentId = _selectedOrder?.id;

    _selectedOrder = visible.firstWhere(
      (order) => order.id == preferId || order.id == currentId,
      orElse: () => visible.first,
    );
  }

  Future<void> _loadOrders() async {
    try {
      setState(() {
        _loading = true;
        _hasError = false;
      });

      final url = Uri.parse('$baseUrl/api/orders/active');
      debugPrint('GET => $url');

      final response = await http.get(
        url,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }

      final loaded = _decodeOrders(response.body)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;

      setState(() {
        _orders
          ..clear()
          ..addAll(loaded);
        _loading = false;
        _ensureSelection();
      });
    } catch (e) {
      debugPrint('Error loading orders: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  List<AppOrder> _decodeOrders(String body) {
    final decoded = jsonDecode(body);
    final List<dynamic> rawOrders;

    if (decoded is Map<String, dynamic>) {
      rawOrders = (decoded['orders'] as List?) ?? [];
    } else if (decoded is List) {
      rawOrders = decoded;
    } else {
      rawOrders = [];
    }

    return rawOrders
        .whereType<Map<String, dynamic>>()
        .map(AppOrder.fromJson)
        .toList();
  }

  Future<void> _reloadAll() async {
    await _loadOrders();
  }

  Future<void> _updateOrderStatus(AppOrder order, String uiStatus) async {
    try {
      await NotificationService.stopIncomingLoopSound();

      final backendStatus = AppOrder.backendStatusForUiStatus(uiStatus);
      final url = Uri.parse('$baseUrl/api/orders/${order.id}/status');
      debugPrint(
          'PATCH => $url uiStatus=$uiStatus backendStatus=$backendStatus');

      final response = await http
          .patch(
            url,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
            },
            body: jsonEncode({
              'status': uiStatus,
              'orderStatus': backendStatus,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw Exception('${response.statusCode} ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawOrder = decoded['order'] ?? decoded;
      final updated = AppOrder.fromJson(Map<String, dynamic>.from(rawOrder));

      if (!mounted) return;
      setState(() {
        updated.needsAttention = false;
        _upsertOrder(updated, preserveAttention: false);
        _selectedFilter =
            _filterForStatus(updated.status, updated.fulfillmentType);
        _ensureSelection(preferId: updated.id);
      });
    } catch (e) {
      debugPrint('Error updating status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el estado: $e')),
      );
    }
  }

  String _filterForStatus(String status, String fulfillmentType) {
    switch (status) {
      case 'new':
        return 'Nuevos';
      case 'preparing':
        return 'Preparando';
      case 'ready':
        return fulfillmentType == 'pickup' ? 'Pickup' : 'Listas';
      case 'dispatch':
        return 'Delivery';
      case 'delivered':
      case 'picked_up':
        return 'Completadas';
      default:
        return 'Todas';
    }
  }

  Future<void> _addTime(AppOrder order, int minutes) async {
    try {
      final url = Uri.parse('$baseUrl/api/orders/${order.id}/add-time');
      final response = await http
          .post(
            url,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
            },
            body: jsonEncode({'minutes': minutes}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 400) {
        throw Exception('${response.statusCode} ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawOrder = decoded['order'] ?? decoded;
      final updated = AppOrder.fromJson(Map<String, dynamic>.from(rawOrder));

      if (!mounted) return;
      setState(() {
        _upsertOrder(updated, preserveAttention: true);
        _ensureSelection(preferId: updated.id);
      });
    } catch (e) {
      debugPrint('Error add-time: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo agregar tiempo')),
      );
    }
  }

  Future<void> _showAddTimeDialog(AppOrder order) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 180),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agregar tiempo',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Orden #${order.publicCode} · ${order.customerName}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [5, 10, 15, 20, 30]
                        .map(
                          (m) => SizedBox(
                            width: 140,
                            height: 58,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF3F4F6),
                                foregroundColor: const Color(0xFF111827),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                if (!dialogContext.mounted) return;
                                Navigator.of(dialogContext).pop();
                                await _addTime(order, m);
                              },
                              child: Text(
                                '+ $m min',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _printOrder(AppOrder order) async {
    try {
      final ok = await PrinterService.instance.printOrder(order);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Impresión enviada para la orden #${order.publicCode}'
                : 'No se pudo conectar con la impresora',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error printing order: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo imprimir la orden')),
      );
    }
  }

  Future<void> _testPrinter() async {
    try {
      setState(() => _syncing = true);
      final ok = await PrinterService.instance.testPrint();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Impresión de prueba enviada'
                : 'No se pudo conectar con la impresora',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error test printer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo hacer la prueba de impresión')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<AppOrder> get _tabFilteredOrders {
    switch (_selectedFilter) {
      case 'Nuevos':
        return _orders.where((o) => o.status == 'new').toList();
      case 'Preparando':
        return _orders.where((o) => o.status == 'preparing').toList();
      case 'Listas':
        return _orders.where((o) => o.status == 'ready').toList();
      case 'Delivery':
        return _orders
            .where((o) =>
                o.fulfillmentType == 'delivery' && o.status == 'dispatch')
            .toList();
      case 'Pickup':
        return _orders
            .where(
              (o) =>
                  o.fulfillmentType == 'pickup' &&
                  (o.status == 'new' ||
                      o.status == 'preparing' ||
                      o.status == 'ready'),
            )
            .toList();
      case 'Completadas':
        return _orders
            .where((o) => o.status == 'delivered' || o.status == 'picked_up')
            .toList();
      case 'Todas':
      default:
        return _orders;
    }
  }

  List<AppOrder> get _filteredOrders {
    final base = _tabFilteredOrders;
    if (_searchQuery.isEmpty) return base;

    final query = _searchQuery.toLowerCase();
    return base.where((order) {
      return order.customerName.toLowerCase().contains(query) ||
          order.phone.toLowerCase().contains(query) ||
          order.id.toLowerCase().contains(query) ||
          order.publicCode.toLowerCase().contains(query);
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'new':
        return const Color(0xFFD9480F);
      case 'preparing':
        return const Color(0xFF2563EB);
      case 'ready':
        return const Color(0xFF15803D);
      case 'dispatch':
        return const Color(0xFF7C3AED);
      case 'delivered':
      case 'picked_up':
        return const Color(0xFF667085);
      default:
        return const Color(0xFF111827);
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'new':
        return const Color(0xFFFFE8DE);
      case 'preparing':
        return const Color(0xFFEAF2FF);
      case 'ready':
        return const Color(0xFFEAF8EE);
      case 'dispatch':
        return const Color(0xFFF2EBFF);
      default:
        return const Color(0xFFF2F4F7);
    }
  }

  Color _fulfillmentColor(String type) {
    return type == 'pickup' ? const Color(0xFF0F766E) : const Color(0xFFB42318);
  }

  Color _fulfillmentBg(String type) {
    return type == 'pickup' ? const Color(0xFFDFF7F3) : const Color(0xFFFEE4E2);
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'new':
        return 'Nueva';
      case 'preparing':
        return 'Preparando';
      case 'ready':
        return 'Lista';
      case 'dispatch':
        return 'Despacho';
      case 'delivered':
        return 'Entregada';
      case 'picked_up':
        return 'Recogida';
      default:
        return status;
    }
  }

  String _fulfillmentLabel(String type) {
    return type == 'pickup' ? 'Pickup' : 'Delivery';
  }

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    return 'Hace ${diff.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _selectedOrder != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = width < 1080;
            final padding = compact ? 8.0 : 14.0;
            final gap = compact ? 8.0 : 12.0;

            return Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                children: [
                  Expanded(
                    flex: compact ? 11 : 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DashboardHeader(
                          controller: _searchController,
                          syncing: _syncing,
                        ),
                        const SizedBox(height: 8),
                        _FilterBar(
                          selectedFilter: _selectedFilter,
                          onSelected: (value) {
                            setState(() {
                              _selectedFilter = value;
                              _ensureSelection();
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(compact ? 22 : 28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D0F172A),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 14 : 20,
                                    compact ? 12 : 16,
                                    compact ? 14 : 20,
                                    compact ? 8 : 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Órdenes activas',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: compact ? 18 : 22,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF111827),
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: compact ? 10 : 12,
                                          vertical: compact ? 6 : 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3ED),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${_orders.where((o) => o.status == 'new').length} nuevas',
                                          style: TextStyle(
                                            color: const Color(0xFFD9480F),
                                            fontWeight: FontWeight.w800,
                                            fontSize: compact ? 12 : 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: _loading
                                      ? const Center(child: CircularProgressIndicator())
                                      : _hasError
                                          ? _OrdersErrorState(onRetry: _reloadAll)
                                          : _filteredOrders.isEmpty
                                              ? _EmptyOrdersState(hasSearch: _searchQuery.isNotEmpty)
                                              : RefreshIndicator(
                                                  onRefresh: _reloadAll,
                                                  child: ListView.separated(
                                                    padding: EdgeInsets.all(compact ? 10 : 14),
                                                    itemCount: _filteredOrders.length,
                                                    separatorBuilder: (_, __) => SizedBox(height: compact ? 8 : 12),
                                                    itemBuilder: (context, index) {
                                                      final item = _filteredOrders[index];
                                                      final selected = _selectedOrder?.id == item.id;
                                                      final isNew = item.status == 'new';

                                                      return _OrderListCard(
                                                        order: item,
                                                        selected: selected,
                                                        isNew: isNew,
                                                        relativeTime: _relativeTime(item.createdAt),
                                                        statusLabel: _statusLabel(item.status),
                                                        statusFg: _statusColor(item.status),
                                                        statusBg: _statusBg(item.status),
                                                        fulfillmentLabel: _fulfillmentLabel(item.fulfillmentType),
                                                        fulfillmentFg: _fulfillmentColor(item.fulfillmentType),
                                                        fulfillmentBg: _fulfillmentBg(item.fulfillmentType),
                                                        onTap: () => setState(() => _selectedOrder = item),
                                                        onAccept: item.status == 'new'
                                                            ? () => _updateOrderStatus(item, 'preparing')
                                                            : null,
                                                        onDispatch: item.status == 'ready' && item.fulfillmentType == 'delivery'
                                                            ? () => _updateOrderStatus(item, 'dispatch')
                                                            : null,
                                                        onPickedUp: item.status == 'ready' && item.fulfillmentType == 'pickup'
                                                            ? () => _updateOrderStatus(item, 'picked_up')
                                                            : null,
                                                        onDelivered: item.status == 'dispatch'
                                                            ? () => _updateOrderStatus(item, 'delivered')
                                                            : null,
                                                      );
                                                    },
                                                  ),
                                                ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: compact ? 9 : 8,
                    child: hasSelected
                        ? _OrderDetailPanel(
                            order: _selectedOrder!,
                            statusLabel: _statusLabel(_selectedOrder!.status),
                            statusFg: _statusColor(_selectedOrder!.status),
                            statusBg: _statusBg(_selectedOrder!.status),
                            fulfillmentLabel: _fulfillmentLabel(_selectedOrder!.fulfillmentType),
                            fulfillmentFg: _fulfillmentColor(_selectedOrder!.fulfillmentType),
                            fulfillmentBg: _fulfillmentBg(_selectedOrder!.fulfillmentType),
                            onPrint: () => _printOrder(_selectedOrder!),
                            onAddTime: _selectedOrder!.status == 'preparing'
                                ? () => _showAddTimeDialog(_selectedOrder!)
                                : null,
                            onAccept: _selectedOrder!.status == 'new'
                                ? () => _updateOrderStatus(_selectedOrder!, 'preparing')
                                : null,
                            onReady: _selectedOrder!.status == 'preparing'
                                ? () => _updateOrderStatus(_selectedOrder!, 'ready')
                                : null,
                            onDispatch: _selectedOrder!.status == 'ready' &&
                                    _selectedOrder!.fulfillmentType == 'delivery'
                                ? () => _updateOrderStatus(_selectedOrder!, 'dispatch')
                                : null,
                            onPickedUp: _selectedOrder!.status == 'ready' &&
                                    _selectedOrder!.fulfillmentType == 'pickup'
                                ? () => _updateOrderStatus(_selectedOrder!, 'picked_up')
                                : null,
                            onDelivered: _selectedOrder!.status == 'dispatch'
                                ? () => _updateOrderStatus(_selectedOrder!, 'delivered')
                                : null,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(compact ? 22 : 28),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D0F172A),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: Text(
                                  'Selecciona una orden para ver sus detalles.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF667085),
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderListCard extends StatelessWidget {
  const _OrderListCard({
    required this.order,
    required this.selected,
    required this.isNew,
    required this.relativeTime,
    required this.statusLabel,
    required this.statusFg,
    required this.statusBg,
    required this.fulfillmentLabel,
    required this.fulfillmentFg,
    required this.fulfillmentBg,
    required this.onTap,
    this.onAccept,
    this.onDispatch,
    this.onPickedUp,
    this.onDelivered,
  });

  final AppOrder order;
  final bool selected;
  final bool isNew;
  final String relativeTime;
  final String statusLabel;
  final Color statusFg;
  final Color statusBg;
  final String fulfillmentLabel;
  final Color fulfillmentFg;
  final Color fulfillmentBg;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDispatch;
  final VoidCallback? onPickedUp;
  final VoidCallback? onDelivered;

  @override
  Widget build(BuildContext context) {
    VoidCallback? action;
    String? actionLabel;

    if (onAccept != null) {
      action = onAccept;
      actionLabel = 'Aceptar pedido';
    } else if (onDispatch != null) {
      action = onDispatch;
      actionLabel = 'Despachar';
    } else if (onPickedUp != null) {
      action = onPickedUp;
      actionLabel = 'Marcar recogido';
    } else if (onDelivered != null) {
      action = onDelivered;
      actionLabel = 'Finalizar entrega';
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isNew ? const Color(0xFFFFFBF8) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? const Color(0xFF111827)
                : isNew
                    ? const Color(0xFFFFD8C2)
                    : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: isNew
              ? const [
                  BoxShadow(
                    color: Color(0x12D9480F),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.publicCode}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isNew
                              ? const Color(0xFFD9480F)
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${order.total}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      relativeTime,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: statusLabel, fg: statusFg, bg: statusBg),
                _Pill(
                    label: fulfillmentLabel,
                    fg: fulfillmentFg,
                    bg: fulfillmentBg),
                _SoftInfoPill(label: '${order.items.length} items'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              order.fulfillmentType == 'pickup'
                  ? 'Recoge en restaurante'
                  : order.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (action != null && actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child:
                    _HugeInlineActionButton(label: actionLabel, onTap: action),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final TextEditingController controller;
  final bool syncing;
  final VoidCallback? onTestPrinter;

  const _DashboardHeader({
    required this.controller,
    required this.syncing,
    this.onTestPrinter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final titleWidth = compact ? 150.0 : 210.0;
        final searchHeight = compact ? 44.0 : 50.0;

        return SizedBox(
          height: compact ? 52 : 58,
          child: Row(
            children: [
              SizedBox(
                width: titleWidth,
                child: Text(
                  'Órdenes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 30 : 38,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
              ),
              if (syncing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: searchHeight,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(compact ? 16 : 20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: const Color(0xFF98A2B3),
                        size: compact ? 20 : 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: compact ? 'Buscar orden' : 'Buscar cliente, pedido o teléfono',
                            hintStyle: TextStyle(
                              color: const Color(0xFF98A2B3),
                              fontSize: compact ? 13 : 15,
                              fontWeight: FontWeight.w600,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: TextStyle(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrdersErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _OrdersErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 54, color: Color(0xFF98A2B3)),
            const SizedBox(height: 14),
            const Text(
              'No se pudieron cargar las órdenes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  final bool hasSearch;

  const _EmptyOrdersState({required this.hasSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.inbox_rounded,
              size: 54,
              color: const Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No encontramos órdenes con esa búsqueda'
                  : 'No hay órdenes en esta vista',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstimatedTimeCard extends StatelessWidget {
  final int minutes;

  const _EstimatedTimeCard({required this.minutes});

  @override
  Widget build(BuildContext context) {
    final label = minutes <= 0 ? 'Sin tiempo asignado' : '$minutes min';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: Color(0xFFD97706)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Tiempo estimado',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF9A3412),
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF9A3412),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  const _FilterBar({required this.selectedFilter, required this.onSelected});

  static const filters = [
    'Todas',
    'Nuevos',
    'Preparando',
    'Listas',
    'Delivery',
    'Pickup',
    'Completadas',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = selectedFilter == filter;

          return GestureDetector(
            onTap: () => onSelected(filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF111827) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Center(
                child: Text(
                  filter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF344054),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderDetailPanel extends StatelessWidget {
  final AppOrder order;
  final String statusLabel;
  final Color statusFg;
  final Color statusBg;
  final String fulfillmentLabel;
  final Color fulfillmentFg;
  final Color fulfillmentBg;
  final VoidCallback onPrint;
  final VoidCallback? onAddTime;
  final VoidCallback? onAccept;
  final VoidCallback? onReady;
  final VoidCallback? onDispatch;
  final VoidCallback? onPickedUp;
  final VoidCallback? onDelivered;

  const _OrderDetailPanel({
    required this.order,
    required this.statusLabel,
    required this.statusFg,
    required this.statusBg,
    required this.fulfillmentLabel,
    required this.fulfillmentFg,
    required this.fulfillmentBg,
    required this.onPrint,
    this.onAddTime,
    this.onAccept,
    this.onReady,
    this.onDispatch,
    this.onPickedUp,
    this.onDelivered,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrimaryAction = onAccept != null ||
        onReady != null ||
        onDispatch != null ||
        onPickedUp != null ||
        onDelivered != null;

    String primaryLabel = '';
    IconData primaryIcon = Icons.task_alt_rounded;
    Color primaryColor = const Color(0xFF111827);
    VoidCallback? primaryAction;

    if (onAccept != null) {
      primaryLabel = 'Aceptar pedido';
      primaryIcon = Icons.check_circle_rounded;
      primaryColor = const Color(0xFFFF6A3D);
      primaryAction = onAccept;
    } else if (onReady != null) {
      primaryLabel = 'Marcar lista';
      primaryIcon = Icons.task_alt_rounded;
      primaryColor = const Color(0xFF15803D);
      primaryAction = onReady;
    } else if (onDispatch != null) {
      primaryLabel = 'Despachar';
      primaryIcon = Icons.delivery_dining_rounded;
      primaryColor = const Color(0xFF7C3AED);
      primaryAction = onDispatch;
    } else if (onPickedUp != null) {
      primaryLabel = 'Marcar recogido';
      primaryIcon = Icons.store_mall_directory_rounded;
      primaryColor = const Color(0xFF0F766E);
      primaryAction = onPickedUp;
    } else if (onDelivered != null) {
      primaryLabel = 'Finalizar entrega';
      primaryIcon = Icons.task_alt_rounded;
      primaryColor = const Color(0xFF111827);
      primaryAction = onDelivered;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 22 : 28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  compact ? 12 : 16,
                  compact ? 14 : 18,
                  compact ? 10 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pedido #${order.publicCode}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 21 : 25,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onPrint,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF3F4F6),
                            minimumSize: Size(compact ? 40 : 44, compact ? 40 : 44),
                          ),
                          icon: Icon(Icons.print_rounded, size: compact ? 20 : 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(label: statusLabel, fg: statusFg, bg: statusBg),
                        _Pill(label: fulfillmentLabel, fg: fulfillmentFg, bg: fulfillmentBg),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 14 : 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 22 : 26,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF111827),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        order.fulfillmentType == 'pickup' ? 'Recoge en tienda' : order.address,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
                          color: const Color(0xFF475467),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _DetailBlock(title: 'Total', value: '\$${order.total}')),
                          const SizedBox(width: 10),
                          Expanded(child: _DetailBlock(title: 'Pago', value: order.paymentMethod.toUpperCase())),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _EstimatedTimeCard(minutes: order.estimatedReadyMinutes),
                      const SizedBox(height: 14),
                      const Text(
                        'Productos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: EdgeInsets.all(compact ? 12 : 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          children: order.items
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE5E7EB)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${item.qty}x',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                            if (item.notes.trim().isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                item.notes,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF667085),
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '\$${item.price}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Notas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(compact ? 12 : 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          order.note.isEmpty ? 'Sin notas adicionales.' : order.note,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF475467),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(compact ? 10 : 12),
                child: Column(
                  children: [
                    if (hasPrimaryAction && primaryAction != null)
                      _HugeActionButton(
                        label: primaryLabel,
                        icon: primaryIcon,
                        bg: primaryColor,
                        fg: Colors.white,
                        onTap: primaryAction,
                      ),
                    if (hasPrimaryAction && onAddTime != null) const SizedBox(height: 8),
                    if (onAddTime != null)
                      _HugeActionButton(
                        label: 'Agregar tiempo',
                        icon: Icons.schedule_rounded,
                        bg: const Color(0xFFF3F4F6),
                        fg: const Color(0xFF111827),
                        onTap: onAddTime!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;
  final Color? valueColor;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.isStrong = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = valueColor ?? const Color(0xFF111827);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isStrong ? 16 : 14,
                fontWeight: isStrong ? FontWeight.w900 : FontWeight.w700,
                color: const Color(0xFF475467),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isStrong ? 18 : 15,
              fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HugeActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _HugeActionButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 21),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: fg),
          ],
        ),
      ),
    );
  }
}

class _HugeInlineActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HugeInlineActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6A3D),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: onTap,
        icon: const Icon(Icons.check_circle_rounded),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String value;

  const _DetailBlock({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _Pill({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SoftInfoPill extends StatelessWidget {
  final String label;

  const _SoftInfoPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF344054),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AppOrder {
  final String id;
  final String publicCode;
  final String customerName;
  final String fulfillmentType;
  final String subtotal;
  final String discountTotal;
  final String deliveryFee;
  final String transactionFee;
  final String taxTotal;
  final String total;
  final String phone;
  final String address;
  final String paymentMethod;
  final String note;
  final String source;
  final List<AppOrderItem> items;
  String status;
  final DateTime createdAt;
  final int estimatedReadyMinutes;
  bool needsAttention;

  AppOrder({
    required this.id,
    required this.publicCode,
    required this.customerName,
    required this.fulfillmentType,
    required this.subtotal,
    required this.discountTotal,
    required this.deliveryFee,
    required this.transactionFee,
    required this.taxTotal,
    required this.total,
    required this.phone,
    required this.address,
    required this.paymentMethod,
    required this.note,
    required this.source,
    required this.items,
    required this.status,
    required this.createdAt,
    required this.estimatedReadyMinutes,
    this.needsAttention = false,
  });

  double get subtotalValue => double.tryParse(subtotal) ?? 0;
  double get discountTotalValue => double.tryParse(discountTotal) ?? 0;
  double get deliveryFeeValue => double.tryParse(deliveryFee) ?? 0;
  double get transactionFeeValue => double.tryParse(transactionFee) ?? 0;
  double get taxTotalValue => double.tryParse(taxTotal) ?? 0;
  double get totalValue => double.tryParse(total) ?? 0;

  static String backendStatusForUiStatus(String status) {
    switch (status) {
      case 'new':
        return 'confirmed';
      case 'preparing':
        return 'in_kitchen';
      case 'ready':
        return 'ready';
      case 'dispatch':
        return 'out_for_delivery';
      case 'picked_up':
      case 'delivered':
        return 'completed';
      default:
        return status;
    }
  }

  static String _normalizeStatus(String rawStatus) {
    final value = rawStatus.trim().toLowerCase();

    switch (value) {
      case 'pending_payment':
      case 'paid':
      case 'confirmed':
        return 'new';
      case 'in_kitchen':
        return 'preparing';
      case 'ready':
        return 'ready';
      case 'out_for_delivery':
        return 'dispatch';
      case 'completed':
        return 'delivered';
      case 'cancelled':
        return 'cancelled';
      default:
        return value.isEmpty ? 'new' : value;
    }
  }

  static String _buildAddress(Map<String, dynamic> json) {
    final direct =
        (json['customerAddress'] ?? json['address'] ?? '').toString();
    if (direct.trim().isNotEmpty) return direct;

    final parts = [
      json['deliveryStreet'],
      json['deliveryCity'],
      json['deliveryState'],
      json['deliveryZipCode'],
    ]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString().trim())
        .toList();

    return parts.join(', ');
  }

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? [];

    return AppOrder(
      id: (json['id'] ?? json['publicCode'] ?? '').toString(),
      publicCode: (json['publicCode'] ?? json['id'] ?? '').toString(),
      customerName: (json['customerName'] ?? 'Cliente sin nombre').toString(),
      fulfillmentType:
          (json['fulfillmentType'] ?? json['orderType'] ?? 'delivery')
              .toString(),
      subtotal: (json['subtotal'] ?? '0.00').toString(),
      discountTotal: (json['discountTotal'] ?? '0.00').toString(),
      deliveryFee: (json['deliveryFee'] ?? '0.00').toString(),
      transactionFee: (json['transactionFee'] ?? '0.00').toString(),
      taxTotal: (json['taxTotal'] ?? '0.00').toString(),
      total: (json['total'] ?? '0.00').toString(),
      phone: (json['customerPhone'] ?? '-').toString(),
      address: _buildAddress(json),
      paymentMethod: (json['paymentMethod'] ?? '-').toString(),
      note: (json['customerNotes'] ??
              json['notes'] ??
              json['deliveryInstructions'] ??
              '')
          .toString(),
      source: (json['source'] ?? 'web').toString(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(AppOrderItem.fromJson)
          .toList(),
      status: _normalizeStatus(
          (json['status'] ?? json['orderStatus'] ?? 'new').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      estimatedReadyMinutes: ((json['estimatedReadyMinutes'] ??
              json['prepTimeMinutes'] ??
              0) as num)
          .toInt(),
    );
  }
}

class AppOrderItem {
  final String name;
  final int qty;
  final String price;
  final String notes;

  AppOrderItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.notes,
  });

  factory AppOrderItem.fromJson(Map<String, dynamic> json) {
    return AppOrderItem(
      name: (json['productName'] ??
              json['nameSnapshot'] ??
              json['name'] ??
              'Producto')
          .toString(),
      qty: ((json['quantity'] ?? json['qty'] ?? 1) as num).toInt(),
      price: (json['unitPrice'] ?? json['price'] ?? '0.00').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}
