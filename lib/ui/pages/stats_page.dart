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
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.text3,
                            ),
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
