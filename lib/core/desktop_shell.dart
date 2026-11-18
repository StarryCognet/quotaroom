// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';
import 'package:window_manager/window_manager.dart' as native_window;

import 'platform.dart';

/// Native desktop shell: window state, tray, close-to-tray and autostart.
///
/// Kept outside AppState so the app remains usable on Android and so the
/// window manager can be initialized before the first Flutter frame.
class DesktopShell with WindowListener, TrayListener {
  DesktopShell._();

  static final DesktopShell instance = DesktopShell._();

  static const _boundsKey = 'quotaroom_window_bounds';
  static const _closeToTrayKey = 'quotaroom_close_to_tray';
  static const _launchAtStartupKey = 'quotaroom_launch_at_startup';
  static const _registryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _runValue = 'QuotaRoom';
  static const _macPlist =
      'Library/LaunchAgents/com.starrycognet.quotaroom.plist';
  static const _linuxDesktop = '.config/autostart/quotaroom.desktop';

  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _closeToTray = true;
  bool _quitting = false;
  bool _handlingClose = false;
  bool _startHidden = false;
  Timer? _boundsTimer;
  Future<void> Function()? _onSync;
  String Function()? _language;

  bool get available => isDesktop && !kIsWeb;
  bool get closeToTray => _closeToTray;
  bool get startedHidden => _startHidden;

  Future<void> initialize() async {
    if (!available || _initialized) return;
    _initialized = true;
    _prefs = await SharedPreferences.getInstance();
    _closeToTray = _prefs?.getBool(_closeToTrayKey) ?? true;
    _startHidden =
        Platform.environment['QUOTAROOM_START_HIDDEN'] == '1' ||
        Platform.executableArguments.contains('--hidden') ||
        Platform.executableArguments.contains('-hidden');

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 860),
        minimumSize: Size(900, 620),
        center: true,
        title: 'QuotaRoom',
        backgroundColor: Color(0x00000000),
      ),
    );
    // nativeapi only exposes the current window after the first frame. Wire
    // the close handler and restore bounds once it is definitely available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_wireWindow());
    });
  }

  Future<void> _wireWindow() async {
    native_window.Window? window;
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        window = native_window.WindowManager.instance.getCurrent();
        if (window != null) break;
      } catch (_) {
        // The engine may still be bringing the view up.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (window != null) {
      window.addListener((event) {
        if (event is! native_window.WindowCloseRequestedEvent) return;
        if (_quitting) return;
        // Cancel the native close and decide whether to hide or quit. The
        // legacy listener is kept below for window move/resize events.
        event.request.cancel();
        unawaited(_handleCloseRequest());
      });
    }
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _restoreAndShow();
  }

  Future<void> _handleCloseRequest() async {
    if (_handlingClose || _quitting) return;
    _handlingClose = true;
    try {
      if (_closeToTray) {
        await _saveBounds();
        await windowManager.hide();
      } else {
        _quitting = true;
        await _saveBounds();
        await windowManager.destroy();
      }
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _restoreAndShow() async {
    try {
      final raw = _prefs?.getStringList(_boundsKey);
      if (raw != null && raw.length == 4) {
        final values = raw.map(double.tryParse).toList();
        if (values.every((value) => value != null)) {
          final rect = Rect.fromLTWH(
            values[0]!,
            values[1]!,
            values[2]!,
            values[3]!,
          );
          if (rect.width >= 900 && rect.height >= 620) {
            await windowManager.setBounds(rect);
          }
        }
      }
    } catch (_) {
      // A stale or off-screen rectangle must never prevent startup.
    }
    if (_startHidden) {
      await windowManager.hide();
      return;
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Called after AppState is ready. The callbacks avoid importing AppState
  /// from this low-level shell (which would create a cycle).
  Future<void> attach({
    required Future<void> Function() onSync,
    required String Function() language,
  }) async {
    if (!available) return;
    _onSync = onSync;
    _language = language;
    trayManager.addListener(this);
    await _configureTray();
  }

  Future<void> _configureTray() async {
    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/icon/tray_icon.ico'
            : 'assets/icon/tray_icon.png',
      );
      await trayManager.setToolTip('QuotaRoom');
      final zh = (_language?.call() ?? 'zh') != 'en';
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(
              key: 'show',
              label: zh ? '打开 QuotaRoom' : 'Open QuotaRoom',
              onClick: (_) => unawaited(showWindow()),
            ),
            MenuItem(
              key: 'sync',
              label: zh ? '立即同步' : 'Sync now',
              onClick: (_) => unawaited(_onSync?.call() ?? Future.value()),
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit',
              label: zh ? '退出' : 'Quit',
              onClick: (_) => unawaited(quit()),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('QuotaRoom tray initialization failed: $e');
    }
  }

  Future<void> refreshTray() async {
    if (!available || !_initialized) return;
    await _configureTray();
  }

  Future<void> showWindow() async {
    if (!available) return;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!available) return;
    await _saveBounds();
    await windowManager.hide();
  }

  Future<void> quit() async {
    if (!available) return;
    _quitting = true;
    await _saveBounds();
    await trayManager.destroy();
    await windowManager.destroy();
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    await _prefs?.setBool(_closeToTrayKey, value);
  }

  Future<bool> isLaunchAtStartupEnabled() async {
    if (!available) return false;
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'QUERY',
          _registryKey,
          '/v',
          _runValue,
        ]);
        return result.exitCode == 0 &&
            result.stdout.toString().contains(_runValue);
      } catch (_) {
        return false;
      }
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      return File('$home/$_macPlist').exists();
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      return File('$home/$_linuxDesktop').exists();
    }
    return false;
  }

  Future<bool> setLaunchAtStartup(bool enabled) async {
    if (!available) return false;
    final exe = Platform.resolvedExecutable;
    if (Platform.isWindows) {
      try {
        final result = enabled
            ? await Process.run('reg', [
                'ADD',
                _registryKey,
                '/v',
                _runValue,
                '/t',
                'REG_SZ',
                '/d',
                '"$exe" --hidden',
                '/f',
              ])
            : await Process.run('reg', [
                'DELETE',
                _registryKey,
                '/v',
                _runValue,
                '/f',
              ]);
        final ok = enabled
            ? result.exitCode == 0
            : result.exitCode == 0 ||
                  result.stderr.toString().contains('unable to find');
        if (ok) await _prefs?.setBool(_launchAtStartupKey, enabled);
        return ok;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final file = Platform.isMacOS
          ? File('$home/$_macPlist')
          : File('$home/$_linuxDesktop');
      if (enabled) {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          Platform.isMacOS
              ? _macPlistContents(exe)
              : _linuxDesktopContents(exe),
        );
      } else if (await file.exists()) {
        await file.delete();
      }
      await _prefs?.setBool(_launchAtStartupKey, enabled);
      return true;
    }
    return false;
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _macPlistContents(String exe) {
    final escaped = _xmlEscape(exe);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.starrycognet.quotaroom</string>
  <key>ProgramArguments</key>
  <array><string>$escaped</string><string>--hidden</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''';
  }

  String _linuxDesktopContents(String exe) =>
      '''[Desktop Entry]
Type=Application
Name=QuotaRoom
Comment=OpenCode quota and usage monitor
Exec="$exe" --hidden
Terminal=false
X-GNOME-Autostart-enabled=true
''';

  Future<void> _saveBounds() async {
    if (!available) return;
    try {
      final maximized = await windowManager.isMaximized();
      final minimized = await windowManager.isMinimized();
      if (maximized || minimized) return;
      final bounds = await windowManager.getBounds();
      await _prefs?.setStringList(_boundsKey, [
        bounds.left.toString(),
        bounds.top.toString(),
        bounds.width.toString(),
        bounds.height.toString(),
      ]);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  void _scheduleSaveBounds() {
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveBounds());
    });
  }

  @override
  void onWindowClose() {
    unawaited(_handleCloseRequest());
  }

  @override
  void onWindowMove() => _scheduleSaveBounds();

  @override
  void onWindowResize() => _scheduleSaveBounds();

  @override
  void onTrayIconMouseDown() => unawaited(showWindow());
}
