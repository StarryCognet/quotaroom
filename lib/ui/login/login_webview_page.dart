import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/cookie_bridge.dart';
import '../../data/opencode_api.dart';
import '../../state/app_state.dart';
import 'paste_cookie_sheet.dart';

/// Hosts opencode.ai's console login inside a WebView and captures the
/// HttpOnly `__Host-console_session` cookie through the native bridge.
class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  late final WebViewController _controller;
  double _progress = 0;
  bool _capturing = false;
  bool _captured = false;
  Timer? _cookiePoll;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_mobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value / 100);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() => _error = null);
          },
          onPageFinished: _onPageFinished,
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame != true) return;
            setState(() => _error = error.description);
          },
        ),
      );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await CookieBridge.clearCookies();
    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(OpenCodeApi.loginUrl));
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _onPageFinished(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'opencode.ai') return;
    // The console may finish login via client-side routing / XHR, where
    // onPageFinished does not fire again. Poll the cookie jar for a while.
    _startCookiePolling();
    await _tryCapture(delay: true);
  }

  void _startCookiePolling() {
    if (_cookiePoll?.isActive ?? false) return;
    var ticks = 0;
    _cookiePoll = Timer.periodic(const Duration(seconds: 1), (timer) async {
      ticks++;
      if (!mounted || _captured || ticks > 120) {
        timer.cancel();
        return;
      }
      await _tryCapture();
    });
  }

  Future<void> _tryCapture({bool delay = false}) async {
    if (_capturing || _captured) return;
    _capturing = true;
    try {
      if (delay) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      final header = await CookieBridge.getCookieHeader('https://opencode.ai');
      final token = OpenCodeApi.extractSessionCookie(header);
      if (token != null && token.isNotEmpty) {
        _captured = true;
        _cookiePoll?.cancel();
        if (mounted) Navigator.of(context).pop(token);
      }
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _cookiePoll?.cancel();
    super.dispose();
  }

  Future<void> _pasteInstead() async {
    final state = context.read<AppState>();
    final token = await showPasteCookieSheet(context, state.l10n);
    if (token != null && mounted) Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    final colors = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('loginTitle'), style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: l10n.t('pasteCookie'),
            onPressed: _pasteInstead,
            icon: const Icon(Icons.keyboard_alt_outlined),
          ),
          IconButton(
            tooltip: l10n.t('refresh'),
            onPressed: () {
              setState(() => _error = null);
              _controller.reload();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.t('close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1 && _error == null)
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: colors.colorScheme.surfaceContainerHighest,
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (!_ready) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 38,
                              color: colors.colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _controller.reload();
                              },
                              child: Text(l10n.t('retry')),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _pasteInstead,
                              child: Text(l10n.t('pasteCookie')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.colorScheme.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      l10n.t('loginAutoNote'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
