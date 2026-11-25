import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Idioma que eligió el cliente en la tablet ('es' o 'en'). Al volver a la bienvenida, regresa
/// al idioma principal del restaurante (el primero de sus idiomas en Ajustes).
final languageProvider = NotifierProvider<LanguageController, String>(LanguageController.new);

class LanguageController extends Notifier<String> {
  String _default = 'es';

  @override
  String build() => _default;

  /// Idioma principal del restaurante (lo pone la marca al cargar).
  void setDefault(List<String>? locales) {
    final first = (locales == null || locales.isEmpty) ? 'es' : locales.first;
    final changed = _default != first;
    _default = first == 'en' ? 'en' : 'es';
    if (changed) state = _default;
  }

  void set(String lang) => state = lang == 'en' ? 'en' : 'es';
  void reset() => state = _default;
}

/// Hace llegar el idioma a todas las pantallas (sin pasar `ref`).
class LanguageScope extends InheritedWidget {
  const LanguageScope({super.key, required this.lang, required super.child});
  final String lang;

  @override
  bool updateShouldNotify(LanguageScope old) => old.lang != lang;
}

extension Tr on BuildContext {
  String get lang => dependOnInheritedWidgetOfExactType<LanguageScope>()?.lang ?? 'es';

  /// El texto en el idioma del cliente.
  String tr(String es, String en) => lang == 'en' ? en : es;
}

/// Texto traducido del menú ({ en: { name, description } }); si falta, el original.
String translated(Object? translations, String lang, String field, String fallback) {
  if (lang == 'es' || translations is! Map) return fallback;
  final values = translations[lang];
  final value = values is Map ? values[field] : null;
  return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
}

/// Botón ES / EN para el cliente.
class LanguageToggle extends ConsumerWidget {
  const LanguageToggle({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final lang = ref.watch(languageProvider);
    Widget option(String code, String label) {
      final on = lang == code;
      return Material(
        color: on ? t.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => ref.read(languageProvider.notifier).set(code),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 6 : 10),
            child: Text(label, style: TextStyle(color: on ? t.onPrimary : t.text, fontWeight: FontWeight.w800, fontSize: compact ? 13 : 15)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(99), border: Border.all(color: t.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        option('es', compact ? 'ES' : 'Español'),
        option('en', compact ? 'EN' : 'English'),
      ]),
    );
  }
}
