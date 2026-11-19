/// Devepmax E-Menu — UI compartida.
library;

import 'package:flutter/material.dart';

/// Construye el tema a partir de los colores de marca del restaurante
/// (vendrán de `RestaurantSettings` en el backend).
ThemeData buildBrandTheme({
  required Color primary,
  required Color accent,
  Brightness brightness = Brightness.light,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    secondary: accent,
    brightness: brightness,
  );
  return ThemeData(colorScheme: scheme, useMaterial3: true);
}
