import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String _dimension = 'input';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final data = state.dashboard;
    final colors = context.colors;
    if (data == null) {
      return state.loadingDashboard
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(
              icon: Icons.bar_chart_rounded,
              title: l10n.t('noData'),
              subtitle: l10n.t('syncHint'),
              action: FilledButton(
                onPressed: () => state.syncNow(),
                child: Text(l10n.t('refresh')),
              ),
            );
    }
    final totals = data.totals;
    return RefreshIndicator(
      onRefresh: () => state.syncNow(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        children: [
          RangeSelector(
            value: state.dashboardRange,
            onChanged: (value) => state.setRange(value),
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          _KpiRow(totals: totals, state: state),
          const SizedBox(height: 14),
          _ComparisonCard(data: data, state: state),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: l10n.t('usageTrend'),
                  subtitle: l10n.t('totalTokenHint'),
                  trailing: Text(
                    l10n.t('trendHint'),
                    style: TextStyle(fontSize: 11, color: colors.text3),
                  ),
                ),
                const SizedBox(height: 10),
                TrendLineChart(
                  days: data.trend30,
                  l10n: l10n,
                  currency: state.currency,
                  rate: state.usdCny,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: l10n.t('modelUsage'),
                  trailing: PillSelector<String>(
                    compact: true,
                    value: _dimension,
                    onChanged: (value) => setState(() => _dimension = value),
                    options: [
                      PillOption(value: 'input', label: l10n.t('input')),
                      PillOption(value: 'output', label: l10n.t('output')),
                      PillOption(value: 'cost', label: l10n.t('cost')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ModelDonut(
                  models: data.models,
                  dimension: _dimension,
                  l10n: l10n,
                  currency: state.currency,
                  rate: state.usdCny,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ModelKeyCard(data: data, state: state),
          const SizedBox(height: 14),
          _TopExpensiveCard(data: data, state: state),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: l10n.t('tokenBreakdown')),
                const SizedBox(height: 10),
                _TokenTiles(totals: totals, l10n: l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.totals, required this.state});

  final Totals totals;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final items = [
      KpiCard(
        label: l10n.t('totalCost'),
        value: fmtMoney(
          totals.totalCostUsd,
          currency: state.currency,
          rate: state.usdCny,
        ),
        color: colors.amber,
        valueColor: colors.amber,
        icon: Icons.payments_outlined,
      ),
      KpiCard(
        label: l10n.t('totalRequests'),
        value: fmtInt(totals.requestCount),
        color: colors.blue,
        icon: Icons.call_made_rounded,
      ),
      KpiCard(
        label: l10n.t('totalTokens'),
        value: fmtTokens(totals.totalTokens),
        color: colors.primary,
        icon: Icons.auto_awesome_rounded,
      ),
      KpiCard(
        label: l10n.t('hitRate'),
        value: '${totals.hitRate.toStringAsFixed(1)}%',
        color: colors.green,
        valueColor: colors.green,
        icon: Icons.bolt_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items) SizedBox(width: width, child: item),
          ],
        );
      },
    );
  }
}

class _TokenTiles extends StatelessWidget {
  const _TokenTiles({required this.totals, required this.l10n});

  final Totals totals;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = [
      (l10n.t('inputTokens'), totals.uncachedInputTokens, colors.blue),
      (l10n.t('outputTokens'), totals.totalOutputTokens, colors.green),
      (l10n.t('reasoningTokens'), totals.totalReasoningTokens, colors.purple),
      (l10n.t('cacheReadTokens'), totals.cacheHitTokens, colors.cyan),
      (l10n.t('cacheWriteTokens'), totals.cacheWriteTokens, colors.amber),
      (l10n.t('sessions'), totals.sessionCount, colors.primary),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              Container(
                width: width,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: item.$3,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            item.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: colors.text3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fmtTokens(item.$2),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.data, required this.state});

  final DashboardData data;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final previousRange = data.previousRange;
    if (previousRange == null) return const SizedBox.shrink();
    final previous = data.previousTotals;
    final current = data.totals;
    final label = switch (previousRange) {
      'yesterday' => l10n.t('yesterday'),
      'prev7d' => l10n.t('prev7d'),
      'prev30d' => l10n.t('prev30d'),
      _ => l10n.t('previousPeriod'),
    };
    final hasPrevious =
        previous.requestCount > 0 ||
        previous.totalTokens > 0 ||
        previous.totalCostUsd > 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: l10n.t('vsPrevious'), subtitle: label),
          const SizedBox(height: 8),
          _ComparisonHeader(l10n: l10n),
          const SizedBox(height: 4),
          _ComparisonRow(
            label: l10n.t('totalCost'),
            current: fmtMoney(
              current.totalCostUsd,
              currency: state.currency,
              rate: state.usdCny,
            ),
            previous: hasPrevious
                ? fmtMoney(
                    previous.totalCostUsd,
                    currency: state.currency,
                    rate: state.usdCny,
                  )
                : '—',
            delta: _delta(current.totalCostUsd, previous.totalCostUsd),
            highlightCost: true,
            colors: colors,
            l10n: l10n,
          ),
          Divider(height: 12, color: colors.border),
          _ComparisonRow(
            label: l10n.t('totalTokens'),
            current: fmtTokens(current.totalTokens),
            previous: hasPrevious ? fmtTokens(previous.totalTokens) : '—',
            delta: _delta(
              current.totalTokens.toDouble(),
              previous.totalTokens.toDouble(),
            ),
            colors: colors,
            l10n: l10n,
          ),
          Divider(height: 12, color: colors.border),
          _ComparisonRow(
            label: l10n.t('totalRequests'),
            current: fmtInt(current.requestCount),
            previous: hasPrevious ? fmtInt(previous.requestCount) : '—',
            delta: _delta(
              current.requestCount.toDouble(),
              previous.requestCount.toDouble(),
            ),
            colors: colors,
            l10n: l10n,
          ),
        ],
      ),
    );
  }

  static double? _delta(double current, double previous) {
    if (previous <= 0) return current > 0 ? null : 0;
    return (current - previous) / previous * 100;
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(fontSize: 9.5, color: colors.text3);
    return Row(
      children: [
        const SizedBox(width: 80),
        Expanded(child: Text(l10n.t('currentPeriod'), style: style)),
        Expanded(child: Text(l10n.t('previousPeriod'), style: style)),
        SizedBox(
          width: 54,
          child: Text(
            l10n.t('change'),
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.current,
    required this.previous,
    required this.delta,
    required this.colors,
    required this.l10n,
    this.highlightCost = false,
  });

  final String label;
  final String current;
  final String previous;
  final double? delta;
  final AppColors colors;
  final L10n l10n;
  final bool highlightCost;

  @override
  Widget build(BuildContext context) {
    final deltaColor = delta == null
        ? colors.text3
        : highlightCost
        ? (delta! > 0 ? colors.red : colors.green)
        : colors.text2;
    final deltaText = delta == null
        ? l10n.t('newValue')
        : '${delta! >= 0 ? '+' : ''}${delta!.toStringAsFixed(1)}%';
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: colors.text3),
          ),
        ),
        Expanded(
          child: Text(
            current,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: Text(
            previous,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: colors.text3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            deltaText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: deltaColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelKeyCard extends StatelessWidget {
  const _ModelKeyCard({required this.data, required this.state});

  final DashboardData data;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final entries = data.modelKeys;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.t('modelKeyUsage'),
            subtitle: l10n.t('modelKeyHint'),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            EmptyState(
              icon: Icons.grid_view_rounded,
              title: l10n.t('noData'),
              compact: true,
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) Divider(height: 12, color: colors.border),
              Row(
                children: [
                  ModelIcon(model: entries[i].model, size: 15),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[i].model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${_keyLabel(entries[i].keyId, state, l10n)} · '
                          '${fmtInt(entries[i].requestCount)} '
                          '${l10n.t('requestsInline')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5, color: colors.text3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtTokens(entries[i].totalTokens),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        fmtMoney(
                          entries[i].totalCostUsd,
                          currency: state.currency,
                          rate: state.usdCny,
                        ),
                        style: TextStyle(fontSize: 9.5, color: colors.amber),
                      ),
                    ],
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static String _keyLabel(String keyId, AppState state, L10n l10n) {
    if (keyId.isEmpty) return l10n.t('unassigned');
    final name = state.keyNames[keyId] ?? '';
    return name.isNotEmpty ? name : truncateMiddle(keyId, 18);
  }
}

class _TopExpensiveCard extends StatelessWidget {
  const _TopExpensiveCard({required this.data, required this.state});

  final DashboardData data;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final entries = data.topExpensive;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.t('topExpensive'),
            subtitle: l10n.t('topExpensiveHint'),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            EmptyState(
              icon: Icons.local_fire_department_outlined,
              title: l10n.t('noData'),
              compact: true,
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) Divider(height: 12, color: colors.border),
              Row(
                children: [
                  ModelIcon(model: entries[i].model, size: 15),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[i].model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${fmtDateTimeShort(entries[i].createdAt)} · '
                          '${_keyLabel(entries[i].keyId, state, l10n)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5, color: colors.text3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmtMoney(
                      entries[i].costUsd,
                      currency: state.currency,
                      rate: state.usdCny,
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.amber,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static String _keyLabel(String keyId, AppState state, L10n l10n) {
    if (keyId.isEmpty) return l10n.t('unassigned');
    final name = state.keyNames[keyId] ?? '';
    return name.isNotEmpty ? name : truncateMiddle(keyId, 18);
  }
}
