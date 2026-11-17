import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

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
    final colors = context.colors;
    var maxValue = 0.0;
    for (final point in points) {
      maxValue = math.max(
        maxValue,
        math.max(point.input, point.output).toDouble(),
      );
    }
    if (points.isEmpty || maxValue <= 0) {
      return EmptyState(
        icon: Icons.bar_chart_rounded,
        title: l10n.t('noData'),
        subtitle: l10n.t('syncHint'),
        compact: true,
      );
    }
    final maxY = maxValue * 1.18;
    final interval = maxY / 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LegendDot(color: colors.blue, label: l10n.t('input')),
            const SizedBox(width: 14),
            LegendDot(color: colors.green, label: l10n.t('output')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              groupsSpace: 2,
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].input.toDouble(),
                        color: colors.blue,
                        width: 5,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                      BarChartRodData(
                        toY: points[i].output.toDouble(),
                        color: colors.green,
                        width: 5,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ],
                  ),
              ],
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: interval,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        fmtTokens(value),
                        style: TextStyle(fontSize: 9, color: colors.text3),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final hour = value.toInt();
                      if (hour < 0 || hour >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if (hour % 3 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          points[hour].label.substring(0, 2),
                          style: TextStyle(fontSize: 9, color: colors.text3),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: colors.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => colors.card,
                  tooltipBorder: BorderSide(color: colors.border),
                  tooltipBorderRadius: BorderRadius.circular(8),
                  maxContentWidth: 180,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (rodIndex != 0) return null;
                    if (group.x < 0 || group.x >= points.length) return null;
                    final point = points[group.x];
                    return BarTooltipItem(
                      '${point.label}\n'
                      '${l10n.t('input')}  ${fmtTokens(point.input)}\n'
                      '${l10n.t('output')}  ${fmtTokens(point.output)}\n'
                      '${l10n.t('colReasoning')}  ${fmtTokens(point.reasoning)}',
                      TextStyle(
                        color: colors.text,
                        fontSize: 10.5,
                        height: 1.5,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
    final colors = context.colors;
    final entries = <({ModelStat stat, double value})>[];
    for (final model in models) {
      final value = _valueOf(model);
      if (value > 0) entries.add((stat: model, value: value));
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(6).toList();
    if (top.isEmpty) {
      return EmptyState(
        icon: Icons.donut_large_rounded,
        title: l10n.t('noData'),
        compact: true,
      );
    }
    final total = top.fold<double>(0, (sum, entry) => sum + entry.value);
    final centerLabel = switch (dimension) {
      'output' => l10n.t('outputTokens'),
      'cost' => l10n.t('totalCost'),
      _ => l10n.t('inputTokens'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 186,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  centerSpaceRadius: 46,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(enabled: false),
                  sections: [
                    for (var i = 0; i < top.length; i++)
                      PieChartSectionData(
                        value: top[i].value,
                        color: _palette[i % _palette.length],
                        radius: 24,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dimension == 'cost'
                        ? fmtMoney(total, currency: currency, rate: rate)
                        : fmtTokens(total),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    centerLabel,
                    style: TextStyle(fontSize: 9.5, color: colors.text3),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < top.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _palette[i % _palette.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                ModelIcon(model: top[i].stat.model, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    top[i].stat.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colors.text2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dimension == 'cost'
                      ? fmtMoney(
                          top[i].value,
                          currency: currency,
                          rate: rate,
                        )
                      : fmtTokens(top[i].value),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(top[i].value / total * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10.5, color: colors.text3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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
    final colors = context.colors;
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
        icon: Icons.show_chart_rounded,
        title: l10n.t('noData'),
        compact: true,
      );
    }
    final tokenScale = maxTokens <= 0 ? 1.0 : maxTokens.toDouble();
    final costScale = maxCost > 0 ? tokenScale / maxCost : 0.0;
    final requestScale = maxRequests > 0 ? tokenScale / maxRequests : 0.0;
    final maxY = tokenScale * 1.12;
    final interval = maxY / 4;
    final labelStep = math.max(1, (days.length / 4).ceil());
    final tokenSpots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].totalTokens.toDouble()),
    ];
    final costSpots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].totalCostUsd * costScale),
    ];
    final requestSpots = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].requestCount * requestScale),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            LegendDot(color: colors.primary, label: l10n.t('totalTokensShort')),
            const SizedBox(width: 12),
            LegendDot(color: colors.blue, label: l10n.t('requests')),
            const SizedBox(width: 12),
            LegendDot(color: colors.amber, label: l10n.t('totalCost')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(0, days.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: tokenSpots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  color: colors.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: colors.primary.withValues(alpha: 0.07),
                  ),
                ),
                LineChartBarData(
                  spots: requestSpots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  color: colors.blue,
                  barWidth: 1.6,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: costSpots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  color: colors.amber,
                  barWidth: 1.6,
                  dotData: const FlDotData(show: false),
                ),
              ],
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: interval,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        fmtTokens(value),
                        style: TextStyle(fontSize: 9, color: colors.text3),
                      ),
                    ),
                  ),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (costScale <= 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          fmtMoney(value / costScale, currency: currency, rate: rate),
                          style: TextStyle(fontSize: 8.5, color: colors.text3),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= days.length) {
                        return const SizedBox.shrink();
                      }
                      if (index % labelStep != 0 && index != days.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          fmtDateShort(days[index].day),
                          style: TextStyle(fontSize: 8.5, color: colors.text3),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: colors.grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => colors.card,
                  tooltipBorder: BorderSide(color: colors.border),
                  tooltipBorderRadius: BorderRadius.circular(8),
                  maxContentWidth: 220,
                  getTooltipItems: (spots) {
                    if (spots.isEmpty) return const [];
                    final index = spots.first.spotIndex;
                    if (index < 0 || index >= days.length) return const [];
                    final day = days[index];
                    final text =
                        '${day.date}\n'
                        '${l10n.t('totalTokensShort')}  ${fmtTokens(day.totalTokens)}\n'
                        '${l10n.t('requests')}  ${fmtInt(day.requestCount)}\n'
                        '${l10n.t('totalCost')}  ${fmtMoney(day.totalCostUsd, currency: currency, rate: rate)}';
                    final items = <LineTooltipItem?>[];
                    for (var i = 0; i < spots.length; i++) {
                      items.add(
                        i == 0
                            ? LineTooltipItem(
                                text,
                                TextStyle(
                                  color: colors.text,
                                  fontSize: 10.5,
                                  height: 1.5,
                                ),
                              )
                            : null,
                      );
                    }
                    return items;
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
      child: CustomPaint(painter: _SparklinePainter(values, color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

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
    canvas.drawPath(path, linePaint);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.24),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
