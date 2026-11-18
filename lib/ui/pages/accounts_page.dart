import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../prism/app_glyphs.dart';
import '../prism/prism_login_page.dart';
import '../prism/prism_route.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        context.appBarInset + 8,
        16,
        24 + context.bottomInset,
      ),
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
              icon: const GlyphIcon(AppGlyphs.addCircle, size: 17),
              label: Text(l10n.t('addAccount')),
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
            pageContext: context,
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
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant, height: 1.5),
        ),
      ],
    );
  }

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push(
      prismPageRoute<void>(builder: (_) => const PrismLoginPage(asRoute: true)),
    );
  }
}

class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = state.l10n;
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
                    color: const Color(0xFF4F8EF7),
                    icon: AppGlyphs.requests,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalTokens'),
                    value: fmtTokens(totals.totalTokens),
                    color: context.colorScheme.primary,
                    icon: AppGlyphs.dataUsage,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    label: l10n.t('todayTotalInput'),
                    value: fmtTokens(totals.totalInputTokens),
                    color: const Color(0xFF06B6D4),
                    icon: AppGlyphs.arrowDown,
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
                    color: const Color(0xFFD97706),
                    valueColor: const Color(0xFFD97706),
                    icon: AppGlyphs.star,
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
    required this.pageContext,
  });

  final Account account;
  final int index;
  final AppState state;
  final BuildContext pageContext;

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
    final scheme = context.colorScheme;
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
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: AppShape.all(AppCorner.sm),
                ),
                child: Text(
                  account.name.isEmpty
                      ? '?'
                      : account.name.substring(0, 1).toUpperCase(),
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: color),
                ),
              ),
              const SizedBox(width: 11),
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
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true)
                                .copyWith(color: scheme.onSurface),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            text: l10n.t('active'),
                            color: scheme.primary,
                            background: scheme.primaryContainer,
                          ),
                        ],
                        if (!account.hasToken) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            text: l10n.t('notLoggedInShort'),
                            color: scheme.error,
                            background: scheme.errorContainer,
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
                      style: AppTextStyle.caption2
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupAnchor(
                targetBuilder: (open) => IconButton(
                  onPressed: open,
                  icon: const GlyphIcon(AppGlyphs.more, size: 20),
                ),
                popupBuilder: (context) => PopupMenu(
                  items: [
                    PopupMenuItem(
                      label: l10n.t('renameBtn'),
                      glyph: AppGlyphs.edit,
                      onPressed: () => unawaited(_rename(pageContext)),
                    ),
                    PopupMenuItem(
                      label: l10n.t('relogin'),
                      glyph: AppGlyphs.key,
                      onPressed: () => unawaited(_relogin(pageContext)),
                    ),
                    if (account.hasToken)
                      PopupMenuItem(
                        label: l10n.t('setLogout'),
                        glyph: AppGlyphs.lock,
                        danger: true,
                        onPressed: () =>
                            unawaited(_onAction(pageContext, 'logout')),
                      ),
                    PopupMenuItem(
                      label: l10n.t('deleteUser'),
                      glyph: AppGlyphs.delete,
                      danger: true,
                      onPressed: () =>
                          unawaited(_onAction(pageContext, 'delete')),
                    ),
                  ],
                ),
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
                  for (var i = 0; i < overview.quota!.windows.length; i++) ...[
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
                  GlyphIcon(
                    AppGlyphs.info,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      overview?.quota?.error ?? l10n.t('quotaNotReady'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption2
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
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
                onPressed: () => unawaited(_switchAccount(pageContext)),
                icon: const GlyphIcon(AppGlyphs.swap, size: 16),
                label: Text(l10n.t('switchTo')),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => unawaited(_relogin(pageContext)),
              icon: const GlyphIcon(AppGlyphs.key, size: 16),
              label: Text(l10n.t('goLogin')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _switchAccount(BuildContext context) async {
    final l10n = state.l10n;
    await state.switchAccount(account.id);
    if (!context.mounted) return;
    BannerHost.maybeOf(context)
        ?.show(l10n.t('switchedAccount'), level: BannerLevel.success);
  }

  Future<void> _relogin(BuildContext context) async {
    if (state.activeAccount?.id != account.id) {
      await state.switchAccount(account.id);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      prismPageRoute<void>(
        builder: (_) => const PrismLoginPage(asRoute: true, relogin: true),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, String action) async {
    final l10n = state.l10n;
    switch (action) {
      case 'logout':
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.t('setLogout'),
          message: l10n.t('logoutUserConfirm', {'name': account.name}),
          cancelLabel: l10n.t('cancel'),
          confirmLabel: l10n.t('logout'),
          danger: true,
        );
        if (!confirmed || !context.mounted) return;
        await state.logoutAccount(account.id);
        if (!context.mounted) return;
        BannerHost.maybeOf(context)
            ?.show(l10n.t('loggedOut'), level: BannerLevel.success);
        break;
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.t('deleteUserTitle'),
          message: l10n.t('deleteUserConfirm', {'name': account.name}),
          cancelLabel: l10n.t('cancel'),
          confirmLabel: l10n.t('deleteUser'),
          danger: true,
        );
        if (!confirmed || !context.mounted) return;
        await state.deleteAccount(account.id);
        if (!context.mounted) return;
        BannerHost.maybeOf(context)
            ?.show(l10n.t('userDeleted'), level: BannerLevel.success);
        break;
    }
  }

  Future<void> _rename(BuildContext context) async {
    final l10n = state.l10n;
    final controller = TextEditingController(text: account.name);
    final name = await showFloatingDialog<String>(
      context: context,
      child: AlertDialog(
        title: l10n.t('renameTitle'),
        hasFields: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.t('save')),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(hintText: l10n.t('accountNameHint')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await state.renameAccount(account.id, name.trim());
    if (!context.mounted) return;
    BannerHost.maybeOf(context)
        ?.show(l10n.t('userRenamed'), level: BannerLevel.success);
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
      decoration: ShapeDecoration(
        color: background,
        shape: AppShape.all(AppCorner.xs),
      ),
      child: Text(
        text,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: color),
      ),
    );
  }
}

class _MiniQuota extends StatelessWidget {
  const _MiniQuota({required this.window, required this.l10n});

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
    final scheme = context.colorScheme;
    final remaining = window.remaining;
    final healthColor = remaining < 20
        ? scheme.error
        : (remaining < 50 ? const Color(0xFFD97706) : const Color(0xFF16A34A));
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
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              '${window.used.toStringAsFixed(window.used % 1 == 0 ? 0 : 1)}%',
              style: AppTextStyle.caption2
                  .of(context, emphasized: true)
                  .copyWith(
                    color: healthColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _MiniProgress(value: window.used / 100, color: healthColor),
      ],
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: ShapeDecoration(
        color: context.colorScheme.outlineVariant.withValues(alpha: 0.35),
        shape: AppShape.full,
      ),
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
              child: const SizedBox(height: 4),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption2
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context, emphasized: true)
              .copyWith(
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      ],
    );
  }
}
