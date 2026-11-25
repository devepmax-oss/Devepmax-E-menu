import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/realtime/realtime.dart';
import 'tables_models.dart';

final tablesApiProvider = Provider<TablesApi>((ref) => TablesApi(ref.watch(dioProvider)));

class TablesApi {
  TablesApi(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<TableView> _table(Future<Response<Map<String, dynamic>>> request) =>
      _call(() async => TableView.fromJson((await request).data!));

  Future<List<AreaView>> floor() => _call(() async {
        final response = await _dio.get<List<dynamic>>('/tables/floor');
        return response.data!.map((a) => AreaView.fromJson(a as TJson)).toList();
      });

  // Operación
  Future<TableView> open(String id, int guests) =>
      _table(_dio.post<Map<String, dynamic>>('/tables/$id/open', data: {'guestCount': guests}));
  Future<TableView> close(String id, {bool force = false}) =>
      _table(_dio.post<Map<String, dynamic>>('/tables/$id/close', data: {'force': force}));
  /// Tomar la mesa (sin [waiterId]) o asignarla a otro mesero (gerente).
  Future<TableView> assignWaiter(String id, {String? waiterId}) =>
      _table(_dio.patch<Map<String, dynamic>>('/tables/$id/waiter', data: {if (waiterId != null) 'waiterId': waiterId}));

  /// Las cuentas por pagar de la mesa, para presentarlas (impresas o con el QR de pago).
  Future<List<Map<String, dynamic>>> checks(String id) => _call(() async {
        final data = (await _dio.get<List<dynamic>>('/billing/tables/$id/check')).data ?? const [];
        return [for (final c in data) Map<String, dynamic>.from(c as Map)];
      });

  Future<TableView> setStatus(String id, String status) =>
      _table(_dio.patch<Map<String, dynamic>>('/tables/$id/status', data: {'status': status}));

  // Plano
  Future<void> createArea(String name) => _call(() => _dio.post('/tables/areas', data: {'name': name}));
  Future<void> renameArea(String id, String name) => _call(() => _dio.patch('/tables/areas/$id', data: {'name': name}));
  Future<void> deleteArea(String id) => _call(() => _dio.delete('/tables/areas/$id'));

  Future<TableView> createTable({required String label, required String areaId, required int seats}) =>
      _table(_dio.post<Map<String, dynamic>>('/tables', data: {'label': label, 'areaId': areaId, 'seats': seats}));

  /// Crea las mesas from, from+1… Devuelve cuántas creó y cuáles ya existían.
  Future<(int, List<String>)> bulkCreate({required String areaId, required int from, required int count, required int seats}) =>
      _call(() async {
        final data = (await _dio.post<Map<String, dynamic>>('/tables/bulk',
                data: {'areaId': areaId, 'from': from, 'count': count, 'seats': seats}))
            .data!;
        return ((data['created'] as num).toInt(), [for (final s in data['skipped'] as List) '$s']);
      });

  Future<TableView> updateTable(String id, {String? label, String? areaId, int? seats}) =>
      _table(_dio.patch<Map<String, dynamic>>('/tables/$id', data: {
        if (label != null) 'label': label,
        if (areaId != null) 'areaId': areaId,
        if (seats != null) 'seats': seats,
      }));

  /// Llamado de la tablet: "Voy" (ACKNOWLEDGED) o "Atendido" (DONE).
  Future<void> resolveRequest(String id, String status) =>
      _call(() => _dio.patch('/tables/requests/$id', data: {'status': status}));

  Future<void> removeTable(String id) => _call(() => _dio.delete('/tables/$id'));

  Future<void> saveLayout(List<TableView> tables) => _call(() => _dio.put('/tables/layout', data: {
        'positions': [for (final t in tables) {'id': t.id, 'posX': t.posX, 'posY': t.posY}],
      }));
}

/// El salón al día: se carga al abrir y con cada `ready`; cada `table.updated` reemplaza la mesa.
final floorProvider = AsyncNotifierProvider<FloorController, List<AreaView>>(FloorController.new);

class FloorController extends AsyncNotifier<List<AreaView>> {
  @override
  Future<List<AreaView>> build() async {
    final sub = ref.read(realtimeProvider.notifier).events.listen(_onEvent);
    ref.onDispose(sub.cancel);
    return ref.read(tablesApiProvider).floor();
  }

  void _onEvent(RealtimeEvent event) {
    switch (event.name) {
      case 'ready':
        unawaited(refresh());
      case 'table.updated':
        final json = event.json;
        if (json == null) return;
        if (json['removed'] == true) {
          _remove(json['id'] as String);
        } else {
          apply(TableView.fromJson(json));
        }
    }
  }

  void _remove(String id) {
    final areas = state.value;
    if (areas == null) return;
    state = AsyncData([for (final a in areas) a.withTables(a.tables.where((t) => t.id != id).toList())]);
  }

  /// Aplica una versión de la mesa (del socket o de una acción propia).
  void apply(TableView table) {
    final areas = state.value;
    if (areas == null) return;
    if (!areas.any((a) => a.id == table.areaId)) {
      unawaited(refresh()); // área nueva que todavía no tenemos
      return;
    }
    state = AsyncData([
      for (final a in areas)
        a.withTables([
          for (final t in a.tables)
            if (t.id != table.id) t,
          if (a.id == table.areaId) table,
        ]..sort(_byLabel)),
    ]);
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await ref.read(tablesApiProvider).floor());
    } catch (error, stack) {
      if (!state.hasValue) state = AsyncError(error, stack);
    }
  }
}

int _byLabel(TableView a, TableView b) {
  final na = int.tryParse(a.label), nb = int.tryParse(b.label);
  if (na != null && nb != null && na != nb) return na - nb;
  return a.label.compareTo(b.label);
}
