import 'dart:async';

import 'package:devepmax_ui/devepmax_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/config.dart';
import '../features/kiosk/staff_menu.dart';
import '../features/menu/menu_data.dart';
import 'device_session.dart';
import 'format.dart';

/// Servidor actual (para armar las direcciones de las fotos).
final apiBaseProvider = Provider<String>(
  (ref) => ref.watch(deviceSessionProvider).value?.apiBaseUrl ?? AppConfig.apiBaseUrl,
);

/// Foto de un plato o categoría; si no hay, un fondo con un ícono.
class ProductPhoto extends ConsumerWidget {
  const ProductPhoto({super.key, required this.url, this.icon = Icons.restaurant_rounded, this.iconSize = 40});
  final String? url;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = BrandTokens.of(context);
    final src = mediaUrl(url, ref.watch(apiBaseProvider));
    final placeholder = Container(
      color: t.surface2,
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: t.faint),
    );
    if (src == null) return placeholder;
    return Image.network(
      src,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 250), child: child),
    );
  }
}

/// Logo del restaurante. Mantenerlo presionado 3 segundos abre el menú del personal.
class StaffLogo extends ConsumerStatefulWidget {
  const StaffLogo({super.key, this.height = 56});
  final double height;

  @override
  ConsumerState<StaffLogo> createState() => _StaffLogoState();
}

class _StaffLogoState extends ConsumerState<StaffLogo> {
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandConfig.fromJson(ref.watch(brandProvider).value);
    final logoUrl = mediaUrl(brand.logoUrl, ref.watch(apiBaseProvider));
    return GestureDetector(
      onLongPressStart: (_) {
        _hold?.cancel();
        _hold = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) openStaffMenu(context);
        });
      },
      onLongPressEnd: (_) => _hold?.cancel(),
      onLongPressCancel: () => _hold?.cancel(),
      child: BrandMark(name: brand.name, logoUrl: logoUrl, height: widget.height),
    );
  }
}

/// Aviso breve abajo de la pantalla.
void showMessage(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 520,
      backgroundColor: error ? scheme.error : null,
      content: Text(message,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: error ? scheme.onError : null)),
    ));
}

/// Botón − cantidad + grande, cómodo para el dedo.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.compact = false});
  final int value;
  final int min;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final size = compact ? 34.0 : 48.0;
    Widget button(IconData icon, VoidCallback? onTap) => Material(
          color: t.surface3,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: compact ? 18 : 24, color: onTap == null ? t.faint : t.text),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(min == 0 && value == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
          value > min ? () => onChanged(value - 1) : null),
      SizedBox(
        width: compact ? 34 : 52,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: compact ? 16 : 22, fontWeight: FontWeight.w800, color: t.text)),
      ),
      button(Icons.add_rounded, value < 99 ? () => onChanged(value + 1) : null),
    ]);
  }
}
