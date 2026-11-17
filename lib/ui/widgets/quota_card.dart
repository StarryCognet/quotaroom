import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

class QuotaCard extends StatelessWidget {
  const QuotaCard({
    super.key,
    required this.window,
    required this.l10n,
  });

  final QuotaWindow? window;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = window == null
        ? ''
        : l10n.t(quotaLabel(window!.label));
    final gradient = _gradientFor(colors, window?.label ?? '');
    final barColor = _barColorFor(colors, window?.label ?? '');
    return AppCard(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
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
                      window == null
                          ? '—'
                          : '${window!.remaining.toStringAsFixed(window!.remaining % 1 == 0 ? 0 : 1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: window == null ? colors.text3 : barColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: window == null
                        ? 0
                        : (window!.used / 100).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: colors.muted,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        window == null
                            ? l10n.t('quotaNotReady')
                            : '${l10n.t('resetsIn')} ${fmtDur(window!.resetInSec, dUnit: l10n.t('dUnit'), hUnit: l10n.t('hUnit'), mUnit: l10n.t('mUnit'), soon: l10n.t('soon'))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: colors.text3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      window == null
                          ? ''
                          : '${window!.used.toStringAsFixed(2)}% ${l10n.t('used')}',
                      style: TextStyle(fontSize: 10.5, color: colors.text3),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<Color> _gradientFor(AppColors colors, String label) {
    return switch (label) {
      '5h Rolling' => [colors.purple, colors.primary],
      'Weekly' => [colors.blue, colors.green],
      'Monthly' => [colors.amber, colors.red],
      _ => [colors.primary, colors.blue],
    };
  }

  static Color _barColorFor(AppColors colors, String label) {
    return switch (label) {
      '5h Rolling' => colors.primary,
      'Weekly' => colors.green,
      'Monthly' => colors.red,
      _ => colors.primary,
    };
  }
}

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
              style: TextStyle(fontSize: 12.5, color: colors.text2),
            ),
          ],
        ),
      );
    }
    if (!quota!.success || quota!.windows.isEmpty) {
      return AppCard(
        borderColor: colors.red.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: colors.red),
                const SizedBox(width: 8),
                Text(
                  l10n.t('quotaFail'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.red,
                  ),
                ),
                const Spacer(),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      l10n.t('retry'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            if ((quota!.error ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                quota!.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.text3, height: 1.5),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              l10n.t('retryTip'),
              style: TextStyle(fontSize: 10.5, color: colors.text3),
            ),
          ],
        ),
      );
    }
    final windows = quota!.windows;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620 && windows.length > 1) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < windows.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: QuotaCard(window: windows[i], l10n: l10n),
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < windows.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              QuotaCard(window: windows[i], l10n: l10n),
            ],
          ],
        );
      },
    );
  }
}
