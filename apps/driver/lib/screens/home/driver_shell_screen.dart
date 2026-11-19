import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/config/app_config.dart';
import '../../models/driver_models.dart';
import '../../services/driver_api_service.dart' as driver_api;
import '../../services/driver_location_service.dart';
import '../../services/driver_notification_service.dart';
import '../../services/socket_service.dart' as socket_service;
import '../../widgets/app_loading.dart';
import '../delivery/active_delivery_screen.dart';
import '../profile/driver_profile_screen.dart';
import 'available_orders_screen.dart';

class DriverShellScreen extends StatefulWidget {
  const DriverShellScreen({super.key});

  @override
  State<DriverShellScreen> createState() => _DriverShellScreenState();
}

class _DriverShellScreenState extends State<DriverShellScreen> {
  final AudioPlayer _alertPlayer = AudioPlayer();
  final DriverLocationService _locationService = DriverLocationService.instance;

  final Queue<Map<String, dynamic>> _incomingOrderQueue =
      Queue<Map<String, dynamic>>();
  final Set<String> _queuedOrDisplayedOrderIds = <String>{};

  int _selectedIndex = 0;
  bool _loading = true;
  bool _changingStatus = false;
  bool _incomingOrderModalVisible = false;

  DriverProfile? _driver;
  DriverAssignment? _activeAssignment;

  int _ordersRefreshTick = 0;
  Timer? _alertStopTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    final socket = socket_service.SocketService.instance;

    socket.off('driver_assigned');
    socket.off('driver_picked_up');
    socket.off('driver_delivered');
    socket.off('driver_assignment_cancelled');
    socket.off('driver_order_available');
    socket.off('driver_orders_refresh');
    socket.off('order_delivery_assigned');

    _alertStopTimer?.cancel();
    _locationService.stop();
    _alertPlayer.dispose();

    super.dispose();
  }

  Future<void> _startLocationTracking(String driverId) async {
    await _locationService.start(
      driverId: driverId,
      onLocationUploaded: (lat, lng) {
        if (!mounted) return;

        setState(() {
          _driver = _driver?.copyWith(
            lastLat: lat,
            lastLng: lng,
            lastSeenAt: DateTime.now(),
          );
        });
      },
    );
  }

  Future<void> _playNewOrderAlert() async {
    try {
      _alertStopTimer?.cancel();

      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);

      await _alertPlayer.stop();
      await _alertPlayer.setAsset('assets/sounds/alert.mp3');
      await _alertPlayer.setLoopMode(LoopMode.off);
      await _alertPlayer.play();

      _alertStopTimer = Timer(
        const Duration(seconds: 8),
        () {
          _stopAlert();
        },
      );
    } catch (error) {
      debugPrint('Driver alert sound error: $error');
    }
  }

  Future<void> _stopAlert() async {
    _alertStopTimer?.cancel();
    _alertStopTimer = null;

    try {
      await _alertPlayer.stop();
    } catch (_) {
      // No hay alerta activa o el reproductor ya fue cerrado.
    }
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      socket_service.SocketService.instance.init();

      final drivers = await driver_api.DriverApiService.instance.listDrivers();

      DriverProfile current;

      if (drivers.isEmpty) {
        current = await driver_api.DriverApiService.instance.createDriver(
          name: AppConfig.defaultDriverName,
          phone: AppConfig.defaultDriverPhone,
        );
      } else {
        current = drivers.first;
      }

      current = await driver_api.DriverApiService.instance.updateStatus(
        driverId: current.id,
        status: 'available',
      );

      final assignments = await driver_api.DriverApiService.instance
          .listDriverAssignments(current.id);

      DriverAssignment? activeAssignment;

      for (final assignment in assignments) {
        if (!assignment.isDelivered) {
          activeAssignment = assignment;
          break;
        }
      }

      if (!mounted) return;

      setState(() {
        _driver = current;
        _activeAssignment = activeAssignment;
        _loading = false;
      });

      await _startLocationTracking(current.id);

      await DriverNotificationService.instance.bindDriver(
        driverId: current.id,
        onOrderAvailable: _handleIncomingOrder,
      );

      _setupSocketListeners();
    } catch (error, stackTrace) {
      debugPrint('Driver bootstrap error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error iniciando Driver App: $error'),
        ),
      );
    }
  }

  Future<void> _handleIncomingOrder(
    String orderId,
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;

    final hasActiveAssignment = _activeAssignment != null;

    _refreshAvailableOrders(
      focusOrdersTab: !hasActiveAssignment,
    );

    if (_driver?.status != 'available') return;

    final shouldPlayInAppSound = data['shouldPlayInAppSound'] == true;

    if (shouldPlayInAppSound) {
      await _playNewOrderAlert();
    } else {
      await _stopAlert();
    }

    if (!mounted) return;

    _enqueueIncomingOrder(
      orderId: orderId,
      data: data,
    );
  }

  void _enqueueIncomingOrder({
    required String orderId,
    required Map<String, dynamic> data,
  }) {
    if (_queuedOrDisplayedOrderIds.contains(orderId)) {
      return;
    }

    _queuedOrDisplayedOrderIds.add(orderId);

    _incomingOrderQueue.add(
      <String, dynamic>{
        ...data,
        'orderId': orderId,
      },
    );

    _showNextIncomingOrderModal();
  }

  Future<void> _showNextIncomingOrderModal() async {
    if (!mounted || _incomingOrderModalVisible || _incomingOrderQueue.isEmpty) {
      return;
    }

    _incomingOrderModalVisible = true;

    final orderData = _incomingOrderQueue.removeFirst();
    final orderId = '${orderData['orderId'] ?? ''}'.trim();
    final publicCode = '${orderData['publicCode'] ?? orderId}'.trim();
    final hasActiveAssignment = _activeAssignment != null;

    final shouldOpenOrders = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            titlePadding: const EdgeInsets.fromLTRB(
              24,
              24,
              24,
              0,
            ),
            contentPadding: const EdgeInsets.fromLTRB(
              24,
              16,
              24,
              8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16,
            ),
            title: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE8E8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delivery_dining_rounded,
                    color: Color(0xFFFF4D4F),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Orden lista',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  publicCode.isEmpty
                      ? 'Hay una nueva orden disponible para entregar.'
                      : 'La orden $publicCode está lista para recoger.',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                if (hasActiveAssignment) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Tu entrega activa continuará abierta. '
                      'Esta orden permanecerá disponible en la lista.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cerrar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                icon: const Icon(Icons.inbox_rounded),
                label: const Text('Ver órdenes'),
              ),
            ],
          ),
        );
      },
    );

    await _stopAlert();

    if (mounted && shouldOpenOrders == true) {
      setState(() {
        _selectedIndex = 0;
        _ordersRefreshTick++;
      });
    }

    _queuedOrDisplayedOrderIds.remove(orderId);
    _incomingOrderModalVisible = false;

    if (mounted && _incomingOrderQueue.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNextIncomingOrderModal();
      });
    }
  }

  void _setupSocketListeners() {
    final socket = socket_service.SocketService.instance;

    socket.off('driver_order_available');
    socket.off('driver_orders_refresh');
    socket.off('order_delivery_assigned');
    socket.off('driver_assigned');
    socket.off('driver_picked_up');
    socket.off('driver_delivered');
    socket.off('driver_assignment_cancelled');

    socket.on('driver_order_available', (payload) async {
      await DriverNotificationService.instance.processSocketOrder(
        payload,
      );
    });

    socket.on('driver_orders_refresh', (_) {
      _refreshAvailableOrders(focusOrdersTab: false);
    });

    socket.on('order_delivery_assigned', (payload) {
      try {
        final data = Map<String, dynamic>.from(payload as Map);
        final assignment = DriverAssignment.fromJson(
          Map<String, dynamic>.from(
            data['assignment'] ?? data,
          ),
        );

        if (!mounted) return;

        if (assignment.driverId == _driver?.id) {
          _stopAlert();

          setState(() {
            _activeAssignment = assignment;
            _selectedIndex = 1;
          });
        } else {
          _refreshAvailableOrders(focusOrdersTab: false);
        }
      } catch (error) {
        debugPrint(
          'order_delivery_assigned parse error: $error',
        );
        _refreshAvailableOrders(focusOrdersTab: false);
      }
    });

    socket.on('driver_assigned', (payload) {
      try {
        final data = Map<String, dynamic>.from(payload as Map);
        final assignment = DriverAssignment.fromJson(
          Map<String, dynamic>.from(
            data['assignment'] ?? data,
          ),
        );

        if (!mounted || assignment.driverId != _driver?.id) {
          return;
        }

        _stopAlert();

        setState(() {
          _activeAssignment = assignment;
          _selectedIndex = 1;
        });
      } catch (error) {
        debugPrint('driver_assigned parse error: $error');
      }
    });

    socket.on('driver_picked_up', (payload) {
      _applyAssignmentPayload(payload);
    });

    socket.on('driver_delivered', (payload) {
      _applyAssignmentPayload(
        payload,
        clearIfDelivered: true,
      );

      _refreshAvailableOrders(focusOrdersTab: true);
    });

    socket.on('driver_assignment_cancelled', (payload) {
      _applyAssignmentPayload(
        payload,
        clearIfDelivered: true,
      );

      _refreshAvailableOrders(focusOrdersTab: true);
    });
  }

  void _refreshAvailableOrders({
    bool focusOrdersTab = false,
  }) {
    if (!mounted) return;

    setState(() {
      _ordersRefreshTick++;

      if (focusOrdersTab && _activeAssignment == null) {
        _selectedIndex = 0;
      }
    });
  }

  void _applyAssignmentPayload(
    dynamic payload, {
    bool clearIfDelivered = false,
  }) {
    try {
      final data = Map<String, dynamic>.from(payload as Map);
      final assignment = DriverAssignment.fromJson(
        Map<String, dynamic>.from(
          data['assignment'] ?? data,
        ),
      );

      if (!mounted || assignment.driverId != _driver?.id) {
        return;
      }

      setState(() {
        _activeAssignment = clearIfDelivered ? null : assignment;
      });
    } catch (error) {
      debugPrint('Assignment payload parse error: $error');
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    final driver = _driver;

    if (driver == null || _changingStatus) return;

    try {
      setState(() => _changingStatus = true);

      final updated = await driver_api.DriverApiService.instance.updateStatus(
        driverId: driver.id,
        status: value ? 'available' : 'offline',
      );

      if (updated.status == 'available') {
        await _startLocationTracking(updated.id);
      } else {
        await _locationService.stop();
        await _stopAlert();
      }

      if (!mounted) return;

      setState(() => _driver = updated);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _changingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: AppLoading(
          message: 'Conectando Driver App...',
        ),
      );
    }

    if (driver == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Center(
          child: ElevatedButton(
            onPressed: _bootstrap,
            child: const Text('Reintentar'),
          ),
        ),
      );
    }

    final pages = <Widget>[
      AvailableOrdersScreen(
        driver: driver,
        refreshSignal: _ordersRefreshTick,
        hasActiveAssignment: _activeAssignment != null,
        onAssignmentCreated: (assignment) {
          _stopAlert();

          setState(() {
            _activeAssignment = assignment;
            _selectedIndex = 1;
          });
        },
      ),
      ActiveDeliveryScreen(
        assignment: _activeAssignment,
        onAssignmentChanged: (assignment) {
          setState(() {
            _activeAssignment = assignment;

            if (assignment == null) {
              _selectedIndex = 0;
            }
          });
        },
      ),
      DriverProfileScreen(driver: driver),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Text(
          'GoPicadera Driver',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Row(
            children: [
              Text(
                driver.status == 'available' ? 'Disponible' : 'Offline',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Switch(
                value: driver.status == 'available',
                onChanged: _changingStatus ? null : _toggleAvailability,
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_rounded),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'Órdenes',
          ),
          NavigationDestination(
            icon: Icon(Icons.delivery_dining_rounded),
            selectedIcon: Icon(Icons.delivery_dining_rounded),
            label: 'Activa',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
