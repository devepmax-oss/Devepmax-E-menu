import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';

Color colorFromHex(String? hex, {Color fallback = Colors.grey}) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => DmPill(label, color: color);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      message: ApiException.from(error).message,
      action: FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Reintentar')),
    );
  }
}

class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.fastfood_rounded, size: 40, color: Theme.of(context).colorScheme.outline)),
    );
    if (url == null) return placeholder;
    return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
  }
}

// ───────────────────────── Pantallas de cualquier tamaño ─────────────────────────

/// Tamaños de pantalla (estándar Material): teléfono, tablet chica, tablet, tablet grande, muy grande.
enum WindowSize { compact, medium, expanded, large, extraLarge }

WindowSize windowSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return WindowSize.compact;
  if (w < 840) return WindowSize.medium;
  if (w < 1200) return WindowSize.expanded;
  if (w < 1600) return WindowSize.large;
  return WindowSize.extraLarge;
}

/// Teléfono (menos de 600 px de ancho).
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// Campos lado a lado si caben; uno debajo del otro si el espacio es angosto.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({super.key, required this.children, this.minChildWidth = 200, this.spacing = 12});

  final List<Widget> children;

  /// Ancho mínimo que necesita cada campo para ir en la misma fila.
  final double minChildWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final fits = box.maxWidth >= children.length * minChildWidth + (children.length - 1) * spacing;
      if (!fits) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ]);
    });
  }
}

/// Una etiqueta y su control: lado a lado si hay espacio; si no, la etiqueta arriba.
class LabeledControl extends StatelessWidget {
  const LabeledControl({super.key, required this.label, required this.child, this.labelWidth = 150, this.breakpoint = 460});

  final String label;
  final Widget child;
  final double labelWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < breakpoint) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          const SizedBox(height: 8),
          child,
        ]);
      }
      return Row(children: [
        SizedBox(width: labelWidth, child: Text(label)),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
      ]);
    });
  }
}

/// Botón de la barra superior: con texto en pantallas grandes, solo ícono en el teléfono.
class AppBarAction extends StatelessWidget {
  const AppBarAction({super.key, required this.icon, required this.label, required this.onPressed, this.filled = true});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) {
      return filled
          ? IconButton.filled(tooltip: label, onPressed: onPressed, icon: Icon(icon))
          : IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));
    }
    return filled
        ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}

/// Margen exterior según la pantalla: 12 en teléfono, 24 en tablet, 32 en pantallas grandes.
double pagePadding(BuildContext context) => switch (windowSizeOf(context)) {
      WindowSize.compact => 12,
      WindowSize.medium || WindowSize.expanded => 24,
      _ => 32,
    };

/// Botón segmentado que, si sus opciones no caben a lo ancho (por ejemplo en un teléfono),
/// se muestra como fichas que bajan de línea. Se usa envolviendo el [SegmentedButton] normal.
class FitSegmented<T> extends StatelessWidget {
  const FitSegmented(this.button, {super.key});
  final SegmentedButton<T> button;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final style = Theme.of(context).textTheme.labelLarge;
      var needed = 0.0;
      for (final s in button.segments) {
        final label = s.label;
        final text = label is Text ? (label.data ?? '') : '';
        final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)
          ..layout();
        needed += painter.width + 48 + (s.icon != null ? 26 : 0);
      }
      if (!box.maxWidth.isFinite || needed <= box.maxWidth) return button;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in button.segments)
          ChoiceChip(
            avatar: s.icon,
            label: s.label ?? Text('${s.value}'),
            selected: button.selected.contains(s.value),
            showCheckmark: false,
            onSelected: button.onSelectionChanged == null || !s.enabled ? null : (_) => button.onSelectionChanged!({s.value}),
          ),
      ]);
    });
  }
}
