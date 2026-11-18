import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';

class KeyFilterSelection {
  const KeyFilterSelection({required this.keyId, required this.keyName});

  final String keyId;
  final String keyName;
}

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final ValueNotifier<KeyFilterSelection?> _keyFilter = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _keyFilter.dispose();
    super.dispose();
  }

  void _selectKey(String keyId, String keyName) {
    _keyFilter.value = KeyFilterSelection(keyId: keyId, keyName: keyName);
    _tabs.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    return Column(
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
              controller: _tabs,
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
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(height: 36, text: l10n.t('sessionUsage')),
                Tab(height: 36, text: l10n.t('usageRecords')),
                Tab(height: 36, text: l10n.t('keyUsage')),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const _SessionsTab(),
              _RecordsTab(keyFilter: _keyFilter),
              _KeyTab(onSelectKey: _selectKey),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfiniteFooter extends StatelessWidget {
  const _InfiniteFooter({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onRetry,
    required this.l10n,
  });

  final bool loading;
  final String? error;
  final bool hasMore;
  final VoidCallback onRetry;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(
              l10n.t('retry'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            l10n.t('allLoaded'),
            style: TextStyle(fontSize: 10.5, color: colors.text3),
          ),
        ),
      );
    }
    return const SizedBox(height: 28);
  }
}

class _SessionsTab extends StatefulWidget {
  const _SessionsTab();

  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab> {
  static const int _pageSize = 10;

  final ScrollController _scroll = ScrollController();
  int? _accountId;
  DateTime? _lastSyncAt;
  int _page = 0;
  int _total = 0;
  final List<SessionStat> _items = [];
  int _requestId = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

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
      _page = 0;
      _total = 0;
      _items.clear();
      _loading = true;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    } else if (syncChanged) {
      _lastSyncAt = syncAt;
      final atTop = !_scroll.hasClients || _scroll.offset <= 120;
      if (_items.isEmpty || atTop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reload();
        });
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || _error != null) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await _fetchPage(1, reset: true);
  }

  void _loadMore() {
    if (_loading || _loadingMore || _error != null) return;
    if (_total > 0 && _items.length >= _total) return;
    _fetchPage(_page + 1, reset: false);
  }

  void _retry() {
    setState(() => _error = null);
    _loadMore();
  }

  Future<void> _fetchPage(int page, {required bool reset}) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final requestId = ++_requestId;
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final data = await state.usageRepo.sessionsPage(
        account.id,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted || requestId != _requestId) return;
      if (state.activeAccount?.id != account.id) return;
      setState(() {
        if (reset) {
          _items.clear();
          _page = 0;
        }
        _items.addAll(data.records);
        _page = page;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    await context.read<AppState>().syncNow();
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    if (_loading && _items.isEmpty) {
      return const ListSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return ErrorState(
        message: '${l10n.t('loadFailed')}: $_error',
        retryLabel: l10n.t('retry'),
        onRetry: _reload,
      );
    }
    if (_items.isEmpty) {
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.t('sessionsTotal', {'n': fmtInt(_total)}),
              style: TextStyle(fontSize: 11, color: colors.text3),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              itemCount: _items.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return _InfiniteFooter(
                    loading: _loadingMore,
                    error: _error,
                    hasMore: _items.length < _total,
                    onRetry: _retry,
                    l10n: l10n,
                  );
                }
                final session = _items[index];
                return _SessionCard(
                  session: session,
                  keyName: state.keyNames[session.keyId] ?? '',
                  state: state,
                );
              },
            ),
          ),
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
              Text(last, style: TextStyle(fontSize: 10, color: colors.text3)),
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
  const _RecordsTab({required this.keyFilter});

  final ValueNotifier<KeyFilterSelection?> keyFilter;

  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  static const int _pageSize = 15;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  int? _accountId;
  DateTime? _lastSyncAt;
  int _page = 0;
  int _total = 0;
  String _model = '';
  List<String> _models = const [];
  final List<UsageRecord> _items = [];
  int _requestId = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  int? _days;
  KeyFilterSelection? _selectedKey;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _selectedKey = widget.keyFilter.value;
    widget.keyFilter.addListener(_onKeyFilterChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    widget.keyFilter.removeListener(_onKeyFilterChanged);
    super.dispose();
  }

  void _onKeyFilterChanged() {
    final value = widget.keyFilter.value;
    if (value == _selectedKey) return;
    setState(() {
      _selectedKey = value;
      _page = 0;
      _total = 0;
      _items.clear();
    });
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final id = state.activeAccount?.id;
    final syncAt = state.dashboard?.sync.lastSyncAt;
    final accountChanged = id != _accountId;
    final syncChanged = syncAt != null && syncAt != _lastSyncAt;
    if (accountChanged) {
      // The first build may already carry a key drill-down selected from the
      // Key tab. Only a real account switch should clear it.
      final firstBuild = _accountId == null;
      _accountId = id;
      _lastSyncAt = syncAt;
      _page = 0;
      _total = 0;
      _model = '';
      _models = const [];
      _items.clear();
      _query = '';
      _days = null;
      if (!firstBuild) {
        _selectedKey = null;
        if (widget.keyFilter.value != null) widget.keyFilter.value = null;
      }
      _search.clear();
      _loading = true;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    } else if (syncChanged) {
      _lastSyncAt = syncAt;
      final atTop = !_scroll.hasClients || _scroll.offset <= 120;
      if (_items.isEmpty || atTop) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reload();
        });
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || _error != null) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    await _fetchPage(1, reset: true);
  }

  void _loadMore() {
    if (_loading || _loadingMore || _error != null) return;
    if (_total > 0 && _items.length >= _total) return;
    _fetchPage(_page + 1, reset: false);
  }

  void _retry() {
    setState(() => _error = null);
    _loadMore();
  }

  Future<void> _fetchPage(int page, {required bool reset}) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final requestId = ++_requestId;
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      List<String>? freshModels;
      if (reset) {
        freshModels = await state.usageRepo.models(account.id);
      }
      final data = await state.usageRepo.recordsPage(
        account.id,
        page: page,
        pageSize: _pageSize,
        model: _model.isEmpty ? null : _model,
        days: _days,
        keyId: _selectedKey?.keyId,
        query: _query.isEmpty ? null : _query,
      );
      if (!mounted || requestId != _requestId) return;
      if (state.activeAccount?.id != account.id) return;
      setState(() {
        if (reset) {
          _items.clear();
          _page = 0;
          if (freshModels != null) _models = freshModels;
        }
        _items.addAll(data.records);
        _page = page;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    await context.read<AppState>().syncNow();
    if (!mounted) return;
    await _reload();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _query) return;
      setState(() {
        _query = next;
        _page = 0;
        _total = 0;
        _items.clear();
      });
      _reload();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    if (_query.isEmpty) return;
    setState(() {
      _query = '';
      _page = 0;
      _total = 0;
      _items.clear();
    });
    _reload();
  }

  void _setDays(String value) {
    final days = value == 'all' ? null : int.tryParse(value);
    if (days == _days) return;
    setState(() {
      _days = days;
      _page = 0;
      _total = 0;
      _items.clear();
    });
    _reload();
  }

  void _clearKeyFilter() {
    widget.keyFilter.value = null;
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
                      style: TextStyle(fontSize: 13, color: colors.onSurface),
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
      _page = 0;
      _total = 0;
      _items.clear();
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    if (_loading && _items.isEmpty) {
      return const ListSkeleton();
    }
    if (_error != null && _items.isEmpty) {
      return ErrorState(
        message: '${l10n.t('loadFailed')}: $_error',
        retryLabel: l10n.t('retry'),
        onRetry: _reload,
      );
    }
    final header = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: l10n.t('searchHint'),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 17),
                      onPressed: _clearSearch,
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('recordsTotal', {'n': fmtInt(_total)}),
                  style: TextStyle(fontSize: 11, color: colors.text3),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillSelector<String>(
              compact: true,
              value: _days == null ? 'all' : _days.toString(),
              onChanged: _setDays,
              options: [
                PillOption(value: '7', label: l10n.t('d7')),
                PillOption(value: '30', label: l10n.t('d30')),
                PillOption(value: 'all', label: l10n.t('all')),
              ],
            ),
          ),
        ),
        if (_selectedKey != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                visualDensity: VisualDensity.compact,
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Text(
                    _selectedKey!.keyName.isEmpty
                        ? l10n.t('unassigned')
                        : _selectedKey!.keyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onDeleted: _clearKeyFilter,
              ),
            ),
          ),
      ],
    );
    if (_items.isEmpty) {
      return Column(
        children: [
          header,
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 30),
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
    return Column(
      children: [
        header,
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: _items.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 7),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  return _InfiniteFooter(
                    loading: _loadingMore,
                    error: _error,
                    hasMore: _items.length < _total,
                    onRetry: _retry,
                    l10n: l10n,
                  );
                }
                final record = _items[index];
                return _RecordCard(
                  record: record,
                  state: state,
                  keyName: state.keyNames[record.keyId] ?? '',
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

class _KeyTab extends StatefulWidget {
  const _KeyTab({required this.onSelectKey});

  final void Function(String keyId, String keyName) onSelectKey;

  @override
  State<_KeyTab> createState() => _KeyTabState();
}

class _KeyTabState extends State<_KeyTab> {
  int? _accountId;
  DateTime? _lastSyncAt;
  List<KeyStat> _stats = const [];
  Map<String, List<double>> _trends = const {};
  int _requestId = 0;
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
      _stats = const [];
      _trends = const {};
      _loading = true;
      _error = null;
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
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await state.usageRepo.keyStats(account.id);
      Map<String, List<double>> trends = const {};
      try {
        trends = await state.usageRepo.keyDailyTokens(account.id);
      } catch (_) {
        // Sparkline is optional; key totals still render.
      }
      if (!mounted || requestId != _requestId) return;
      if (state.activeAccount?.id != account.id) return;
      setState(() {
        _stats = stats;
        _trends = trends;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await context.read<AppState>().syncNow();
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final colors = context.colors;
    if (_loading && _stats.isEmpty) {
      return const ListSkeleton(rows: 3, rowHeight: 190);
    }
    if (_error != null) {
      return ErrorState(
        message: '${l10n.t('loadFailed')}: $_error',
        retryLabel: l10n.t('retry'),
        onRetry: _load,
      );
    }
    if (_stats.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 50),
            EmptyState(
              icon: Icons.key_outlined,
              title: l10n.t('noData'),
              subtitle: l10n.t('syncHint'),
            ),
          ],
        ),
      );
    }
    final totalTokens = _stats.fold<int>(
      0,
      (sum, stat) => sum + stat.totalTokens,
    );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('keysTotal', {'n': _stats.length}),
                  style: TextStyle(fontSize: 11, color: colors.text3),
                ),
              ),
              Text(
                l10n.t('keyUsageDesc'),
                style: TextStyle(fontSize: 10, color: colors.text3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _stats.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _KeyCard(
              stat: _stats[i],
              index: i,
              totalTokens: totalTokens,
              trend: _trends[_stats[i].keyId] ?? const [],
              state: state,
              onSelectKey: widget.onSelectKey,
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.stat,
    required this.index,
    required this.totalTokens,
    required this.trend,
    required this.state,
    required this.onSelectKey,
  });

  final KeyStat stat;
  final int index;
  final int totalTokens;
  final List<double> trend;
  final AppState state;
  final void Function(String keyId, String keyName) onSelectKey;

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
    final colors = context.colors;
    final l10n = state.l10n;
    final color = _palette[index % _palette.length];
    final rawName = state.keyNames[stat.keyId] ?? '';
    final keyName = stat.keyId.isEmpty
        ? l10n.t('unassigned')
        : (rawName.isNotEmpty ? rawName : truncateMiddle(stat.keyId, 24));
    final displayId = stat.keyId.isEmpty ? '' : truncateMiddle(stat.keyId, 34);
    final showId = displayId.isNotEmpty && displayId != keyName;
    final share = totalTokens > 0 ? stat.totalTokens / totalTokens : 0.0;
    final last = fmtRelative(
      stat.lastAt,
      never: l10n.t('never'),
      justNow: l10n.t('justNow'),
      minAgo: l10n.t('minAgo'),
      hrAgo: l10n.t('hrAgo'),
      dayAgo: l10n.t('dayAgo'),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onSelectKey(stat.keyId, keyName),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      keyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fmtMoney(
                      stat.totalCostUsd,
                      currency: state.currency,
                      rate: state.usdCny,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.amber,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colors.text3,
                  ),
                ],
              ),
              if (showId) ...[
                const SizedBox(height: 2),
                Text(
                  displayId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: colors.text3),
                ),
              ],
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: colors.muted,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${(share * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 10, color: colors.text3),
                  ),
                  const Spacer(),
                  Text(
                    '${l10n.t('colLastUsed')} $last',
                    style: TextStyle(fontSize: 10, color: colors.text3),
                  ),
                ],
              ),
              if (trend.isNotEmpty) ...[
                const SizedBox(height: 5),
                Sparkline(values: trend, color: color, height: 24),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  StatChip(
                    label: l10n.t('requests'),
                    value: fmtInt(stat.requestCount),
                  ),
                  StatChip(
                    label: l10n.t('totalTokensShort'),
                    value: fmtTokens(stat.totalTokens),
                  ),
                  StatChip(
                    label: l10n.t('input'),
                    value: fmtTokens(stat.totalInputTokens),
                  ),
                  StatChip(
                    label: l10n.t('output'),
                    value: fmtTokens(stat.totalOutputTokens),
                  ),
                  StatChip(
                    label: l10n.t('colReasoning'),
                    value: fmtTokens(stat.totalReasoningTokens),
                  ),
                  StatChip(
                    label: l10n.t('cacheReadTokens'),
                    value: fmtTokens(stat.cacheHitTokens),
                  ),
                  StatChip(
                    label: l10n.t('cacheWriteTokens'),
                    value: fmtTokens(stat.cacheWriteTokens),
                  ),
                  StatChip(
                    label: l10n.t('sessions'),
                    value: fmtInt(stat.sessionCount),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
