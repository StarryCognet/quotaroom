import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart' as p;

/// QuotaRoom's brand seed. Prism derives every accent and surface role from it.
const Color prismSeedColor = Color(0xFF7C5CF6);

p.ThemeData buildPrismTheme(Brightness brightness, {bool amoled = false}) {
  var scheme = p.ColorScheme.fromSeed(
    seedColor: prismSeedColor,
    brightness: brightness,
    style: p.ColorStyle.tinted,
  );
  if (amoled && brightness == Brightness.dark) {
    scheme = scheme.copyWith(
      surface: const Color(0xFF000000),
      surfaceDim: const Color(0xFF000000),
      surfaceBright: const Color(0xFF17151C),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF08070A),
      surfaceContainer: const Color(0xFF0E0D12),
      surfaceContainerHigh: const Color(0xFF151319),
      surfaceContainerHighest: const Color(0xFF1D1A22),
    );
  }
  return p.ThemeData(
    colorScheme: scheme,
    platform: defaultTargetPlatform,
    elevatedColorScheme: brightness == Brightness.dark ? scheme.elevated : null,
  );
}
