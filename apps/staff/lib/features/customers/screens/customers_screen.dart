import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../data/customers_api.dart';

/// Clientes: quiénes vienen, cuánto gastan y qué piden. Con notas del personal.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';

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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerSearchProvider(_q));
    final text = Theme.of(context).textTheme;
    final t = BrandTokens.of(context);
    final date = DateFormat.yMd();
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar por nombre, teléfono o email'),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(customerSearchProvider(_q))),
            data: (result) {
              final (total, list) = result;
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.people_alt_rounded,
                  message: _q.isEmpty
                      ? 'Todavía no hay clientes. Aparecen al crear su cuenta en la web o al identificarlos en la caja o la mesa.'
                      : 'Nadie coincide con "$_q".',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(customerSearchProvider(_q)),
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
                        onTap: () => showDialog<void>(context: context, builder: (_) => CustomerDetailDialog(id: c.id)),
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
