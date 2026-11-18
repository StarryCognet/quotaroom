import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/desktop_shell.dart';
import '../../core/i18n.dart';
import '../../core/platform.dart';
import '../../data/apk_installer.dart';
import '../../data/update_service.dart';
import '../../state/app_state.dart';
import '../prism/app_glyphs.dart';
import 'confetti.dart';

/// Shows the update announcement in a prism_ui card. The dialog doubles as a
/// downloader on Android and as a release link on desktop.
Future<void> showUpdateDialog(
  BuildContext context, {
  required AppState state,
  required UpdateInfo info,
}) {
  return showFloatingDialog<void>(
    context: context,
    dismissible: false,
    child: _UpdateDialog(state: state, info: info),
  );
}

enum _UpdatePhase {
  idle,
  downloading,
  permission,
  installing,
  installFailed,
  done,
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.state, required this.info});

  final AppState state;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String? _error;
  File? _file;
  bool _showConfetti = false;
  Animation<double>? _routeAnimation;

  bool get _busy =>
      _phase == _UpdatePhase.downloading || _phase == _UpdatePhase.installing;

  /// Android installs the APK in-app; Windows downloads the verified Inno
  /// Setup installer and runs it silently.
  bool get _canInstall => ApkInstaller.isSupported && widget.info.hasApk;

  bool get _windowsInstaller => isWindows && widget.info.hasWindowsInstaller;

  int get _sizeBytes {
    if (_canInstall) return widget.info.apkSize;
    if (_windowsInstaller) return widget.info.windowsSetupSize;
    if (isWindows && widget.info.hasWindowsPackage) {
      return widget.info.windowsSize;
    }
    return 0;
  }

  String get _downloadUrl {
    final info = widget.info;
    if (isWindows && info.hasWindowsPackage) return info.windowsUrl!;
    if (info.releaseUrl.isNotEmpty) return info.releaseUrl;
    return info.apkUrl ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation;
    _routeAnimation?.addStatusListener(_onRouteStatus);
    if (animation?.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startConfetti());
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _startConfetti();
  }

  void _startConfetti() {
    if (!mounted || _showConfetti) return;
    setState(() => _showConfetti = true);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  Future<void> _later() async {
    await widget.state.dismissUpdate(widget.info.latest);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _primaryAction() async {
    if (_windowsInstaller) {
      await _downloadAndInstallWindows();
      return;
    }
    if (!_canInstall) {
      final url = _downloadUrl;
      if (url.isEmpty) {
        setState(() => _error = widget.state.l10n.t('updateNotesEmpty'));
        return;
      }
      try {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        if (!opened) {
          setState(() => _error = widget.state.l10n.t('openFailed'));
          return;
        }
        await widget.state.dismissUpdate(widget.info.latest);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      }
      return;
    }
    await _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _received = 0;
      _total = widget.info.apkSize;
      _error = null;
    });
    try {
      final file = await widget.state.updateService.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            if (total > 0) _progress = received / total;
          });
        },
      );
      if (!mounted) return;
      _file = file;
      await _launchInstaller();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.idle;
        _error = e.toString();
      });
    }
  }

  Future<void> _downloadAndInstallWindows() async {
    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = 0;
      _received = 0;
      _total = widget.info.windowsSetupSize;
      _error = null;
    });
    try {
      final file = await widget.state.updateService.downloadWindowsSetup(
        widget.info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
            if (total > 0) _progress = received / total;
          });
        },
      );
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.installing);
      await UpdateService.runWindowsInstaller(file);
      await widget.state.dismissUpdate(widget.info.latest);
      if (mounted) await DesktopShell.instance.quit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.installFailed;
        _error = e.toString();
      });
    }
  }

  Future<void> _launchInstaller() async {
    final file = _file;
    if (file == null) {
      await _downloadAndInstall();
      return;
    }
    if (!await ApkInstaller.canInstall()) {
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.permission);
      return;
    }
    setState(() {
      _phase = _UpdatePhase.installing;
      _error = null;
    });
    try {
      await ApkInstaller.install(file.path);
      if (!mounted) return;
      setState(() => _phase = _UpdatePhase.done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.installFailed;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.state.l10n;
    final scheme = context.colorScheme;
    final info = widget.info;
    final notes = info.notes.isEmpty ? l10n.t('updateNotesEmpty') : info.notes;
    final sizeLabel = _sizeBytes > 0
        ? l10n.t('updateApkSize', {
            'size': (_sizeBytes / (1024 * 1024)).toStringAsFixed(1),
          })
        : null;
    return PopScope(
      canPop: !_busy,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppCorner.xl),
            child: Container(
              decoration: ShapeDecoration(
                color: scheme.surface,
                shape: AppShape.all(AppCorner.xl),
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(
                        latest: info.latest,
                        current: info.current,
                        sizeLabel: sizeLabel,
                        title: l10n.t('updateFound'),
                        currentLabel: l10n.t('currentVersion'),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.t('updateAvailableBody'),
                                style: AppTextStyle.footnote
                                    .of(context)
                                    .copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                              ),
                              if (!_canInstall &&
                                  isWindows &&
                                  info.hasWindowsPackage) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l10n.t(
                                    info.hasWindowsInstaller
                                        ? 'updateWindowsHint'
                                        : 'updateWindowsManualHint',
                                  ),
                                  style: AppTextStyle.caption2
                                      .of(context)
                                      .copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.5,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                l10n.t('releaseNotes'),
                                style: AppTextStyle.caption1
                                    .of(context, emphasized: true)
                                    .copyWith(color: scheme.onSurface),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 210,
                                ),
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: ShapeDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  shape: AppShape.all(AppCorner.md),
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    notes,
                                    style: AppTextStyle.caption2
                                        .of(context)
                                        .copyWith(
                                          color: scheme.onSurfaceVariant,
                                          height: 1.65,
                                        ),
                                  ),
                                ),
                              ),
                              if (_phase == _UpdatePhase.downloading) ...[
                                const SizedBox(height: 16),
                                LinearProgressIndicator(
                                  value: _total > 0 ? _progress : null,
                                  minHeight: 7,
                                ),
                                const SizedBox(height: 7),
                                Row(
                                  children: [
                                    Text(
                                      l10n.t('updateDownloading', {
                                        'pct': (_progress * 100).round(),
                                      }),
                                      style: AppTextStyle.caption2
                                          .of(context)
                                          .copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const Spacer(),
                                    if (_total > 0)
                                      Text(
                                        '${_mb(_received)} / ${_mb(_total)}',
                                        style: AppTextStyle.caption2
                                            .of(context)
                                            .copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                              if (_phase == _UpdatePhase.permission) ...[
                                const SizedBox(height: 14),
                                _PermissionNotice(
                                  title: l10n.t('updatePermissionTitle'),
                                  body: l10n.t('updatePermissionBody'),
                                  scheme: scheme,
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${l10n.t(_phase == _UpdatePhase.installFailed ? 'updateInstallFailed' : 'updateDownloadFailed')}: $_error',
                                  style: AppTextStyle.caption2
                                      .of(context)
                                      .copyWith(
                                        color: scheme.error,
                                        height: 1.4,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                        child: _actions(context, l10n),
                      ),
                    ],
                  ),
                  if (_showConfetti)
                    const Positioned.fill(child: ConfettiBurst()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, L10n l10n) {
    if (_phase == _UpdatePhase.downloading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: null,
            child: Text(
              l10n.t('updateDownloading', {'pct': (_progress * 100).round()}),
            ),
          ),
        ],
      );
    }
    if (_phase == _UpdatePhase.installing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: null, child: Text(l10n.t('updateInstalling'))),
        ],
      );
    }
    if (_phase == _UpdatePhase.permission ||
        _phase == _UpdatePhase.installFailed) {
      return OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('updateLater')),
          ),
          if (_phase == _UpdatePhase.permission)
            TextButton(
              onPressed: () async {
                try {
                  await ApkInstaller.openInstallPermissionSettings();
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _error = e.toString());
                }
              },
              child: Text(l10n.t('openInstallSettings')),
            ),
          FilledButton(
            onPressed: _launchInstaller,
            child: Text(l10n.t('retryInstall')),
          ),
        ],
      );
    }
    if (_phase == _UpdatePhase.done) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('close')),
          ),
        ],
      );
    }
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      spacing: 8,
      children: [
        TextButton(onPressed: _later, child: Text(l10n.t('updateLater'))),
        FilledButton.icon(
          onPressed: _primaryAction,
          icon: GlyphIcon(
            _canInstall || _windowsInstaller
                ? AppGlyphs.cloudDownload
                : AppGlyphs.openExternal,
            size: 17,
          ),
          label: Text(
            _canInstall || _windowsInstaller
                ? l10n.t('updateNow')
                : l10n.t('goDownload'),
          ),
        ),
      ],
    );
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.latest,
    required this.current,
    required this.sizeLabel,
    required this.title,
    required this.currentLabel,
  });

  final String latest;
  final String current;
  final String? sizeLabel;
  final String title;
  final String currentLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7B5CFF), Color(0xFF5B8CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: GlyphIcon(
                AppGlyphs.cloudDownload,
                color: Color(0xFFFFFFFF),
                size: 25,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.title2
                      .of(context, emphasized: true)
                      .copyWith(color: const Color(0xFFFFFFFF)),
                ),
                const SizedBox(height: 3),
                Text(
                  '$latest · $currentLabel $current'
                  '${sizeLabel == null ? '' : ' · $sizeLabel'}',
                  maxLines: 2,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.82),
                        height: 1.4,
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

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({
    required this.title,
    required this.body,
    required this.scheme,
  });

  final String title;
  final String body;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        shape: AppShape.all(AppCorner.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlyphIcon(AppGlyphs.info, size: 17, color: scheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
