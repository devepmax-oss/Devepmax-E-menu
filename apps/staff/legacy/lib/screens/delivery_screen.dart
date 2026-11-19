import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gopicadera/core/config/app_config.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final List<DeliveryOrder> _orders = [];
  final TextEditingController _searchController = TextEditingController();

  io.Socket? _socket;

  bool _loading = true;
  bool _hasError = false;
  String _searchQuery = '';
  DeliveryOrder? _selectedOrder;

  final String baseUrl = AppConfig.apiBaseUrl;
  late final String socketBaseUrl = Uri.parse(baseUrl).origin;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _connectSocket();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
      _ensureSelection();
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _searchController.dispose();
    super.dispose();
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
      );

      debugPrint(
        'Delivery response => ${response.statusCode} ${response.body.length} chars',
      );

      if (response.statusCode != 200) {
        throw Exception('Error HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawOrders = (data['orders'] as List?) ?? [];

      final loaded = rawOrders
          .map((e) => DeliveryOrder.fromJson(Map<String, dynamic>.from(e)))
          .where((order) => order.shouldAppearInDelivery)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;

      setState(() {
        _orders
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });

      _ensureSelection();
    } catch (e) {
      debugPrint('Error loading delivery orders: $e');

      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  void _connectSocket() {
    debugPrint('Connecting delivery socket to => $socketBaseUrl');

    _socket = io.io(
      socketBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setPath('/socket.io')
          .enableForceNew()
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    _socket?.onConnect((_) {
      debugPrint('Delivery socket conectado');
    });

    _socket?.onConnectError((data) {
      debugPrint('Delivery socket connect error: $data');
    });

    _socket?.onError((data) {
      debugPrint('Delivery socket error: $data');
    });

    _socket?.on('order_updated', (data) {
      try {
        final updated = DeliveryOrder.fromJson(Map<String, dynamic>.from(data));

        if (!mounted) return;

        setState(() {
          _orders.removeWhere((o) => o.id == updated.id);

          if (updated.shouldAppearInDelivery) {
            _orders.insert(0, updated);
            _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }

          if (_selectedOrder?.id == updated.id) {
            _selectedOrder = updated.shouldAppearInDelivery ? updated : null;
          }
        });

        _ensureSelection();
      } catch (e) {
        debugPrint('Error parsing delivery order_updated: $e');
      }
    });

    _socket?.on('new_order', (data) {
      try {
        final incoming =
            DeliveryOrder.fromJson(Map<String, dynamic>.from(data));

        if (!mounted) return;
        if (!incoming.shouldAppearInDelivery) return;

        setState(() {
          _orders.removeWhere((o) => o.id == incoming.id);
          _orders.insert(0, incoming);
          _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });

        _ensureSelection();
      } catch (e) {
        debugPrint('Error parsing delivery new_order: $e');
      }
    });

    _socket?.onDisconnect((_) {
      debugPrint('Delivery socket desconectado');
    });

    _socket?.connect();
  }

  Future<void> _markDelivered(DeliveryOrder order) async {
    try {
      final url = Uri.parse('$baseUrl/api/orders/${order.id}/status');
      debugPrint('PATCH => $url status=delivered');

      final response = await http.patch(
        url,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
        body: jsonEncode({'status': 'delivered'}),
      );

      debugPrint(
        'Delivery mark delivered response => ${response.statusCode} ${response.body}',
      );

      if (response.statusCode >= 400) {
        throw Exception('No se pudo finalizar la entrega');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Entrega finalizada para la orden #${order.id}'),
        ),
      );

      await _loadOrders();
    } catch (e) {
      debugPrint('Error mark delivered: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo finalizar la entrega'),
        ),
      );
    }
  }

  List<DeliveryOrder> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;

    final query = _searchQuery.toLowerCase();

    return _orders.where((order) {
      return order.customerName.toLowerCase().contains(query) ||
          order.phone.toLowerCase().contains(query) ||
          order.id.toString().contains(query) ||
          order.driverName.toLowerCase().contains(query) ||
          order.deliveryStatus.toLowerCase().contains(query);
    }).toList();
  }

  void _ensureSelection() {
    final visible = _filteredOrders;

    if (visible.isEmpty) {
      if (_selectedOrder != null) {
        setState(() {
          _selectedOrder = null;
        });
      }
      return;
    }

    final stillVisible = _selectedOrder != null &&
        visible.any((order) => order.id == _selectedOrder!.id);

    if (!stillVisible) {
      setState(() {
        _selectedOrder = visible.first;
      });
    }
  }

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
  }

  String _deliveryStatusLabel(String value) {
    switch (value.toLowerCase()) {
      case 'assigned':
        return 'Driver asignado';
      case 'pending':
        return 'Pendiente';
      case 'picked_up':
        return 'Recogido';
      case 'on_the_way':
        return 'En camino';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return value.isEmpty ? 'Pendiente' : value;
    }
  }

  Color _deliveryStatusBg(String value) {
    switch (value.toLowerCase()) {
      case 'assigned':
        return const Color(0xFFEAF2FF);
      case 'pending':
        return const Color(0xFFF3F4F6);
      case 'picked_up':
        return const Color(0xFFF2EBFF);
      case 'on_the_way':
        return const Color(0xFFFFF3ED);
      case 'delivered':
        return const Color(0xFFEAF8EE);
      case 'cancelled':
        return const Color(0xFFFEE4E2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _deliveryStatusFg(String value) {
    switch (value.toLowerCase()) {
      case 'assigned':
        return const Color(0xFF2563EB);
      case 'pending':
        return const Color(0xFF475467);
      case 'picked_up':
        return const Color(0xFF7C3AED);
      case 'on_the_way':
        return const Color(0xFFD9480F);
      case 'delivered':
        return const Color(0xFF15803D);
      case 'cancelled':
        return const Color(0xFFB42318);
      default:
        return const Color(0xFF475467);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeliveryHeader(controller: _searchController),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x100F172A),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Despachos activos',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2EBFF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_orders.length} en ruta',
                                    style: const TextStyle(
                                      color: Color(0xFF7C3AED),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _hasError
                                    ? _DeliveryErrorState(onRetry: _loadOrders)
                                    : _filteredOrders.isEmpty
                                        ? _DeliveryEmptyState(
                                            hasSearch: _searchQuery.isNotEmpty,
                                          )
                                        : RefreshIndicator(
                                            onRefresh: _loadOrders,
                                            child: ListView.separated(
                                              padding: const EdgeInsets.all(16),
                                              itemCount: _filteredOrders.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 14),
                                              itemBuilder: (context, index) {
                                                final order =
                                                    _filteredOrders[index];

                                                return GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _selectedOrder = order;
                                                    });
                                                  },
                                                  child: _DeliveryCard(
                                                    order: order,
                                                    isSelected:
                                                        _selectedOrder?.id ==
                                                            order.id,
                                                    relativeTime: _relativeTime(
                                                      order.createdAt,
                                                    ),
                                                    statusLabel:
                                                        _deliveryStatusLabel(
                                                      order.deliveryStatus,
                                                    ),
                                                    statusBg: _deliveryStatusBg(
                                                      order.deliveryStatus,
                                                    ),
                                                    statusFg: _deliveryStatusFg(
                                                      order.deliveryStatus,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 5,
                    child: _selectedOrder == null
                        ? Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x100F172A),
                                  blurRadius: 24,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Selecciona un delivery para ver su detalle.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Color(0xFF667085),
                                    fontWeight: FontWeight.w600,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : _DeliveryDetailPanel(
                            order: _selectedOrder!,
                            onMarkDelivered: _selectedOrder!.canMarkDelivered
                                ? () => _markDelivered(_selectedOrder!)
                                : null,
                            statusLabel: _deliveryStatusLabel(
                              _selectedOrder!.deliveryStatus,
                            ),
                            statusBg: _deliveryStatusBg(
                              _selectedOrder!.deliveryStatus,
                            ),
                            statusFg: _deliveryStatusFg(
                              _selectedOrder!.deliveryStatus,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryHeader extends StatelessWidget {
  final TextEditingController controller;

  const _DeliveryHeader({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Delivery',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -1.6,
              height: 1.0,
            ),
          ),
        ),
        Container(
          width: 360,
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: Color(0xFF98A2B3),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Buscar cliente, pedido, driver o teléfono',
                    hintStyle: TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final DeliveryOrder order;
  final bool isSelected;
  final String relativeTime;
  final String statusLabel;
  final Color statusBg;
  final Color statusFg;

  const _DeliveryCard({
    required this.order,
    required this.isSelected,
    required this.relativeTime,
    required this.statusLabel,
    required this.statusBg,
    required this.statusFg,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
          width: isSelected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${order.id} · ${order.customerName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Text(
                '\$${order.total}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusFg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.driverName,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.etaLabel,
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (order.deliveryProvider.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    order.deliveryProvider.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.address.isEmpty ? 'Sin dirección' : order.address,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tel: ${order.phone}',
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
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
    );
  }
}

class _DeliveryDetailPanel extends StatelessWidget {
  final DeliveryOrder order;
  final VoidCallback? onMarkDelivered;
  final String statusLabel;
  final Color statusBg;
  final Color statusFg;

  const _DeliveryDetailPanel({
    required this.order,
    required this.onMarkDelivered,
    required this.statusLabel,
    required this.statusBg,
    required this.statusFg,
  });

  @override
  Widget build(BuildContext context) {
    final canFinish = onMarkDelivered != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Pedido #${order.id}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.customerName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    order.address.isEmpty ? 'Sin dirección' : order.address,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF475467),
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'Total',
                          value: '\$${order.total}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'Teléfono',
                          value: order.phone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'Driver',
                          value: order.driverName,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'ETA',
                          value: order.etaLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'Proveedor',
                          value: order.deliveryProvider.isEmpty
                              ? 'Sin proveedor'
                              : order.deliveryProvider.toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DeliveryDetailBlock(
                          title: 'Estado',
                          value: statusLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Productos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      children: order.items
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                        if (item.notes.trim().isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            item.notes,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF667085),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
                  const SizedBox(height: 18),
                  const Text(
                    'Tracking',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TrackingLine(
                          label: 'Estado',
                          value: statusLabel,
                        ),
                        _TrackingLine(
                          label: 'Driver',
                          value: order.driverName,
                        ),
                        _TrackingLine(
                          label: 'ETA',
                          value: order.etaLabel,
                        ),
                        _TrackingLine(
                          label: 'Proveedor',
                          value: order.deliveryProvider.isEmpty
                              ? 'Sin proveedor'
                              : order.deliveryProvider.toUpperCase(),
                        ),
                        _TrackingLine(
                          label: 'Tracking URL',
                          value: order.trackingUrl.isEmpty
                              ? 'No disponible'
                              : order.trackingUrl,
                          multiline: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canFinish ? onMarkDelivered : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF98A2B3),
                  minimumSize: const Size(double.infinity, 62),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.task_alt_rounded),
                label: Text(
                  canFinish
                      ? 'Finalizar entrega'
                      : 'Esperando confirmación del driver',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingLine extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _TrackingLine({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: multiline
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeliveryDetailBlock extends StatelessWidget {
  final String title;
  final String value;

  const _DeliveryDetailBlock({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
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
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryEmptyState extends StatelessWidget {
  final bool hasSearch;

  const _DeliveryEmptyState({
    required this.hasSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.delivery_dining_rounded,
              size: 54,
              color: const Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No encontramos deliveries con esa búsqueda'
                  : 'No hay deliveries activos',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Prueba con otro cliente, pedido, driver o teléfono.'
                  : 'Las órdenes en despacho aparecerán aquí automáticamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _DeliveryErrorState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 54,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            const Text(
              'No se pudo cargar delivery',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa la conexión con el backend y vuelve a intentar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class DeliveryOrder {
  final String id;
  final String customerName;
  final String fulfillmentType;
  final String total;
  final String phone;
  final String address;
  final String status;
  final DateTime createdAt;
  final List<DeliveryOrderItem> items;

  final String driverName;
  final int? etaMinutes;
  final String deliveryStatus;
  final String deliveryProvider;
  final String trackingUrl;

  const DeliveryOrder({
    required this.id,
    required this.customerName,
    required this.fulfillmentType,
    required this.total,
    required this.phone,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.driverName,
    required this.etaMinutes,
    required this.deliveryStatus,
    required this.deliveryProvider,
    required this.trackingUrl,
  });

  String get etaLabel => etaMinutes != null ? '${etaMinutes!} min' : 'Sin ETA';

  bool get shouldAppearInDelivery {
    if (fulfillmentType != 'delivery') return false;
    if (status == 'delivered' ||
        status == 'picked_up' ||
        status == 'cancelled') {
      return false;
    }
    return status == 'dispatch' ||
        status == 'ready' ||
        deliveryStatus.isNotEmpty;
  }

  bool get canMarkDelivered {
    final normalized = deliveryStatus.toLowerCase();
    return normalized == 'delivered' || status == 'delivered';
  }

  static String _normalizeStatus(Map<String, dynamic> json) {
    final raw = (json['status'] ?? json['orderStatus'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    switch (raw) {
      case 'confirmed':
      case 'paid':
        return 'new';
      case 'in_kitchen':
      case 'preparing':
        return 'preparing';
      case 'out_for_delivery':
      case 'dispatch':
        return 'dispatch';
      case 'completed':
      case 'delivered':
        return 'delivered';
      default:
        return raw;
    }
  }

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? [];

    return DeliveryOrder(
      id: (json['id'] ?? json['publicCode'] ?? '').toString(),
      customerName: (json['customerName'] ?? 'Cliente sin nombre').toString(),
      fulfillmentType:
          ((json['fulfillmentType'] ?? json['orderType'] ?? 'delivery')
                      .toString()
                      .toLowerCase() ==
                  'pickup')
              ? 'pickup'
              : 'delivery',
      total: (json['total'] ?? '0.00').toString(),
      phone: (json['customerPhone'] ?? '-').toString(),
      address: (json['customerAddress'] ?? '').toString(),
      status: _normalizeStatus(json),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      items: rawItems
          .map((e) => DeliveryOrderItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      driverName: (json['driverName'] ?? 'Sin asignar').toString(),
      etaMinutes: json['etaMinutes'] is num
          ? (json['etaMinutes'] as num).toInt()
          : int.tryParse('${json['etaMinutes'] ?? ''}'),
      deliveryStatus: (json['deliveryStatus'] ?? 'pending').toString(),
      deliveryProvider: (json['deliveryProvider'] ?? '').toString(),
      trackingUrl: (json['trackingUrl'] ?? '').toString(),
    );
  }
}

class DeliveryOrderItem {
  final String name;
  final int qty;
  final String price;
  final String notes;

  const DeliveryOrderItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.notes,
  });

  factory DeliveryOrderItem.fromJson(Map<String, dynamic> json) {
    return DeliveryOrderItem(
      name: (json['productName'] ?? json['name'] ?? 'Producto').toString(),
      qty: ((json['quantity'] ?? json['qty'] ?? 1) as num).toInt(),
      price: (json['unitPrice'] ?? json['price'] ?? '0.00').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}
