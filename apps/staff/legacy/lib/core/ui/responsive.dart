import 'package:flutter/widgets.dart';

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compactTablet = 900;
  static const double regularTablet = 1200;
}

class AppResponsive {
  const AppResponsive._();

  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).width < AppBreakpoints.compactTablet;
  }

  static bool isRegular(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppBreakpoints.compactTablet && width < AppBreakpoints.regularTablet;
  }

  static bool isLarge(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AppBreakpoints.regularTablet;
  }

  static double value(
    BuildContext context, {
    required double compact,
    required double regular,
    required double large,
  }) {
    if (isCompact(context)) return compact;
    if (isRegular(context)) return regular;
    return large;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final size = value(context, compact: 12, regular: 16, large: 20);
    return EdgeInsets.all(size);
  }
}
