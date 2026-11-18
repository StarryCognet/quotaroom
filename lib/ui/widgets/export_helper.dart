import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../state/app_state.dart';

/// Mobile uses the system share sheet; desktop asks for a destination.
Future<void> saveOrShareExport(
  BuildContext context, {
  required File file,
  required String shareText,
}) async {
  final state = context.read<AppState>();
  final l10n = state.l10n;
  if (!isDesktop) {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: shareText),
    );
    return;
  }
  final location = await getSaveLocation(suggestedName: p.basename(file.path));
  if (location == null) return;
  await file.copy(location.path);
  try {
    await file.delete();
  } catch (_) {
    // The destination copy is already complete; temp cleanup is best-effort.
  }
  if (!context.mounted) return;
  BannerHost.maybeOf(context)?.show(
    l10n.t('savedTo', {'path': location.path}),
    level: BannerLevel.success,
  );
}

void showExportError(BuildContext context, Object error) {
  final l10n = context.read<AppState>().l10n;
  BannerHost.maybeOf(context)
      ?.show('${l10n.t('exportFailed')}: $error', level: BannerLevel.error);
}

/// Shared text export (clipboard on desktop, share sheet on mobile).
Future<void> shareTextExport(
  BuildContext context, {
  required String text,
}) async {
  if (isDesktop) {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final l10n = context.read<AppState>().l10n;
    BannerHost.maybeOf(context)
        ?.show(l10n.t('copiedToClipboard'), level: BannerLevel.success);
    return;
  }
  await SharePlus.instance.share(ShareParams(text: text));
}
