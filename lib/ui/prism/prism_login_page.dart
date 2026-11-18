import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../data/account_repository.dart';
import '../../data/opencode_api.dart';
import '../../state/app_state.dart';
import '../login/login_webview_page.dart';
import '../widgets/dialogs.dart';
import 'app_glyphs.dart';
import 'paste_cookie_sheet.dart';
import 'prism_route.dart';

/// FlClash-style login: a tinted card floating over the page surface.
class PrismLoginPage extends StatefulWidget {
  const PrismLoginPage({super.key, this.asRoute = false, this.relogin = false});

  final bool asRoute;
  final bool relogin;

  @override
  State<PrismLoginPage> createState() => _PrismLoginPageState();
}

class _PrismLoginPageState extends State<PrismLoginPage> {
  bool _busy = false;
  bool _lastAuthFailure = false;

  Future<void> _openWebLogin() async {
    final token = await Navigator.of(context).push<String>(
      prismPageRoute<String>(builder: (_) => const LoginWebViewPage()),
    );
    if (token == null || !mounted) return;
    await _finishLogin(token);
  }

  Future<void> _openBrowserLogin() async {
    final l10n = context.read<AppState>().l10n;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(OpenCodeApi.loginUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      BannerHost.maybeOf(context)
          ?.show(l10n.t('desktopOpenBrowserFailed'), level: BannerLevel.error);
      return;
    }
    await _openPasteCookie();
  }

  Future<void> _openPasteCookie() async {
    final state = context.read<AppState>();
    var initial = '';
    String? error;
    while (mounted) {
      final token = await showPasteCookieSheet(
        context,
        state.l10n,
        initialText: initial,
        errorText: error,
      );
      if (token == null || !mounted) return;
      final ok = await _finishLogin(token);
      if (ok || !mounted || !_lastAuthFailure) return;
      // Keep the invalid cookie in the field instead of discarding what the
      // user pasted and forcing them to copy it again.
      initial = token;
      error = state.l10n.t('pasteCookieInvalid');
    }
  }

  Future<bool> _finishLogin(String token) async {
    final state = context.read<AppState>();
    _lastAuthFailure = false;
    setState(() => _busy = true);
    try {
      if (widget.relogin) {
        await state.reloginActiveWithToken(token);
      } else {
        await state.addAccountWithToken(token);
      }
      if (!mounted) return true;
      _afterLoginSuccess(state);
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (e is WorkspaceChangedException && widget.relogin) {
        final add = await showConfirmDialog(
          context,
          title: state.l10n.t('workspaceChangedTitle'),
          message: state.l10n.t('workspaceChangedBody', {
            'current': e.currentWorkspaceId,
            'next': e.nextWorkspaceId,
          }),
          cancelLabel: state.l10n.t('cancel'),
          confirmLabel: state.l10n.t('workspaceAsNewAccount'),
        );
        if (!add || !mounted) return false;
        try {
          await state.addAccountWithToken(token);
          if (!mounted) return true;
          _afterLoginSuccess(state);
          return true;
        } catch (e2) {
          if (!mounted) return false;
          BannerHost.maybeOf(context)?.show(
            '${state.l10n.t('loginFailed')}: $e2',
            level: BannerLevel.error,
          );
          return false;
        }
      }
      _lastAuthFailure = e is AuthException;
      BannerHost.maybeOf(
        context,
      )?.show('${state.l10n.t('loginFailed')}: $e', level: BannerLevel.error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _afterLoginSuccess(AppState state) {
    if (!mounted) return;
    if (widget.asRoute) {
      Navigator.of(context).pop();
    } else {
      BannerHost.maybeOf(context)
          ?.show(state.l10n.t('loginSuccess'), level: BannerLevel.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colorScheme = context.colorScheme;
    final mobile = ViewScope.isMobileOf(context);
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(
        radius: AppCorner.xl,
        padding: EdgeInsets.fromLTRB(
          mobile ? 22 : 28,
          mobile ? 24 : 30,
          mobile ? 22 : 28,
          mobile ? 22 : 28,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  semanticLabel: 'QuotaRoom',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'QuotaRoom',
              textAlign: TextAlign.center,
              style: AppTextStyle.title3
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.primary),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.t('slogan'),
              textAlign: TextAlign.center,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            Text(
              widget.relogin ? l10n.t('relogin') : l10n.t('loginTitle'),
              textAlign: TextAlign.center,
              style: AppTextStyle.pageTitle
                  .of(context)
                  .copyWith(color: colorScheme.onSurface, letterSpacing: -0.4),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('welcomeDesc'),
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _FeatureRow(glyph: AppGlyphs.speed, text: l10n.t('welcomeFeat1')),
            const SizedBox(height: 10),
            _FeatureRow(
              glyph: AppGlyphs.dataUsage,
              text: l10n.t('welcomeFeat2'),
            ),
            const SizedBox(height: 10),
            _FeatureRow(glyph: AppGlyphs.lock, text: l10n.t('welcomeFeat3')),
            const SizedBox(height: 24),
            if (isDesktop) ...[
              FilledButton(
                onPressed: _busy ? null : _openBrowserLogin,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GlyphIcon(AppGlyphs.openExternal, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.t('desktopLoginBtn')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _openPasteCookie,
                child: Text(l10n.t('pasteCookie')),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.t('desktopLoginNote'),
                textAlign: TextAlign.center,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ] else ...[
              FilledButton(
                onPressed: _busy ? null : _openWebLogin,
                child: Text(l10n.t('loginBtn')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _openPasteCookie,
                child: Text(l10n.t('pasteCookie')),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.t('loginNote'),
                textAlign: TextAlign.center,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );

    final body = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.8),
                radius: 1.4,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.16),
                  SurfaceLevel.page.colorOf(colorScheme),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Center(child: card),
          ),
        ),
        // Settings (and its language switch) is unreachable before login, so
        // expose a direct toggle here for first-run and expired-session users.
        Positioned(
          top: 6,
          right: 10,
          child: SafeArea(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () =>
                        state.setLanguage(state.language == 'en' ? 'zh' : 'en'),
              child: Text(state.language == 'en' ? '中文' : 'English'),
            ),
          ),
        ),
        if (_busy) ...[
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
          Center(
            child: Card(
              radius: AppCorner.lg,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ActivityIndicator(size: 26, color: colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    l10n.t('loginLoading'),
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.asRoute) {
      return PrismScaffold(
        bar: ScaffoldBar(
          isCompact: false,
          listenable: const AlwaysStoppedAnimation<double>(0),
          loading: const AlwaysStoppedAnimation<bool>(false),
          builder: (context) => ColoredBox(
            color: SurfaceLevel.page.colorOf(context.colorScheme),
            child: AppBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(AppGlyphs.chevronBack),
                tooltip: l10n.t('back'),
              ),
              title: Text(
                widget.relogin ? l10n.t('relogin') : l10n.t('loginTitle'),
              ),
            ),
          ),
        ),
        body: body,
      );
    }
    return Surface(color: SurfaceLevel.page.colorOf(colorScheme), child: body);
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.glyph, required this.text});

  final Glyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: ShapeDecoration(
            color: colorScheme.primaryContainer,
            shape: AppShape.all(AppCorner.sm),
          ),
          child: Center(
            child: GlyphIcon(
              glyph,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
