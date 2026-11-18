import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../data/usage_repository.dart';
import '../../state/app_state.dart';
import '../../state/records_navigation.dart';
import '../prism/app_glyphs.dart';
import 'charts.dart';
import 'common.dart';

Future<void> showModelDetail(
  BuildContext context,
  AppState state,
  String model,
) {
  return showFloatingDialog<void>(
    context: context,
    child: _ModelDetailSheet(state: state, model: model),
  );
}

Future<void> showSessionDetail(
  BuildContext context,
  AppState state,
  SessionStat session,
) {
  return showFloatingDialog<void>(
    context: context,
    child: _SessionDetailSheet(state: state, session: session),
  );
}

class _ModelDetailData {
  const _ModelDetailData({
    required this.totals,
    required this.trend,
    required this.keys,
    required this.records,
  });

  final Totals totals;
  final List<DailyStat> trend;
  final List<ModelKeyStat> keys;
  final List<UsageRecord> records;
}

class _ModelDetailSheet extends StatefulWidget {
  const _ModelDetailSheet({required this.state, required this.model});

  final AppState state;
  final String model;

  @override
  State<_ModelDetailSheet> createState() => _ModelDetailSheetState();
}

class _ModelDetailSheetState extends State<_ModelDetailSheet> {
  late final Future<_ModelDetailData?> _future = _load();

  Future<_ModelDetailData?> _load() async {
    final account = widget.state.activeAccount;
    if (account == null) return null;
    final repo = widget.state.usageRepo;
    final period = widget.state.dashboardRange;
    final totals = await repo.totalsBetween(
      account.id,
      fromMs: UsageRepository.fromMsForPeriod(period),
      model: widget.model,
    );
    final daily = await repo.modelDailyStats(account.id, widget.model, 14);
    final keys = await repo.modelKeyStats(
      account.id,
      period,
      limit: 5,
      model: widget.model,
    );
    final records = await repo.recordsPage(
      account.id,
      pageSize: 6,
      model: widget.model,
    );
    return _ModelDetailData(
      totals: totals,
      trend: AppState.fillDays(daily, 14),
      keys: keys,
      records: records.records,
    );
  }

  void _openAll() {
    Navigator.of(context).pop();
    widget.state.navigateRecords(
      RecordsNavigationRequest(tabIndex: 1, model: widget.model),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = widget.state.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          decoration: ShapeDecoration(
            color: scheme.surface,
            shape: AppShape.all(AppCorner.xl),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: FutureBuilder<_ModelDetailData?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: ActivityIndicator(size: 24)),
                );
              }
              if (snapshot.hasError) {
                return _DetailError(
                  message: '${l10n.t('loadFailed')}: ${snapshot.error}',
                  closeLabel: l10n.t('close'),
                  onClose: () => Navigator.of(context).pop(),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return _DetailError(
                  message: l10n.t('noData'),
                  closeLabel: l10n.t('close'),
                  onClose: () => Navigator.of(context).pop(),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailHeader(
                        glyph: AppGlyphs.dataUsage,
                        icon: ModelIcon(model: widget.model, size: 22),
                        title: widget.model,
                        subtitle: l10n.t('modelDetail'),
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 14),
                      _DetailStats(
                        items: [
                          (
                            label: l10n.t('requests'),
                            value: fmtInt(data.totals.requestCount),
                          ),
                          (
                            label: l10n.t('totalTokensShort'),
                            value: fmtTokens(data.totals.totalTokens),
                          ),
                          (
                            label: l10n.t('totalCost'),
                            value: fmtMoney(
                              data.totals.totalCostUsd,
                              currency: widget.state.currency,
                              rate: widget.state.usdCny,
                            ),
                          ),
                          (
                            label: l10n.t('cacheHitRate'),
                            value: '${data.totals.hitRate.toStringAsFixed(1)}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SectionHeader(
                        title: l10n.t('usageTrend'),
                        subtitle: l10n.t('last14d'),
                      ),
                      const SizedBox(height: 8),
                      TrendLineChart(
                        days: data.trend,
                        l10n: l10n,
                        currency: widget.state.currency,
                        rate: widget.state.usdCny,
                        height: 180,
                      ),
                      if (data.keys.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        SectionHeader(title: l10n.t('topKeys')),
                        const SizedBox(height: 6),
                        for (final key in data.keys)
                          _KeyRow(
                            stat: key,
                            state: widget.state,
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.state.navigateRecords(
                                RecordsNavigationRequest(
                                  tabIndex: 1,
                                  model: widget.model,
                                  keyId: key.keyId,
                                  keyName:
                                      widget.state.keyNames[key.keyId] ?? '',
                                ),
                              );
                            },
                          ),
                      ],
                      if (data.records.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        SectionHeader(title: l10n.t('recentRecords')),
                        const SizedBox(height: 6),
                        for (final record in data.records)
                          _RecordRow(record: record, state: widget.state),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _openAll,
                        child: Text(l10n.t('viewAllRecords')),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SessionDetailSheet extends StatefulWidget {
  const _SessionDetailSheet({required this.state, required this.session});

  final AppState state;
  final SessionStat session;

  @override
  State<_SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends State<_SessionDetailSheet> {
  late final Future<List<UsageRecord>> _future = _load();

  Future<List<UsageRecord>> _load() async {
    final account = widget.state.activeAccount;
    if (account == null) return const [];
    final session = widget.session;
    final page = await widget.state.usageRepo.recordsPage(
      account.id,
      pageSize: 12,
      sessionId: session.sessionId.isEmpty ? null : session.sessionId,
      keyId: session.sessionId.isEmpty ? session.keyId : null,
    );
    return page.records;
  }

  void _filterRecords() {
    Navigator.of(context).pop();
    final session = widget.session;
    widget.state.navigateRecords(
      RecordsNavigationRequest(
        tabIndex: 1,
        query: session.sessionId.isEmpty ? session.keyId : session.sessionId,
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    BannerHost.maybeOf(context)?.show(
      widget.state.l10n.t('copiedToClipboard'),
      level: BannerLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = widget.state.l10n;
    final session = widget.session;
    final keyName = widget.state.keyNames[session.keyId] ?? '';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          decoration: ShapeDecoration(
            color: scheme.surface,
            shape: AppShape.all(AppCorner.xl),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    glyph: AppGlyphs.requests,
                    title: session.sessionId.isEmpty
                        ? l10n.t('unassigned')
                        : truncateMiddle(session.sessionId, 38),
                    subtitle: l10n.t('sessionDetail'),
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 12),
                  _CopyLine(
                    label: l10n.t('sessionId'),
                    value: session.sessionId.isEmpty
                        ? l10n.t('unassigned')
                        : session.sessionId,
                    onCopy: session.sessionId.isEmpty
                        ? null
                        : () => _copy(session.sessionId),
                  ),
                  _CopyLine(
                    label: l10n.t('keyUsage'),
                    value: keyName.isNotEmpty
                        ? keyName
                        : (session.keyId.isEmpty
                              ? l10n.t('unassigned')
                              : session.keyId),
                    onCopy: session.keyId.isEmpty
                        ? null
                        : () => _copy(session.keyId),
                  ),
                  const SizedBox(height: 14),
                  _DetailStats(
                    items: [
                      (
                        label: l10n.t('requests'),
                        value: fmtInt(session.requestCount),
                      ),
                      (
                        label: l10n.t('totalTokensShort'),
                        value: fmtTokens(session.totalTokens),
                      ),
                      (
                        label: l10n.t('totalCost'),
                        value: fmtMoney(
                          session.totalCostUsd,
                          currency: widget.state.currency,
                          rate: widget.state.usdCny,
                        ),
                      ),
                      (
                        label: l10n.t('cacheHitRate'),
                        value:
                            '${(session.totalInputTokens <= 0 ? 0 : (session.totalInputTokens - session.uncachedInputTokens) / session.totalInputTokens * 100).toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SectionHeader(title: l10n.t('recentRecords')),
                  const SizedBox(height: 6),
                  FutureBuilder<List<UsageRecord>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: ActivityIndicator(size: 22)),
                        );
                      }
                      final records = snapshot.data ?? const <UsageRecord>[];
                      if (records.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            l10n.t('noData'),
                            textAlign: TextAlign.center,
                            style: AppTextStyle.caption2
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          for (final record in records)
                            _RecordRow(record: record, state: widget.state),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _filterRecords,
                    child: Text(l10n.t('filterInRecords')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.glyph,
    this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final Glyph glyph;
  final Widget? icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: ShapeDecoration(
            color: scheme.primaryContainer,
            shape: AppShape.all(AppCorner.sm),
          ),
          child: Center(
            child:
                icon ??
                GlyphIcon(glyph, size: 21, color: scheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.headline
                    .of(context, emphasized: true)
                    .copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          tooltip: 'Close',
          icon: const GlyphIcon(AppGlyphs.close, size: 18),
        ),
      ],
    );
  }
}

class _DetailStats extends StatelessWidget {
  const _DetailStats({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            width: 132,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHigh,
              shape: AppShape.all(AppCorner.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
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
            ),
          ),
      ],
    );
  }
}

class _CopyLine extends StatelessWidget {
  const _CopyLine({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurface, fontFamily: 'monospace'),
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              tooltip: 'Copy',
              icon: const GlyphIcon(AppGlyphs.copy, size: 15),
            ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.stat, required this.state, required this.onTap});

  final ModelKeyStat stat;
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final name = state.keyNames[stat.keyId] ?? '';
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(AppCorner.md),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      onPressed: onTap,
      child: Row(
        children: [
          GlyphIcon(AppGlyphs.key, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name.isEmpty
                  ? (stat.keyId.isEmpty
                        ? state.l10n.t('unassigned')
                        : truncateMiddle(stat.keyId, 30))
                  : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurface),
            ),
          ),
          Text(
            fmtTokens(stat.totalTokens),
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 13,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.state});

  final UsageRecord record;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = state.l10n;
    final time = fmtRelative(
      record.createdAt.toLocal(),
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ModelIcon(model: record.model, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.model.isEmpty ? l10n.t('unassigned') : record.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                Text(
                  '${fmtTokens(record.totalTokens)} · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            fmtMoney(
              record.costUsd,
              currency: state.currency,
              rate: state.usdCny,
            ),
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: const Color(0xFFD97706)),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({
    required this.message,
    required this.closeLabel,
    required this.onClose,
  });

  final String message;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onClose, child: Text(closeLabel)),
        ],
      ),
    );
  }
}
