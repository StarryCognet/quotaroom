import 'package:flutter/foundation.dart';

/// Platform capabilities shared by the Android and desktop builds.
///
/// The app ships one Flutter codebase: Android keeps the native WebView login,
/// WorkManager sync, home-screen widget and quick actions, while desktop uses
/// browser + cookie login and FFI SQLite.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Embedded opencode.ai login relies on Android's WebView cookie bridge.
bool get supportsEmbeddedWebLogin => isAndroid;

/// WorkManager, home-screen widgets and launcher quick actions are Android-only.
bool get supportsAndroidIntegrations => isAndroid;

/// Local notifications are implemented for Android, Windows, macOS and Linux
/// (Linux requires a running notification daemon).
bool get supportsLocalNotifications =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Current platform name used in the about/settings pages.
String get platformLabel {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}
