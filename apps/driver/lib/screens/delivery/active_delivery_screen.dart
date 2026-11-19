import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/driver_models.dart';
import '../../services/driver_api_service.dart';

class ActiveDeliveryScreen extends StatefulWidget {
  const ActiveDeliveryScreen({
    super.key,
    required this.assignment,
    required this.onAssignmentChanged,
  });

  final DriverAssignment? assignment;
  final ValueChanged<DriverAssignment?> onAssignmentChanged;

  @override
  State<ActiveDeliveryScreen> createState() => _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends State<ActiveDeliveryScreen> {
  static const String restaurantAddress =
      'GoPicadera, 4th Avenue, Brooklyn, NY';

  bool _working = false;

  Future<void> _pickup() async {
    final assignment = widget.assignment;
    if (assignment == null || _working) return;

    try {
      HapticFeedback.mediumImpact();

      setState(() => _working = true);

      final updated =
          await DriverApiService.instance.pickupAssignment(assignment.id);

      widget.onAssignmentChanged(updated);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deliver() async {
    final assignment = widget.assignment;
    if (assignment == null || _working) return;

    try {
      HapticFeedback.heavyImpact();

      setState(() => _working = true);

      final updated =
          await DriverApiService.instance.deliverAssignment(assignment.id);

      widget.onAssignmentChanged(null);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Orden ${updated.order?.publicCode ?? ''} entregada'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openDirections(String destination) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${Uri.encodeComponent(destination)}'
      '&travelmode=driving',
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;

    if (assignment == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delivery_dining_rounded,
                size: 80,
                color: Color(0xFF98A2B3),
              ),
              SizedBox(height: 18),
              Text(
                'No tienes entrega activa',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'Cuando aceptes una orden aparecerá aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final order = assignment.order;
    final customerAddress = order?.deliveryAddress ?? 'Dirección no disponible';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Entrega activa',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10101828),
                blurRadius: 22,
                offset: Offset(0, 10),
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
                      order?.publicCode ?? 'Orden',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _StatusBadge(status: assignment.status),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                order?.customerName ?? 'Cliente',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                order?.customerPhone ?? '',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
              const Divider(height: 32),
              const Text(
                'Restaurante',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                restaurantAddress,
                style: TextStyle(
                  color: Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _openDirections(restaurantAddress),
                  icon: const Icon(Icons.store_mall_directory_rounded),
                  label: const Text('Navegar al restaurante'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const Divider(height: 32),
              const Text(
                'Cliente',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                customerAddress,
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _openDirections(customerAddress),
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Navegar al cliente'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              if ((order?.deliveryInstructions ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Instrucciones',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  order!.deliveryInstructions!,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
              ],
              const Divider(height: 32),
              if (order != null && order.items.isNotEmpty) ...[
                const Text(
                  'Productos',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          '${item.quantity}x',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item.name)),
                        Text('\$${item.totalPrice.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _working
                      ? null
                      : assignment.isPickedUp
                          ? _deliver
                          : _pickup,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          assignment.isPickedUp
                              ? Icons.check_circle_rounded
                              : Icons.shopping_bag_rounded,
                        ),
                  label: Text(
                    assignment.isPickedUp
                        ? 'Marcar entregada'
                        : 'Marcar recogida',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: assignment.isPickedUp
                        ? const Color(0xFF128A3C)
                        : const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      'pending' => 'Pendiente',
      'accepted' => 'Aceptada',
      'picked_up' => 'En camino',
      'delivered' => 'Entregada',
      _ => status,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF8FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF175CD3),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
