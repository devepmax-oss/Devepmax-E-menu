import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

/// Tono de una etiqueta de estado. El texto siempre acompaña al color.
enum DmTone { neutral, primary, accent, success, warning, danger, info }

/// Etiqueta redondeada ("Activa", "Agotado", "2x1"…), legible en fondo claro u oscuro.
class DmPill extends StatelessWidget {
  const DmPill(this.label, {super.key, this.tone = DmTone.neutral, this.icon, this.color});

  final String label;
  final DmTone tone;
  final IconData? icon;

  /// Color propio (por ejemplo, el de una estación de cocina). Tiene prioridad sobre [tone].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final (bg, fg) = switch (tone) {
      DmTone.primary => (t.primarySoft, t.primaryText),
      DmTone.accent => (t.accentSoft, t.accentText),
      DmTone.success => (t.successSoft, t.success),
      DmTone.warning => (t.warningSoft, t.warning),
      DmTone.danger => (t.dangerSoft, t.danger),
      DmTone.info => (t.infoSoft, t.info),
      DmTone.neutral => (t.surface3, t.muted),
    };
    final custom = color;
    final background = custom == null ? bg : Color.alphaBlend(custom.withValues(alpha: t.isDark ? 0.18 : 0.14), t.surface);
    final foreground = custom == null ? fg : _legible(custom, background);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      // Un solo texto (con el ícono adentro): se recorta con "…" si no cabe, sin desbordar.
      child: Text.rich(
        TextSpan(children: [
          if (icon != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(padding: const EdgeInsets.only(right: 5), child: Icon(icon, size: 14, color: foreground)),
            ),
          ],
          TextSpan(text: label),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }

  static Color _legible(Color color, Color background) {
    final dark = background.computeLuminance() < 0.5;
    for (var i = 0.0; i <= 1; i += 0.1) {
      final c = Color.lerp(color, dark ? Colors.white : Colors.black, i)!;
      final l1 = c.computeLuminance(), l2 = background.computeLuminance();
      final ratio = ((l1 > l2 ? l1 : l2) + 0.05) / ((l1 > l2 ? l2 : l1) + 0.05);
      if (ratio >= 4.5) return c;
    }
    return dark ? Colors.white : Colors.black;
  }
}

/// Panel con el estilo del sistema (superficie, borde suave, esquinas amplias).
class DmPanel extends StatelessWidget {
  const DmPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.line),
      ),
      child: child,
    );
  }
}

/// Logo del restaurante; si no tiene, su nombre con la tipografía de la marca.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.name, this.logoUrl, this.height = 48});

  final String name;
  final String? logoUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = Container(
      width: height,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primarySoft, borderRadius: BorderRadius.circular(height * 0.3)),
      child: Text(initials, style: brandFont(t.headingFamily, weight: t.headingWeight, size: height * 0.38, color: t.primaryText)),
    );
    final url = logoUrl;
    if (url == null || url.isEmpty) return fallback;
    return Image.network(
      url,
      height: height,
      fit: BoxFit.contain,
      semanticLabel: name,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
