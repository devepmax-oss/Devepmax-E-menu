import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/feedback.dart';
import '../data/menu_models.dart';
import '../menu_controller.dart';
import '../widgets/common.dart';

const _stationColors = ['#EF4444', '#F97316', '#EAB308', '#22C55E', '#06B6D4', '#3B82F6', '#8B5CF6', '#EC4899'];

/// Estaciones de cocina (a qué pantalla va cada plato) e impuestos.
class MenuSetupScreen extends ConsumerWidget {
  const MenuSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(adminMenuProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cocina e impuestos')),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(adminMenuProvider)),
        data: (data) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              SizedBox(width: 520, child: _StationsCard(stations: data.stations)),
              SizedBox(width: 520, child: _TaxRatesCard(taxRates: data.taxRates)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

class _StationsCard extends ConsumerWidget {
  const _StationsCard({required this.stations});
  final List<Station> stations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(adminMenuProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('Estaciones de cocina', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => _editStation(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar'),
              ),
            ]),
            Text(
              'Cada producto se envía a la pantalla de su estación (ej. Cocina, Bebidas, Postres).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final station in stations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 10, backgroundColor: colorFromHex(station.color)),
                title: Text(station.name),
                subtitle: station.isActive ? null : const Text('Inactiva'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                    value: station.isActive,
                    onChanged: (v) => _run(context,
                        () => controller.mutate((api) => api.updateStation(station.id, {'isActive': v}))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded),
                    onPressed: () => _editStation(context, ref, station: station),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      final ok = await confirm(context,
                          title: 'Eliminar "${station.name}"',
                          message: 'Solo se puede eliminar si ningún producto ni pantalla la usa.');
                      if (ok && context.mounted) {
                        await _run(context, () => controller.mutate((api) => api.deleteStation(station.id)));
                      }
                    },
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editStation(BuildContext context, WidgetRef ref, {Station? station}) async {
    final name = TextEditingController(text: station?.name);
    var color = station?.color ?? _stationColors.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(station == null ? 'Nueva estación' : 'Editar estación'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              for (final c in _stationColors)
                InkWell(
                  onTap: () => setState(() => color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorFromHex(c),
                    child: color == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final text = name.text.trim();
    if (saved != true || text.isEmpty || !context.mounted) return;
    final data = {'name': text, 'color': color};
    final controller = ref.read(adminMenuProvider.notifier);
    await _run(context, () => controller.mutate(
        (api) => station == null ? api.createStation(data) : api.updateStation(station.id, data)));
  }
}

class _TaxRatesCard extends ConsumerWidget {
  const _TaxRatesCard({required this.taxRates});
  final List<TaxRate> taxRates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(adminMenuProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('Impuestos', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => _editTax(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar'),
              ),
            ]),
            Text(
              'El predeterminado se aplica a todos los productos que no tengan uno propio.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final tax in taxRates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(tax.isDefault ? Icons.star_rounded : Icons.percent_rounded),
                title: Text(tax.name),
                subtitle: Text('${(tax.rate * 100).toStringAsFixed(3)} %${tax.isDefault ? ' · Predeterminado' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editTax(context, ref, tax: tax)),
                  if (!tax.isDefault)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _run(context, () => controller.mutate((api) => api.deleteTaxRate(tax.id))),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTax(BuildContext context, WidgetRef ref, {TaxRate? tax}) async {
    final name = TextEditingController(text: tax?.name);
    final percent = TextEditingController(text: tax == null ? '' : (tax.rate * 100).toStringAsFixed(3));
    var isDefault = tax?.isDefault ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(tax == null ? 'Nuevo impuesto' : 'Editar impuesto'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre (ej. Sales tax)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: percent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(
                labelText: 'Tasa',
                suffixText: '%',
                helperText: 'Ejemplo: 8.875',
                border: OutlineInputBorder(),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Predeterminado'),
              value: isDefault,
              onChanged: tax?.isDefault == true ? null : (v) => setState(() => isDefault = v ?? false),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final nameText = name.text.trim();
    final value = double.tryParse(percent.text.trim().replaceAll(',', '.'));
    if (saved != true || !context.mounted) return;
    if (nameText.isEmpty || value == null || value < 0 || value > 100) {
      showError(context, 'Escribe un nombre y una tasa entre 0 y 100');
      return;
    }
    final data = {
      'name': nameText,
      'rate': double.parse((value / 100).toStringAsFixed(5)),
      'isDefault': isDefault,
    };
    final controller = ref.read(adminMenuProvider.notifier);
    await _run(context, () => controller.mutate(
        (api) => tax == null ? api.createTaxRate(data) : api.updateTaxRate(tax.id, data)));
  }
}
