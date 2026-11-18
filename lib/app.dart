import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:prism_ui/icons/icons.dart' as pi;
import 'package:prism_ui/prism_ui.dart' as p;
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/prism/app_glyphs.dart';
import 'ui/prism/prism_l10n.dart';
import 'ui/prism/prism_login_page.dart';
import 'ui/prism/prism_shell.dart';
import 'ui/prism/prism_theme.dart';

/// FlClash-style app root. Everything visible is drawn by prism_ui; the app
/// no longer depends on Material widgets for its pages.
class QuotaRoomApp extends StatelessWidget {
  const QuotaRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final themeMode = switch (state.themeMode) {
      'light' => p.ThemeMode.light,
      'dark' => p.ThemeMode.dark,
      _ => p.ThemeMode.system,
    };
    return p.PrismApp(
      title: 'QuotaRoom',
      debugShowCheckedModeBanner: false,
      theme: buildPrismTheme(Brightness.light),
      darkTheme: buildPrismTheme(
        Brightness.dark,
        amoled: state.settings.amoled,
      ),
      themeMode: themeMode,
      locale: Locale(state.language == 'en' ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        AppPrismLocalizationsDelegate(),
        GlobalWidgetsLocalizations.delegate,
      ],
      liquidGlass: p.LiquidGlassQuality.standard,
      builder: (context, child) {
        final prismTheme = p.Theme.of(context);
        final brightness = prismTheme.brightness;
        final pageColor = p.SurfaceLevel.page.colorOf(prismTheme.colorScheme);
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return p.ViewScope(
              size: size,
              isMobile: size.width < 700,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: const Color(0x00000000),
                  statusBarIconBrightness: brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarColor: pageColor,
                  systemNavigationBarDividerColor: pageColor,
                  systemNavigationBarIconBrightness:
                      brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                  systemNavigationBarContrastEnforced: false,
                ),
                child: child!,
              ),
            );
          },
        );
      },
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final Widget page;
    final Object key;
    if (state.loading) {
      page = const _PrismSplashScreen();
      key = 'splash';
    } else if (state.initError != null) {
      page = _PrismInitErrorScreen(message: state.initError!);
      key = 'error';
    } else if (!state.hasLoggedInAccount) {
      page = const PrismLoginPage();
      key = 'login';
    } else {
      page = const PrismShell();
      key = 'shell';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(key), child: page),
    );
  }
}

class _PrismSplashScreen extends StatelessWidget {
  const _PrismSplashScreen();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return p.Surface(
      color: p.SurfaceLevel.page.colorOf(colors),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 68,
                height: 68,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'QuotaRoom',
              style: p.AppTextStyle.title3
                  .of(context)
                  .copyWith(color: colors.onSurface, letterSpacing: -0.3),
            ),
            const SizedBox(height: 18),
            p.ActivityIndicator(size: 22, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _PrismInitErrorScreen extends StatelessWidget {
  const _PrismInitErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final state = context.read<AppState>();
    return p.Surface(
      color: p.SurfaceLevel.page.colorOf(colors),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: p.Card(
            radius: p.AppCorner.xl,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                pi.GlyphIcon(AppGlyphs.warning, size: 34, color: colors.error),
                const SizedBox(height: 12),
                Text(
                  'QuotaRoom',
                  style: p.AppTextStyle.title2
                      .of(context, emphasized: true)
                      .copyWith(color: colors.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: p.AppTextStyle.footnote
                      .of(context)
                      .copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                p.FilledButton(
                  onPressed: () => state.init(),
                  child: Text(state.l10n.t('retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FatalErrorApp extends StatelessWidget {
  const FatalErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = buildPrismTheme(Brightness.light);
    return p.PrismApp(
      title: 'QuotaRoom',
      debugShowCheckedModeBanner: false,
      theme: theme,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        AppPrismLocalizationsDelegate(),
        GlobalWidgetsLocalizations.delegate,
      ],
      home: p.Surface(
        color: p.SurfaceLevel.page.colorOf(theme.colorScheme),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: p.Card(
              radius: p.AppCorner.xl,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pi.GlyphIcon(
                    AppGlyphs.warning,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'QuotaRoom failed to start',
                    style: p.AppTextStyle.title2
                        .of(context, emphasized: true)
                        .copyWith(color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: p.AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
