import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/feedback.dart';
import '../../menu/widgets/common.dart';
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
const _brandColors = ['#FF6A3D', '#EF4444', '#F59E0B', '#16A34A', '#0EA5E9', '#2563EB', '#7C3AED', '#111111'];

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

  late String _primary = _s['primaryColor'] as String? ?? '#FF6A3D';
  late String _accent = _s['accentColor'] as String? ?? '#FACC15';
  late String _timezone = _s['timezone'] as String? ?? 'America/New_York';
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
      'phone': _phone.text.trim(),
      'whatsapp': _whatsapp.text.trim(),
      if (email.isNotEmpty) 'email': email,
      'addressLine': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'zipCode': _zip.text.trim(),
      'timezone': _timezone,
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
                : const Text('Guardar cambios'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _section('Marca', 'Se usa en la app, las tablets, la web y los recibos.', [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      const SizedBox(width: 16),
                      Expanded(
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
                    const SizedBox(height: 16),
                    _colorPicker('Color principal', _primary, (c) => setState(() => _primary = c)),
                    const SizedBox(height: 12),
                    _colorPicker('Color de acento', _accent, (c) => setState(() => _accent = c)),
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
                  _section('Operación', null, [
                    _row([
                      _field(_prep, 'Tiempo de preparación (min)', digits: true),
                      DropdownButtonFormField<String>(
                        initialValue: _timezones.containsKey(_timezone) ? _timezone : 'America/New_York',
                        decoration: const InputDecoration(labelText: 'Zona horaria', border: OutlineInputBorder()),
                        items: [
                          for (final e in _timezones.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => _timezone = v ?? _timezone),
                      ),
                    ]),
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
    return Row(children: [
      SizedBox(width: 110, child: Text(name)),
      Switch(value: hours.isOpen, onChanged: (v) => setState(() => hours.isOpen = v)),
      const SizedBox(width: 8),
      if (hours.isOpen) ...[
        OutlinedButton(onPressed: () => _pickTime(hours, true), child: Text(hours.opensAt)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('a')),
        OutlinedButton(onPressed: () => _pickTime(hours, false), child: Text(hours.closesAt)),
      ] else
        Text('Cerrado', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    ]);
  }

  Widget _colorPicker(String label, String value, ValueChanged<String> onChanged) {
    return Row(children: [
      SizedBox(width: 140, child: Text(label)),
      Wrap(spacing: 8, children: [
        for (final c in _brandColors)
          InkWell(
            onTap: () => onChanged(c),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: colorFromHex(c),
              child: value.toUpperCase() == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
            ),
          ),
      ]),
      const SizedBox(width: 12),
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
    ]);
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: fields[i]),
        ],
      ]),
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
