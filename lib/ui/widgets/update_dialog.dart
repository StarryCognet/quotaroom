import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../data/apk_installer.dart';
import '../../data/update_service.dart';
import '../../state/app_state.dart';
import 'confetti.dart';

/// Shows the update announcement. The dialog doubles as a downloader: the
/// primary action fetches the release APK and then opens Android's installer.
Future<void> showUpdateDialog(
  BuildContext context, {
  required AppState state,
  required UpdateInfo info,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(state: state, info: info),
  );
}

enum _UpdatePhase { idle, downloading, permission, installing, done }

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
    if (!widget.info.hasApk) {
      if (widget.info.releaseUrl.isNotEmpty) {
        await launchUrl(
          Uri.parse(widget.info.releaseUrl),
          mode: LaunchMode.externalApplication,
        );
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
        _phase = _UpdatePhase.permission;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.state.l10n;
    final colors = Theme.of(context).colorScheme;
    final info = widget.info;
    final notes = info.notes.isEmpty ? l10n.t('updateNotesEmpty') : info.notes;
    final sizeLabel = info.apkSize > 0
        ? l10n.t('updateApkSize', {
            'size': (info.apkSize / (1024 * 1024)).toStringAsFixed(1),
          })
        : null;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('updateAvailableBody'),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.t('releaseNotes'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 210),
                            width: double.infinity,
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                notes,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.65,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          if (_phase == _UpdatePhase.downloading) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: _total > 0 ? _progress : null,
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Text(
                                  l10n.t('updateDownloading', {
                                    'pct': (_progress * 100).round(),
                                  }),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                if (_total > 0)
                                  Text(
                                    '${_mb(_received)} / ${_mb(_total)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.onSurfaceVariant,
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
                              colors: colors,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              '${l10n.t('updateDownloadFailed')}: $_error',
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: colors.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: _actions(context, l10n, colors),
                  ),
                ],
              ),
              if (_showConfetti) const Positioned.fill(child: ConfettiBurst()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, L10n l10n, ColorScheme colors) {
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
    if (_phase == _UpdatePhase.permission) {
      return Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('updateLater')),
          ),
          const Spacer(),
          TextButton(
            onPressed: ApkInstaller.openInstallPermissionSettings,
            child: Text(l10n.t('openInstallSettings')),
          ),
          const SizedBox(width: 4),
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
    return Row(
      children: [
        TextButton(onPressed: _later, child: Text(l10n.t('updateLater'))),
        const Spacer(),
        FilledButton.icon(
          onPressed: _primaryAction,
          icon: Icon(
            widget.info.hasApk
                ? Icons.file_download_outlined
                : Icons.open_in_new_rounded,
            size: 17,
          ),
          label: Text(
            widget.info.hasApk ? l10n.t('updateNow') : l10n.t('goDownload'),
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
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_alt_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$latest · $currentLabel $current'
                  '${sizeLabel == null ? '' : ' · $sizeLabel'}',
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.82),
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
    required this.colors,
  });

  final String title;
  final String body;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: colors.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
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
