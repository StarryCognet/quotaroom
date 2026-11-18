import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/quota_pacing.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import 'app_glyphs.dart';

/// FlClash-style bento dashboard: quota windows, KPI tiles, budget and the
/// 24-hour trend on one page.
class PrismHomePage extends StatelessWidget {
  const PrismHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final data = state.dashboard;
    if (data == null) {
      if (state.loadingDashboard) return const _HomeSkeleton();
      return NullStatus(
        illustration: const _EmptyDashboardIllustration(),
        label: l10n.t('noData'),
        description: l10n.t('syncHint'),
        action: FilledButton(
          onPressed: () => state.refreshDashboard(forceQuota: true),
          child: Text(l10n.t('refresh')),
        ),
      );
    }
    final colorScheme = context.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        context.appBarInset + 8,
        16,
        24 + context.bottomInset,
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SegmentedControl<String>(
              segments: [
                ('today', l10n.t('today')),
                ('7d', l10n.t('d7')),
                ('30d', l10n.t('d30')),
                ('all', l10n.t('all')),
              ],
              value: state.dashboardRange,
              onChanged: state.setRange,
            ),
          ),
        ),
        if (state.progress.running) ...[
          const SizedBox(height: 12),
          _SyncCard(state: state),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(state: state),
        ],
        const SizedBox(height: 12),
        _QuotaCard(
          quota: data.quota,
          l10n: l10n,
          onRetry: () => state.refreshDashboard(forceQuota: true),
        ),
        if (state.settings.dailyBudgetUsd != null) ...[
          const SizedBox(height: 12),
          _BudgetCard(state: state, todayCost: data.today.totalCostUsd),
        ],
        const SizedBox(height: 20),
        _SectionTitle(
          title: l10n.t('overviewTitle'),
          glyph: AppGlyphs.dataUsage,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        _KpiGrid(state: state, data: data),
        const SizedBox(height: 20),
        _TrendCard(data: data, l10n: l10n),
      ],
    );
  }
}

class _EmptyDashboardIllustration implements Illustration {
  const _EmptyDashboardIllustration();

  @override
  Glyph get glyph => AppGlyphs.dashboard;

  @override
  bool get isError => false;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.glyph,
    required this.color,
  });

  final String title;
  final Glyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlyphIcon(glyph, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyle.headline
              .of(context, emphasized: true)
              .copyWith(color: context.colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final progress = state.progress;
    final label = progress.message.isEmpty
        ? state.l10n.t('syncing')
        : progress.message;
    return Card(
      child: Row(
        children: [
          ActivityIndicator(size: 18, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.listSubtitleStyle,
            ),
          ),
          if (progress.inserted > 0)
            Text(
              '+${progress.inserted}',
              style: AppTextStyle.caption2
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Card(
      child: Row(
        children: [
          GlyphIcon(AppGlyphs.warning, size: 18, color: colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.errorMessage ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.listSubtitleStyle,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => state.refreshDashboard(forceQuota: true),
            child: Text(state.l10n.t('retry')),
          ),
        ],
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({
    required this.quota,
    required this.l10n,
    required this.onRetry,
  });

  final QuotaResult? quota;
  final L10n l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final quota = this.quota;
    if (quota == null) {
      return Card(
        child: Row(
          children: [
            ActivityIndicator(size: 18, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text(l10n.t('quotaNotReady'), style: context.listSubtitleStyle),
          ],
        ),
      );
    }
    if (!quota.success || quota.windows.isEmpty) {
      return Card(
        child: Row(
          children: [
            GlyphIcon(AppGlyphs.warning, size: 18, color: colorScheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('quotaFail'),
                    style: context.listTitleStyle.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  if ((quota.error ?? '').isNotEmpty)
                    Text(
                      quota.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.listCaptionStyle,
                    ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(l10n.t('retry'))),
          ],
        ),
      );
    }
    return Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlyphIcon(
                AppGlyphs.speed,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.t('quotaSpace'),
                style: AppTextStyle.headline
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurface),
              ),
              const Spacer(),
              Text(
                '${l10n.t('updatedAt')} ${fmtDateTimeShort(quota.updatedAt)}',
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < quota.windows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1),
            _QuotaRow(window: quota.windows[i], l10n: l10n),
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
    final colorScheme = context.colorScheme;
    final pacing = computeQuotaPacing(window);
    final remaining = window.remaining;
    final health = remaining < 20
        ? colorScheme.error
        : (remaining < 50 ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    final reset = window.resetAt != null
        ? '${l10n.t('resetsIn')} ${fmtResetAt(window.resetAt)}'
        : '${l10n.t('resetsIn')} ${fmtDur(window.resetInSec, dUnit: l10n.t('dUnit'), hUnit: l10n.t('hUnit'), mUnit: l10n.t('mUnit'), soon: l10n.t('soon'))}';
    final paceText = pacing == null || window.used <= 0
        ? null
        : l10n.t('paceShort', {'n': pacing.pace.toStringAsFixed(1)});
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: health,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.t(_windowLabel(window.label)),
                  style: context.listTitleStyle,
                ),
              ),
              if (paceText != null) ...[
                TonalChip(
                  label: paceText,
                  color: health.withValues(alpha: 0.14),
                  foregroundColor: health,
                ),
                const SizedBox(width: 8),
              ],
              TonalChip(
                label:
                    '${window.used.toStringAsFixed(window.used < 10 ? 1 : 0)}% ${l10n.t('used')}',
                color: health.withValues(alpha: 0.14),
                foregroundColor: health,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressBar(
            value: (window.used / 100).clamp(0.0, 1.0),
            color: health,
            height: 7,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(reset, style: context.listCaptionStyle),
              const Spacer(),
              Text(
                '${l10n.t('remaining')} ${window.remaining.toStringAsFixed(window.remaining < 10 ? 1 : 0)}%',
                style: AppTextStyle.caption2
                    .of(context, emphasized: true)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (pacing?.willExhaustBeforeReset == true) ...[
            const SizedBox(height: 4),
            Text(
              l10n.t('etaExhaust', {
                'duration': fmtDur(
                  pacing!.etaSeconds ?? 0,
                  dUnit: l10n.t('dUnit'),
                  hUnit: l10n.t('hUnit'),
                  mUnit: l10n.t('mUnit'),
                  soon: l10n.t('soon'),
                ),
              }),
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  static String _windowLabel(String label) => switch (label) {
    '5h Rolling' => 'rolling',
    'Weekly' => 'weekly',
    'Monthly' => 'monthly',
    _ => label,
  };
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.state, required this.todayCost});

  final AppState state;
  final double todayCost;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final l10n = state.l10n;
    final budget = state.settings.dailyBudgetUsd ?? 0;
    final ratio = budget > 0 ? (todayCost / budget).clamp(0.0, 1.0) : 0.0;
    final over = todayCost > budget;
    final color = over
        ? colorScheme.error
        : (ratio >= 0.8 ? colorScheme.tertiary : colorScheme.primary);
    final remaining = budget - todayCost;
    final status = over
        ? '${l10n.t('budgetOver')} ${fmtMoney(-remaining, currency: state.currency, rate: state.usdCny)}'
        : '${l10n.t('remaining')} ${fmtMoney(remaining, currency: state.currency, rate: state.usdCny)}';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlyphIcon(AppGlyphs.star, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.t('dailyBudget'),
                  style: context.listTitleStyle,
                ),
              ),
              Text(
                status,
                style: AppTextStyle.caption2
                    .of(context, emphasized: true)
                    .copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressBar(value: ratio, color: color, height: 7),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${l10n.t('budgetUsed')} ${fmtMoney(todayCost, currency: state.currency, rate: state.usdCny)}',
                style: context.listCaptionStyle,
              ),
              const Spacer(),
              Text(
                '${l10n.t('dailyBudget')} ${fmtMoney(budget, currency: state.currency, rate: state.usdCny)}',
                style: context.listCaptionStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.state, required this.data});

  final AppState state;
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final l10n = state.l10n;
    final totals = data.totals;
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    Color tint(Color accent) => Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.16 : 0.08),
      colorScheme.surface,
    );
    final dailyValues = data.daily7
        .map((day) => day.totalTokens.toDouble())
        .toList(growable: false);
    final items = <Widget>[
      _MetricCard(
        glyph: AppGlyphs.bolt,
        label: l10n.t('hitRate'),
        value: '${totals.hitRate.toStringAsFixed(1)}%',
        detail:
            '${l10n.t('hit')} ${fmtTokens(totals.cacheHitTokens)} · ${l10n.t('miss')} ${fmtTokens(totals.uncachedInputTokens)}',
        accent: tint(const Color(0xFF22C55E)),
        accentColor: const Color(0xFF22C55E),
        sparkline: dailyValues,
      ),
      _MetricCard(
        glyph: AppGlyphs.dataUsage,
        label: l10n.t('totalTokens'),
        value: fmtTokens(totals.totalTokens),
        detail: l10n.t('inclCache'),
        accent: tint(colorScheme.primary),
        accentColor: colorScheme.primary,
        sparkline: dailyValues,
      ),
      _MetricCard(
        glyph: AppGlyphs.requests,
        label: l10n.t('totalRequests'),
        value: fmtInt(totals.requestCount),
        detail: '${fmtInt(totals.sessionCount)} ${l10n.t('sessions')}',
        accent: tint(const Color(0xFF4F8EF7)),
        accentColor: const Color(0xFF4F8EF7),
      ),
      _MetricCard(
        glyph: AppGlyphs.star,
        label: l10n.t('totalCost'),
        value: fmtMoney(
          totals.totalCostUsd,
          currency: state.currency,
          rate: state.usdCny,
        ),
        detail: l10n.t('currentRange'),
        accent: tint(const Color(0xFFD97706)),
        accentColor: const Color(0xFFD97706),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 860 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items) SizedBox(width: width, child: item),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.glyph,
    required this.label,
    required this.value,
    required this.detail,
    required this.accent,
    required this.accentColor,
    this.sparkline,
  });

  final Glyph glyph;
  final String label;
  final String value;
  final String detail;
  final Color accent;
  final Color accentColor;
  final List<double>? sparkline;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final dark = Theme.brightnessOf(context) == Brightness.dark;
    final sparkline = this.sparkline;
    return Container(
      constraints: const BoxConstraints(minHeight: 142),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: ShapeDecoration(
        color: accent,
        shape: AppShape.all(AppCorner.lg),
        shadows: dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF18122B).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlyphIcon(glyph, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              value,
              key: ValueKey(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .copyWith(color: colorScheme.onSurface),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (sparkline != null && sparkline.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: Sparkline(
                values: sparkline,
                color: accentColor.withValues(alpha: 0.7),
                height: 34,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.data, required this.l10n});

  final DashboardData data;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final inputColor = colorScheme.primary;
    final outputColor = colorScheme.tertiary;
    final labelStyle = AppTextStyle.caption2
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    return Card(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlyphIcon(
                AppGlyphs.requests,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.t('todayTrend'),
                  style: AppTextStyle.headline
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.onSurface),
                ),
              ),
              Text(
                l10n.t('hours24'),
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: _HourlyBars(
              points: data.todayTrend,
              inputColor: inputColor,
              outputColor: outputColor,
              labelStyle: labelStyle,
              gridColor: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(color: inputColor, label: l10n.t('input')),
              const SizedBox(width: 16),
              _LegendDot(color: outputColor, label: l10n.t('output')),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.color,
    this.height = 6,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final track = context.colorScheme.outlineVariant.withValues(alpha: 0.35);
    return Container(
      height: height,
      decoration: ShapeDecoration(color: track, shape: AppShape.full),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: progress,
            child: DecoratedBox(
              decoration: ShapeDecoration(color: color, shape: AppShape.full),
              child: SizedBox(height: height),
            ),
          ),
        ),
      ),
    );
  }
}

class _HourlyBars extends StatelessWidget {
  const _HourlyBars({
    required this.points,
    required this.inputColor,
    required this.outputColor,
    required this.labelStyle,
    required this.gridColor,
  });

  final List<HourPoint> points;
  final Color inputColor;
  final Color outputColor;
  final TextStyle labelStyle;
  final Color gridColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _HourlyBarsPainter(
          points: points,
          inputColor: inputColor,
          outputColor: outputColor,
          labelStyle: labelStyle,
          gridColor: gridColor,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _HourlyBarsPainter extends CustomPainter {
  _HourlyBarsPainter({
    required this.points,
    required this.inputColor,
    required this.outputColor,
    required this.labelStyle,
    required this.gridColor,
  });

  final List<HourPoint> points;
  final Color inputColor;
  final Color outputColor;
  final TextStyle labelStyle;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelHeight = 18.0;
    final plotHeight = math.max(1.0, size.height - labelHeight);
    final maxValue = points.fold<int>(
      0,
      (value, point) => math.max(value, math.max(point.input, point.output)),
    );
    final scale = maxValue <= 0 ? 1.0 : maxValue.toDouble();
    final gridPaint = ui.Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = plotHeight * i / 4;
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y), gridPaint);
    }
    final groupWidth = size.width / 24;
    final barWidth = math.max(2.0, groupWidth * 0.24);
    final radius = ui.Radius.circular(barWidth / 2);
    final inputPaint = ui.Paint()..color = inputColor;
    final outputPaint = ui.Paint()..color = outputColor;
    for (var hour = 0; hour < 24; hour++) {
      final point = hour < points.length
          ? points[hour]
          : const HourPoint(hour: 0);
      final center = groupWidth * hour + groupWidth / 2;
      final inputHeight = plotHeight * point.input / scale;
      final outputHeight = plotHeight * point.output / scale;
      if (inputHeight > 0.5) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              center - barWidth - 1,
              plotHeight - inputHeight,
              barWidth,
              inputHeight,
            ),
            radius,
          ),
          inputPaint,
        );
      }
      if (outputHeight > 0.5) {
        canvas.drawRRect(
          ui.RRect.fromRectAndRadius(
            ui.Rect.fromLTWH(
              center + 1,
              plotHeight - outputHeight,
              barWidth,
              outputHeight,
            ),
            radius,
          ),
          outputPaint,
        );
      }
      if (hour % 3 == 0) {
        final painter = TextPainter(
          text: TextSpan(
            text: hour.toString().padLeft(2, '0'),
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          ui.Offset(center - painter.width / 2, plotHeight + 4),
        );
        painter.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_HourlyBarsPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.inputColor != inputColor ||
        oldDelegate.outputColor != outputColor;
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        context.appBarInset + 8,
        16,
        24 + context.bottomInset,
      ),
      children: const [
        SkeletonPill(width: 360, height: 44),
        SizedBox(height: 12),
        SkeletonPill(width: double.infinity, height: 208),
        SizedBox(height: 20),
        SkeletonPill(width: 120, height: 22),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: SkeletonPill(width: double.infinity, height: 142)),
            SizedBox(width: 12),
            Expanded(child: SkeletonPill(width: double.infinity, height: 142)),
          ],
        ),
        SizedBox(height: 12),
        SkeletonPill(width: double.infinity, height: 240),
      ],
    );
  }
}
