import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gopicadera/core/config/app_config.dart';

import '../services/socket_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<HistoryOrder> _orders = [];
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _hasError = false;
  String _searchQuery = '';
  HistoryOrder? _selectedOrder;

  final String baseUrl = AppConfig.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _connectSocket();

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
      _ensureSelection();
    });
  }

  Future<void> _bootstrap() async {
    await _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  Future<void> _loadOrders() async {
    try {
      setState(() {
        _loading = true;
        _hasError = false;
      });

      final url = Uri.parse('$baseUrl/api/orders');
      debugPrint('GET => $url');

      final response = await http.get(
        url,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      ).timeout(const Duration(seconds: 20));

      debugPrint(
        'History response => ${response.statusCode} ${response.body.length} chars',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final loaded = _decodeOrders(response.body)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint('History loaded => ${loaded.length}');

      if (!mounted) return;

      setState(() {
        _orders
          ..clear()
          ..addAll(loaded);
        _loading = false;
      });

      _ensureSelection();
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (!mounted) return;

      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  List<HistoryOrder> _decodeOrders(String body) {
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
        .map(HistoryOrder.fromJson)
        .toList();
  }

  void _connectSocket() {
    SocketService.instance.init();

    SocketService.instance.onConnect((_) {
      debugPrint('History socket conectado');
    });

    SocketService.instance.onDisconnect((_) {
      debugPrint('History socket desconectado');
    });

    SocketService.instance.onConnectError((data) {
      debugPrint('History socket connect error: $data');
    });

    SocketService.instance.onError((data) {
      debugPrint('History socket error: $data');
    });

    SocketService.instance.on('order_updated', (data) {
      try {
        final updated = HistoryOrder.fromJson(Map<String, dynamic>.from(data));

        if (!mounted) return;

        setState(() {
          _orders.removeWhere((o) => o.id == updated.id);

          if (updated.status == 'delivered' || updated.status == 'picked_up') {
            _orders.insert(0, updated);
            _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }

          if (_selectedOrder?.id == updated.id) {
            _selectedOrder =
                updated.status == 'delivered' || updated.status == 'picked_up'
                    ? updated
                    : null;
          }
        });

        _ensureSelection();
      } catch (e) {
        debugPrint('Error parsing history order_updated: $e');
      }
    });

    SocketService.instance.on('new_order', (data) {
      try {
        final incoming = HistoryOrder.fromJson(Map<String, dynamic>.from(data));

        if (!mounted) return;
        if (incoming.status != 'delivered' && incoming.status != 'picked_up') {
          return;
        }

        setState(() {
          _orders.removeWhere((o) => o.id == incoming.id);
          _orders.insert(0, incoming);
          _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });

        _ensureSelection();
      } catch (e) {
        debugPrint('Error parsing history new_order: $e');
      }
    });
  }

  List<HistoryOrder> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;

    final query = _searchQuery.toLowerCase();

    return _orders.where((order) {
      return order.customerName.toLowerCase().contains(query) ||
          order.phone.toLowerCase().contains(query) ||
          order.id.toString().contains(query);
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

  String _statusLabel(String status) {
    switch (status) {
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

  Color _statusBg(String status) {
    return const Color(0xFFEAF8EE);
  }

  Color _statusFg(String status) {
    return const Color(0xFF15803D);
  }

  String _relativeTime(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
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
            _HistoryHeader(controller: _searchController),
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
                                    'Órdenes completadas',
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
                                    color: const Color(0xFFEAF8EE),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${_orders.length} en historial',
                                    style: const TextStyle(
                                      color: Color(0xFF15803D),
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
                                    ? _HistoryErrorState(onRetry: _loadOrders)
                                    : _filteredOrders.isEmpty
                                        ? _HistoryEmptyState(
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
                                                  child: _HistoryCard(
                                                    order: order,
                                                    isSelected:
                                                        _selectedOrder?.id ==
                                                            order.id,
                                                    resultLabel: _statusLabel(
                                                        order.status),
                                                    typeLabel:
                                                        _fulfillmentLabel(order
                                                            .fulfillmentType),
                                                    statusBg:
                                                        _statusBg(order.status),
                                                    statusFg:
                                                        _statusFg(order.status),
                                                    relativeTime: _relativeTime(
                                                        order.createdAt),
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
                                padding: EdgeInsets.all(28),
                                child: Text(
                                  'Selecciona una orden del historial para ver su detalle.',
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
                        : _HistoryDetailPanel(
                            order: _selectedOrder!,
                            resultLabel: _statusLabel(_selectedOrder!.status),
                            typeLabel: _fulfillmentLabel(
                              _selectedOrder!.fulfillmentType,
                            ),
                            statusBg: _statusBg(_selectedOrder!.status),
                            statusFg: _statusFg(_selectedOrder!.status),
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

class _HistoryHeader extends StatelessWidget {
  final TextEditingController controller;

  const _HistoryHeader({
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Historial',
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
                    hintText: 'Buscar cliente, pedido o teléfono',
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

class _HistoryCard extends StatelessWidget {
  final HistoryOrder order;
  final bool isSelected;
  final String resultLabel;
  final String typeLabel;
  final Color statusBg;
  final Color statusFg;
  final String relativeTime;

  const _HistoryCard({
    required this.order,
    required this.isSelected,
    required this.resultLabel,
    required this.typeLabel,
    required this.statusBg,
    required this.statusFg,
    required this.relativeTime,
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
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: -0.4,
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
                  resultLabel,
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
                  typeLabel,
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
                  '${order.items.length} items',
                  style: const TextStyle(
                    color: Color(0xFF344054),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.fulfillmentType == 'pickup'
                ? 'Recogida en tienda'
                : (order.address.isEmpty ? 'Sin dirección' : order.address),
            style: const TextStyle(
              fontSize: 15,
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

class _HistoryDetailPanel extends StatelessWidget {
  final HistoryOrder order;
  final String resultLabel;
  final String typeLabel;
  final Color statusBg;
  final Color statusFg;

  const _HistoryDetailPanel({
    required this.order,
    required this.resultLabel,
    required this.typeLabel,
    required this.statusBg,
    required this.statusFg,
  });

  @override
  Widget build(BuildContext context) {
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
                      letterSpacing: -0.6,
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
                    resultLabel,
                    style: TextStyle(
                      color: statusFg,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    typeLabel,
                    style: const TextStyle(
                      color: Color(0xFF344054),
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
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    order.fulfillmentType == 'pickup'
                        ? 'Recogida en tienda'
                        : (order.address.isEmpty
                            ? 'Sin dirección'
                            : order.address),
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
                        child: _HistoryDetailBlock(
                          title: 'Total',
                          value: '\$${order.total}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HistoryDetailBlock(
                          title: 'Teléfono',
                          value: order.phone,
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
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
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
                                  const SizedBox(width: 12),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDetailBlock extends StatelessWidget {
  final String title;
  final String value;

  const _HistoryDetailBlock({
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

class _HistoryEmptyState extends StatelessWidget {
  final bool hasSearch;

  const _HistoryEmptyState({
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
              hasSearch ? Icons.search_off_rounded : Icons.history_rounded,
              size: 54,
              color: const Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? 'No encontramos órdenes en historial'
                  : 'Todavía no hay órdenes en historial',
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
                  ? 'Prueba con otro nombre, pedido o teléfono.'
                  : 'Las órdenes entregadas y recogidas aparecerán aquí.',
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

class _HistoryErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _HistoryErrorState({
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
              'No se pudo cargar el historial',
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

class HistoryOrder {
  final String id;
  final String customerName;
  final String fulfillmentType;
  final String total;
  final String phone;
  final String address;
  final String status;
  final DateTime createdAt;
  final List<HistoryOrderItem> items;

  HistoryOrder({
    required this.id,
    required this.customerName,
    required this.fulfillmentType,
    required this.total,
    required this.phone,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.items,
  });

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

  factory HistoryOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? [];

    return HistoryOrder(
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
          .map((e) => HistoryOrderItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class HistoryOrderItem {
  final String name;
  final int qty;
  final String price;
  final String notes;

  HistoryOrderItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.notes,
  });

  factory HistoryOrderItem.fromJson(Map<String, dynamic> json) {
    return HistoryOrderItem(
      name: (json['productName'] ?? json['name'] ?? 'Producto').toString(),
      qty: ((json['quantity'] ?? json['qty'] ?? 1) as num).toInt(),
      price: (json['unitPrice'] ?? json['price'] ?? '0.00').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}
