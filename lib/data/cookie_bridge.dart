import 'package:flutter/services.dart';

/// Reads cookies from Android's `android.webkit.CookieManager`.
///
/// Flutter WebView plugins cannot see HttpOnly cookies; opencode.ai's session
/// cookie (`__Host-console_session`) is HttpOnly, so we go through the native
/// `getCookie(url, includeHttpOnly = true)` API.
class CookieBridge {
  static const MethodChannel _channel = MethodChannel(
    'quotaroom/cookie_bridge',
  );

  static Future<String?> getCookieHeader(String url) async {
    try {
      return await _channel.invokeMethod<String>('getCookie', {
        'url': url,
        'includeHttpOnly': true,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> clearCookies() async {
    try {
      await _channel.invokeMethod<bool>('clearCookies');
    } on MissingPluginException {
      // Desktop/test runner: nothing to clear.
    } on PlatformException {
      // Best effort; the login page still works with a fresh WebView.
    }
  }
}
