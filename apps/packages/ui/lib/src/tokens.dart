import 'package:flutter/material.dart';

import 'brand.dart';

/// Colores del sistema de diseño, ya resueltos para la marca del restaurante.
/// Se leen con `BrandTokens.of(context)`.
@immutable
class BrandTokens extends ThemeExtension<BrandTokens> {
  const BrandTokens({
    required this.mode,
    required this.bg,
    required this.rail,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.primaryText,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentText,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.headingFamily,
    required this.bodyFamily,
    required this.headingWeight,
  });

  final BrandMode mode;

  /// Fondo de la pantalla y de la barra lateral.
  final Color bg;
  final Color rail;

  /// Tarjetas y paneles, de menos a más elevados.
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color lineStrong;

  /// Texto principal, secundario y tenue.
  final Color text;
  final Color muted;
  final Color faint;

  /// Color principal de la marca (botones) y sus variantes legibles.
  final Color primary;
  final Color onPrimary;
  final Color primarySoft;
  final Color primaryText;

  /// Acento de la marca (promociones, etiquetas).
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color accentText;

  /// Estados: el texto (fuerte) se lee sobre su fondo (soft).
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  final String headingFamily;
  final String bodyFamily;
  final FontWeight headingWeight;

  bool get isDark => mode == BrandMode.dark;

  static BrandTokens of(BuildContext context) =>
      Theme.of(context).extension<BrandTokens>() ?? BrandTokens.resolve(const BrandConfig());

  /// Calcula todos los colores a partir de la marca, cuidando el contraste.
  factory BrandTokens.resolve(BrandConfig brand) {
    final dark = brand.mode == BrandMode.dark;
    final pair = fontPairFor(brand.fontPair);

    final bg = dark ? const Color(0xFF120E0B) : const Color(0xFFF6F2EA);
    final surface = dark ? const Color(0xFF1C1612) : const Color(0xFFFFFFFF);
    Color soft(Color c) => Color.alphaBlend(c.withValues(alpha: dark ? 0.16 : 0.12), surface);

    return BrandTokens(
      mode: brand.mode,
      bg: bg,
      rail: dark ? const Color(0xFF0D0A08) : const Color(0xFFFFFFFF),
      surface: surface,
      surface2: dark ? const Color(0xFF241C16) : const Color(0xFFF1EBE1),
      surface3: dark ? const Color(0xFF2C231C) : const Color(0xFFE8E0D3),
      line: dark ? const Color(0xFF2E241C) : const Color(0xFFE4DCCF),
      lineStrong: dark ? const Color(0xFF4A3B2F) : const Color(0xFFCFC4B4),
      text: dark ? const Color(0xFFF8F1E7) : const Color(0xFF1F1A14),
      muted: dark ? const Color(0xFFB9AA98) : const Color(0xFF665D51),
      faint: dark ? const Color(0xFF8C7D6C) : const Color(0xFF8A8174),
      primary: brand.primary,
      onPrimary: readableOn(brand.primary),
      primarySoft: soft(brand.primary),
      primaryText: legibleTint(brand.primary, surface),
      accent: brand.accent,
      onAccent: readableOn(brand.accent),
      accentSoft: soft(brand.accent),
      accentText: legibleTint(brand.accent, surface),
      success: dark ? const Color(0xFF7FE8AE) : const Color(0xFF1F7A4D),
      successSoft: dark ? const Color(0xFF173226) : const Color(0xFFE3F2E9),
      warning: dark ? const Color(0xFFFFD98A) : const Color(0xFF8A5A12),
      warningSoft: dark ? const Color(0xFF3A2E10) : const Color(0xFFFBF0DC),
      danger: dark ? const Color(0xFFFF9A90) : const Color(0xFFA3291F),
      dangerSoft: dark ? const Color(0xFF3A1A15) : const Color(0xFFFCEDEA),
      info: dark ? const Color(0xFFB7CEFF) : const Color(0xFF2B5BA8),
      infoSoft: dark ? const Color(0xFF1A2233) : const Color(0xFFE6EEFB),
      headingFamily: pair.heading,
      bodyFamily: pair.body,
      headingWeight: pair.headingWeight,
    );
  }

  @override
  BrandTokens copyWith() => this;

  @override
  BrandTokens lerp(ThemeExtension<BrandTokens>? other, double t) {
    if (other is! BrandTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BrandTokens(
      mode: t < 0.5 ? mode : other.mode,
      bg: l(bg, other.bg),
      rail: l(rail, other.rail),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      surface3: l(surface3, other.surface3),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      primaryText: l(primaryText, other.primaryText),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      accentText: l(accentText, other.accentText),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      info: l(info, other.info),
      infoSoft: l(infoSoft, other.infoSoft),
      headingFamily: t < 0.5 ? headingFamily : other.headingFamily,
      bodyFamily: t < 0.5 ? bodyFamily : other.bodyFamily,
      headingWeight: t < 0.5 ? headingWeight : other.headingWeight,
    );
  }
}
