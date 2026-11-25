import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
import '../../orders/data/orders_api.dart';
import '../data/admin_api.dart';
import '../data/admin_models.dart';

const _days = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
const _timezones = <String, String>{
  'America/New_York': 'Este (Nueva York, Miami)',
  'America/Chicago': 'Centro (Chicago, Houston)',
  'America/Denver': 'Montaña (Denver)',
  'America/Phoenix': 'Arizona (Phoenix)',
  'America/Los_Angeles': 'Pacífico (Los Ángeles)',
  'America/Anchorage': 'Alaska',
  'Pacific/Honolulu': 'Hawái',
  'America/Puerto_Rico': 'Puerto Rico',
};
const _brandColors = ['#FF7A1A', '#FFC247', '#E2483D', '#E8B230', '#2F6B4F', '#2BB673', '#2563EB', '#7C3AED', '#1F1A14'];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(settingsProvider);
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: ErrorView(error: error, onRetry: () => ref.invalidate(settingsProvider)),
      ),
      data: (value) => _SettingsForm(key: ValueKey(value.$1['updatedAt']), settings: value.$1, hours: value.$2),
    );
  }
}

class _DayHours {
  _DayHours(this.isOpen, this.opensAt, this.closesAt);
  bool isOpen;
  String opensAt;
  String closesAt;
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({super.key, required this.settings, required this.hours});
  final Json settings;
  final List<OpeningHour> hours;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  Json get _s => widget.settings;

  TextEditingController _text(String key) => TextEditingController(text: _s[key]?.toString() ?? '');

  late final _name = _text('name');
  late final _phone = _text('phone');
  late final _whatsapp = _text('whatsapp');
  late final _email = _text('email');
  late final _address = _text('addressLine');
  late final _city = _text('city');
  late final _state = _text('state');
  late final _zip = _text('zipCode');
  late final _prep = _text('prepTimeMinutes');
  late final _footer = _text('receiptFooter');
  late final List<TextEditingController> _tips = List.generate(3, (i) {
    final presets = ((_s['tipPresets'] as List?) ?? const []).cast<int>();
    return TextEditingController(text: i < presets.length ? '${presets[i]}' : '');
  });

  late String _primary = _s['primaryColor'] as String? ?? '#FF7A1A';
  late String _accent = _s['accentColor'] as String? ?? '#FFC247';
  late String _mode = _s['themeMode'] as String? ?? 'dark';
  late String _fontPair = _s['fontPair'] as String? ?? 'bricolage-inter';
  late String _timezone = _s['timezone'] as String? ?? 'America/New_York';
  /// Idioma con que abren la tablet de mesa y la web (el cliente puede cambiarlo).
  late String _language = ((_s['locales'] as List?)?.firstOrNull as String?) == 'en' ? 'en' : 'es';
  late bool _dineIn = _s['acceptsDineIn'] as bool? ?? true;
  late bool _pickup = _s['acceptsPickup'] as bool? ?? true;
  late bool _delivery = _s['acceptsDelivery'] as bool? ?? true;
  late bool _paused = _s['onlineOrderingPaused'] as bool? ?? false;
  late bool _approval = _s['requireWaiterApproval'] as bool? ?? false;
  late bool _maintenance = _s['maintenanceMode'] as bool? ?? false;
  late final List<_DayHours> _week = List.generate(7, (day) {
    final h = widget.hours.where((h) => h.dayOfWeek == day).firstOrNull;
    return _DayHours(h != null, h?.opensAt ?? '11:00', h?.closesAt ?? '22:00');
  });

  bool _saving = false;
  bool _logoBusy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _email, _address, _city, _state, _zip, _prep, _footer, ..._tips]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final email = _email.text.trim();
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'primaryColor': _primary,
      'accentColor': _accent,
      'themeMode': _mode,
      'fontPair': _fontPair,
      'phone': _phone.text.trim(),
      'whatsapp': _whatsapp.text.trim(),
      if (email.isNotEmpty) 'email': email,
      'addressLine': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'zipCode': _zip.text.trim(),
      'timezone': _timezone,
      'locales': _language == 'en' ? ['en', 'es'] : ['es', 'en'],
      'acceptsDineIn': _dineIn,
      'acceptsPickup': _pickup,
      'acceptsDelivery': _delivery,
      'onlineOrderingPaused': _paused,
      'requireWaiterApproval': _approval,
      'maintenanceMode': _maintenance,
      'prepTimeMinutes': int.tryParse(_prep.text.trim()) ?? 20,
      'tipPresets': [for (final t in _tips) int.tryParse(t.text.trim())].whereType<int>().toList(),
      'receiptFooter': _footer.text.trim(),
    };
    final hours = [
      for (var day = 0; day < 7; day++)
        if (_week[day].isOpen) OpeningHour(dayOfWeek: day, opensAt: _week[day].opensAt, closesAt: _week[day].closesAt),
    ];
    try {
      final api = ref.read(adminApiProvider);
      await api.updateSettings(data);
      await api.replaceOpeningHours(hours);
      ref.invalidate(settingsProvider);
      ref.invalidate(publicSettingsProvider);
      if (mounted) showSuccess(context, 'Ajustes guardados');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeLogo({bool remove = false}) async {
    final api = ref.read(adminApiProvider);
    try {
      if (remove) {
        setState(() => _logoBusy = true);
        await api.removeLogo();
      } else {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
        if (file == null) return;
        setState(() => _logoBusy = true);
        await api.uploadLogo(await file.readAsBytes(), file.name);
      }
      ref.invalidate(settingsProvider);
      ref.invalidate(publicSettingsProvider);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _pickTime(_DayHours day, bool opens) async {
    final parts = (opens ? day.opensAt : day.closesAt).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    final value = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (opens) {
        day.opensAt = value;
      } else {
        day.closesAt = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = _s['logoUrl'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes del restaurante'),
        actions: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(isCompact(context) ? 'Guardar' : 'Guardar cambios'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(pagePadding(context)),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _section('Marca', 'Se usa en la app, las tablets, la web y los recibos.', [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: logoUrl == null
                              ? ColoredBox(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.storefront_rounded, size: 48),
                                )
                              : Image.network(logoUrl, fit: BoxFit.contain),
                        ),
                      ),
                      ConstrainedBox(
                        // Al lado del logo si cabe; debajo en el teléfono.
                        constraints: const BoxConstraints(minWidth: 240, maxWidth: 560),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _field(_name, 'Nombre del restaurante', required: true),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            FilledButton.tonalIcon(
                              onPressed: _logoBusy ? null : _changeLogo,
                              icon: const Icon(Icons.upload_rounded),
                              label: Text(logoUrl == null ? 'Subir logo' : 'Cambiar logo'),
                            ),
                            if (logoUrl != null)
                              TextButton(
                                onPressed: _logoBusy ? null : () => _changeLogo(remove: true),
                                child: const Text('Quitar'),
                              ),
                          ]),
                        ]),
                      ),
                    ]),
                  ]),
                  _section('Apariencia', 'Así se ven la app, las tablets y la web. Revisa la vista previa antes de guardar.', [
                    Text('Fondo', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FitSegmented(SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'dark', label: Text('Oscuro'), icon: Icon(Icons.dark_mode_rounded)),
                          ButtonSegment(value: 'light', label: Text('Claro'), icon: Icon(Icons.light_mode_rounded)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) => setState(() => _mode = v.first),
                      )),
                    ),
                    const SizedBox(height: 20),
                    Text('Tipografía', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, runSpacing: 10, children: [for (final p in fontPairs) _fontOption(p)]),
                    const SizedBox(height: 20),
                    _colorPicker('Color principal', _primary, (c) => setState(() => _primary = c)),
                    Padding(
                      padding: EdgeInsets.only(left: isCompact(context) ? 0 : 140, top: 4, bottom: 12),
                      child: Text('Botones y acciones', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    _colorPicker('Color de acento', _accent, (c) => setState(() => _accent = c)),
                    Padding(
                      padding: EdgeInsets.only(left: isCompact(context) ? 0 : 140, top: 4, bottom: 20),
                      child: Text('Promociones y etiquetas', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    _preview(),
                  ]),
                  _section('Contacto y dirección', null, [
                    _row([_field(_phone, 'Teléfono'), _field(_whatsapp, 'WhatsApp'), _field(_email, 'Email', email: true)]),
                    _row([_field(_address, 'Dirección')]),
                    _row([_field(_city, 'Ciudad'), _field(_state, 'Estado'), _field(_zip, 'Código postal')]),
                  ]),
                  _section('Canales de venta', null, [
                    _switch('Pedidos en mesa (tablets y meseros)', _dineIn, (v) => _dineIn = v),
                    _switch('Pickup (recoger en el local)', _pickup, (v) => _pickup = v),
                    _switch('Delivery', _delivery, (v) => _delivery = v),
                    _switch('Pausar pedidos online', _paused, (v) => _paused = v,
                        subtitle: 'Úsalo cuando la cocina esté saturada'),
                    _switch('Las órdenes de las tablets esperan aprobación del mesero', _approval, (v) => _approval = v),
                    _switch('Web en mantenimiento', _maintenance, (v) => _maintenance = v),
                  ]),
                  if (_delivery) const _DeliveryZoneCard(),
                  const _LoyaltyCard(),
                  _section('Operación', null, [
                    _row([
                      _field(_prep, 'Tiempo de preparación (min)', digits: true),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _timezones.containsKey(_timezone) ? _timezone : 'America/New_York',
                        decoration: const InputDecoration(labelText: 'Zona horaria', border: OutlineInputBorder()),
                        items: [
                          for (final e in _timezones.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => _timezone = v ?? _timezone),
                      ),
                    ]),
                    LabeledControl(
                      label: 'Idioma de los clientes',
                      child: FitSegmented(SegmentedButton<String>(
                        segments: const [ButtonSegment(value: 'es', label: Text('Español primero')), ButtonSegment(value: 'en', label: Text('Inglés primero'))],
                        selected: {_language},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() => _language = s.first),
                      )),
                    ),
                    Text('La tablet de mesa y la web abren en este idioma; el cliente puede cambiarlo. Las traducciones de cada plato se escriben en el Menú.',
                        style: TextStyle(color: BrandTokens.of(context).muted, fontSize: 13)),
                    _row([
                      for (var i = 0; i < 3; i++) _field(_tips[i], 'Propina sugerida ${i + 1} (%)', digits: true),
                    ]),
                    _row([_field(_footer, 'Mensaje al pie del recibo', lines: 2)]),
                  ]),
                  _section('Horario de atención', 'Si cierra después de medianoche, pon la hora del día siguiente (ej. 01:00).', [
                    for (var day = 0; day < 7; day++) _dayRow(day),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(int day) {
    final hours = _week[(day + 1) % 7]; // empieza en lunes
    final name = _days[(day + 1) % 7];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 100, child: Text(name)),
        Switch(value: hours.isOpen, onChanged: (v) => setState(() => hours.isOpen = v)),
        if (hours.isOpen)
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(onPressed: () => _pickTime(hours, true), child: Text(hours.opensAt)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('a')),
            OutlinedButton(onPressed: () => _pickTime(hours, false), child: Text(hours.closesAt)),
          ])
        else
          Text('Cerrado', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ]),
    );
  }

  Widget _fontOption(FontPairOption pair) {
    final t = BrandTokens.of(context);
    final selected = pair.key == _fontPair;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _fontPair = pair.key),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? t.primarySoft : t.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? t.primary : t.line, width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Aa', style: fontPairHeading(pair.key, size: 30, color: t.text)),
          const SizedBox(height: 6),
          Text(pair.label, style: Theme.of(context).textTheme.labelLarge),
          Text('${pair.heading} + ${pair.body}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  /// Vista previa con la marca tal como quedaría al guardar.
  Widget _preview() {
    final config = BrandConfig(
      name: _name.text.trim().isEmpty ? 'Tu restaurante' : _name.text.trim(),
      logoUrl: _s['logoUrl'] as String?,
      primary: colorFromHex(_primary, fallback: const Color(0xFFFF7A1A)),
      accent: colorFromHex(_accent, fallback: const Color(0xFFFFC247)),
      mode: _mode == 'light' ? BrandMode.light : BrandMode.dark,
      fontPair: _fontPair,
    );
    return Theme(
      data: buildBrandTheme(config),
      child: Builder(builder: (context) {
        final t = BrandTokens.of(context);
        final text = Theme.of(context).textTheme;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              BrandMark(name: config.name, logoUrl: config.logoUrl, height: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(config.name, style: text.headlineSmall, overflow: TextOverflow.ellipsis)),
              const DmPill('Vista previa'),
            ]),
            const SizedBox(height: 16),
            DmPanel(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text('Plato de ejemplo', style: text.titleLarge)),
                      const SizedBox(width: 8),
                      const DmPill('2x1', tone: DmTone.accent),
                    ]),
                    const SizedBox(height: 4),
                    Text('Así se ven las descripciones de tus platos.', style: text.bodyMedium?.copyWith(color: t.muted)),
                  ]),
                ),
                const SizedBox(width: 12),
                Text(r'$14.50', style: text.titleLarge),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton(onPressed: () {}, child: const Text('Enviar a cocina')),
              OutlinedButton(onPressed: () {}, child: const Text('Llamar al mesero')),
              const DmPill('Listo', tone: DmTone.success),
              const DmPill('Atención', tone: DmTone.warning),
              const DmPill('Atrasado', tone: DmTone.danger),
            ]),
          ]),
        );
      }),
    );
  }

  Widget _colorPicker(String label, String value, ValueChanged<String> onChanged) {
    return LabeledControl(
      label: label,
      labelWidth: 140,
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final c in _brandColors)
          InkWell(
            onTap: () => onChanged(c),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorFromHex(c),
              child: value.toUpperCase() == c ? Icon(Icons.check_rounded, color: readableOn(colorFromHex(c)), size: 18) : null,
            ),
          ),
        SizedBox(
        width: 110,
        child: TextFormField(
          key: ValueKey('$label-$value'),
          initialValue: value,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
          onFieldSubmitted: (v) {
            if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)) onChanged(v.toUpperCase());
          },
          validator: (v) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v ?? '') ? null : '#RRGGBB',
        ),
      ),
      ]),
    );
  }

  Widget _switch(String title, bool value, void Function(bool) set, {String? subtitle}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: (v) => setState(() => set(v)),
    );
  }

  Widget _section(String title, String? help, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (help != null) Text(help, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }

  Widget _row(List<Widget> fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdaptiveRow(minChildWidth: 180, children: fields),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, bool digits = false, bool email = false, int lines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: lines,
      keyboardType: digits ? TextInputType.number : (email ? TextInputType.emailAddress : null),
      inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: (v) {
        final value = (v ?? '').trim();
        if (required && value.isEmpty) return 'Campo obligatorio';
        if (email && value.isNotEmpty && !value.contains('@')) return 'Email inválido';
        return null;
      },
    );
  }
}

/// Envío, pedido mínimo y tiempo de entrega del delivery. Se guarda aparte del resto.
class _DeliveryZoneCard extends ConsumerStatefulWidget {
  const _DeliveryZoneCard();

  @override
  ConsumerState<_DeliveryZoneCard> createState() => _DeliveryZoneCardState();
}

class _DeliveryZoneCardState extends ConsumerState<_DeliveryZoneCard> {
  final _key = GlobalKey<FormState>();
  final _fee = TextEditingController();
  final _min = TextEditingController();
  final _eta = TextEditingController();
  bool _auto = true;
  int _offer = 60;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _fee.dispose();
    _min.dispose();
    _eta.dispose();
    super.dispose();
  }

  String _money(Object? v) {
    final n = double.tryParse('${v ?? 0}') ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(ordersApiProvider).saveDeliveryZone(
            fee: double.parse(_fee.text.trim()),
            minOrder: double.parse(_min.text.trim()),
            etaMinutes: int.parse(_eta.text.trim()),
            autoAssign: _auto,
            offerSeconds: _offer,
          );
      ref.invalidate(deliveryZoneProvider);
      if (mounted) showSuccess(context, 'Zona de delivery guardada');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _amount(String? v, {double max = 1000}) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null || n < 0) return 'Escribe un monto';
    if (n > max) return 'Máximo ${max.toStringAsFixed(0)}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final zone = ref.watch(deliveryZoneProvider);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: zone.when(
          loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('No se pudo cargar la zona de delivery: $e'),
          data: (z) {
            if (!_loaded) {
              _loaded = true;
              _fee.text = _money(z['fee']);
              _min.text = _money(z['minOrder']);
              _eta.text = '${z['etaMinutes'] ?? 35}';
              _auto = z['autoAssign'] as bool? ?? true;
              _offer = (z['offerSeconds'] as num?)?.toInt() ?? 60;
            }
            final configured = z['configured'] == true;
            return Form(
              key: _key,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Delivery', style: text.titleMedium),
                Text(
                  configured ? 'Lo que paga el cliente por el envío y cuánto tarda en llegar.' : 'Todavía sin configurar: el envío sale gratis.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fee,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Costo de envío (\$)', border: OutlineInputBorder()),
                      validator: (v) => _amount(v, max: 100),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _min,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Pedido mínimo (\$)', border: OutlineInputBorder()),
                      validator: _amount,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _eta,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Tiempo de entrega (min)', border: OutlineInputBorder()),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 5 || n > 240 ? 'Entre 5 y 240' : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Asignar repartidor automáticamente'),
                  subtitle: const Text(
                    'Al entrar a cocina, el pedido va al repartidor disponible con menos entregas. '
                    'Si no acepta a tiempo, pasa al siguiente y queda desconectado.',
                  ),
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                ),
                if (_auto)
                  Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('Tiempo para aceptar', style: text.bodyMedium),
                    FitSegmented(SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 30, label: Text('30 s')),
                        ButtonSegment(value: 60, label: Text('60 s')),
                        ButtonSegment(value: 120, label: Text('2 min')),
                      ],
                      selected: {const [30, 60, 120].contains(_offer) ? _offer : 60},
                      onSelectionChanged: (v) => setState(() => _offer = v.first),
                    )),
                  ]),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar delivery'),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Lealtad: puntos por dólar, premio en cupón y regalo de cumpleaños.
class _LoyaltyCard extends ConsumerStatefulWidget {
  const _LoyaltyCard();

  @override
  ConsumerState<_LoyaltyCard> createState() => _LoyaltyCardState();
}

class _LoyaltyCardState extends ConsumerState<_LoyaltyCard> {
  final _key = GlobalKey<FormState>();
  final _perDollar = TextEditingController();
  final _goal = TextEditingController();
  final _amount = TextEditingController();
  final _days = TextEditingController();
  final _birthdayAmount = TextEditingController();
  bool _enabled = false;
  bool _birthday = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_perDollar, _goal, _amount, _days, _birthdayAmount]) {
      c.dispose();
    }
    super.dispose();
  }

  String _money(Object? v) {
    final n = double.tryParse('${v ?? 0}') ?? 0;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  String? _int(String? v, int min, int max) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < min || n > max ? 'Entre $min y $max' : null;
  }

  String? _dollars(String? v) {
    final n = double.tryParse((v ?? '').trim());
    return n == null || n < 1 || n > 500 ? 'Entre 1 y 500' : null;
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).updateSettings({
        'loyaltyEnabled': _enabled,
        'loyaltyPointsPerDollar': int.parse(_perDollar.text.trim()),
        'loyaltyRewardPoints': int.parse(_goal.text.trim()),
        'loyaltyRewardAmount': double.parse(_amount.text.trim()),
        'loyaltyRewardDays': int.parse(_days.text.trim()),
        'birthdayRewardEnabled': _birthday,
        'birthdayRewardAmount': double.parse(_birthdayAmount.text.trim()),
      });
      ref.invalidate(settingsProvider);
      if (mounted) showSuccess(context, 'Lealtad guardada');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider).value?.$1;
    if (settings == null) return const SizedBox.shrink();
    if (!_loaded) {
      _loaded = true;
      _enabled = settings['loyaltyEnabled'] as bool? ?? false;
      _perDollar.text = '${settings['loyaltyPointsPerDollar'] ?? 1}';
      _goal.text = '${settings['loyaltyRewardPoints'] ?? 100}';
      _amount.text = _money(settings['loyaltyRewardAmount'] ?? 5);
      _days.text = '${settings['loyaltyRewardDays'] ?? 60}';
      _birthday = settings['birthdayRewardEnabled'] as bool? ?? false;
      _birthdayAmount.text = _money(settings['birthdayRewardAmount'] ?? 10);
    }
    final perDollar = int.tryParse(_perDollar.text) ?? 1;
    final goal = int.tryParse(_goal.text) ?? 100;
    final amount = double.tryParse(_amount.text) ?? 5;
    final spend = perDollar > 0 ? goal / perDollar : 0;
    InputDecoration deco(String label, {String? prefix}) => InputDecoration(labelText: label, prefixText: prefix, border: const OutlineInputBorder());
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _key,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Lealtad', style: text.titleMedium),
            Text('Los clientes identificados (web, caja o mesa) ganan puntos al pagar. Al llegar a la meta reciben un cupón.', style: text.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Programa de puntos'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (_enabled) ...[
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                  width: 170,
                  child: TextFormField(controller: _perDollar, keyboardType: TextInputType.number, inputFormatters: digits, decoration: deco('Puntos por cada \$1'), validator: (v) => _int(v, 1, 100), onChanged: (_) => setState(() {})),
                ),
                SizedBox(
                  width: 170,
                  child: TextFormField(controller: _goal, keyboardType: TextInputType.number, inputFormatters: digits, decoration: deco('Puntos para el premio'), validator: (v) => _int(v, 10, 100000), onChanged: (_) => setState(() {})),
                ),
                SizedBox(
                  width: 170,
                  child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimals, decoration: deco('Premio', prefix: '\$ '), validator: _dollars, onChanged: (_) => setState(() {})),
                ),
                SizedBox(
                  width: 170,
                  child: TextFormField(controller: _days, keyboardType: TextInputType.number, inputFormatters: digits, decoration: deco('Días que vale el premio'), validator: (v) => _int(v, 7, 365)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Así queda: por cada \$${spend.toStringAsFixed(spend % 1 == 0 ? 0 : 2)} gastados, el cliente recibe \$${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)} '
                '(${spend > 0 ? (amount / spend * 100).toStringAsFixed(1) : '0'} % de regreso).',
                style: text.bodySmall,
              ),
            ],
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Regalo de cumpleaños'),
              subtitle: const Text('En el mes de su cumpleaños, el cliente recibe un cupón (una vez al año).'),
              value: _birthday,
              onChanged: (v) => setState(() => _birthday = v),
            ),
            if (_birthday)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 170,
                  child: TextFormField(controller: _birthdayAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: decimals, decoration: deco('Regalo', prefix: '\$ '), validator: _dollars),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar lealtad'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
