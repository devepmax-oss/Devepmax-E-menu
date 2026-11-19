import 'package:flutter/material.dart';
import '../utils/image_utils.dart';

class AppNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = proxifyImageUrl(imageUrl);

    Widget child;

    if (resolved.isEmpty) {
      child = _fallback();
    } else {
      child = Image.network(
        resolved,
        width: width,
        height: height,
        fit: fit,

        // 🔥 MUY IMPORTANTE para evitar bloqueos 403
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },

        errorBuilder: (context, error, stackTrace) {
          debugPrint('IMAGE ERROR URL => $resolved');
          debugPrint('IMAGE ERROR => $error');
          return _fallback();
        },

        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;

          return Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }

    return child;
  }

  Widget _fallback() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}