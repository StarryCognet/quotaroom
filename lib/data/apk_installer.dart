import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges APK installation to Android's PackageInstaller activity.
/// Android always shows a confirmation screen; truly silent installs require
/// device-owner/root privileges.
class ApkInstaller {
  static const MethodChannel _channel = MethodChannel(
    'quotaroom/cookie_bridge',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> canInstall() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstallApk') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openInstallPermissionSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<void> install(String path) async {
    if (!isSupported) {
      throw const ApkInstallException(
        'APK install is only available on Android',
      );
    }
    try {
      await _channel.invokeMethod<void>('installApk', {'path': path});
    } on PlatformException catch (e) {
      throw ApkInstallException(e.message ?? e.code);
    }
  }
}

class ApkInstallException implements Exception {
  const ApkInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
