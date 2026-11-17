import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Container(
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
          ),
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

class _PagerFooter extends StatelessWidget {
  const _PagerFooter({
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
    required this.l10n,
  });

  final int page;
  final int totalPages;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Pager(
        page: page,
        totalPages: totalPages,
        onPrev: onPrev,
        onNext: onNext,
        l10n: l10n,
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
    final accountChanged = id != _accountId;
    final syncChanged = syncAt != null && syncAt != _lastSyncAt;
    if (accountChanged) {
      _accountId = id;
      _lastSyncAt = syncAt;
      _page = 1;
      _data = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } else if (syncChanged) {
      _lastSyncAt = syncAt;
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

  Future<void> _refresh() async {
    await context.read<AppState>().syncNow();
    if (!mounted) return;
    setState(() => _page = 1);
    await _load();
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
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 50),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.t('sessionsTotal', {'n': fmtInt(data.total)}),
              style: TextStyle(fontSize: 11, color: colors.text3),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              itemCount: data.records.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final session = data.records[index];
                return _SessionCard(
                  session: session,
                  keyName: state.keyNames[session.keyId] ?? '',
                  state: state,
                );
              },
            ),
          ),
        ),
        _PagerFooter(
          page: _page,
          totalPages: totalPages,
          onPrev: () => _goTo(_page - 1),
          onNext: () => _goTo(_page + 1),
          l10n: l10n,
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    keyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
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
              const SizedBox(width: 6),
              Text(
                last,
                style: TextStyle(fontSize: 10, color: colors.text3),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              StatChip(
                label: l10n.t('requests'),
                value: fmtInt(session.requestCount),
              ),
              StatChip(
                label: l10n.t('totalTokensShort'),
                value: fmtTokens(session.totalTokens),
              ),
              StatChip(
                label: l10n.t('input'),
                value: fmtTokens(session.totalInputTokens),
              ),
              StatChip(
                label: l10n.t('output'),
                value: fmtTokens(session.totalOutputTokens),
              ),
              StatChip(
                label: l10n.t('colReasoning'),
                value: fmtTokens(session.totalReasoningTokens),
              ),
              StatChip(
                label: l10n.t('totalCost'),
                value: fmtMoney(
                  session.totalCostUsd,
                  currency: state.currency,
                  rate: state.usdCny,
                ),
                highlight: colors.amber,
              ),
            ],
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
    final accountChanged = id != _accountId;
    final syncChanged = syncAt != null && syncAt != _lastSyncAt;
    if (accountChanged) {
      _accountId = id;
      _lastSyncAt = syncAt;
      _page = 1;
      _model = '';
      _data = null;
      _models = const [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } else if (syncChanged) {
      _lastSyncAt = syncAt;
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

  Future<void> _refresh() async {
    await context.read<AppState>().syncNow();
    if (!mounted) return;
    setState(() => _page = 1);
    await _load();
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
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: OutlinedButton.icon(
              onPressed: _pickModel,
              icon: const Icon(Icons.filter_list_rounded, size: 15),
              label: Text(
                _model.isEmpty ? l10n.t('allModels') : _model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 7,
                ),
                textStyle: const TextStyle(fontSize: 11.5),
              ),
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
              onRefresh: _refresh,
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
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              itemCount: data.records.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 7),
              itemBuilder: (context, index) {
                final record = data.records[index];
                return _RecordCard(
                  record: record,
                  state: state,
                  keyName: state.keyNames[record.keyId] ?? '',
                );
              },
            ),
          ),
        ),
        _PagerFooter(
          page: _page,
          totalPages: totalPages,
          onPrev: () => _goTo(_page - 1),
          onNext: () => _goTo(_page + 1),
          l10n: l10n,
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
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ModelIcon(model: record.model, size: 16),
              const SizedBox(width: 6),
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
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    plan,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: colors.text3,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                fmtDateTimeShort(record.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: colors.text3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  keyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: colors.text3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmtMoney(
                  record.costUsd,
                  currency: state.currency,
                  rate: state.usdCny,
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.amber,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              StatChip(
                label: l10n.t('input'),
                value: fmtTokens(record.inputTokens),
              ),
              StatChip(
                label: l10n.t('output'),
                value: fmtTokens(record.outputTokens),
              ),
              StatChip(
                label: l10n.t('colReasoning'),
                value: fmtTokens(record.reasoningTokens),
              ),
              StatChip(
                label: l10n.t('cacheReadTokens'),
                value: fmtTokens(record.cacheReadTokens),
              ),
              StatChip(
                label: l10n.t('cacheWriteTokens'),
                value: fmtTokens(record.cacheWriteTokens),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
