import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pager.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SectionHeader(title: l10n.t('recordsPage')),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              labelColor: colors.primary,
              unselectedLabelColor: colors.text3,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(height: 36, text: l10n.t('sessionUsage')),
                Tab(height: 36, text: l10n.t('usageRecords')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(
            child: TabBarView(
              children: [_SessionsTab(), _RecordsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionsTab extends StatefulWidget {
  const _SessionsTab();

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  static const int _pageSize = 10;

  int? _accountId;
  DateTime? _lastSyncAt;
  int _page = 1;
  SessionsPageResult? _data;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final id = state.activeAccount?.id;
    final syncAt = state.dashboard?.sync.lastSyncAt;
    final syncChanged = syncAt != null && syncAt != _lastSyncAt;
    if (id != _accountId || syncChanged) {
      _accountId = id;
      _lastSyncAt = syncAt;
      _page = 1;
      _data = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await state.usageRepo.sessionsPage(
        account.id,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(
        message: '${l10n.t('loadFailed')}: $_error',
        retryLabel: l10n.t('retry'),
        onRetry: _load,
      );
    }
    final data = _data;
    if (data == null || data.records.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 60),
            EmptyState(
              icon: Icons.forum_outlined,
              title: l10n.t('emptySessions'),
              subtitle: l10n.t('syncHint'),
            ),
          ],
        ),
      );
    }
    final totalPages = (data.total / _pageSize).ceil().clamp(1, 1 << 30).toInt();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        itemCount: data.records.length + 2,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              l10n.t('sessionsTotal', {'n': fmtInt(data.total)}),
              style: TextStyle(fontSize: 11, color: colors.text3),
            );
          }
          if (index == data.records.length + 1) {
            return Pager(
              page: _page,
              totalPages: totalPages,
              onPrev: () => _goTo(_page - 1),
              onNext: () => _goTo(_page + 1),
              l10n: l10n,
            );
          }
          final session = data.records[index - 1];
          return _SessionCard(
            session: session,
            keyName: state.keyNames[session.keyId] ?? '',
            state: state,
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.keyName,
    required this.state,
  });

  final SessionStat session;
  final String keyName;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final keyLabel = session.keyId.isEmpty
        ? l10n.t('unassigned')
        : (keyName.isNotEmpty ? keyName : truncateMiddle(session.keyId, 18));
    final sessionLabel = session.sessionId.isEmpty
        ? l10n.t('unassigned')
        : truncateMiddle(session.sessionId, 22);
    final last = fmtRelative(
      session.lastAt,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  keyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sessionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                last,
                style: TextStyle(fontSize: 10.5, color: colors.text3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const columns = 2;
              final width = (constraints.maxWidth - 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Metric(
                    width: width,
                    label: l10n.t('requests'),
                    value: fmtInt(session.requestCount),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('totalTokensShort'),
                    value: fmtTokens(session.totalTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('input'),
                    value: fmtTokens(session.totalInputTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('output'),
                    value: fmtTokens(session.totalOutputTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('colReasoning'),
                    value: fmtTokens(session.totalReasoningTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('totalCost'),
                    value: fmtMoney(
                      session.totalCostUsd,
                      currency: state.currency,
                      rate: state.usdCny,
                    ),
                    highlight: colors.amber,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecordsTab extends StatefulWidget {
  const _RecordsTab();

  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  static const int _pageSize = 15;

  int? _accountId;
  DateTime? _lastSyncAt;
  int _page = 1;
  String _model = '';
  List<String> _models = const [];
  RecordsPageResult? _data;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final id = state.activeAccount?.id;
    final syncAt = state.dashboard?.sync.lastSyncAt;
    final syncChanged = syncAt != null && syncAt != _lastSyncAt;
    if (id != _accountId || syncChanged) {
      _accountId = id;
      _lastSyncAt = syncAt;
      _page = 1;
      _model = '';
      _data = null;
      _models = const [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await state.usageRepo.models(account.id);
      final data = await state.usageRepo.recordsPage(
        account.id,
        page: _page,
        pageSize: _pageSize,
        model: _model.isEmpty ? null : _model,
      );
      if (!mounted) return;
      setState(() {
        _models = models;
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _load();
  }

  Future<void> _pickModel() async {
    final l10n = context.read<AppState>().l10n;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.6,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                ListTile(
                  title: Text(
                    l10n.t('allModels'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  trailing: _model.isEmpty
                      ? Icon(Icons.check_rounded, color: colors.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(''),
                ),
                const Divider(height: 1),
                for (final model in _models)
                  ListTile(
                    leading: ModelIcon(model: model, size: 20),
                    title: Text(
                      model,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface,
                      ),
                    ),
                    trailing: _model == model
                        ? Icon(Icons.check_rounded, color: colors.primary)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(model),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _model = selected;
      _page = 1;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(
        message: '${l10n.t('loadFailed')}: $_error',
        retryLabel: l10n.t('retry'),
        onRetry: _load,
      );
    }
    final data = _data;
    final filterRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data == null
                  ? ''
                  : l10n.t('recordsTotal', {'n': fmtInt(data.total)}),
              style: TextStyle(fontSize: 11, color: colors.text3),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickModel,
            icon: const Icon(Icons.filter_list_rounded, size: 15),
            label: Text(
              _model.isEmpty ? l10n.t('allModels') : _model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
    if (data == null || data.records.isEmpty) {
      return Column(
        children: [
          filterRow,
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.t('emptyRecords'),
                    subtitle: l10n.t('syncHint'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final totalPages = (data.total / _pageSize).ceil().clamp(1, 1 << 30).toInt();
    return Column(
      children: [
        filterRow,
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
              itemCount: data.records.length + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == data.records.length) {
                  return Pager(
                    page: _page,
                    totalPages: totalPages,
                    onPrev: () => _goTo(_page - 1),
                    onNext: () => _goTo(_page + 1),
                    l10n: l10n,
                  );
                }
                return _RecordCard(
                  record: data.records[index],
                  state: state,
                  keyName: state.keyNames[data.records[index].keyId] ?? '',
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.state,
    required this.keyName,
  });

  final UsageRecord record;
  final AppState state;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = state.l10n;
    final plan = planBadge(record.plan);
    final keyLabel = record.keyId.isEmpty
        ? l10n.t('unassigned')
        : (keyName.isNotEmpty ? keyName : truncateMiddle(record.keyId, 16));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ModelIcon(model: record.model, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  record.model.isEmpty ? '—' : record.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              if (plan.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.muted,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    plan,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: colors.text3,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                fmtDateTime(record.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: colors.text3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            keyLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: colors.text3),
          ),
          const SizedBox(height: 9),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 3 : 2;
              final width =
                  (constraints.maxWidth - 8 * (columns - 1)) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Metric(
                    width: width,
                    label: l10n.t('input'),
                    value: fmtTokens(record.inputTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('output'),
                    value: fmtTokens(record.outputTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('colReasoning'),
                    value: fmtTokens(record.reasoningTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('cacheReadTokens'),
                    value: fmtTokens(record.cacheReadTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('cacheWriteTokens'),
                    value: fmtTokens(record.cacheWriteTokens),
                  ),
                  _Metric(
                    width: width,
                    label: l10n.t('totalCost'),
                    value: fmtMoney(
                      record.costUsd,
                      currency: state.currency,
                      rate: state.usdCny,
                    ),
                    highlight: colors.amber,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.label,
    required this.value,
    this.highlight,
  });

  final double width;
  final String label;
  final String value;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: colors.text3),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: highlight ?? colors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
