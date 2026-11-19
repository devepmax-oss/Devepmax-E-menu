import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gopicadera/core/config/app_config.dart';

import '../services/notification_service.dart';
import '../services/order_events_service.dart';
import '../services/printer_service.dart';
import '../services/socket_service.dart';
import 'delivery_screen.dart';
import 'history_screen.dart';
import 'menu_screen.dart';
import 'orders_dashboard_screen.dart';
import 'settings_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int selectedIndex = 0;

  final List<AppOrder> _incomingQueue = <AppOrder>[];
  final Set<String> _alertedOrderKeys = <String>{};

  AppOrder? _activeIncomingOrder;
  Timer? _incomingAutoCloseTimer;
  bool _acceptingIncomingOrder = false;

  late final List<Widget> screens = [
    const OrdersDashboardScreen(),
    const MenuScreen(),
    const DeliveryScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];

  final List<_NavItem> items = const [
    _NavItem('Órdenes', Icons.receipt_long_rounded),
    _NavItem('Menú', Icons.restaurant_menu_rounded),
    _NavItem('Delivery', Icons.delivery_dining_rounded),
    _NavItem('Historial', Icons.history_rounded),
    _NavItem('Ajustes', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _initGlobalRealtimeOrders();
  }

  @override
  void dispose() {
    NotificationService.setForegroundOrderPushHandler(null);
    _incomingAutoCloseTimer?.cancel();
    super.dispose();
  }

  void _initGlobalRealtimeOrders() {
    // App abierta: FCM no muestra notificación local. Aquí buscamos la orden
    // específica y mostramos el overlay global con un único sonido.
    NotificationService.setForegroundOrderPushHandler(_handleOrderPush);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.consumeInitialOrderPush());
    });

    final socket = SocketService.instance;
    socket.init();

    socket.on('new_order', (data) async {
      try {
        final order = AppOrder.fromJson(Map<String, dynamic>.from(data));
        await _handleIncomingOrder(order, source: 'socket');
      } catch (e) {
        debugPrint('Global new_order parse error: $e');
      }
    });
  }

  Future<void> _handleOrderPush({
    String? orderId,
    String? publicCode,
  }) async {
    debugPrint('FCM order push orderId=$orderId publicCode=$publicCode');

    if ((orderId == null || orderId.isEmpty) &&
        (publicCode == null || publicCode.isEmpty)) {
      debugPrint('FCM sin orderId/publicCode. Ignorado.');
      return;
    }

    final order = await _fetchActiveOrder(
      orderId: orderId,
      publicCode: publicCode,
    );

    if (order == null) {
      debugPrint('No se encontró orden activa para el push.');
      return;
    }

    await _handleIncomingOrder(order, source: 'fcm');
  }

  String _orderKey(AppOrder order) {
    if (order.id.isNotEmpty) return order.id;
    if (order.publicCode.isNotEmpty) return order.publicCode;
    return '${order.customerName}-${order.total}-${order.createdAt.toIso8601String()}';
  }

  bool _isIncomingStatus(AppOrder order) {
    return order.status == 'new' ||
        order.status == 'confirmed' ||
        order.status == 'paid';
  }

  Future<AppOrder?> _fetchActiveOrder({
    String? orderId,
    String? publicCode,
  }) async {
    try {
      final url = Uri.parse('${AppConfig.apiBaseUrl}/api/orders/active');
      final response = await http.get(
        url,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final orders = _decodeOrdersResponse(response.body);

      for (final order in orders) {
        final matchesId =
            orderId != null && orderId.isNotEmpty && order.id == orderId;
        final matchesCode = publicCode != null &&
            publicCode.isNotEmpty &&
            order.publicCode == publicCode;

        if ((matchesId || matchesCode) && _isIncomingStatus(order)) {
          return order;
        }
      }
    } catch (e) {
      debugPrint('Fetch active order from foreground push failed: $e');
    }

    return null;
  }

  List<AppOrder> _decodeOrdersResponse(String body) {
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

  Future<void> _handleIncomingOrder(
    AppOrder order, {
    required String source,
  }) async {
    if (!mounted) return;
    if (!_isIncomingStatus(order)) return;

    final key = _orderKey(order);
    if (key.isEmpty || _alertedOrderKeys.contains(key)) return;

    _alertedOrderKeys.add(key);
    order.needsAttention = true;

    debugPrint('🚨 Nueva orden global ($source): ${order.publicCode}');

    try {
      if (PrinterService.instance.autoPrintNewOrders) {
        await PrinterService.instance.printOrder(order);
      }
    } catch (e) {
      debugPrint('Auto print new order error: $e');
    }

    _incomingQueue.add(order);
    _showNextIncomingOrderOverlay();
  }

  void _showNextIncomingOrderOverlay() {
    if (!mounted || _activeIncomingOrder != null || _incomingQueue.isEmpty) {
      return;
    }

    final order = _incomingQueue.removeAt(0);

    setState(() {
      _activeIncomingOrder = order;
    });

    unawaited(NotificationService.playIncomingLoopSound());

    _incomingAutoCloseTimer?.cancel();
    _incomingAutoCloseTimer = Timer(const Duration(seconds: 45), () {
      if (!mounted) return;
      unawaited(_closeIncomingOverlay(keepSoundStopped: true));
    });
  }

  Future<void> _closeIncomingOverlay({bool keepSoundStopped = true}) async {
    _incomingAutoCloseTimer?.cancel();

    if (keepSoundStopped) {
      await NotificationService.stopIncomingLoopSound();
    }

    if (!mounted) return;

    setState(() {
      _activeIncomingOrder = null;
      _acceptingIncomingOrder = false;
    });

    if (_incomingQueue.isNotEmpty) {
      _showNextIncomingOrderOverlay();
    }
  }

  Future<void> _acceptIncomingOrder(AppOrder order) async {
    if (_acceptingIncomingOrder) return;

    setState(() {
      _acceptingIncomingOrder = true;
    });

    try {
      final response = await http
          .patch(
            Uri.parse('${AppConfig.apiBaseUrl}/api/orders/${order.id}/status'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
            },
            body: jsonEncode({
              'orderStatus': 'in_kitchen',
              'status': 'in_kitchen',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('${response.statusCode} ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      final rawOrder = decoded is Map<String, dynamic>
          ? (decoded['order'] ?? decoded)
          : null;

      if (rawOrder is Map<String, dynamic>) {
        OrderEventsService.instance.emitOrderUpdated(
          Map<String, dynamic>.from(rawOrder),
        );
      }

      await NotificationService.stopIncomingLoopSound();

      if (!mounted) return;
      setState(() {
        selectedIndex = 0;
        _activeIncomingOrder = null;
        _acceptingIncomingOrder = false;
      });
    } catch (e) {
      debugPrint('Error accepting incoming order: $e');
      if (!mounted) return;

      setState(() {
        _acceptingIncomingOrder = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo aceptar el pedido: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101828),
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                Container(
                  width: 76,
                  color: const Color(0xFF101828),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6A3D), Color(0xFFFF2D55)],
                          ),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(items.length, (index) {
                        final item = items[index];
                        final selected = index == selectedIndex;

                        return _SidebarItem(
                          label: item.label,
                          icon: item.icon,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              selectedIndex = index;
                            });
                          },
                        );
                      }),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(0xFF344054),
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF5F7FB),
                    child: IndexedStack(
                      index: selectedIndex.clamp(0, screens.length - 1),
                      children: screens,
                    ),
                  ),
                ),
              ],
            ),
            if (_activeIncomingOrder != null)
              _GlobalIncomingOrderOverlay(
                order: _activeIncomingOrder!,
                accepting: _acceptingIncomingOrder,
                onAccept: () => _acceptIncomingOrder(_activeIncomingOrder!),
                onViewOrders: () async {
                  await NotificationService.stopIncomingLoopSound();
                  if (!mounted) return;
                  setState(() {
                    selectedIndex = 0;
                  });
                },
                onSilence: () async {
                  await NotificationService.stopIncomingLoopSound();
                },
                onDismissToQueue: () async {
                  await _closeIncomingOverlay(keepSoundStopped: true);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _GlobalIncomingOrderOverlay extends StatelessWidget {
  const _GlobalIncomingOrderOverlay({
    required this.order,
    required this.accepting,
    required this.onAccept,
    required this.onViewOrders,
    required this.onSilence,
    required this.onDismissToQueue,
  });

  final AppOrder order;
  final bool accepting;
  final VoidCallback onAccept;
  final Future<void> Function() onViewOrders;
  final Future<void> Function() onSilence;
  final Future<void> Function() onDismissToQueue;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.58),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 790),
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 32,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Color(0xFFE11D48),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NUEVA ORDEN ENTRANTE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFE11D48),
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.publicCode.isNotEmpty
                                ? order.publicCode
                                : order.id,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF101828),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${order.total}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${order.fulfillmentType.toUpperCase()} · ${order.items.length} item(s)',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF667085),
                        ),
                      ),
                      if (order.note.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          order.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF344054),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: accepting ? null : onSilence,
                        icon: const Icon(Icons.volume_off_rounded),
                        label: const Text('Silenciar'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: accepting
                            ? null
                            : () => unawaited(onDismissToQueue()),
                        icon: const Icon(Icons.move_to_inbox_rounded),
                        label: const Text('Dejar en Nuevos'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: accepting ? null : onAccept,
                        icon: accepting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(
                          accepting ? 'Aceptando...' : 'Aceptar y preparar',
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(58),
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: accepting ? null : () => unawaited(onViewOrders()),
                  child: const Text('Aceptar para ver pantalla de órdenes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1F2937) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF98A2B3),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem(this.label, this.icon);
}
