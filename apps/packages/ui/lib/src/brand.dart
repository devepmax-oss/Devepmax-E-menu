import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fondo de las pantallas que elige cada restaurante.
enum BrandMode { dark, light }

/// Una combinación tipográfica probada: títulos + texto (Google Fonts).
class FontPairOption {
  const FontPairOption(this.key, this.label, this.heading, this.body, {this.headingWeight = FontWeight.w800});

  /// Clave que guarda el backend (`fontPair`).
  final String key;

  /// Nombre que ve el dueño en Ajustes.
  final String label;
  final String heading;
  final String body;
  final FontWeight headingWeight;
}

/// Deben coincidir con FONT_PAIRS del backend (settings/brand.ts).
const fontPairs = <FontPairOption>[
  FontPairOption('bricolage-inter', 'Moderna con carácter', 'Bricolage Grotesque', 'Inter'),
  FontPairOption('fraunces-inter', 'Clásica y cálida', 'Fraunces', 'Inter', headingWeight: FontWeight.w700),
  FontPairOption('dmserif-dmsans', 'Elegante', 'DM Serif Display', 'DM Sans', headingWeight: FontWeight.w400),
  FontPairOption('oswald-inter', 'Urbana', 'Oswald', 'Inter', headingWeight: FontWeight.w700),
  FontPairOption('poppins', 'Amigable', 'Poppins', 'Poppins', headingWeight: FontWeight.w700),
];

FontPairOption fontPairFor(String? key) =>
    fontPairs.firstWhere((p) => p.key == key, orElse: () => fontPairs.first);

/// La marca del restaurante tal como la guarda Ajustes.
class BrandConfig {
  const BrandConfig({
    this.name = 'Devepmax E-Menu',
    this.logoUrl,
    this.primary = const Color(0xFFFF7A1A),
    this.accent = const Color(0xFFFFC247),
    this.mode = BrandMode.dark,
    this.fontPair = 'bricolage-inter',
  });

  final String name;
  final String? logoUrl;

  /// Botones y acciones principales.
  final Color primary;

  /// Promociones, etiquetas y destacados.
  final Color accent;
  final BrandMode mode;
  final String fontPair;

  /// Lee la respuesta de `GET /settings/public` (o `GET /settings`).
  factory BrandConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const BrandConfig();
    const fallback = BrandConfig();
    return BrandConfig(
      name: (json['name'] as String?) ?? fallback.name,
      logoUrl: json['logoUrl'] as String?,
      primary: hexToColor(json['primaryColor'] as String?) ?? fallback.primary,
      accent: hexToColor(json['accentColor'] as String?) ?? fallback.accent,
      mode: json['themeMode'] == 'light' ? BrandMode.light : BrandMode.dark,
      fontPair: (json['fontPair'] as String?) ?? fallback.fontPair,
    );
  }

  BrandConfig copyWith({Color? primary, Color? accent, BrandMode? mode, String? fontPair}) => BrandConfig(
        name: name,
        logoUrl: logoUrl,
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        mode: mode ?? this.mode,
        fontPair: fontPair ?? this.fontPair,
      );
}

Color? hexToColor(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

/// Relación de contraste WCAG entre dos colores (1 a 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _ink = Color(0xFF1A0C02);
const _white = Color(0xFFFFFFFF);

/// Texto que se lee mejor encima de [background]: tinta oscura o blanco.
Color readableOn(Color background) =>
    contrastRatio(background, _ink) >= contrastRatio(background, _white) ? _ink : _white;

/// Ajusta [color] (aclarando u oscureciendo) hasta que se lea sobre [background].
/// Así un color de marca muy claro u oscuro sigue siendo legible como texto.
Color legibleTint(Color color, Color background, {double minRatio = 4.5}) {
  if (contrastRatio(color, background) >= minRatio) return color;
  final toward = background.computeLuminance() < 0.5 ? _white : const Color(0xFF000000);
  for (var t = 0.05; t <= 1; t += 0.05) {
    final candidate = Color.lerp(color, toward, t)!;
    if (contrastRatio(candidate, background) >= minRatio) return candidate;
  }
  return toward;
}
