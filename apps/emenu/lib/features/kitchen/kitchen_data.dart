import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device_session.dart';
import '../../core/realtime.dart';

typedef KJson = Map<String, dynamic>;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class KitchenItem {
  const KitchenItem({required this.id, required this.name, required this.quantity, this.notes, this.seat, required this.modifiers});
  final String id;
  final String name;
  final int quantity;
  final String? notes;
  final int? seat;
  final List<String> modifiers;

  factory KitchenItem.fromJson(KJson j) => KitchenItem(
        id: j['id'] as String,
        name: j['name'] as String,
        quantity: (j['quantity'] as num).toInt(),
        notes: (j['notes'] as String?)?.trim().isEmpty ?? true ? null : (j['notes'] as String).trim(),
        seat: (j['seat'] as num?)?.toInt(),
        modifiers: [for (final m in j['modifiers'] as List? ?? const []) '${(m as KJson)['option']}'],
      );
}

/// Un ticket de cocina: lo que esta estación tiene que preparar de una orden.
class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.status,
    required this.updatedAt,
    required this.createdAt,
    this.startedAt,
    this.readyAt,
    required this.orderNumber,
    required this.channel,
    required this.fulfillment,
    this.table,
    this.customerName,
    this.orderNotes,
    this.scheduledFor,
    required this.items,
  });

  final String id;
  final String status;
  final DateTime updatedAt;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? readyAt;
  final int orderNumber;
  final String channel;
  final String fulfillment;
  final String? table;
  final String? customerName;
  final String? orderNotes;
  final DateTime? scheduledFor;
  final List<KitchenItem> items;

  bool get isActive => status == 'NEW' || status == 'ACCEPTED' || status == 'PREPARING' || status == 'READY';
  bool get isPending => status == 'NEW' || status == 'ACCEPTED';
  bool get isCooking => status == 'PREPARING';
  bool get isReady => status == 'READY';

  /// "Mesa 14", "Para llevar", "Recoger", "Delivery" o "Aquí".
  String get destination {
    if (table != null) return 'Mesa $table';
    return switch (fulfillment) {
      'TAKEOUT' => 'Para llevar',
      'PICKUP' => 'Recoger',
      'DELIVERY' => 'Delivery',
      _ => 'Aquí',
    };
  }

  String get channelLabel => switch (channel) {
        'TABLET' => 'Tablet',
        'POS' => 'Caja',
        'WAITER' => 'Mesero',
        'ONLINE' => 'Web',
        _ => channel,
      };

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  KitchenTicket withStatus(String next) => KitchenTicket(
        id: id,
        status: next,
        updatedAt: DateTime.now(),
        createdAt: createdAt,
        startedAt: next == 'PREPARING' ? (startedAt ?? DateTime.now()) : startedAt,
        readyAt: next == 'READY' ? DateTime.now() : (next == 'PREPARING' ? null : readyAt),
        orderNumber: orderNumber,
        channel: channel,
        fulfillment: fulfillment,
        table: table,
        customerName: customerName,
        orderNotes: orderNotes,
        scheduledFor: scheduledFor,
        items: items,
      );

  factory KitchenTicket.fromJson(KJson j) {
    final order = j['order'] as KJson? ?? const {};
    return KitchenTicket(
      id: j['id'] as String,
      status: j['status'] as String,
      updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
      startedAt: _date(j['startedAt']),
      readyAt: _date(j['readyAt']),
      orderNumber: (order['number'] as num?)?.toInt() ?? 0,
      channel: order['channel'] as String? ?? '',
      fulfillment: order['fulfillmentType'] as String? ?? '',
      table: order['table'] as String?,
      customerName: order['customerName'] as String?,
      orderNotes: (order['notes'] as String?)?.trim().isEmpty ?? true ? null : (order['notes'] as String).trim(),
      scheduledFor: _date(order['scheduledFor']),
      items: [for (final i in j['items'] as List? ?? const []) KitchenItem.fromJson(i as KJson)],
    );
  }
}

class KitchenStation {
  const KitchenStation({required this.id, required this.name, this.color});
  final String id;
  final String name;
  final String? color;
}

class KitchenState {
  const KitchenState({required this.station, required this.tickets, this.arrived = const {}});
  final KitchenStation? station;
  final Map<String, KitchenTicket> tickets;

  /// Cuándo llegó cada ticket a esta pantalla (para resaltar los nuevos unos segundos).
  final Map<String, DateTime> arrived;

  List<KitchenTicket> get todo => tickets.values.where((t) => t.isPending || t.isCooking).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<KitchenTicket> get ready => tickets.values.where((t) => t.isReady).toList()
    ..sort((a, b) => (b.readyAt ?? b.updatedAt).compareTo(a.readyAt ?? a.updatedAt));

  KitchenState copyWith({Map<String, KitchenTicket>? tickets, Map<String, DateTime>? arrived, KitchenStation? station}) =>
      KitchenState(station: station ?? this.station, tickets: tickets ?? this.tickets, arrived: arrived ?? this.arrived);
}

/// Sonido al llegar un ticket nuevo (se puede silenciar desde la pantalla).
final kitchenSoundProvider = NotifierProvider<KitchenSound, bool>(KitchenSound.new);

class KitchenSound extends Notifier<bool> {
  final _player = AudioPlayer();

  @override
  bool build() {
    ref.onDispose(_player.dispose);
    return true;
  }

  void toggle() => state = !state;

  Future<void> play() async {
    if (!state) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/new_ticket.mp3'));
    } catch (_) {
      // El navegador puede bloquear el sonido hasta que se toque la pantalla.
    }
  }
}

/// Órdenes canceladas mientras estaban en esta pantalla (para avisar a la cocina).
final kitchenCancelledProvider = StreamProvider<int>((ref) => ref.watch(kitchenProvider.notifier).cancelled);

/// Tickets de esta estación, al día con el tiempo real. Al reconectar se vuelve a cargar todo.
final kitchenProvider = AsyncNotifierProvider<KitchenController, KitchenState>(KitchenController.new);

class KitchenController extends AsyncNotifier<KitchenState> {
  Timer? _poll;
  final _cancelled = StreamController<int>.broadcast();
  Stream<int> get cancelled => _cancelled.stream;

  @override
  Future<KitchenState> build() async {
    ref.watch(deviceSessionProvider.select((s) => s.value?.token));
    final sub = ref.read(realtimeProvider.notifier).events.listen(_onEvent);
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => reload());
    ref.onDispose(() {
      sub.cancel();
      _poll?.cancel();
    });
    return _load();
  }

  Future<KitchenState> _load() async {
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      apiCall(() async => (await dio.get<KJson>('/auth/me')).data!),
      apiCall(() async => (await dio.get<List<dynamic>>('/menu/stations')).data ?? const []),
      apiCall(() async => (await dio.get<List<dynamic>>('/kitchen/tickets')).data ?? const []),
    ]);
    final me = results[0] as KJson;
    final stations = results[1] as List<dynamic>;
    final tickets = [for (final t in results[2] as List<dynamic>) KitchenTicket.fromJson(t as KJson)];
    final stationId = me['stationId'] as String?;
    final s = stations.cast<KJson>().where((e) => e['id'] == stationId).firstOrNull;
    return KitchenState(
      station: s == null ? null : KitchenStation(id: s['id'] as String, name: s['name'] as String, color: s['color'] as String?),
      tickets: {for (final t in tickets) t.id: t},
    );
  }

  Future<void> reload() async {
    try {
      final before = state.value;
      var next = await _load();
      // Tickets que llegaron mientras no había conexión: también suenan y se resaltan.
      if (before != null) {
        final fresh = next.tickets.keys.where((id) => !before.tickets.containsKey(id)).toList();
        next = next.copyWith(arrived: {
          for (final e in before.arrived.entries)
            if (next.tickets.containsKey(e.key)) e.key: e.value,
          for (final id in fresh) id: DateTime.now(),
        });
        if (fresh.isNotEmpty) unawaited(ref.read(kitchenSoundProvider.notifier).play());
      }
      state = AsyncData(next);
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }

  void _onEvent(RealtimeEvent e) {
    if (e.name == 'ready') {
      unawaited(reload());
      return;
    }
    if (e.name != 'ticket.created' && e.name != 'ticket.updated') return;
    final json = e.json;
    final current = state.value;
    if (json == null || current == null) return;
    final ticket = KitchenTicket.fromJson(json);
    final stationId = (json['station'] as KJson?)?['id'];
    if (current.station != null && stationId != null && stationId != current.station!.id) return;
    final existing = current.tickets[ticket.id];
    // Un aviso viejo que llega tarde no pisa uno más nuevo.
    if (existing != null && existing.updatedAt.isAfter(ticket.updatedAt)) return;

    final tickets = {...current.tickets};
    final arrived = {...current.arrived};
    if (ticket.isActive) {
      tickets[ticket.id] = ticket;
      if (existing == null) {
        arrived[ticket.id] = DateTime.now();
        unawaited(ref.read(kitchenSoundProvider.notifier).play());
      }
    } else {
      tickets.remove(ticket.id);
      arrived.remove(ticket.id);
      if (existing != null && ticket.status == 'CANCELLED' && !_cancelled.isClosed) _cancelled.add(ticket.orderNumber);
    }
    state = AsyncData(current.copyWith(tickets: tickets, arrived: arrived));
  }

  /// Empezar, Listo o Deshacer. Se ve al instante; si el servidor lo rechaza, vuelve atrás.
  Future<void> move(String id, String status) async {
    final current = state.value;
    final ticket = current?.tickets[id];
    if (current == null || ticket == null) return;
    state = AsyncData(current.copyWith(tickets: {...current.tickets, id: ticket.withStatus(status)}));
    try {
      final dio = ref.read(dioProvider);
      final data = await apiCall(() async => (await dio.patch<KJson>('/kitchen/tickets/$id', data: {'status': status})).data!);
      final updated = KitchenTicket.fromJson(data);
      final now = state.value!;
      final tickets = {...now.tickets};
      if (updated.isActive) {
        tickets[id] = updated;
      } else {
        tickets.remove(id);
      }
      state = AsyncData(now.copyWith(tickets: tickets));
    } catch (error) {
      final now = state.value!;
      state = AsyncData(now.copyWith(tickets: {...now.tickets, id: ticket}));
      rethrow;
    }
  }
}

/// Productos para marcar agotados desde la cocina.
class KitchenProduct {
  const KitchenProduct({required this.id, required this.name, required this.category, required this.isAvailable});
  final String id;
  final String name;
  final String category;
  final bool isAvailable;
}

Future<List<KitchenProduct>> loadKitchenProducts(Dio dio) async {
  final menu = await apiCall(() async => (await dio.get<KJson>('/menu', queryParameters: {'channel': 'dine_in'})).data!);
  return [
    for (final c in menu['categories'] as List? ?? const [])
      for (final p in (c as KJson)['products'] as List? ?? const [])
        KitchenProduct(
          id: (p as KJson)['id'] as String,
          name: p['name'] as String,
          category: c['name'] as String,
          isAvailable: p['isAvailable'] as bool? ?? true,
        ),
  ];
}

Future<void> setProductAvailable(Dio dio, String productId, bool available) async {
  await apiCall(() async => dio.patch<KJson>('/menu/products/$productId/availability', data: {'isAvailable': available}));
}
