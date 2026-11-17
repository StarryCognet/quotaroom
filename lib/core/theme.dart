import 'package:flutter/material.dart';

/// Palette mirrored from the desktop app's `app/web/style.css`.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.card,
    required this.border,
    required this.text,
    required this.text2,
    required this.text3,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.blue,
    required this.green,
    required this.purple,
    required this.cyan,
    required this.amber,
    required this.red,
    required this.dangerSoft,
    required this.muted,
    required this.hover,
    required this.grid,
    required this.sidebar,
    required this.titlebar,
    required this.isDark,
  });

  final Color bg;
  final Color card;
  final Color border;
  final Color text;
  final Color text2;
  final Color text3;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color blue;
  final Color green;
  final Color purple;
  final Color cyan;
  final Color amber;
  final Color red;
  final Color dangerSoft;
  final Color muted;
  final Color hover;
  final Color grid;
  final Color sidebar;
  final Color titlebar;
  final bool isDark;

  static const light = AppColors(
    bg: Color(0xFFF7F6F4),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFEAE7F2),
    text: Color(0xFF221F33),
    text2: Color(0xFF5F5B73),
    text3: Color(0xFF7C7690),
    primary: Color(0xFF7C5CF6),
    primaryStrong: Color(0xFF6A46EA),
    primarySoft: Color(0xFFF2EEFE),
    blue: Color(0xFF4F8EF7),
    green: Color(0xFF22C55E),
    purple: Color(0xFFA78BFA),
    cyan: Color(0xFF06B6D4),
    amber: Color(0xFFD97706),
    red: Color(0xFFEF4444),
    dangerSoft: Color(0xFFFDF0F0),
    muted: Color(0xFFF1EFF6),
    hover: Color(0xFFF3F0FB),
    grid: Color(0xFFEFEDF5),
    sidebar: Color(0xFFFBFAF8),
    titlebar: Color(0xFFFFFFFF),
    isDark: false,
  );

  static const dark = AppColors(
    bg: Color(0xFF14121A),
    card: Color(0xFF1D1A26),
    border: Color(0xFF2E2A3D),
    text: Color(0xFFE9E6F5),
    text2: Color(0xFFA8A3C0),
    text3: Color(0xFF8C86A6),
    primary: Color(0xFF9D7CF8),
    primaryStrong: Color(0xFF8B6CF6),
    primarySoft: Color(0xFF272040),
    blue: Color(0xFF4F8EF7),
    green: Color(0xFF22C55E),
    purple: Color(0xFFA78BFA),
    cyan: Color(0xFF06B6D4),
    amber: Color(0xFFD97706),
    red: Color(0xFFEF4444),
    dangerSoft: Color(0xFF3D2429),
    muted: Color(0xFF232030),
    hover: Color(0xFF272040),
    grid: Color(0xFF29253A),
    sidebar: Color(0xFF181520),
    titlebar: Color(0xFF1D1A26),
    isDark: true,
  );

  static const amoled = AppColors(
    bg: Color(0xFF000000),
    card: Color(0xFF0B0B0E),
    border: Color(0xFF24222C),
    text: Color(0xFFE9E6F5),
    text2: Color(0xFFA8A3C0),
    text3: Color(0xFF8C86A6),
    primary: Color(0xFF9D7CF8),
    primaryStrong: Color(0xFF8B6CF6),
    primarySoft: Color(0xFF221C38),
    blue: Color(0xFF4F8EF7),
    green: Color(0xFF22C55E),
    purple: Color(0xFFA78BFA),
    cyan: Color(0xFF06B6D4),
    amber: Color(0xFFD97706),
    red: Color(0xFFEF4444),
    dangerSoft: Color(0xFF3D2429),
    muted: Color(0xFF15141A),
    hover: Color(0xFF1E1B26),
    grid: Color(0xFF24222C),
    sidebar: Color(0xFF050506),
    titlebar: Color(0xFF0B0B0E),
    isDark: true,
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? border,
    Color? text,
    Color? text2,
    Color? text3,
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? blue,
    Color? green,
    Color? purple,
    Color? cyan,
    Color? amber,
    Color? red,
    Color? dangerSoft,
    Color? muted,
    Color? hover,
    Color? grid,
    Color? sidebar,
    Color? titlebar,
    bool? isDark,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      border: border ?? this.border,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      primarySoft: primarySoft ?? this.primarySoft,
      blue: blue ?? this.blue,
      green: green ?? this.green,
      purple: purple ?? this.purple,
      cyan: cyan ?? this.cyan,
      amber: amber ?? this.amber,
      red: red ?? this.red,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      muted: muted ?? this.muted,
      hover: hover ?? this.hover,
      grid: grid ?? this.grid,
      sidebar: sidebar ?? this.sidebar,
      titlebar: titlebar ?? this.titlebar,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: mix(bg, other.bg),
      card: mix(card, other.card),
      border: mix(border, other.border),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      primary: mix(primary, other.primary),
      primaryStrong: mix(primaryStrong, other.primaryStrong),
      primarySoft: mix(primarySoft, other.primarySoft),
      blue: mix(blue, other.blue),
      green: mix(green, other.green),
      purple: mix(purple, other.purple),
      cyan: mix(cyan, other.cyan),
      amber: mix(amber, other.amber),
      red: mix(red, other.red),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      muted: mix(muted, other.muted),
      hover: mix(hover, other.hover),
      grid: mix(grid, other.grid),
      sidebar: mix(sidebar, other.sidebar),
      titlebar: mix(titlebar, other.titlebar),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;

  /// Monospace-ish tabular figures for all numeric cells.
  TextStyle get numStyle => const TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

const List<BoxShadow> cardShadowLight = [
  BoxShadow(color: Color(0x0D1E143C), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0F1E143C), blurRadius: 20, offset: Offset(0, 6)),
];

const List<BoxShadow> cardShadowDark = [
  BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, 6)),
];

List<BoxShadow> cardShadowFor(AppColors c) =>
    c.isDark ? cardShadowDark : cardShadowLight;

ThemeData buildAppTheme(Brightness brightness, {bool amoled = false}) {
  final c = brightness == Brightness.dark
      ? (amoled ? AppColors.amoled : AppColors.dark)
      : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.primary,
    brightness: brightness,
  ).copyWith(
    primary: c.primary,
    onPrimary: Colors.white,
    secondary: c.blue,
    surface: c.card,
    onSurface: c.text,
    error: c.red,
    outline: c.border,
    surfaceContainerHighest: c.muted,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    cardColor: c.card,
    dividerColor: c.border,
    disabledColor: c.text3,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          bodySmall: base.textTheme.bodySmall?.copyWith(color: c.text3),
          labelSmall: base.textTheme.labelSmall?.copyWith(color: c.text3),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.text,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primarySoft,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? c.primary : c.text3,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? c.primary : c.text3,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.muted,
      hintStyle: TextStyle(color: c.text3, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.primary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : c.text3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.primary : c.border,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.isDark ? c.card : const Color(0xFF2B2740),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        color: c.text,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: c.text2, fontSize: 13.5, height: 1.6),
    ),
    extensions: [c],
  );
}
