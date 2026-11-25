import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/customers_api.dart';

/// Clientes: quiénes vienen, cuánto gastan y qué piden. Con notas del personal.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

const _filters = [('all', 'Todos'), ('optIn', 'Aceptan promociones'), ('account', 'Con cuenta web'), ('noVisits', 'Sin visitas')];
const _sorts = [('recent', 'Recientes'), ('spent', 'Más gasto'), ('visits', 'Más visitas'), ('lastVisit', 'Última visita'), ('name', 'Nombre')];

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String _filter = 'all';
  String _sort = 'recent';
  bool _exporting = false;

  CustomerQuery get _query => (q: _q, filter: _filter, sort: _sort);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = value.trim()));
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final url = await ref.read(customersApiProvider).exportLink(q: _q, filter: _filter);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showError(context, 'No se pudo abrir la descarga');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _open(String id) async {
    await showDialog<void>(context: context, builder: (_) => CustomerDetailDialog(id: id));
    ref.invalidate(customerSearchProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerSearchProvider(_query));
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    final date = DateFormat.yMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          AppBarAction(icon: Icons.download_rounded, label: 'Excel', filled: false, onPressed: _exporting ? null : _export),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar por nombre, teléfono o email'),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), children: [
            for (final (key, label) in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label), selected: _filter == key, onSelected: (_) => setState(() => _filter = key)),
              ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Ordenar',
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [for (final (key, label) in _sorts) PopupMenuItem(value: key, child: Text(label))],
              child: Chip(
                avatar: const Icon(Icons.sort_rounded, size: 18),
                label: Text(_sorts.firstWhere((s) => s.$1 == _sort).$2),
              ),
            ),
          ]),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(customerSearchProvider(_query))),
            data: (result) {
              final (total, list) = result;
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.people_alt_rounded,
                  message: _q.isEmpty && _filter == 'all'
                      ? 'Todavía no hay clientes. Aparecen al crear su cuenta en la web o al identificarlos en la caja o la mesa.'
                      : 'Nadie coincide con esa búsqueda.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(customerSearchProvider(_query)),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Text('$total ${total == 1 ? 'cliente' : 'clientes'}', style: text.bodySmall?.copyWith(color: t.muted));
                    }
                    final c = list[index - 1];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                        title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (c.hasAccount) const DmPill('Cuenta web', icon: Icons.language_rounded),
                        ]),
                        subtitle: Text([
                          if (c.phone != null) prettyPhone(c.phone),
                          '${c.visits} ${c.visits == 1 ? 'visita' : 'visitas'}',
                          if (c.lastVisitAt != null) 'última ${date.format(c.lastVisitAt!)}',
                        ].join(' · ')),
                        trailing: Text(formatMoney(c.spent), style: text.titleMedium),
                        onTap: () => _open(c.id),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class CustomerDetailDialog extends ConsumerStatefulWidget {
  const CustomerDetailDialog({super.key, required this.id});
  final String id;

  @override
  ConsumerState<CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends ConsumerState<CustomerDetailDialog> {
  final _notes = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    setState(() => _saving = true);
    try {
      final notes = _notes.text.trim();
      await ref.read(customersApiProvider).update(widget.id, notes: notes.isEmpty ? null : notes, clearNotes: notes.isEmpty);
      ref.invalidate(customerDetailProvider(widget.id));
      if (mounted) showSuccess(context, 'Nota guardada');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(CustomerDetail d) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _EditCustomerDialog(detail: d));
    if (saved == true) ref.invalidate(customerDetailProvider(widget.id));
  }

  Future<void> _merge(CustomerDetail d) async {
    final other = await showDialog<CustomerSummary>(context: context, builder: (_) => _PickDuplicateDialog(exclude: d.summary.id));
    if (other == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Juntar clientes',
      message: 'Las visitas, direcciones, notas y datos de "${other.name}" pasan a "${d.summary.name}", y la ficha de "${other.name}" se borra. No se puede deshacer.',
      confirmLabel: 'Juntar',
    );
    if (!ok) return;
    try {
      await ref.read(customersApiProvider).merge(d.summary.id, other.id);
      _loaded = false; // las notas de ambos se juntaron
      ref.invalidate(customerDetailProvider(widget.id));
      if (mounted) showSuccess(context, 'Clientes juntados');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(CustomerDetail d) async {
    final ok = await confirm(
      context,
      title: 'Borrar cliente',
      message: 'Se borran los datos de "${d.summary.name}": teléfono, email, direcciones, notas y su cuenta web. Sus ventas se quedan en los reportes, sin su nombre. No se puede deshacer.',
      confirmLabel: 'Borrar',
    );
    if (!ok) return;
    try {
      await ref.read(customersApiProvider).remove(d.summary.id);
      if (!mounted) return;
      showSuccess(context, 'Cliente borrado');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerDetailProvider(widget.id));
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    final when = DateFormat.yMd().add_jm();
    final d = async.value;
    if (d != null && !_loaded) {
      _loaded = true;
      _notes.text = d.notes ?? '';
    }

    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: text.bodySmall?.copyWith(color: t.muted)),
              const SizedBox(height: 2),
              Text(value, style: text.titleMedium),
            ]),
          ),
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: d == null
            ? SizedBox(
                height: 240,
                child: async.hasError
                    ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(customerDetailProvider(widget.id)))
                    : const Center(child: CircularProgressIndicator()),
              )
            : ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
                Row(children: [
                  Expanded(child: Text(d.summary.name, style: text.headlineSmall)),
                  IconButton(onPressed: () => _edit(d), icon: const Icon(Icons.edit_rounded), tooltip: 'Editar'),
                  PopupMenuButton<String>(
                    tooltip: 'Más',
                    onSelected: (v) => v == 'merge' ? _merge(d) : _delete(d),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'merge', child: ListTile(leading: Icon(Icons.merge_rounded), title: Text('Juntar con otro cliente'))),
                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Borrar cliente'))),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), tooltip: 'Cerrar'),
                ]),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (d.summary.phone != null) DmPill(prettyPhone(d.summary.phone), icon: Icons.phone_rounded),
                  if (d.summary.email != null) DmPill(d.summary.email!, icon: Icons.mail_rounded),
                  if (d.summary.hasAccount) const DmPill('Cuenta web', icon: Icons.language_rounded),
                  if (d.summary.marketingOptIn) const DmPill('Acepta promociones', tone: DmTone.success, icon: Icons.campaign_rounded),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  stat('Visitas', '${d.summary.visits}'),
                  const SizedBox(width: 8),
                  stat('Gastado', formatMoney(d.summary.spent)),
                  const SizedBox(width: 8),
                  stat('Promedio', d.summary.visits == 0 ? '—' : formatMoney(d.summary.spent / d.summary.visits)),
                ]),
                const SizedBox(height: 16),
                _LoyaltySection(customerId: d.summary.id, detail: d, onChanged: () => ref.invalidate(customerDetailProvider(widget.id))),
                const SizedBox(height: 20),
                Text('Notas del personal', style: text.titleMedium),
                const SizedBox(height: 4),
                Text('Solo las ve el personal: preferencias, alergias, ocasiones…', style: text.bodySmall?.copyWith(color: t.muted)),
                const SizedBox(height: 8),
                TextField(controller: _notes, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(hintText: 'Ej.: prefiere mesa junto a la ventana')),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(onPressed: _saving ? null : _saveNotes, child: const Text('Guardar nota')),
                ),
                if (d.addresses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Direcciones', style: text.titleMedium),
                  for (final a in d.addresses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place_rounded),
                      title: Text(a.label ?? a.line),
                      subtitle: a.label == null ? null : Text(a.line),
                    ),
                ],
                const SizedBox(height: 12),
                Text('Historial', style: text.titleMedium),
                if (d.history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Todavía sin visitas.', style: text.bodyMedium?.copyWith(color: t.muted)),
                  ),
                for (final v in d.history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${v.kindLabel}${v.orderNumbers.isEmpty ? '' : ' · #${v.orderNumbers.join(', #')}'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (v.status == 'CANCELLED') const DmPill('Cancelado', tone: DmTone.danger),
                      if (v.status == 'REFUNDED') const DmPill('Reembolsado', tone: DmTone.danger),
                    ]),
                    subtitle: Text('${when.format(v.date)}\n${v.items.join(' · ')}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    trailing: Text(formatMoney(v.total), style: text.titleMedium),
                  ),
              ]),
      ),
    );
  }
}

class _EditCustomerDialog extends ConsumerStatefulWidget {
  const _EditCustomerDialog({required this.detail});
  final CustomerDetail detail;

  @override
  ConsumerState<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends ConsumerState<_EditCustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.detail.summary.name);
  late final _phone = TextEditingController(text: prettyPhone(widget.detail.summary.phone));
  late final _email = TextEditingController(text: widget.detail.summary.email ?? '');
  late bool _optIn = widget.detail.summary.marketingOptIn;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(customersApiProvider).update(
            widget.detail.summary.id,
            name: _name.text.trim(),
            phone: _phone.text,
            email: _email.text,
            marketingOptIn: _optIn,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Editar cliente'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.isNotEmpty && digits.length < 10 ? 'Teléfono de 10 dígitos' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) {
                final value = (v ?? '').trim();
                return value.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value) ? 'Revisa el email' : null;
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _optIn,
              onChanged: (v) => setState(() => _optIn = v),
              title: const Text('Acepta promociones'),
              subtitle: const Text('Solo si el cliente lo pidió'),
            ),
            if (widget.detail.summary.hasAccount)
              Text(
                'Tiene cuenta web: entra con su teléfono o email. Si los cambias, entrará con los nuevos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Buscar la ficha duplicada de la misma persona.
class _PickDuplicateDialog extends ConsumerStatefulWidget {
  const _PickDuplicateDialog({required this.exclude});
  final String exclude;

  @override
  ConsumerState<_PickDuplicateDialog> createState() => _PickDuplicateDialogState();
}

class _PickDuplicateDialogState extends ConsumerState<_PickDuplicateDialog> {
  Timer? _debounce;
  String _q = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = _q.length < 2 ? null : ref.watch(customerSearchProvider((q: _q, filter: 'all', sort: 'name')));
    final list = (async?.value?.$2 ?? const <CustomerSummary>[]).where((c) => c.id != widget.exclude).toList();
    return AlertDialog(
      scrollable: true,
      title: const Text('Juntar con otro cliente'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Busca la otra ficha de la misma persona (por nombre, teléfono o email).'),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar'),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v.trim()));
            },
          ),
          const SizedBox(height: 8),
          if (async?.isLoading ?? false) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (async != null && !async.isLoading && list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Nadie coincide.')),
          for (final c in list.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
              title: Text(c.name),
              subtitle: Text([if (c.phone != null) prettyPhone(c.phone), if (c.email != null) c.email!, '${c.visits} visitas'].join(' · ')),
              onTap: () => Navigator.pop(context, c),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}

const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// Puntos, premios vigentes, ajuste manual y cumpleaños.
class _LoyaltySection extends ConsumerWidget {
  const _LoyaltySection({required this.customerId, required this.detail, required this.onChanged});
  final String customerId;
  final CustomerDetail detail;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    final async = ref.watch(customerLoyaltyProvider(customerId));
    final info = async.value;
    final date = DateFormat.yMd();
    final birthday = detail.birthMonth != null && detail.birthDay != null ? '${detail.birthDay} de ${_months[detail.birthMonth! - 1]}' : 'Sin fecha';

    Future<void> adjust() async {
      final result = await showDialog<(int, String)>(context: context, builder: (_) => const _AdjustPointsDialog());
      if (result == null) return;
      try {
        await ref.read(customersApiProvider).adjustPoints(customerId, result.$1, result.$2);
        ref.invalidate(customerLoyaltyProvider(customerId));
        onChanged();
        if (context.mounted) showSuccess(context, 'Puntos ajustados');
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> editBirthday() async {
      final result = await showDialog<(int, int)?>(
        context: context,
        builder: (_) => _BirthdayDialog(month: detail.birthMonth, day: detail.birthDay),
      );
      if (result == null) return;
      try {
        final (month, day) = result;
        await ref.read(customersApiProvider).setBirthday(customerId, month == 0 ? null : month, day == 0 ? null : day);
        onChanged();
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.stars_rounded, color: t.accentText),
          const SizedBox(width: 8),
          Expanded(child: Text('Lealtad', style: text.titleMedium)),
          Text('${info?.points ?? detail.points} pts', style: text.titleLarge),
          const SizedBox(width: 4),
          IconButton(tooltip: 'Ajustar puntos', onPressed: adjust, icon: const Icon(Icons.edit_rounded, size: 20)),
        ]),
        if (info != null && !info.enabled)
          Text('El programa de puntos está apagado (Ajustes → Lealtad).', style: text.bodySmall?.copyWith(color: t.muted)),
        if (info != null && info.enabled && info.rewardPoints > 0)
          Text('Le faltan ${(info.rewardPoints - info.points).clamp(0, info.rewardPoints)} puntos para su próximo premio.', style: text.bodySmall?.copyWith(color: t.muted)),
        for (final r in info?.rewards ?? const <LoyaltyReward>[])
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(r.code.startsWith('CUMPLE-') ? Icons.cake_rounded : Icons.card_giftcard_rounded, color: t.accentText),
            title: Text('${r.value != null ? '${formatMoney(r.value!)} · ' : ''}${r.code}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([r.name, if (r.endsAt != null) 'vence ${date.format(r.endsAt!.subtract(const Duration(seconds: 1)))}'].join(' · ')),
          ),
        const Divider(height: 16),
        Row(children: [
          Icon(Icons.cake_rounded, size: 18, color: t.muted),
          const SizedBox(width: 8),
          Expanded(child: Text('Cumpleaños: $birthday')),
          TextButton(onPressed: editBirthday, child: const Text('Cambiar')),
        ]),
      ]),
    );
  }
}

class _AdjustPointsDialog extends StatefulWidget {
  const _AdjustPointsDialog();

  @override
  State<_AdjustPointsDialog> createState() => _AdjustPointsDialogState();
}

class _AdjustPointsDialogState extends State<_AdjustPointsDialog> {
  final _points = TextEditingController();
  final _reason = TextEditingController();
  bool _add = true;

  @override
  void dispose() {
    _points.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_points.text.trim()) ?? 0;
    final ok = value > 0 && _reason.text.trim().length >= 3;
    return AlertDialog(
      scrollable: true,
      title: const Text('Ajustar puntos'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Sumar'), selected: _add, showCheckmark: false, onSelected: (_) => setState(() => _add = true)),
            ChoiceChip(label: const Text('Restar'), selected: !_add, showCheckmark: false, onSelected: (_) => setState(() => _add = false)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _points,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Puntos'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Ej.: compensación por demora'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, (_add ? value : -value, _reason.text.trim())) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _BirthdayDialog extends StatefulWidget {
  const _BirthdayDialog({this.month, this.day});
  final int? month;
  final int? day;

  @override
  State<_BirthdayDialog> createState() => _BirthdayDialogState();
}

class _BirthdayDialogState extends State<_BirthdayDialog> {
  late int _month = widget.month ?? 0;
  late int _day = widget.day ?? 0;

  @override
  Widget build(BuildContext context) {
    final days = _month == 0 ? 31 : const [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][_month - 1];
    if (_day > days) _day = 0;
    return AlertDialog(
      scrollable: true,
      title: const Text('Cumpleaños'),
      content: SizedBox(
        width: 360,
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Mes'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('—')),
                for (var i = 0; i < 12; i++) DropdownMenuItem(value: i + 1, child: Text(_months[i])),
              ],
              onChanged: (v) => setState(() => _month = v ?? 0),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey(days),
              isExpanded: true,
              initialValue: _day,
              decoration: const InputDecoration(labelText: 'Día'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('—')),
                for (var d = 1; d <= days; d++) DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (v) => setState(() => _day = v ?? 0),
            ),
          ),
        ]),
      ),
      actions: [
        if (widget.month != null) TextButton(onPressed: () => Navigator.pop(context, (0, 0)), child: const Text('Quitar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: (_month == 0) == (_day == 0) ? () => Navigator.pop(context, (_month, _day)) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
