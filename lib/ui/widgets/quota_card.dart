import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

/// Compact quota block: one card, one row per window.
///
/// The prominent number is the *used* percentage, matching the progress bar.
/// Remaining percentage is shown next to the reset time so the two numbers
/// never contradict each other.
class QuotaSection extends StatelessWidget {
  const QuotaSection({
    super.key,
    required this.quota,
    required this.l10n,
    this.onRetry,
  });

  final QuotaResult? quota;
  final L10n l10n;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (quota == null) {
      return AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.t('quotaNotReady'),
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
          ],
        ),
      );
    }
    if (!quota!.success || quota!.windows.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        borderColor: colors.red.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 17, color: colors.red),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    l10n.t('quotaFail'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.red,
                    ),
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      l10n.t('retry'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
            if ((quota!.error ?? '').isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                quota!.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: colors.text3,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      );
    }
    final windows = quota!.windows;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < windows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.border),
            _QuotaRow(window: windows[i], l10n: l10n),
          ],
        ],
      ),
    );
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({required this.window, required this.l10n});

  final QuotaWindow window;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final remaining = window.remaining;
    final health = remaining < 20
        ? colors.red
        : (remaining < 50 ? colors.amber : colors.green);
    final typeColor = switch (window.label) {
      '5h Rolling' => colors.purple,
      'Weekly' => colors.blue,
      'Monthly' => colors.amber,
      _ => colors.primary,
    };
    final reset = window.resetAt != null
        ? '${l10n.t('resetsIn')} ${fmtResetAt(window.resetAt)}'
        : '${l10n.t('resetsIn')} ${fmtDur(window.resetInSec, dUnit: l10n.t('dUnit'), hUnit: l10n.t('hUnit'), mUnit: l10n.t('mUnit'), soon: l10n.t('soon'))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: typeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.t(quotaLabel(window.label)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_pct(window.used)} ${l10n.t('used')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: health,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (window.used / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.muted,
              valueColor: AlwaysStoppedAnimation(health),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.t('remaining')} ${_pct(remaining)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: colors.text3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                reset,
                style: TextStyle(fontSize: 10.5, color: colors.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _pct(double value) {
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
  }
}
