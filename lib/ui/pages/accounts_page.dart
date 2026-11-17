import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../login/login_page.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    return RefreshIndicator(
      onRefresh: () async {
        await state.syncNow();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(
                title: l10n.t('accountsTab'),
                subtitle: l10n.t('accountsCount', {'n': state.accounts.length}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _openLogin(context),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: Text(
                l10n.t('addAccount'),
                style: const TextStyle(fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < state.accounts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _AccountCard(
            account: state.accounts[i],
            index: i,
            state: state,
          ),
        ],
        if (state.settings.showAccountsPanel && state.overviews.isNotEmpty) ...[
          const SizedBox(height: 14),
          _OverviewSummary(state: state),
        ],
        const SizedBox(height: 14),
        Text(
          l10n.t('addUserTip'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: colors.text3, height: 1.5),
        ),
      ],
      ),
    );
  }

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginPage(asRoute: true),
      ),
    );
  }
}

class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
    final colors = context.colors;
    var requests = 0;
    var input = 0;
    var output = 0;
    var reasoning = 0;
    var cost = 0.0;
    for (final overview in state.overviews) {
      requests += overview.today.requestCount;
      input += overview.today.totalInputTokens;
      output += overview.today.totalOutputTokens;
      reasoning += overview.today.totalReasoningTokens;
      cost += overview.today.totalCostUsd;
    }
    final totals = Totals(
      requestCount: requests,
      totalInputTokens: input,
      totalOutputTokens: output,
      totalReasoningTokens: reasoning,
      totalCostUsd: cost,
    );
    final daily = _combineDaily(state.overviews, 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.t('accountOverview'),
          subtitle: l10n.t('todayShort'),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalReq'),
                    value: fmtInt(totals.requestCount),
                    color: colors.blue,
                    icon: Icons.call_made_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalTokens'),
                    value: fmtTokens(totals.totalTokens),
                    color: colors.primary,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalInput'),
                    value: fmtTokens(totals.totalInputTokens),
                    color: colors.cyan,
                    icon: Icons.login_rounded,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalCost'),
                    value: fmtMoney(
                      totals.totalCostUsd,
                      currency: state.currency,
                      rate: state.usdCny,
                    ),
                    color: colors.amber,
                    valueColor: colors.amber,
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: l10n.t('costTrend7d'),
                subtitle: l10n.t('d7'),
              ),
              const SizedBox(height: 10),
              TrendLineChart(
                days: daily,
                l10n: l10n,
                currency: state.currency,
                rate: state.usdCny,
                height: 180,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<DailyStat> _combineDaily(
    List<AccountOverview> overviews,
    int days,
  ) {
    final acc = <String, _DailyAcc>{};
    for (final overview in overviews) {
      for (final stat in overview.daily7) {
        acc.putIfAbsent(stat.date, () => _DailyAcc()).add(stat);
      }
    }
    final combined = acc.entries
        .map((entry) => entry.value.build(entry.key))
        .toList();
    return AppState.fillDays(combined, days);
  }
}

class _DailyAcc {
  int input = 0;
  int output = 0;
  int reasoning = 0;
  int hit = 0;
  int write = 0;
  int requests = 0;
  double cost = 0;

  void add(DailyStat stat) {
    input += stat.totalInputTokens;
    output += stat.totalOutputTokens;
    reasoning += stat.totalReasoningTokens;
    hit += stat.cacheHitTokens;
    write += stat.cacheWriteTokens;
    requests += stat.requestCount;
    cost += stat.totalCostUsd;
  }

  DailyStat build(String date) => DailyStat(
    date: date,
    totalInputTokens: input,
    uncachedInputTokens: input - hit - write < 0 ? 0 : input - hit - write,
    totalReasoningTokens: reasoning,
    cacheHitTokens: hit,
    cacheWriteTokens: write,
    totalOutputTokens: output,
    totalCostUsd: cost,
    requestCount: requests,
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.index,
    required this.state,
  });

  final Account account;
  final int index;
  final AppState state;

  static const List<Color> _palette = [
    Color(0xFF7C5CF6),
    Color(0xFF4F8EF7),
    Color(0xFF22C55E),
    Color(0xFFD97706),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
    final colors = context.colors;
    final color = _palette[index % _palette.length];
    final isActive = state.activeAccount?.id == account.id;
    AccountOverview? overview;
    for (final item in state.overviews) {
      if (item.account.id == account.id) {
        overview = item;
        break;
      }
    }
    final lastSync = overview?.lastSyncAt;
    final lastSyncText = fmtRelative(
      lastSync,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  account.name.isEmpty
                      ? '?'
                      : account.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: colors.text,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            text: l10n.t('active'),
                            color: colors.primary,
                            background: colors.primarySoft,
                          ),
                        ],
                        if (!account.hasToken) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            text: l10n.t('notLoggedInShort'),
                            color: colors.red,
                            background: colors.dangerSoft,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.hasToken
                          ? '${l10n.t('lastSync')} $lastSyncText · ${maskWorkspace(account.resolvedWorkspaceId ?? account.workspaceHint)}'
                          : l10n.t('loginRequired'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: colors.text3),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '',
                icon: Icon(Icons.more_horiz_rounded, color: colors.text3),
                onSelected: (value) => _onAction(context, value),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: _menuRow(
                      Icons.edit_outlined,
                      l10n.t('renameBtn'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'relogin',
                    child: _menuRow(
                      Icons.login_rounded,
                      l10n.t('relogin'),
                    ),
                  ),
                  if (account.hasToken)
                    PopupMenuItem(
                      value: 'logout',
                      child: _menuRow(
                        Icons.logout_rounded,
                        l10n.t('setLogout'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _menuRow(
                      Icons.delete_outline_rounded,
                      l10n.t('deleteUser'),
                      color: colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (account.hasToken) ...[
            const SizedBox(height: 12),
            if (overview?.quota?.success == true &&
                overview!.quota!.windows.isNotEmpty)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0;
                      i < overview.quota!.windows.length;
                      i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _MiniQuota(
                        window: overview.quota!.windows[i],
                        l10n: l10n,
                      ),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: colors.text3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      overview?.quota?.error ?? l10n.t('quotaNotReady'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: colors.text3),
                    ),
                  ),
                ],
              ),
            if (overview != null) ...[
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: l10n.t('requests'),
                      value: fmtInt(overview.today.requestCount),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: l10n.t('totalTokensShort'),
                      value: fmtTokens(overview.today.totalTokens),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: l10n.t('input'),
                      value: fmtTokens(overview.today.totalInputTokens),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: l10n.t('totalCost'),
                      value: fmtMoney(
                        overview.today.totalCostUsd,
                        currency: state.currency,
                        rate: state.usdCny,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Sparkline(
                values: [
                  for (final point in overview.todayTrend)
                    point.total.toDouble(),
                ],
                color: color,
                height: 28,
              ),
            ],
            if (!isActive) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _switchAccount(context),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: Text(l10n.t('switchTo')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _relogin(context),
              icon: const Icon(Icons.login_rounded, size: 16),
              label: Text(l10n.t('goLogin')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 9),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 9),
        Text(text, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }

  Future<void> _switchAccount(BuildContext context) async {
    final l10n = state.l10n;
    await state.switchAccount(account.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('switchedAccount'))),
    );
  }

  Future<void> _relogin(BuildContext context) async {
    if (state.activeAccount?.id != account.id) {
      await state.switchAccount(account.id);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginPage(asRoute: true, relogin: true),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, String action) async {
    final l10n = state.l10n;
    switch (action) {
      case 'rename':
        await _rename(context);
      case 'relogin':
        await _relogin(context);
      case 'logout':
        final confirmed = await _confirm(
          context,
          title: l10n.t('setLogout'),
          message: l10n.t('logoutUserConfirm', {'name': account.name}),
          confirmLabel: l10n.t('logout'),
          danger: true,
        );
        if (!confirmed || !context.mounted) return;
        await state.logoutAccount(account.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('loggedOut'))),
        );
        break;
      case 'delete':
        final confirmed = await _confirm(
          context,
          title: l10n.t('deleteUserTitle'),
          message: l10n.t('deleteUserConfirm', {'name': account.name}),
          confirmLabel: l10n.t('deleteUser'),
          danger: true,
        );
        if (!confirmed || !context.mounted) return;
        await state.deleteAccount(account.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('userDeleted'))),
        );
        break;
    }
  }

  Future<void> _rename(BuildContext context) async {
    final l10n = state.l10n;
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('renameTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: l10n.t('accountName'),
            hintText: l10n.t('accountNameHint'),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.t('save')),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await state.renameAccount(account.id, name.trim());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('userRenamed'))),
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final l10n = state.l10n;
    final colors = context.colors;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: colors.red)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MiniQuota extends StatelessWidget {
  const _MiniQuota({
    required this.window,
    required this.l10n,
  });

  final QuotaWindow window;
  final L10n l10n;

  String get _shortLabel => switch (window.label) {
    '5h Rolling' => '5h',
    'Weekly' => l10n.isZh ? '周' : 'Week',
    'Monthly' => l10n.isZh ? '月' : 'Month',
    _ => window.label,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final remaining = window.remaining;
    final healthColor = remaining < 20
        ? colors.red
        : (remaining < 50 ? colors.amber : colors.green);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: colors.text3),
              ),
            ),
            Text(
              '${window.used.toStringAsFixed(window.used % 1 == 0 ? 0 : 1)}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: healthColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (window.used / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: colors.muted,
            valueColor: AlwaysStoppedAnimation(healthColor),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9.5, color: colors.text3),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
