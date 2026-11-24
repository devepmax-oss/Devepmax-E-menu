import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand.dart';
import 'tokens.dart';

/// Estilo de texto con una familia de Google Fonts. Si la familia no estuviera
/// disponible, usa la del sistema sin romper la pantalla.
TextStyle brandFont(
  String family, {
  FontWeight? weight,
  double? size,
  Color? color,
  double? height,
  double? letterSpacing,
}) {
  try {
    return GoogleFonts.getFont(
      family,
      fontWeight: weight,
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  } catch (_) {
    return TextStyle(fontWeight: weight, fontSize: size, color: color, height: height, letterSpacing: letterSpacing);
  }
}

/// Estilo de títulos de una combinación tipográfica (para muestras en Ajustes).
TextStyle fontPairHeading(String pairKey, {double size = 28, Color? color}) {
  final pair = fontPairFor(pairKey);
  return brandFont(pair.heading, weight: pair.headingWeight, size: size, color: color, height: 1.1);
}

/// Construye el tema completo de la app a partir de la marca del restaurante:
/// fondo claro u oscuro, colores con contraste garantizado y su tipografía.
ThemeData buildBrandTheme([BrandConfig brand = const BrandConfig()]) {
  final t = BrandTokens.resolve(brand);
  final dark = t.isDark;

  TextStyle heading(double size, {double height = 1.12, double spacing = -0.3}) =>
      brandFont(t.headingFamily, weight: t.headingWeight, size: size, color: t.text, height: height, letterSpacing: spacing);
  TextStyle body(double size, FontWeight weight, {Color? color, double height = 1.4}) =>
      brandFont(t.bodyFamily, weight: weight, size: size, color: color ?? t.text, height: height);

  final textTheme = TextTheme(
    displayLarge: heading(52, height: 1.0, spacing: -1),
    displayMedium: heading(44, height: 1.02, spacing: -0.8),
    displaySmall: heading(36, height: 1.05, spacing: -0.6),
    headlineLarge: heading(32),
    headlineMedium: heading(28),
    headlineSmall: heading(24),
    titleLarge: heading(22, spacing: -0.2),
    titleMedium: body(17, FontWeight.w700, height: 1.3),
    titleSmall: body(15, FontWeight.w700, height: 1.3),
    bodyLarge: body(16, FontWeight.w400),
    bodyMedium: body(15, FontWeight.w400),
    bodySmall: body(13, FontWeight.w400, color: t.muted),
    labelLarge: body(15, FontWeight.w700, height: 1.2),
    labelMedium: body(13, FontWeight.w600, height: 1.2),
    labelSmall: body(12, FontWeight.w600, color: t.muted, height: 1.2),
  );

  // Rojo con relleno legible (botones de borrar, avisos de error).
  final errorFill = dark ? const Color(0xFFD9443A) : const Color(0xFFB3261E);

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.primarySoft,
    onPrimaryContainer: t.primaryText,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.primarySoft,
    onSecondaryContainer: t.primaryText,
    tertiary: t.accent,
    onTertiary: t.onAccent,
    tertiaryContainer: t.accentSoft,
    onTertiaryContainer: t.accentText,
    error: errorFill,
    onError: const Color(0xFFFFFFFF),
    errorContainer: t.dangerSoft,
    onErrorContainer: t.danger,
    surface: t.bg,
    onSurface: t.text,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surface2,
    surfaceContainerHighest: t.surface3,
    outline: t.lineStrong,
    outlineVariant: t.line,
    inverseSurface: t.text,
    onInverseSurface: t.bg,
    inversePrimary: t.primaryText,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    surfaceTint: const Color(0x00000000),
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  final rounded14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: textTheme,
    fontFamily: textTheme.bodyMedium?.fontFamily,
    dividerColor: t.line,
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: heading(26, spacing: -0.5),
      toolbarHeight: 72,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: t.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        disabledBackgroundColor: t.surface3,
        disabledForegroundColor: t.faint,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: rounded14,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        side: BorderSide(color: t.lineStrong),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: rounded14,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primaryText,
        minimumSize: const Size(0, 44),
        shape: rounded14,
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: t.text, minimumSize: const Size(44, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.primary,
      foregroundColor: t.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: body(15, FontWeight.w500, color: t.muted),
      floatingLabelStyle: body(15, FontWeight.w600, color: t.primaryText),
      hintStyle: body(15, FontWeight.w400, color: t.faint),
      helperStyle: body(13, FontWeight.w400, color: t.muted),
      errorStyle: body(13, FontWeight.w600, color: t.danger),
      border: inputBorder(t.line),
      enabledBorder: inputBorder(t.line),
      disabledBorder: inputBorder(t.line),
      focusedBorder: inputBorder(t.primary, 2),
      errorBorder: inputBorder(t.danger),
      focusedErrorBorder: inputBorder(t.danger, 2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surface2,
      selectedColor: t.primarySoft,
      disabledColor: t.surface2,
      side: BorderSide(color: t.line),
      labelStyle: body(14, FontWeight.w600),
      secondaryLabelStyle: body(14, FontWeight.w700, color: t.primaryText),
      checkmarkColor: t.primaryText,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.rail,
      indicatorColor: t.primarySoft,
      useIndicator: true,
      minWidth: 96,
      selectedIconTheme: IconThemeData(color: t.primaryText, size: 26),
      unselectedIconTheme: IconThemeData(color: t.muted, size: 24),
      selectedLabelTextStyle: body(12, FontWeight.w700, color: t.primaryText, height: 1.2),
      unselectedLabelTextStyle: body(12, FontWeight.w600, color: t.muted, height: 1.2),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.onPrimary : t.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.surface3),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.lineStrong),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : null),
      checkColor: WidgetStatePropertyAll(t.onPrimary),
      side: BorderSide(color: t.lineStrong, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.lineStrong),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.text : t.surface2),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.bg : t.muted),
        side: WidgetStatePropertyAll(BorderSide(color: t.line)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      // Márgenes chicos: en el teléfono los diálogos aprovechan casi todo el ancho.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: t.surface,
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: heading(24),
      contentTextStyle: body(15, FontWeight.w400, color: t.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.text,
      contentTextStyle: body(15, FontWeight.w600, color: t.bg),
      actionTextColor: t.bg,
      shape: rounded14,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.text,
      selectedColor: t.primaryText,
      selectedTileColor: t.primarySoft,
      shape: rounded14,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface2,
      surfaceTintColor: const Color(0x00000000),
      shape: rounded14,
      textStyle: body(15, FontWeight.w500),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface2),
        surfaceTintColor: const WidgetStatePropertyAll(Color(0x00000000)),
        shape: WidgetStatePropertyAll(rounded14),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary, linearTrackColor: t.surface3),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.text, borderRadius: BorderRadius.circular(10)),
      textStyle: body(13, FontWeight.w600, color: t.bg),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.text,
      unselectedLabelColor: t.muted,
      indicatorColor: t.primary,
      dividerColor: t.line,
      labelStyle: textTheme.labelLarge,
    ),
  );
}
