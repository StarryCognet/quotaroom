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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
        children: [
          RangeSelector(
            value: state.dashboardRange,
            onChanged: (value) => state.setRange(value),
            l10n: l10n,
          ),
          if (state.progress.running) ...[
            const SizedBox(height: 10),
            SyncBanner(progress: state.progress, l10n: l10n),
            if (state.progress.mode == 'full')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.t('firstSyncHint'),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.text3,
                    height: 1.4,
                  ),
                ),
              ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              borderColor: colors.red.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colors.red,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.text2),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        state.refreshDashboard(forceQuota: true),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(
                      l10n.t('retry'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          QuotaSection(
            quota: data.quota,
            l10n: l10n,
            onRetry: () => state.refreshDashboard(forceQuota: true),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.t('overviewTitle'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          _KpiGrid(totals: data.totals, state: state),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.t('todayTrend'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Text(
                      l10n.t('hours24'),
                      style: TextStyle(fontSize: 11, color: colors.text3),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TodayTrendChart(
                  points: data.todayTrend,
                  l10n: l10n,
                  height: 185,
                ),
              ],
            ),
          ),
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
    final items = [
      KpiCard(
        label: l10n.t('hitRate'),
        value: '${totals.hitRate.toStringAsFixed(1)}%',
        sub: '${l10n.t('hit')} ${fmtTokens(totals.cacheHitTokens)} · ${l10n.t('miss')} ${fmtTokens(totals.uncachedInputTokens)}',
        color: colors.green,
        valueColor: colors.green,
        icon: Icons.bolt_rounded,
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
        valueColor: colors.amber,
        icon: Icons.payments_outlined,
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
