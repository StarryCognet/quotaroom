import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../data/opencode_api.dart';
import '../../state/app_state.dart';
import '../widgets/app_logo.dart';
import 'login_webview_page.dart';
import 'paste_cookie_sheet.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.asRoute = false, this.relogin = false});

  /// When opened from Settings, show a back button and pop after success.
  final bool asRoute;

  /// Replace the active account's token instead of adding a new account.
  final bool relogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _openWebLogin() async {
    final token = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const LoginWebViewPage()));
    if (token == null || !mounted) return;
    await _finishLogin(token);
  }

  /// Desktop has no embedded WebView: open the console in the system browser,
  /// then let the user paste the session cookie straight from dev tools.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('desktopOpenBrowserFailed'))),
      );
      return;
    }
    await _openPasteCookie();
  }

  Future<void> _openPasteCookie() async {
    final state = context.read<AppState>();
    final token = await showPasteCookieSheet(context, state.l10n);
    if (token == null || !mounted) return;
    await _finishLogin(token);
  }

  Future<void> _finishLogin(String token) async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (widget.relogin) {
        await state.reloginActiveWithToken(token);
      } else {
        await state.addAccountWithToken(token);
      }
      if (!mounted) return;
      if (widget.asRoute) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.l10n.t('loginSuccess'))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${state.l10n.t('loginFailed')}: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final desktop = isDesktop;
    return Scaffold(
      appBar: widget.asRoute
          ? AppBar(
              title: Text(
                widget.relogin ? l10n.t('relogin') : l10n.t('loginTitle'),
              ),
            )
          : null,
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary.withValues(alpha: colors.isDark ? 0.20 : 0.14),
                  colors.bg,
                  colors.blue.withValues(alpha: colors.isDark ? 0.10 : 0.08),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: AppLogo(size: 76)),
                        const SizedBox(height: 12),
                        Text(
                          'QuotaRoom',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          l10n.t('slogan'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: colors.text3,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          l10n.t('loginTitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.t('welcomeDesc'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.75,
                            color: colors.text2,
                          ),
                        ),
                        const SizedBox(height: 26),
                        _FeatureRow(
                          icon: Icons.speed_rounded,
                          text: l10n.t('welcomeFeat1'),
                        ),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: Icons.query_stats_rounded,
                          text: l10n.t('welcomeFeat2'),
                        ),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: Icons.lock_outline_rounded,
                          text: l10n.t('welcomeFeat3'),
                        ),
                        const SizedBox(height: 30),
                        if (desktop) ...[
                          FilledButton.icon(
                            onPressed: _busy ? null : _openBrowserLogin,
                            icon: const Icon(
                              Icons.open_in_browser_rounded,
                              size: 19,
                            ),
                            label: Text(l10n.t('desktopLoginBtn')),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _openPasteCookie,
                            icon: const Icon(
                              Icons.keyboard_alt_outlined,
                              size: 18,
                            ),
                            label: Text(l10n.t('pasteCookie')),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.t('desktopLoginNote'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.6,
                              color: colors.text3,
                            ),
                          ),
                        ] else ...[
                          FilledButton.icon(
                            onPressed: _busy ? null : _openWebLogin,
                            icon: const Icon(Icons.login_rounded, size: 19),
                            label: Text(l10n.t('loginBtn')),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _busy ? null : _openPasteCookie,
                            child: Text(l10n.t('pasteCookie')),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.t('loginNote'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.6,
                              color: colors.text3,
                            ),
                          ),
                        ],
                        if (media.padding.bottom > 0) const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_busy) ...[
            const ModalBarrier(dismissible: false, color: Color(0x66000000)),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: cardShadowFor(colors),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.t('loginLoading'),
                      style: TextStyle(fontSize: 13, color: colors.text2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, height: 1.5, color: colors.text2),
          ),
        ),
      ],
    );
  }
}
