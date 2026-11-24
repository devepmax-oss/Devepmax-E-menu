import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../../orders/screens/orders_screen.dart' show LiveIndicator;
import '../data/tables_api.dart';
import '../data/tables_models.dart';
import 'table_panel.dart';

/// Cada mesa ocupa 3 × 3 casillas del plano.
const kTableSpan = 3;
const _maxPos = 39;

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  String? _areaId;
  bool _editing = false;
  bool _saving = false;

  /// Posiciones movidas en modo edición que aún no se guardan.
  final Map<String, (int, int)> _draft = {};
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // El tiempo que llevan las mesas ocupadas se actualiza solo.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  TablesApi get _api => ref.read(tablesApiProvider);

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      await ref.read(floorProvider.notifier).refresh();
      if (done != null && mounted) showSuccess(context, done);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void _startEditing() => setState(() {
        _draft.clear();
        _editing = true;
      });

  Future<void> _finishEditing(List<AreaView> areas, {required bool save}) async {
    if (save && _draft.isNotEmpty) {
      final moved = [
        for (final a in areas)
          for (final t in a.tables)
            if (_draft.containsKey(t.id)) t.moved(_draft[t.id]!.$1, _draft[t.id]!.$2),
      ];
      setState(() => _saving = true);
      try {
        await _api.saveLayout(moved);
        await ref.read(floorProvider.notifier).refresh();
        if (mounted) showSuccess(context, 'Plano guardado');
      } catch (error) {
        if (mounted) showError(context, error);
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    if (mounted) {
      setState(() {
        _saving = false;
        _editing = false;
        _draft.clear();
      });
    }
  }

  List<TableView> _placed(AreaView area) => [
        for (final t in area.tables)
          if (_draft[t.id] case final p?) t.moved(p.$1, p.$2) else t,
      ];

  void _drop(AreaView area, TableView table, int x, int y) {
    final others = _placed(area).where((t) => t.id != table.id);
    final hit = others.firstWhereOrNull((o) => (o.posX - x).abs() < kTableSpan && (o.posY - y).abs() < kTableSpan);
    if (hit != null) {
      showError(context, 'Ahí ya está la mesa ${hit.label}');
      setState(() {}); // vuelve a su lugar
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _draft[table.id] = (x, y));
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final floor = ref.watch(floorProvider);
    final status = ref.watch(realtimeProvider);
    final employee = ref.watch(authControllerProvider).value?.employee;
    final canManage = employee?.can('tables.manage') ?? false;
    final areas = floor.value ?? const <AreaView>[];

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Row(children: [
          Text(_editing ? 'Editar plano' : 'Mesas'),
          const SizedBox(width: 16),
          if (!_editing) LiveIndicator(status: status),
        ]),
        actions: [
          if (_editing) ...[
            TextButton(
              onPressed: _saving ? null : () => _finishEditing(areas, save: false),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _saving ? null : () => _finishEditing(areas, save: true),
              icon: const Icon(Icons.check_rounded),
              label: Text(_draft.isEmpty ? 'Listo' : 'Guardar plano'),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(floorProvider.notifier).refresh(),
            ),
            if (canManage && areas.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _startEditing,
                icon: const Icon(Icons.edit_location_alt_rounded),
                label: const Text('Editar plano'),
              ),
            ],
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: floor.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: () => ref.invalidate(floorProvider)),
        data: (areas) {
          if (areas.isEmpty) {
            return EmptyState(
              icon: Icons.table_restaurant_rounded,
              message: canManage
                  ? 'Crea el primer área del restaurante (Salón, Terraza, Barra…)\ny después agrega sus mesas.'
                  : 'Todavía no hay mesas. Pide a un administrador que arme el plano del salón.',
              action: canManage
                  ? FilledButton.icon(
                      onPressed: () => _editArea(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Crear área'),
                    )
                  : null,
            );
          }
          final area = areas.firstWhereOrNull((a) => a.id == _areaId) ?? areas.first;
          final tables = _placed(area);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in areas)
                    ChoiceChip(
                      label: Text('${a.name} · ${a.tables.length}'),
                      selected: a.id == area.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _areaId = a.id),
                    ),
                  if (_editing)
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Área'),
                      onPressed: () => _editArea(),
                    ),
                ]),
                if (!_editing) _Summary(tables: area.tables),
              ]),
            ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _editTable(areas, area),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Mesa'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _bulk(areas, area),
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('Crear varias'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editArea(area: area),
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    label: const Text('Renombrar área'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _deleteArea(area),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Eliminar área'),
                  ),
                  const SizedBox(width: 8),
                  Text('Arrastra las mesas para acomodarlas · toca una para editarla',
                      style: TextStyle(color: t.muted)),
                ]),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: tables.isEmpty
                    ? EmptyState(
                        icon: Icons.table_bar_rounded,
                        message: _editing
                            ? 'Esta área no tiene mesas. Agrega una o crea varias de una vez.'
                            : 'Esta área no tiene mesas todavía.',
                      )
                    : _FloorCanvas(
                        key: ValueKey(area.id),
                        tables: tables,
                        editing: _editing,
                        onTap: (table) => _editing ? _editTable(areas, area, table: table) : showTablePanel(context, table.id),
                        onDrop: (table, x, y) => _drop(area, table, x, y),
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  // ───────── Edición del plano ─────────

  Future<void> _editArea({AreaView? area}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: area == null ? 'Nueva área' : 'Renombrar área',
        initial: area?.name,
        hint: 'Salón, Terraza, Barra…',
      ),
    );
    if (name == null) return;
    await _run(() async {
      if (area == null) {
        await _api.createArea(name);
      } else {
        await _api.renameArea(area.id, name);
      }
    });
    if (area == null) {
      final created = ref.read(floorProvider).value?.lastWhereOrNull((a) => a.name == name);
      if (created != null && mounted) setState(() => _areaId = created.id);
    }
  }

  Future<void> _deleteArea(AreaView area) async {
    if (area.tables.isNotEmpty) {
      showError(context, 'Primero quita o mueve las ${area.tables.length} mesas de "${area.name}"');
      return;
    }
    final ok = await confirm(context, title: 'Eliminar "${area.name}"', message: 'El área se quita del plano.');
    if (!ok) return;
    await _run(() => _api.deleteArea(area.id), done: 'Área eliminada');
    if (mounted) setState(() => _areaId = null);
  }

  Future<void> _editTable(List<AreaView> areas, AreaView area, {TableView? table}) async {
    final result = await showDialog<_TableEdit>(
      context: context,
      builder: (_) => _TableDialog(table: table, areas: areas, areaId: area.id),
    );
    if (result == null) return;
    if (result.delete && table != null) {
      await _run(() => _api.removeTable(table.id), done: 'Mesa ${table.label} eliminada');
      _draft.remove(table.id);
      return;
    }
    if (table == null) {
      await _run(() => _api.createTable(label: result.label, areaId: result.areaId, seats: result.seats),
          done: 'Mesa ${result.label} agregada');
    } else {
      await _run(() => _api.updateTable(table.id, label: result.label, areaId: result.areaId, seats: result.seats));
      // Si cambió de área, la posición del borrador ya no aplica.
      if (result.areaId != table.areaId) _draft.remove(table.id);
    }
  }

  Future<void> _bulk(List<AreaView> areas, AreaView area) async {
    final numbers = [for (final a in areas) for (final t in a.tables) int.tryParse(t.label)].whereType<int>();
    final next = numbers.isEmpty ? 1 : numbers.reduce(math.max) + 1;
    final result = await showDialog<(int, int, int)>(context: context, builder: (_) => _BulkDialog(from: next, area: area));
    if (result == null) return;
    try {
      final (created, skipped) = await _api.bulkCreate(areaId: area.id, from: result.$1, count: result.$2, seats: result.$3);
      await ref.read(floorProvider.notifier).refresh();
      if (!mounted) return;
      showSuccess(
        context,
        'Se crearon $created mesas${skipped.isEmpty ? '' : ' · ya existían: ${skipped.join(', ')}'}',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

// ───────────────────────── Resumen ─────────────────────────

class _Summary extends StatelessWidget {
  const _Summary({required this.tables});
  final List<TableView> tables;

  @override
  Widget build(BuildContext context) {
    int count(String s) => tables.where((t) => t.displayStatus == s).length;
    final guests = tables.fold<int>(0, (sum, t) => sum + (t.session?.guestCount ?? 0));
    final calls = tables.where((t) => t.hasRequests).length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      DmPill('Libres ${count('AVAILABLE')}', tone: DmTone.success),
      DmPill('Ocupadas ${count('OCCUPIED')}', tone: DmTone.primary),
      if (count('RESERVED') > 0) DmPill('Reservadas ${count('RESERVED')}', tone: DmTone.info),
      if (count('CLEANING') > 0) DmPill('Por limpiar ${count('CLEANING')}', tone: DmTone.warning),
      if (guests > 0) DmPill('$guests clientes', icon: Icons.people_alt_rounded),
      if (calls > 0) DmPill('$calls llamando', tone: DmTone.accent, icon: Icons.notifications_active_rounded),
    ]);
  }
}

// ───────────────────────── Plano ─────────────────────────

class _FloorCanvas extends StatelessWidget {
  const _FloorCanvas({
    super.key,
    required this.tables,
    required this.editing,
    required this.onTap,
    required this.onDrop,
  });

  final List<TableView> tables;
  final bool editing;
  final void Function(TableView) onTap;
  final void Function(TableView, int x, int y) onDrop;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final usedCols = tables.fold<int>(0, (m, e) => math.max(m, e.posX + kTableSpan));
    final usedRows = tables.fold<int>(0, (m, e) => math.max(m, e.posY + kTableSpan));
    // En edición queda espacio libre alrededor para mover las mesas.
    final cols = math.min(_maxPos + kTableSpan, math.max(editing ? 24 : 18, usedCols + (editing ? kTableSpan : 0)));
    final rows = math.min(_maxPos + kTableSpan, math.max(editing ? 14 : 10, usedRows + (editing ? kTableSpan : 0)));

    return LayoutBuilder(builder: (context, constraints) {
      final cell = math.min(constraints.maxWidth / cols, constraints.maxHeight / rows).clamp(14.0, 72.0);
      final width = cols * cell, height = rows * cell;
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: editing ? t.lineStrong : t.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter(cell: cell, color: t.line, lines: editing))),
              for (final table in tables)
                _PlacedTable(
                  key: ValueKey(table.id),
                  table: table,
                  cell: cell,
                  cols: cols,
                  rows: rows,
                  editing: editing,
                  onTap: () => onTap(table),
                  onDrop: (x, y) => onDrop(table, x, y),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.cell, required this.color, required this.lines});
  final double cell;
  final Color color;
  final bool lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (lines) {
      paint.strokeWidth = 1;
      for (var x = cell; x < size.width; x += cell) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = cell; y < size.height; y += cell) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      // Puntos suaves, como un piso.
      for (var x = cell; x < size.width; x += cell) {
        for (var y = cell; y < size.height; y += cell) {
          canvas.drawCircle(Offset(x, y), 1.2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.cell != cell || old.color != color || old.lines != lines;
}

/// Una mesa en su lugar. En modo edición se arrastra y cae en la casilla más cercana.
class _PlacedTable extends StatefulWidget {
  const _PlacedTable({
    super.key,
    required this.table,
    required this.cell,
    required this.cols,
    required this.rows,
    required this.editing,
    required this.onTap,
    required this.onDrop,
  });

  final TableView table;
  final double cell;
  final int cols;
  final int rows;
  final bool editing;
  final VoidCallback onTap;
  final void Function(int x, int y) onDrop;

  @override
  State<_PlacedTable> createState() => _PlacedTableState();
}

class _PlacedTableState extends State<_PlacedTable> {
  Offset _drag = Offset.zero;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final size = cell * kTableSpan;
    final left = widget.table.posX * cell + _drag.dx;
    final top = widget.table.posY * cell + _drag.dy;

    final tile = _TableTile(table: widget.table, size: size - 10, lifted: _dragging, editing: widget.editing);

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: left + 5,
      top: top + 5,
      width: size - 10,
      height: size - 10,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanStart: widget.editing ? (_) => setState(() => _dragging = true) : null,
        onPanUpdate: widget.editing ? (d) => setState(() => _drag += d.delta) : null,
        onPanEnd: widget.editing ? (_) => _end() : null,
        onPanCancel: widget.editing
            ? () => setState(() {
                  _drag = Offset.zero;
                  _dragging = false;
                })
            : null,
        child: MouseRegion(cursor: widget.editing ? SystemMouseCursors.grab : SystemMouseCursors.click, child: tile),
      ),
    );
  }

  void _end() {
    final cell = widget.cell;
    final maxX = math.min(_maxPos, widget.cols - kTableSpan);
    final maxY = math.min(_maxPos, widget.rows - kTableSpan);
    final x = ((widget.table.posX * cell + _drag.dx) / cell).round().clamp(0, maxX);
    final y = ((widget.table.posY * cell + _drag.dy) / cell).round().clamp(0, maxY);
    setState(() {
      _drag = Offset.zero;
      _dragging = false;
    });
    if (x != widget.table.posX || y != widget.table.posY) widget.onDrop(x, y);
  }
}

/// La mesa dibujada: color por estado, nombre grande, tiempo y cuenta si está ocupada.
class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.size, required this.lifted, required this.editing});
  final TableView table;
  final double size;
  final bool lifted;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final status = table.displayStatus;
    final (bg, border, fg) = switch (status) {
      'OCCUPIED' => (t.primary, t.primary, t.onPrimary),
      'RESERVED' => (t.infoSoft, t.info, t.info),
      'CLEANING' => (t.warningSoft, t.warning, t.warning),
      _ => (t.surface2, t.success, t.text),
    };
    final round = table.seats <= 2;
    final s = table.session;
    final roomy = size >= 76;

    final lines = <Widget>[
      Text(
        table.label,
        maxLines: 1,
        style: brandFont(t.headingFamily, weight: t.headingWeight, size: 30, color: fg),
      ),
      if (roomy) ...[
        const SizedBox(height: 2),
        if (s != null) ...[
          Text(elapsedLabel(s.openedAt), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
          if (s.total > 0)
            Text(formatMoney(s.total), style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85))),
        ] else
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_rounded, size: 15, color: fg.withValues(alpha: 0.8)),
            const SizedBox(width: 2),
            Text('${table.seats}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.8))),
          ]),
        if (status == 'RESERVED' || status == 'CLEANING')
          Text(tableStatusLabels[status]!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ],
    ];

    return Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(round ? size / 2 : 20),
          border: Border.all(color: border, width: status == 'OCCUPIED' ? 0 : 2.5),
          boxShadow: [
            if (lifted)
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))
            else if (status == 'OCCUPIED')
              BoxShadow(color: t.primary.withValues(alpha: 0.30), blurRadius: 14, offset: const Offset(0, 5)),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: lines),
          ),
        ),
      ),
      if (table.hasRequests && !editing)
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.accent,
              shape: BoxShape.circle,
              border: Border.all(color: t.surface, width: 2),
            ),
            child: Icon(
              table.session!.requests.any((r) => r.type == 'REQUEST_BILL')
                  ? Icons.receipt_long_rounded
                  : Icons.notifications_active_rounded,
              size: 16,
              color: t.onAccent,
            ),
          ),
        ),
      if (table.tablets.isNotEmpty && roomy && !editing)
        Positioned(
          bottom: 6,
          right: round ? size / 2 - 8 : 8,
          child: Icon(Icons.tablet_android_rounded, size: 14, color: fg.withValues(alpha: 0.6)),
        ),
    ]);
  }
}

/// "12 min", "1 h 05".
String elapsedLabel(DateTime since) {
  final minutes = DateTime.now().difference(since).inMinutes;
  if (minutes < 1) return 'Recién';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

// ───────────────────────── Diálogos ─────────────────────────

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial, required this.hint});
  final String title;
  final String? initial;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 380,
          child: Form(
            key: _form,
            child: TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              decoration: InputDecoration(labelText: 'Nombre', hintText: widget.hint, border: const OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ],
      );
}

class _TableEdit {
  const _TableEdit({this.label = '', this.areaId = '', this.seats = 4, this.delete = false});
  final String label;
  final String areaId;
  final int seats;
  final bool delete;
}

final _labelPattern = RegExp(r'^[A-Za-z0-9 -]{1,10}$');

class _TableDialog extends StatefulWidget {
  const _TableDialog({this.table, required this.areas, required this.areaId});
  final TableView? table;
  final List<AreaView> areas;
  final String areaId;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.table?.label);
  late int _seats = widget.table?.seats ?? 4;
  late String _areaId = widget.table?.areaId ?? widget.areaId;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, _TableEdit(label: _label.text.trim(), areaId: _areaId, seats: _seats));
  }

  Future<void> _delete() async {
    final table = widget.table!;
    final ok = await confirm(
      context,
      title: 'Quitar la mesa ${table.label}',
      message: 'Se quita del plano y su tablet queda sin mesa. El historial de pedidos se conserva.',
      confirmLabel: 'Quitar',
    );
    if (ok && mounted) Navigator.pop(context, const _TableEdit(delete: true));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.table == null;
    final busy = widget.table?.session != null;
    return AlertDialog(
      title: Text(isNew ? 'Nueva mesa' : 'Mesa ${widget.table!.label}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _label,
              autofocus: isNew,
              decoration: const InputDecoration(
                labelText: 'Nombre o número',
                hintText: '12, T3, Barra 1',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Escribe el nombre de la mesa';
                if (!_labelPattern.hasMatch(value)) return 'Hasta 10 letras, números o espacios';
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text('Lugares', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in const [1, 2, 4, 6, 8, 10, 12])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _seats == n,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _seats = n),
                ),
            ]),
            if (widget.areas.length > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _areaId,
                decoration: const InputDecoration(labelText: 'Área', border: OutlineInputBorder()),
                items: [for (final a in widget.areas) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _areaId = v ?? _areaId),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        if (!isNew)
          TextButton(
            onPressed: busy ? null : _delete,
            child: Text(busy ? 'Ocupada: no se puede quitar' : 'Quitar mesa',
                style: TextStyle(color: busy ? null : Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: Text(isNew ? 'Agregar' : 'Guardar')),
      ],
    );
  }
}

class _BulkDialog extends StatefulWidget {
  const _BulkDialog({required this.from, required this.area});
  final int from;
  final AreaView area;

  @override
  State<_BulkDialog> createState() => _BulkDialogState();
}

class _BulkDialogState extends State<_BulkDialog> {
  final _form = GlobalKey<FormState>();
  late final _from = TextEditingController(text: '${widget.from}');
  final _count = TextEditingController(text: '10');
  int _seats = 4;

  @override
  void dispose() {
    _from.dispose();
    _count.dispose();
    super.dispose();
  }

  String? _number(String? v, int min, int max) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < min || n > max) return 'Entre $min y $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final from = int.tryParse(_from.text) ?? widget.from;
    final count = int.tryParse(_count.text) ?? 0;
    return AlertDialog(
      title: Text('Crear varias mesas en ${widget.area.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          onChanged: () => setState(() {}),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _from,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Desde el número', border: OutlineInputBorder()),
                  validator: (v) => _number(v, 1, 999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _count,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Cuántas', border: OutlineInputBorder()),
                  validator: (v) => _number(v, 1, 50),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Lugares por mesa', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final n in const [2, 4, 6, 8])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _seats == n,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _seats = n),
                ),
            ]),
            const SizedBox(height: 16),
            if (count > 0)
              Text(
                count == 1 ? 'Se creará la mesa $from.' : 'Se crearán las mesas $from a ${from + count - 1}.',
                style: TextStyle(color: BrandTokens.of(context).muted),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, (int.parse(_from.text), int.parse(_count.text), _seats));
            }
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
