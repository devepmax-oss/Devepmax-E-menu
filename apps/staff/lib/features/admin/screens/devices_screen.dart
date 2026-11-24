import 'package:devepmax_ui/devepmax_ui.dart';
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/config.dart';
import '../../../core/ui/feedback.dart';
import '../../billing/data/billing_api.dart';
import '../../billing/data/billing_models.dart';
import '../../menu/data/menu_models.dart' show Station;
import '../../menu/widgets/common.dart';
import '../../tables/data/tables_api.dart';
import '../../tables/data/tables_models.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';

const _typeIcons = <String, IconData>{
  'EMENU': Icons.tablet_rounded,
  'POS': Icons.point_of_sale_rounded,
  'KDS': Icons.soup_kitchen_rounded,
  'WAITER': Icons.room_service_rounded,
};

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca la cuenta regresiva de los códigos y el estado de vinculación.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(devicesProvider);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AdminApi api) action) async {
    try {
      await action(ref.read(adminApiProvider));
      ref.invalidate(devicesProvider);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(devicesProvider);
    final stations = ref.watch(stationsProvider).value ?? const <Station>[];
    final tables = [for (final a in ref.watch(floorProvider).value ?? const <AreaView>[]) ...a.tables];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          AppBarAction(
            icon: Icons.add_rounded,
            label: 'Nuevo dispositivo',
            onPressed: () => _openEditor(stations),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(devicesProvider)),
        data: (list) {
          return ListView.separated(
            padding: EdgeInsets.all(pagePadding(context)),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const _ReadersSection(),
                  const SizedBox(height: 24),
                  Text('Tablets, pantallas y cajas', style: Theme.of(context).textTheme.titleLarge),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Registra aquí las tablets de las mesas, las pantallas de cocina y las cajas. Cada una se vincula con un QR o un código de 6 dígitos.'),
                    ),
                ]);
              }
              final index = i - 1;
              return _DeviceCard(
              device: list[index],
              station: stations.firstWhereOrNull((s) => s.id == list[index].stationId),
              table: tables.firstWhereOrNull((t) => t.id == list[index].tableId),
              onEdit: () => _openEditor(stations, device: list[index]),
              onNewCode: () => _run((api) async {
                final updated = await api.newPairingCode(list[index].id);
                if (mounted) _showCode(updated);
              }),
              onRevoke: () async {
                final ok = await confirm(
                  context,
                  title: 'Desvincular "${list[index].name}"',
                  message: 'El dispositivo dejará de funcionar de inmediato. Para volver a usarlo, genera un código nuevo.',
                  confirmLabel: 'Desvincular',
                );
                if (ok) await _run((api) => api.revokeDevice(list[index].id));
              },
            );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(List<Station> stations, {DeviceView? device}) async {
    final created = await showDialog<DeviceView>(
      context: context,
      builder: (_) => _DeviceDialog(device: device, stations: stations),
    );
    ref.invalidate(devicesProvider);
    unawaited(ref.read(floorProvider.notifier).refresh()); // el plano muestra qué mesas tienen tablet
    if (created != null && mounted) _showCode(created);
  }

  void _showCode(DeviceView device) {
    if (device.pairingCode == null) return;
    showDialog<void>(context: context, builder: (_) => _PairingDialog(device: device))
        .then((_) {
      if (mounted) ref.invalidate(devicesProvider);
    });
  }
}

/// Lo que lleva el QR: el código y la dirección del servidor, para que la tablet quede lista sola.
String pairingQrData(String code) =>
    'devepmax://pair?code=$code&api=${Uri.encodeComponent(AppConfig.apiBaseUrl)}';

/// QR + código de 6 dígitos. Se da cuenta sola cuando el dispositivo queda vinculado.
class _PairingDialog extends ConsumerStatefulWidget {
  const _PairingDialog({required this.device});
  final DeviceView device;

  @override
  ConsumerState<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends ConsumerState<_PairingDialog> {
  Timer? _poll;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final devices = await ref.read(adminApiProvider).devices();
      final current = devices.firstWhereOrNull((d) => d.id == widget.device.id);
      if (current != null && current.isPaired && current.pairingCode == null && mounted) {
        _poll?.cancel();
        setState(() => _paired = true);
      }
    } catch (_) {
      // Se vuelve a intentar en el siguiente ciclo.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final code = widget.device.pairingCode!;
    final expires = widget.device.pairingExpiresAt!;
    return AlertDialog(
      title: Text(_paired ? '¡Listo!' : 'Vincular "${widget.device.name}"'),
      content: SizedBox(
        width: 420,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _paired
              ? Column(key: const ValueKey('ok'), mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, size: 88, color: t.success),
                  const SizedBox(height: 12),
                  Text('"${widget.device.name}" quedó vinculado.', textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium),
                ])
              : Column(key: const ValueKey('code'), mainAxisSize: MainAxisSize.min, children: [
                  const Text('Escanéalo con la cámara del dispositivo:', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: QrImageView(
                      data: pairingQrData(code),
                      size: 240,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      semanticsLabel: 'Código QR de vinculación',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('o escribe este código:', style: TextStyle(color: t.muted)),
                  const SizedBox(height: 4),
                  SelectableText(
                    '${code.substring(0, 3)} ${code.substring(3)}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 6),
                  ),
                  const SizedBox(height: 8),
                  Text('Vence a las ${DateFormat.jm().format(expires)} (15 minutos).', style: TextStyle(color: t.muted)),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Esperando al dispositivo…', style: TextStyle(color: t.muted)),
                  ]),
                ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(_paired ? 'Listo' : 'Cerrar'))],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.station,
    this.table,
    required this.onEdit,
    required this.onNewCode,
    required this.onRevoke,
  });

  final DeviceView device;
  final Station? station;
  final TableView? table;
  final VoidCallback onEdit;
  final VoidCallback onNewCode;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget status;
    if (!device.isActive) {
      status = StatusChip('Desactivado', color: theme.colorScheme.error);
    } else if (device.isPaired) {
      final seen = device.lastSeenAt;
      status = StatusChip(
        seen == null ? 'Vinculado' : 'Vinculado · visto ${DateFormat.MMMd().add_jm().format(seen)}',
        color: BrandTokens.of(context).success,
      );
    } else if (device.hasValidCode) {
      status = StatusChip(
        'Esperando vinculación · código ${device.pairingCode} (vence ${DateFormat.jm().format(device.pairingExpiresAt!)})',
        color: BrandTokens.of(context).warning,
      );
    } else {
      status = const StatusChip('Sin vincular · genera un código');
    }

    final actions = <Widget>[
      TextButton.icon(
        onPressed: device.isActive ? onNewCode : null,
        icon: const Icon(Icons.qr_code_rounded),
        label: Text(device.isPaired ? 'Volver a vincular' : 'Generar código'),
      ),
      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_rounded), onPressed: onEdit),
      if (device.isPaired)
        IconButton(tooltip: 'Desvincular', icon: const Icon(Icons.link_off_rounded), onPressed: onRevoke),
    ];
    final compact = isCompact(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_typeIcons[device.type] ?? Icons.devices_rounded, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                StatusChip(deviceTypeLabels[device.type] ?? device.type),
                if (station != null) StatusChip(station!.name, color: colorFromHex(station!.color)),
                if (table != null) DmPill('Mesa ${table!.label}', tone: DmTone.primary, icon: Icons.table_restaurant_rounded)
                else if (device.type == 'EMENU') const DmPill('Sin mesa', tone: DmTone.warning),
                status,
              ]),
            ]),
          ),
          if (!compact) ...actions,
        ]),
        if (compact) Wrap(alignment: WrapAlignment.end, children: actions),
        ]),
      ),
    );
  }
}

class _DeviceDialog extends ConsumerStatefulWidget {
  const _DeviceDialog({this.device, required this.stations});
  final DeviceView? device;
  final List<Station> stations;

  @override
  ConsumerState<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<_DeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.device?.name);
  late String _type = widget.device?.type ?? 'KDS';
  late String? _stationId = widget.device?.stationId;
  late String? _tableId = widget.device?.tableId;
  late bool _isActive = widget.device?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final api = ref.read(adminApiProvider);
    try {
      final existing = widget.device;
      if (existing == null) {
        final created = await api.createDevice({
          'name': _name.text.trim(),
          'type': _type,
          if (_type == 'KDS' && _stationId != null) 'stationId': _stationId,
          if (_type == 'EMENU' && _tableId != null) 'tableId': _tableId,
        });
        if (mounted) Navigator.pop(context, created);
      } else {
        await api.updateDevice(existing.id, {
          'name': _name.text.trim(),
          'stationId': existing.type == 'KDS' ? _stationId : null,
          'tableId': existing.type == 'EMENU' ? _tableId : null,
          'isActive': _isActive,
        });
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.device == null;
    final type = widget.device?.type ?? _type;
    return AlertDialog(
      title: Text(isNew ? 'Nuevo dispositivo' : 'Editar dispositivo'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              autofocus: isNew,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Pantalla parrilla, Tablet mesa 4, Caja 1',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
              items: [
                for (final entry in deviceTypeLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: isNew ? (v) => setState(() => _type = v ?? _type) : null,
            ),
            if (type == 'KDS') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _stationId,
                decoration: const InputDecoration(
                  labelText: 'Estación que muestra',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Elige una estación')),
                  for (final s in widget.stations) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _stationId = v),
                validator: (v) => v == null ? 'Elige la estación' : null,
              ),
            ],
            if (type == 'EMENU') ...[
              const SizedBox(height: 12),
              _TablePicker(deviceId: widget.device?.id, value: _tableId, onChanged: (v) => setState(() => _tableId = v)),
            ],
            if (!isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                subtitle: const Text('Si lo desactivas, queda desvinculado al instante'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(isNew ? 'Crear y ver código' : 'Guardar')),
      ],
    );
  }
}

/// Mesa donde queda la tablet: el menú que muestra hace los pedidos para esa mesa.
class _TablePicker extends ConsumerWidget {
  const _TablePicker({this.deviceId, required this.value, required this.onChanged});
  final String? deviceId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = ref.watch(floorProvider);
    final areas = floor.value ?? const <AreaView>[];
    final all = [for (final a in areas) ...a.tables];
    if (floor.isLoading && !floor.hasValue) return const LinearProgressIndicator();
    if (all.isEmpty) {
      return const Text('Primero crea las mesas en la sección Mesas; después vuelve aquí para asignar la tablet.');
    }
    final current = all.any((t) => t.id == value) ? value : null;
    final others = (all.firstWhereOrNull((t) => t.id == current)?.tablets ?? const <TabletView>[])
        .where((d) => d.id != deviceId)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String?>(
        isExpanded: true,
        initialValue: current,
        decoration: const InputDecoration(labelText: 'Mesa', border: OutlineInputBorder()),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Sin mesa por ahora')),
          for (final a in areas)
            for (final t in a.tables)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(areas.length > 1 ? '${a.name} · Mesa ${t.label}' : 'Mesa ${t.label}'),
              ),
        ],
        onChanged: onChanged,
      ),
      if (others.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Esa mesa ya tiene la tablet "${others.first.name}". Las dos mostrarán la misma cuenta.',
              style: TextStyle(color: BrandTokens.of(context).warning)),
        ),
    ]);
  }
}

/// Lectores de tarjetas (Stripe Terminal): el cobro llega solo al lector y la cuenta se paga sola.
class _ReadersSection extends ConsumerStatefulWidget {
  const _ReadersSection();

  @override
  ConsumerState<_ReadersSection> createState() => _ReadersSectionState();
}

class _ReadersSectionState extends ConsumerState<_ReadersSection> {
  bool _busy = false;

  Future<void> _register(String code, String label) async {
    setState(() => _busy = true);
    try {
      await ref.read(billingApiProvider).registerReader(code, label);
      ref.invalidate(cardReadersProvider);
      if (mounted) showSuccess(context, 'Lector "$label" conectado');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => const _AddReaderDialog());
    if (result != null) await _register(result.$1, result.$2);
  }

  Future<void> _remove(CardReader r) async {
    final ok = await confirm(context, title: 'Quitar "${r.label}"', message: 'El lector deja de recibir cobros de esta caja.', confirmLabel: 'Quitar');
    if (!ok) return;
    try {
      await ref.read(billingApiProvider).removeReader(r.id);
      ref.invalidate(cardReadersProvider);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(terminalConfigProvider).value;
    final readers = ref.watch(cardReadersProvider);

    return DmPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.contactless_rounded, color: t.accentText, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Lectores de tarjetas', style: text.titleLarge),
              Text('Tarjeta, Apple Pay y Google Pay: el monto llega solo al lector y el cliente elige la propina ahí.',
                  style: TextStyle(color: t.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          if (config?.enabled ?? false) ...[
            if (config!.testMode)
              TextButton.icon(
                onPressed: _busy ? null : () => _register('simulated-s700', 'Lector de prueba'),
                icon: const Icon(Icons.science_rounded),
                label: const Text('Lector de prueba'),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar lector'),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        if (!(config?.enabled ?? true))
          Text('Configura las claves de Stripe en el servidor para conectar lectores.', style: TextStyle(color: t.muted))
        else
          readers.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text(error.toString(), style: TextStyle(color: t.warning, fontWeight: FontWeight.w600)),
            data: (list) => list.isEmpty
                ? Text('Todavía no hay lectores. Enciende el lector, toma el código de registro de su pantalla y tócalo en "Agregar lector".',
                    style: TextStyle(color: t.muted))
                : Column(children: [
                    for (final r in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.point_of_sale_rounded, color: r.online ? t.success : t.faint),
                        title: Text(r.label),
                        subtitle: Text(r.simulated ? 'Lector simulado de Stripe (modo prueba)' : r.deviceType.replaceAll('_', ' ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          DmPill(
                            r.busy ? 'Cobrando' : (r.online ? 'En línea' : 'Apagado'),
                            tone: r.busy ? DmTone.accent : (r.online ? DmTone.success : DmTone.neutral),
                          ),
                          IconButton(tooltip: 'Quitar', onPressed: () => _remove(r), icon: const Icon(Icons.delete_outline_rounded)),
                        ]),
                      ),
                  ]),
          ),
      ]),
    );
  }
}

class _AddReaderDialog extends StatefulWidget {
  const _AddReaderDialog();

  @override
  State<_AddReaderDialog> createState() => _AddReaderDialogState();
}

class _AddReaderDialogState extends State<_AddReaderDialog> {
  final _code = TextEditingController();
  final _label = TextEditingController(text: 'Caja');

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _code.text.trim().length >= 3 && _label.text.trim().length >= 2;
    return AlertDialog(
      title: const Text('Agregar lector'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('En el lector: Ajustes → "Generate pairing code". Escribe aquí las palabras que muestra.'),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Código de registro', hintText: 'sepia-cerulean-aqua', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Caja, Barra, Mesero 1', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, (_code.text.trim(), _label.text.trim())) : null,
          child: const Text('Conectar'),
        ),
      ],
    );
  }
}
