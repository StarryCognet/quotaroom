import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/quota_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final data = state.dashboard;
    if (data == null) {
      return state.loadingDashboard
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(
              icon: Icons.dashboard_outlined,
              title: l10n.t('noData'),
              subtitle: l10n.t('syncHint'),
              action: FilledButton(
                onPressed: () => state.refreshDashboard(forceQuota: true),
                child: Text(l10n.t('refresh')),
              ),
            );
    }
    final colors = context.colors;
    return RefreshIndicator(
      onRefresh: () async {
        await state.syncNow();
        await state.refreshFx();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final header = SectionHeader(
                title: l10n.t('homeTitle'),
                subtitle: l10n.t('followRange'),
              );
              final range = RangeSelector(
                value: state.dashboardRange,
                onChanged: (value) => state.setRange(value),
                l10n: l10n,
              );
              if (constraints.maxWidth >= 520) {
                return Row(
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    range,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 10),
                  range,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          QuotaSection(
            quota: data.quota,
            l10n: l10n,
            onRetry: () => state.refreshDashboard(forceQuota: true),
          ),
          const SizedBox(height: 18),
          SectionHeader(
            title: l10n.t('overviewTitle'),
            subtitle: l10n.t('followRange'),
          ),
          const SizedBox(height: 10),
          _KpiGrid(totals: data.totals, state: state),
          const SizedBox(height: 18),
          SectionHeader(
            title: l10n.t('todayTrend'),
            subtitle: l10n.t('hours24'),
          ),
          const SizedBox(height: 10),
          AppCard(
            child: TodayTrendChart(
              points: data.todayTrend,
              l10n: l10n,
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            AppCard(
              borderColor: colors.red.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: colors.text2),
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.refreshDashboard(forceQuota: true),
                    child: Text(l10n.t('retry')),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.totals, required this.state});

  final Totals totals;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final hitPercent = totals.totalInputTokens <= 0
        ? 0.0
        : totals.cacheHitTokens / totals.totalInputTokens * 100;
    final items = [
      KpiCard(
        label: l10n.t('hitRate'),
        value: '${totals.hitRate.toStringAsFixed(1)}%',
        sub: '${l10n.t('hit')} ${fmtTokens(totals.cacheHitTokens)} · ${l10n.t('miss')} ${fmtTokens(totals.uncachedInputTokens)}',
        color: colors.green,
        icon: Icons.bolt_rounded,
      ),
      KpiCard(
        label: l10n.t('hitAmount'),
        value: fmtTokens(totals.cacheHitTokens),
        sub: '${hitPercent.toStringAsFixed(1)}% ${l10n.t('pctOfInput')}',
        color: colors.cyan,
        icon: Icons.saved_search_rounded,
      ),
      KpiCard(
        label: l10n.t('totalTokens'),
        value: fmtTokens(totals.totalTokens),
        sub: l10n.t('inclCache'),
        color: colors.primary,
        icon: Icons.auto_awesome_rounded,
      ),
      KpiCard(
        label: l10n.t('totalRequests'),
        value: fmtInt(totals.requestCount),
        sub: '${fmtInt(totals.sessionCount)} ${l10n.t('sessions')}',
        color: colors.blue,
        icon: Icons.call_made_rounded,
      ),
      KpiCard(
        label: l10n.t('totalCost'),
        value: fmtMoney(
          totals.totalCostUsd,
          currency: state.currency,
          rate: state.usdCny,
        ),
        sub: l10n.t('currentRange'),
        color: colors.amber,
        icon: Icons.payments_outlined,
      ),
      KpiCard(
        label: l10n.t('sessions'),
        value: fmtInt(totals.sessionCount),
        sub: l10n.t('dedup'),
        color: const Color(0xFF64748B),
        icon: Icons.forum_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
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
