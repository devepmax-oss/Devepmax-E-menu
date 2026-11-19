import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/driver_models.dart';
import '../../services/driver_api_service.dart';

class AvailableOrdersScreen extends StatefulWidget {
  const AvailableOrdersScreen({
    super.key,
    required this.driver,
    required this.refreshSignal,
    required this.hasActiveAssignment,
    required this.onAssignmentCreated,
  });

  final DriverProfile driver;
  final int refreshSignal;
  final bool hasActiveAssignment;
  final ValueChanged<DriverAssignment> onAssignmentCreated;

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  List<DriverOrder> _orders = [];
  bool _loading = true;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void didUpdateWidget(
    covariant AvailableOrdersScreen oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshSignal != widget.refreshSignal) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders() async {
    try {
      setState(() => _loading = true);

      final orders = await DriverApiService.instance.listAvailableOrders();

      if (!mounted) return;

      setState(() => _orders = orders);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudieron cargar órdenes: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _acceptOrder(DriverOrder order) async {
    if (_accepting || widget.hasActiveAssignment) return;

    try {
      HapticFeedback.mediumImpact();

      setState(() => _accepting = true);

      final assignment = await DriverApiService.instance.assignOrder(
        orderId: order.id,
        driverId: widget.driver.id,
      );

      final accepted = await DriverApiService.instance.acceptAssignment(
        assignment.id,
      );

      if (!mounted) return;

      widget.onAssignmentCreated(accepted);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orden ${order.publicCode} aceptada',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo aceptar: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _accepting = false);
      }
    }
  }

  Future<void> _copyCustomerPhone(
    DriverOrder order,
  ) async {
    final phone = order.customerPhone.trim();

    if (phone.isEmpty) return;

    await Clipboard.setData(
      ClipboardData(text: phone),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Teléfono de ${order.customerName} copiado',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Órdenes disponibles',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.driver.status == 'available'
                          ? 'Estás disponible para recibir pedidos.'
                          : 'Cambia a disponible para recibir pedidos.',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: _loading ? null : _loadOrders,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.hasActiveAssignment) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFFED7AA),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFB45309),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ya tienes una entrega activa. Puedes revisar las '
                      'órdenes disponibles, pero debes completar la entrega '
                      'actual antes de aceptar otra.',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_orders.isEmpty)
            const _EmptyOrders()
          else
            for (final order in _orders) ...[
              _OrderCard(
                order: order,
                accepting: _accepting,
                hasActiveAssignment: widget.hasActiveAssignment,
                onAccept: () => _acceptOrder(order),
                onCopyPhone: order.customerPhone.trim().isEmpty
                    ? null
                    : () => _copyCustomerPhone(order),
              ),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.accepting,
    required this.hasActiveAssignment,
    required this.onAccept,
    required this.onCopyPhone,
  });

  final DriverOrder order;
  final bool accepting;
  final bool hasActiveAssignment;
  final VoidCallback onAccept;
  final VoidCallback? onCopyPhone;

  @override
  Widget build(BuildContext context) {
    final customerPhone = order.customerPhone.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.publicCode.isEmpty ? 'Orden' : order.publicCode,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              Text(
                '\$${order.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.person_rounded,
                  size: 19,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.phone_rounded,
                size: 19,
                color: Color(0xFF667085),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customerPhone.isEmpty
                      ? 'Teléfono no disponible'
                      : customerPhone,
                  style: TextStyle(
                    color: customerPhone.isEmpty
                        ? const Color(0xFF98A2B3)
                        : const Color(0xFF344054),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onCopyPhone != null)
                IconButton(
                  tooltip: 'Copiar teléfono',
                  onPressed: onCopyPhone,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 19,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.deliveryAddress,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Pill(
                text: '${order.items.length} items',
              ),
              const SizedBox(width: 8),
              _Pill(
                text: order.orderType.toUpperCase(),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: accepting || hasActiveAssignment ? null : onAccept,
                icon: accepting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.check_circle_rounded,
                      ),
                label: Text(
                  hasActiveAssignment ? 'Entrega activa' : 'Aceptar',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF128A3C),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF475467),
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 64,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 16),
          Text(
            'No hay órdenes disponibles',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Desliza hacia abajo para actualizar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
