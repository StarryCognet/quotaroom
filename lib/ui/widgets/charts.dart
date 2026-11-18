import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/models.dart';
import '../prism/app_glyphs.dart';
import 'common.dart';

const _blue = Color(0xFF4F8EF7);
const _green = Color(0xFF22C55E);
const _amber = Color(0xFFD97706);

/// Prism-native bar chart for the 24-hour input/output trend.
class TodayTrendChart extends StatelessWidget {
  const TodayTrendChart({
    super.key,
    required this.points,
    required this.l10n,
    this.height = 210,
  });

  final List<HourPoint> points;
  final L10n l10n;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    var maxValue = 0.0;
    for (final point in points) {
      maxValue = math.max(
        maxValue,
        math.max(point.input, point.output).toDouble(),
      );
    }
    if (points.isEmpty || maxValue <= 0) {
      return EmptyState(
        glyph: AppGlyphs.dataUsage,
        title: l10n.t('noData'),
        subtitle: l10n.t('syncHint'),
        compact: true,
      );
    }
    final style = AppTextStyle.caption2
        .of(context)
        .copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LegendDot(color: scheme.primary, label: l10n.t('input')),
            const SizedBox(width: 14),
            LegendDot(color: _green, label: l10n.t('output')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('hour-bars-${points.hashCode}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              painter: _HourBarsPainter(
                points: points,
                progress: progress,
                inputColor: scheme.primary,
                outputColor: _green,
                gridColor: scheme.outlineVariant.withValues(alpha: 0.45),
                textStyle: style,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _HourBarsPainter extends CustomPainter {
  _HourBarsPainter({
    required this.points,
    required this.progress,
    required this.inputColor,
    required this.outputColor,
    required this.gridColor,
    required this.textStyle,
  });

  final List<HourPoint> points;
  final double progress;
  final Color inputColor;
  final Color outputColor;
  final Color gridColor;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const bottom = 20.0;
    const top = 6.0;
    final plotWidth = math.max(1.0, size.width - left);
    final plotHeight = math.max(1.0, size.height - bottom - top);
    final maxValue = points.fold<int>(
      0,
      (value, point) => math.max(value, math.max(point.input, point.output)),
    );
    final scale = maxValue <= 0 ? 1.0 : maxValue.toDouble();
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotHeight * (1 - i / 4);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final label = TextPainter(
        text: TextSpan(text: fmtTokens(scale * i / 4), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(left - 6 - label.width, y - label.height / 2));
      label.dispose();
    }
    final groupWidth = plotWidth / 24;
    final barWidth = math.max(2.0, math.min(5.0, groupWidth * 0.26));
    final radius = Radius.circular(barWidth / 2);
    final inputPaint = Paint()..color = inputColor;
    final outputPaint = Paint()..color = outputColor;
    for (var hour = 0; hour < 24; hour++) {
      final point = hour < points.length
          ? points[hour]
          : const HourPoint(hour: 0);
      final center = left + groupWidth * hour + groupWidth / 2;
      final inputHeight = plotHeight * point.input / scale * progress;
      final outputHeight = plotHeight * point.output / scale * progress;
      if (inputHeight > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center - barWidth - 1,
              top + plotHeight - inputHeight,
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
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center + 1,
              top + plotHeight - outputHeight,
              barWidth,
              outputHeight,
            ),
            radius,
          ),
          outputPaint,
        );
      }
      if (hour % 3 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: hour.toString().padLeft(2, '0'),
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(center - label.width / 2, top + plotHeight + 5),
        );
        label.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_HourBarsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.points != points ||
        oldDelegate.inputColor != inputColor ||
        oldDelegate.outputColor != outputColor;
  }
}

/// Prism-native donut chart and model ranking.
class ModelDonut extends StatelessWidget {
  const ModelDonut({
    super.key,
    required this.models,
    required this.dimension,
    required this.l10n,
    required this.currency,
    required this.rate,
  });

  final List<ModelStat> models;
  final String dimension;
  final L10n l10n;
  final String currency;
  final double rate;

  static const List<Color> _palette = [
    Color(0xFF7C5CF6),
    Color(0xFF4F8EF7),
    Color(0xFF22C55E),
    Color(0xFFD97706),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  double _valueOf(ModelStat stat) => switch (dimension) {
    'output' => stat.totalOutputTokens.toDouble(),
    'cost' => stat.totalCostUsd,
    _ => stat.totalInputTokens.toDouble(),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final entries = <({ModelStat stat, double value})>[];
    for (final model in models) {
      final value = _valueOf(model);
      if (value > 0) entries.add((stat: model, value: value));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final otherTotal = entries
        .skip(5)
        .fold<double>(0, (sum, entry) => sum + entry.value);
    if (top.isEmpty) {
      return EmptyState(
        glyph: AppGlyphs.dataUsage,
        title: l10n.t('noData'),
        compact: true,
      );
    }
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    final centerLabel = switch (dimension) {
      'output' => l10n.t('outputTokens'),
      'cost' => l10n.t('totalCost'),
      _ => l10n.t('inputTokens'),
    };
    final sections = <({double value, Color color})>[
      for (var i = 0; i < top.length; i++)
        (value: top[i].value, color: _palette[i % _palette.length]),
      if (otherTotal > 0) (value: otherTotal, color: const Color(0xFF94A3B8)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 186,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey('donut-$dimension-${total.toStringAsFixed(3)}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) => CustomPaint(
                  painter: _DonutPainter(
                    sections: sections,
                    total: total,
                    progress: progress,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dimension == 'cost'
                        ? fmtMoney(total, currency: currency, rate: rate)
                        : fmtTokens(total),
                    style: AppTextStyle.title3
                        .of(context, emphasized: true)
                        .copyWith(
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    centerLabel,
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < top.length; i++)
          _ModelLegendRow(
            color: _palette[i % _palette.length],
            model: top[i].stat.model,
            value: dimension == 'cost'
                ? fmtMoney(top[i].value, currency: currency, rate: rate)
                : fmtTokens(top[i].value),
            pct: top[i].value / total * 100,
            scheme: scheme,
          ),
        if (otherTotal > 0)
          _ModelLegendRow(
            color: const Color(0xFF94A3B8),
            model: l10n.t('other'),
            value: dimension == 'cost'
                ? fmtMoney(otherTotal, currency: currency, rate: rate)
                : fmtTokens(otherTotal),
            pct: otherTotal / total * 100,
            scheme: scheme,
            glyph: AppGlyphs.more,
          ),
      ],
    );
  }
}

class _ModelLegendRow extends StatelessWidget {
  const _ModelLegendRow({
    required this.color,
    required this.model,
    required this.value,
    required this.pct,
    required this.scheme,
    this.glyph,
  });

  final Color color;
  final String model;
  final String value;
  final double pct;
  final ColorScheme scheme;
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          if (glyph != null)
            GlyphIcon(glyph!, size: 15, color: scheme.onSurfaceVariant)
          else
            ModelIcon(model: model, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .copyWith(
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              '${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.sections,
    required this.total,
    required this.progress,
  });

  final List<({double value, Color color})> sections;
  final double total;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    const gap = 0.012;
    final totalSweep = math.pi * 2 * progress;
    for (final section in sections) {
      final sweep = section.value / total * totalSweep;
      if (sweep <= 0) continue;
      paint.color = section.color;
      canvas.drawArc(
        rect,
        start + gap,
        math.max(0.0, sweep - gap * 2),
        false,
        paint,
      );
      start += section.value / total * math.pi * 2 * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.total != total;
  }
}

/// Prism-native multi-series trend chart with token/request/cost axes.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.days,
    required this.l10n,
    required this.currency,
    required this.rate,
    this.height = 220,
  });

  final List<DailyStat> days;
  final L10n l10n;
  final String currency;
  final double rate;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    var maxTokens = 0;
    var maxCost = 0.0;
    var maxRequests = 0;
    for (final day in days) {
      maxTokens = math.max(maxTokens, day.totalTokens);
      maxCost = math.max(maxCost, day.totalCostUsd);
      maxRequests = math.max(maxRequests, day.requestCount);
    }
    if (days.isEmpty || (maxTokens == 0 && maxCost == 0 && maxRequests == 0)) {
      return EmptyState(
        glyph: AppGlyphs.dataUsage,
        title: l10n.t('noData'),
        compact: true,
      );
    }
    final style = AppTextStyle.caption2
        .of(context)
        .copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LegendDot(color: scheme.primary, label: l10n.t('totalTokensShort')),
            const SizedBox(width: 12),
            LegendDot(color: _blue, label: l10n.t('requests')),
            const SizedBox(width: 12),
            LegendDot(color: _amber, label: l10n.t('totalCost')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(
              'trend-${days.length}-$maxTokens-${maxCost.toStringAsFixed(4)}',
            ),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 760),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => CustomPaint(
              painter: _TrendPainter(
                days: days,
                progress: progress,
                tokenColor: scheme.primary,
                requestColor: _blue,
                costColor: _amber,
                gridColor: scheme.outlineVariant.withValues(alpha: 0.45),
                textStyle: style,
                currency: currency,
                rate: rate,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.days,
    required this.progress,
    required this.tokenColor,
    required this.requestColor,
    required this.costColor,
    required this.gridColor,
    required this.textStyle,
    required this.currency,
    required this.rate,
  });

  final List<DailyStat> days;
  final double progress;
  final Color tokenColor;
  final Color requestColor;
  final Color costColor;
  final Color gridColor;
  final TextStyle textStyle;
  final String currency;
  final double rate;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0;
    const right = 44.0;
    const top = 8.0;
    const bottom = 22.0;
    final plotWidth = math.max(1.0, size.width - left - right);
    final plotHeight = math.max(1.0, size.height - top - bottom);
    var maxTokens = 0;
    var maxCost = 0.0;
    var maxRequests = 0;
    for (final day in days) {
      maxTokens = math.max(maxTokens, day.totalTokens);
      maxCost = math.max(maxCost, day.totalCostUsd);
      maxRequests = math.max(maxRequests, day.requestCount);
    }
    final tokenScale = maxTokens <= 0 ? 1.0 : maxTokens.toDouble();
    final costScale = maxCost > 0 ? tokenScale / maxCost : 0.0;
    final requestScale = maxRequests > 0 ? tokenScale / maxRequests : 0.0;
    final maxY = tokenScale * 1.12;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotHeight * (1 - i / 4);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final tokenLabel = TextPainter(
        text: TextSpan(text: fmtTokens(maxY * i / 4), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tokenLabel.paint(
        canvas,
        Offset(left - 6 - tokenLabel.width, y - tokenLabel.height / 2),
      );
      tokenLabel.dispose();
      if (costScale > 0) {
        final costLabel = TextPainter(
          text: TextSpan(
            text: fmtMoney(
              maxY * i / 4 / costScale,
              currency: currency,
              rate: rate,
            ),
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        costLabel.paint(
          canvas,
          Offset(size.width - right + 6, y - costLabel.height / 2),
        );
        costLabel.dispose();
      }
    }
    final count = days.length;
    if (count < 2) return;
    final step = plotWidth / (count - 1);
    final tokenPoints = <Offset>[];
    final requestPoints = <Offset>[];
    final costPoints = <Offset>[];
    for (var i = 0; i < count; i++) {
      final x = left + step * i;
      tokenPoints.add(
        Offset(x, top + plotHeight * (1 - days[i].totalTokens / maxY)),
      );
      if (requestScale > 0) {
        requestPoints.add(
          Offset(
            x,
            top + plotHeight * (1 - days[i].requestCount * requestScale / maxY),
          ),
        );
      }
      if (costScale > 0) {
        costPoints.add(
          Offset(
            x,
            top + plotHeight * (1 - days[i].totalCostUsd * costScale / maxY),
          ),
        );
      }
    }
    final tokenPath = _smoothPath(tokenPoints);
    final fillPath = Path.from(tokenPath)
      ..lineTo(left + plotWidth, top + plotHeight)
      ..lineTo(left, top + plotHeight)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tokenColor.withValues(alpha: 0.14 * progress),
            tokenColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(left, top, plotWidth, plotHeight)),
    );
    _drawPartialPath(
      canvas,
      tokenPath,
      Paint()
        ..color = tokenColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
      progress,
    );
    if (requestPoints.length > 1) {
      _drawPartialPath(
        canvas,
        _smoothPath(requestPoints),
        Paint()
          ..color = requestColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        progress,
      );
    }
    if (costPoints.length > 1) {
      _drawPartialPath(
        canvas,
        _smoothPath(costPoints),
        Paint()
          ..color = costColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
        progress,
      );
    }
    final labelStep = math.max(1, (count / 4).ceil());
    for (var i = 0; i < count; i++) {
      if (i % labelStep != 0 && i != count - 1) continue;
      final label = TextPainter(
        text: TextSpan(text: fmtDateShort(days[i].day), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = left + step * i - label.width / 2;
      label.paint(
        canvas,
        Offset(x.clamp(0.0, size.width - label.width), top + plotHeight + 5),
      );
      label.dispose();
    }
  }

  static Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  static void _drawPartialPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double progress,
  ) {
    for (final metric in path.computeMetrics()) {
      final length = metric.length * progress.clamp(0.0, 1.0);
      if (length > 0) {
        canvas.drawPath(metric.extractPath(0, length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.days != days ||
        oldDelegate.tokenColor != tokenColor;
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 30,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        key: ValueKey('spark-${values.hashCode}-$color'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) =>
            CustomPaint(painter: _SparklinePainter(values, color, progress)),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.progress);

  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final maxValue = values.reduce(math.max);
    if (maxValue <= 0) return;
    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = step * i;
      final y = size.height - (values[i] / maxValue) * (size.height - 3) - 1.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final metric in path.computeMetrics()) {
      final length = metric.length * progress.clamp(0.0, 1.0);
      if (length <= 0) continue;
      final partial = metric.extractPath(0, length);
      canvas.drawPath(partial, linePaint);
      final end = metric.getTangentForOffset(length)?.position ?? Offset.zero;
      final fillPath = Path.from(partial)
        ..lineTo(end.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.24),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}
