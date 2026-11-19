import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/data/menu_models.dart' show Station;
import '../../menu/widgets/common.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          FilledButton.icon(
            onPressed: () => _openEditor(stations),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuevo dispositivo'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(devicesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.devices_other_rounded,
              message: 'Registra aquí las tablets de las mesas, las pantallas de cocina\ny las cajas. Cada una se vincula con un código de 6 dígitos.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _DeviceCard(
              device: list[index],
              station: stations.firstWhereOrNull((s) => s.id == list[index].stationId),
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
            ),
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
    if (created != null && mounted) _showCode(created);
  }

  void _showCode(DeviceView device) {
    if (device.pairingCode == null) return;
    final code = device.pairingCode!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Código para "${device.name}"'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Escríbelo en el dispositivo para vincularlo:'),
          const SizedBox(height: 16),
          SelectableText(
            '${code.substring(0, 3)} ${code.substring(3)}',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 6),
          ),
          const SizedBox(height: 8),
          Text('Vence a las ${DateFormat.jm().format(device.pairingExpiresAt!)} (15 minutos).'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.station,
    required this.onEdit,
    required this.onNewCode,
    required this.onRevoke,
  });

  final DeviceView device;
  final Station? station;
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
        color: Colors.green.shade700,
      );
    } else if (device.hasValidCode) {
      status = StatusChip(
        'Esperando vinculación · código ${device.pairingCode} (vence ${DateFormat.jm().format(device.pairingExpiresAt!)})',
        color: Colors.orange.shade800,
      );
    } else {
      status = const StatusChip('Sin vincular · genera un código');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(_typeIcons[device.type] ?? Icons.devices_rounded, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, children: [
                StatusChip(deviceTypeLabels[device.type] ?? device.type),
                if (station != null) StatusChip(station!.name, color: colorFromHex(station!.color)),
                status,
              ]),
            ]),
          ),
          TextButton.icon(
            onPressed: device.isActive ? onNewCode : null,
            icon: const Icon(Icons.qr_code_rounded),
            label: Text(device.isPaired ? 'Volver a vincular' : 'Generar código'),
          ),
          IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_rounded), onPressed: onEdit),
          if (device.isPaired)
            IconButton(tooltip: 'Desvincular', icon: const Icon(Icons.link_off_rounded), onPressed: onRevoke),
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
        });
        if (mounted) Navigator.pop(context, created);
      } else {
        await api.updateDevice(existing.id, {
          'name': _name.text.trim(),
          'stationId': existing.type == 'KDS' ? _stationId : null,
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
              const Text('La mesa se asigna cuando creemos el plano del salón (Fase 3).'),
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
