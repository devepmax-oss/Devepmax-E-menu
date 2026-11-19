import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gopicadera/core/config/app_config.dart';

import '../services/printer_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final String baseUrl = AppConfig.apiBaseUrl;

  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _prepTimeController = TextEditingController();
  final TextEditingController _taxController = TextEditingController();
  final TextEditingController _currencyController = TextEditingController();
  final TextEditingController _supportPhoneController = TextEditingController();
  final TextEditingController _closedMessageController =
      TextEditingController();

  bool _autoPrint = false;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _isStoreOpen = true;
  bool _acceptsPickup = true;
  bool _acceptsDelivery = true;

  String _operationMode = 'automatic';
  String _timezone = 'America/New_York';

  late List<_DaySchedule> _schedule;

  @override
  void initState() {
    super.initState();
    _schedule = _defaultSchedule();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _prepTimeController.dispose();
    _taxController.dispose();
    _currencyController.dispose();
    _supportPhoneController.dispose();
    _closedMessageController.dispose();
    super.dispose();
  }

  List<_DaySchedule> _defaultSchedule() {
    return [
      _DaySchedule(
        key: 'monday',
        label: 'Lunes',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 23, minute: 0),
      ),
      _DaySchedule(
        key: 'tuesday',
        label: 'Martes',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 23, minute: 0),
      ),
      _DaySchedule(
        key: 'wednesday',
        label: 'Miércoles',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 23, minute: 0),
      ),
      _DaySchedule(
        key: 'thursday',
        label: 'Jueves',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 23, minute: 0),
      ),
      _DaySchedule(
        key: 'friday',
        label: 'Viernes',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 1, minute: 0),
      ),
      _DaySchedule(
        key: 'saturday',
        label: 'Sábado',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 1, minute: 0),
      ),
      _DaySchedule(
        key: 'sunday',
        label: 'Domingo',
        isOpen: true,
        open: const TimeOfDay(hour: 10, minute: 30),
        close: const TimeOfDay(hour: 23, minute: 0),
      ),
    ];
  }

  TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    if (value == null || !value.contains(':')) return fallback;

    final parts = value.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return fallback;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return fallback;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeToApi(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: false,
    );
  }

  Future<void> _loadAllSettings() async {
    try {
      final printerSettings = await PrinterService.instance.getSettings();

      final response = await http.get(
        Uri.parse('$baseUrl/api/settings'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
      );

      Map<String, dynamic> backendSettings = <String, dynamic>{};

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          backendSettings = decoded;
        }
      } else {
        debugPrint(
          'LOAD RESTAURANT SETTINGS RESPONSE => ${response.statusCode} ${response.body}',
        );
      }

      if (!mounted) return;

      setState(() {
        _ipController.text = (printerSettings['ip'] ?? '').toString();
        _portController.text = (printerSettings['port'] ?? 9100).toString();
        _autoPrint = (printerSettings['autoPrint'] ?? false) as bool;

        _currencyController.text =
            (backendSettings['currency'] ?? 'USD').toString();
        _supportPhoneController.text =
            (backendSettings['supportPhone'] ?? '').toString();
        _prepTimeController.text =
            (backendSettings['prepTimeMinutes'] ?? 20).toString();

        final taxPercentage = NumberParser.toDouble(
          backendSettings['taxPercentage'],
          fallback: 0,
        );
        _taxController.text = taxPercentage.toStringAsFixed(2);

        _isStoreOpen = backendSettings['isStoreOpen'] != false;
        _acceptsPickup = backendSettings['acceptsPickup'] != false;
        _acceptsDelivery = backendSettings['acceptsDelivery'] != false;
        _operationMode =
            (backendSettings['operationMode'] ?? 'automatic').toString();
        _timezone = (backendSettings['timezone'] ?? 'America/New_York')
            .toString()
            .trim();
        if (_timezone.isEmpty) {
          _timezone = 'America/New_York';
        }
        _closedMessageController.text =
            (backendSettings['closedMessage'] ?? '').toString();

        final rawSchedule = backendSettings['storeSchedule'];
        if (rawSchedule is Map) {
          final defaults = _defaultSchedule();
          _schedule = defaults.map((day) {
            final rawDay = rawSchedule[day.key];
            if (rawDay is! Map) return day;

            return _DaySchedule(
              key: day.key,
              label: day.label,
              isOpen: rawDay['isOpen'] != false,
              open: _parseTime(rawDay['open']?.toString(), day.open),
              close: _parseTime(rawDay['close']?.toString(), day.close),
            );
          }).toList();
        }

        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showSnack('No se pudieron cargar los ajustes');
    }
  }

  Future<void> _saveAllSettings() async {
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);

    if (ip.isEmpty) {
      _showSnack('Debes ingresar la IP de la impresora');
      return;
    }

    if (port == null || port <= 0) {
      _showSnack('Debes ingresar un puerto válido');
      return;
    }

    final prepTime = int.tryParse(_prepTimeController.text.trim());
    if (prepTime == null || prepTime < 0) {
      _showSnack('El tiempo de preparación no es válido');
      return;
    }

    final taxPercentage = double.tryParse(_taxController.text.trim());
    if (taxPercentage == null || taxPercentage < 0) {
      _showSnack('El impuesto no es válido');
      return;
    }

    try {
      setState(() {
        _saving = true;
      });

      final settingsResponse = await http.patch(
        Uri.parse('$baseUrl/api/settings'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 Flutter Restaurant App',
        },
        body: jsonEncode({
          'currency': _currencyController.text.trim().isEmpty
              ? 'USD'
              : _currencyController.text.trim().toUpperCase(),
          'supportPhone': _supportPhoneController.text.trim(),
          'prepTimeMinutes': prepTime,
          'acceptsPickup': _acceptsPickup,
          'acceptsDelivery': _acceptsDelivery,
          'isStoreOpen': _isStoreOpen,
          'operationMode': _operationMode,
          'timezone': _timezone,
          'closedMessage': _closedMessageController.text.trim(),
          'taxPercentage': taxPercentage,
          'storeSchedule': {
            for (final day in _schedule) day.key: day.toJson(_timeToApi),
          },
        }),
      );

      debugPrint('SAVE SETTINGS RESPONSE => ${settingsResponse.statusCode}');
      debugPrint('SAVE SETTINGS BODY => ${settingsResponse.body}');

      if (settingsResponse.statusCode >= 400) {
        throw Exception(
          'No se pudo guardar configuración del restaurante: ${settingsResponse.body}',
        );
      }

      await PrinterService.instance.saveSettings(
        ip: ip,
        port: port,
        autoPrint: _autoPrint,
      );

      if (!mounted) return;

      _showSnack('Configuración guardada correctamente');
    } catch (e) {
      debugPrint('Error saving settings: $e');

      if (!mounted) return;
      _showSnack('No se pudieron guardar los ajustes');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _testPrinter() async {
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();
    final port = int.tryParse(portText);

    if (ip.isEmpty) {
      _showSnack('Debes ingresar la IP antes de probar');
      return;
    }

    if (port == null || port <= 0) {
      _showSnack('Debes ingresar un puerto válido');
      return;
    }

    try {
      setState(() {
        _testing = true;
      });

      await PrinterService.instance.saveSettings(
        ip: ip,
        port: port,
        autoPrint: _autoPrint,
      );

      final ok = await PrinterService.instance.testPrint();

      if (!mounted) return;

      _showSnack(
        ok
            ? 'Prueba de impresión enviada'
            : 'No se pudo conectar con la impresora',
      );
    } catch (e) {
      debugPrint('Error testing printer: $e');

      if (!mounted) return;
      _showSnack('No se pudo realizar la prueba de impresión');
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  Future<void> _pickTime({
    required int dayIndex,
    required bool isOpenTime,
  }) async {
    final day = _schedule[dayIndex];
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpenTime ? day.open : day.close,
    );

    if (picked == null || !mounted) return;

    setState(() {
      final current = _schedule[dayIndex];
      _schedule[dayIndex] = current.copyWith(
        open: isOpenTime ? picked : current.open,
        close: isOpenTime ? current.close : picked,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ListView(
                  children: [
                    _SectionCard(
                      title: 'Restaurante',
                      subtitle:
                          'Controla si el restaurante puede recibir órdenes.',
                      icon: Icons.storefront_rounded,
                      child: Column(
                        children: [
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'automatic',
                                label: Text('Automático'),
                                icon: Icon(Icons.schedule_rounded),
                              ),
                              ButtonSegment(
                                value: 'manual_open',
                                label: Text('Abrir ahora'),
                                icon: Icon(Icons.check_circle_rounded),
                              ),
                              ButtonSegment(
                                value: 'manual_closed',
                                label: Text('Cerrar ahora'),
                                icon: Icon(Icons.cancel_rounded),
                              ),
                            ],
                            selected: {_operationMode},
                            onSelectionChanged: (values) {
                              setState(() {
                                _operationMode = values.first;
                              });
                            },
                          ),
                          const SizedBox(height: 18),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _isStoreOpen,
                            onChanged: (value) {
                              setState(() {
                                _isStoreOpen = value;
                              });
                            },
                            title: const Text(
                              'Tienda habilitada',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            subtitle: const Text(
                              'Si está apagado, no se aceptarán órdenes aunque el horario esté abierto.',
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _acceptsPickup,
                            onChanged: (value) {
                              setState(() {
                                _acceptsPickup = value;
                              });
                            },
                            title: const Text(
                              'Aceptar Pickup',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _acceptsDelivery,
                            onChanged: (value) {
                              setState(() {
                                _acceptsDelivery = value;
                              });
                            },
                            title: const Text(
                              'Aceptar Delivery',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _LabeledField(
                            label: 'Tiempo de preparación en minutos',
                            controller: _prepTimeController,
                            keyboardType: TextInputType.number,
                            hintText: '20',
                          ),
                          const SizedBox(height: 14),
                          _LabeledField(
                            label: 'Mensaje cuando esté cerrado',
                            controller: _closedMessageController,
                            hintText:
                                'El restaurante está cerrado en este momento.',
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Horario',
                      subtitle: 'Se usa cuando el modo está en automático.',
                      icon: Icons.access_time_filled_rounded,
                      child: Column(
                        children: List.generate(_schedule.length, (index) {
                          final day = _schedule[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      day.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: day.isOpen,
                                    onChanged: (value) {
                                      setState(() {
                                        _schedule[index] = day.copyWith(
                                          isOpen: value,
                                        );
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: !day.isOpen
                                          ? null
                                          : () => _pickTime(
                                                dayIndex: index,
                                                isOpenTime: true,
                                              ),
                                      child:
                                          Text(_formatTime(context, day.open)),
                                    ),
                                  ),
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 8),
                                    child: Text('a'),
                                  ),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: !day.isOpen
                                          ? null
                                          : () => _pickTime(
                                                dayIndex: index,
                                                isOpenTime: false,
                                              ),
                                      child:
                                          Text(_formatTime(context, day.close)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Taxes',
                      subtitle:
                          'Este porcentaje se aplicará automáticamente durante el checkout.',
                      icon: Icons.percent_rounded,
                      child: Row(
                        children: [
                          Expanded(
                            child: _LabeledField(
                              label: 'Sales Tax',
                              controller: _taxController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              hintText: '11.50',
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Padding(
                            padding: EdgeInsets.only(top: 28),
                            child: Text(
                              '%',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'General',
                      subtitle:
                          'Datos generales que usa la app del restaurante y el checkout.',
                      icon: Icons.settings_rounded,
                      child: Column(
                        children: [
                          _LabeledField(
                            label: 'Moneda',
                            controller: _currencyController,
                            hintText: 'USD',
                          ),
                          const SizedBox(height: 14),
                          _LabeledField(
                            label: 'Teléfono de soporte',
                            controller: _supportPhoneController,
                            hintText: '+1 809...',
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Impresora',
                      subtitle: 'Configura la impresora térmica por red local.',
                      icon: Icons.print_rounded,
                      child: Column(
                        children: [
                          _LabeledField(
                            label: 'IP de la impresora',
                            controller: _ipController,
                            hintText: 'Ej. 192.168.1.100',
                          ),
                          const SizedBox(height: 14),
                          _LabeledField(
                            label: 'Puerto',
                            controller: _portController,
                            hintText: '9100',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 14),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Imprimir automáticamente nuevas órdenes',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            subtitle: const Text(
                              'Cuando llegue una orden nueva, se intentará imprimir automáticamente.',
                            ),
                            value: _autoPrint,
                            onChanged: (value) {
                              setState(() {
                                _autoPrint = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: _testing ? null : _testPrinter,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.print_rounded),
                              label: Text(
                                _testing ? 'Probando...' : 'Probar impresora',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF111827),
                                side: const BorderSide(
                                  color: Color(0xFFE5E7EB),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 62,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveAllSettings,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _saving ? 'Guardando...' : 'Guardar configuración',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF111827)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final int maxLines;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF344054),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFFE5E7EB),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFFE5E7EB),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF111827),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DaySchedule {
  final String key;
  final String label;
  final bool isOpen;
  final TimeOfDay open;
  final TimeOfDay close;

  const _DaySchedule({
    required this.key,
    required this.label,
    required this.isOpen,
    required this.open,
    required this.close,
  });

  _DaySchedule copyWith({
    bool? isOpen,
    TimeOfDay? open,
    TimeOfDay? close,
  }) {
    return _DaySchedule(
      key: key,
      label: label,
      isOpen: isOpen ?? this.isOpen,
      open: open ?? this.open,
      close: close ?? this.close,
    );
  }

  Map<String, dynamic> toJson(String Function(TimeOfDay time) timeToApi) {
    return {
      'isOpen': isOpen,
      'open': timeToApi(open),
      'close': timeToApi(close),
    };
  }
}

class NumberParser {
  const NumberParser._();

  static double toDouble(dynamic value, {required double fallback}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
