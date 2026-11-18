import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/export_service.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/records_navigation.dart';
import '../prism/app_glyphs.dart';
import '../prism/keep_alive_page.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/detail_sheets.dart';
import '../widgets/export_helper.dart';
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
  late final TabController _tabsController;
  int _lastIndex = 0;
  final ValueNotifier<KeyFilterSelection?> _keyFilter = ValueNotifier(null);
  final ValueNotifier<RecordsFilterRequest?> _filterRequest = ValueNotifier(
    null,
  );
  AppState? _navState;
  bool _handlingNavigation = false;

  @override
  void initState() {
    super.initState();
    _tabsController = TabController(length: 3, vsync: this);
    _tabsController.addListener(_onTabsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (identical(_navState, state)) return;
    _navState?.recordsNavigation.removeListener(_handleNavigation);
    _navState = state;
    state.recordsNavigation.addListener(_handleNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleNavigation();
    });
  }

  void _handleNavigation() {
    final state = _navState;
    final request = state?.recordsNavigation.value;
    if (state == null || request == null || _handlingNavigation) return;
    _handlingNavigation = true;
    state.recordsNavigation.value = null;
    final tab = request.tabIndex.clamp(0, 2);
    if (_tabsController.index != tab) {
      _tabsController.animateTo(tab);
    }
    if (request.keyId != null ||
        request.query.isNotEmpty ||
        request.model.isNotEmpty ||
        request.days != null) {
      _filterRequest.value = RecordsFilterRequest(
        query: request.query,
        model: request.model,
        days: request.days,
        keyId: request.keyId,
        keyName: request.keyName,
      );
    }
    _handlingNavigation = false;
  }

  void _onTabsChanged() {
    if (!mounted || _tabsController.index == _lastIndex) return;
    _lastIndex = _tabsController.index;
    setState(() {});
  }

  @override
  void dispose() {
    _navState?.recordsNavigation.removeListener(_handleNavigation);
    _tabsController.dispose();
    _keyFilter.dispose();
    _filterRequest.dispose();
    super.dispose();
  }

  void _selectKey(String keyId, String keyName) {
    _keyFilter.value = KeyFilterSelection(keyId: keyId, keyName: keyName);
    _tabsController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppState>().l10n;
    final index = _tabsController.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, context.appBarInset + 8, 16, 8),
          child: SegmentedControl<int>(
            segments: [
              (0, l10n.t('sessionUsage')),
              (1, l10n.t('usageRecords')),
              (2, l10n.t('keyUsage')),
            ],
            value: index,
            onChanged: (value) => _tabsController.animateTo(value),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabsController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              const KeepAlivePage(child: _SessionsTab()),
              KeepAlivePage(
                child: _RecordsTab(
                  keyFilter: _keyFilter,
                  filterRequest: _filterRequest,
                ),
              ),
              KeepAlivePage(child: _KeyTab(onSelectKey: _selectKey)),
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
    final scheme = context.colorScheme;
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: ActivityIndicator(size: 18, color: scheme.primary),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: TextButton(onPressed: onRetry, child: Text(l10n.t('retry'))),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            l10n.t('allLoaded'),
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
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
  bool _pendingSyncReload = false;
  bool _failedReset = false;

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
      } else {
        // Don't advance past this sync silently; reload when the user
        // returns to the top instead of leaving the list stale forever.
        _pendingSyncReload = true;
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_pendingSyncReload && _scroll.offset <= 80) {
      _pendingSyncReload = false;
      _reload();
      return;
    }
    if (_loading || _loadingMore || _error != null) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  void _jumpToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    if (_failedReset) {
      _reload();
    } else {
      _loadMore();
    }
  }

  void _scheduleAutoLoadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _loadingMore || _error != null) return;
      if (_items.length >= _total) return;
      final position = _scroll.hasClients ? _scroll.position : null;
      if (position == null || position.maxScrollExtent <= 0) {
        _loadMore();
      }
    });
  }

  Future<void> _fetchPage(int page, {required bool reset}) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final requestId = ++_requestId;
    if (reset) _jumpToTop();
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
        _failedReset = false;
      });
      _scheduleAutoLoadMore();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
        _failedReset = reset;
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 30, 16, 24 + context.bottomInset),
        children: [
          EmptyState(
            glyph: AppGlyphs.requests,
            title: l10n.t('emptySessions'),
            subtitle: l10n.t('syncHint'),
            action: FilledButton(
              onPressed: _refresh,
              child: Text(l10n.t('refresh')),
            ),
          ),
        ],
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
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + context.bottomInset),
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
    final scheme = context.colorScheme;
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
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: PressSurface(
        fill: const Color(0x00000000),
        shape: AppShape.all(0),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        onPressed: () => showSessionDetail(context, state, session),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: ShapeDecoration(
                      color: scheme.primaryContainer,
                      shape: AppShape.all(AppCorner.xs),
                    ),
                    child: Text(
                      keyLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption2
                          .of(context, emphasized: true)
                          .copyWith(color: scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sessionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .copyWith(
                          color: scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  last,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  highlight: const Color(0xFFD97706),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsTab extends StatefulWidget {
  const _RecordsTab({required this.keyFilter, required this.filterRequest});

  final ValueNotifier<KeyFilterSelection?> keyFilter;
  final ValueNotifier<RecordsFilterRequest?> filterRequest;

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
  bool _pendingSyncReload = false;
  bool _failedReset = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _selectedKey = widget.keyFilter.value;
    widget.keyFilter.addListener(_onKeyFilterChanged);
    widget.filterRequest.addListener(_onFilterRequest);
    final pending = widget.filterRequest.value;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFilterRequest(pending);
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    widget.keyFilter.removeListener(_onKeyFilterChanged);
    widget.filterRequest.removeListener(_onFilterRequest);
    super.dispose();
  }

  void _onFilterRequest() {
    final request = widget.filterRequest.value;
    if (request != null) _applyFilterRequest(request);
  }

  void _applyFilterRequest(RecordsFilterRequest request) {
    final key = request.keyId == null
        ? null
        : KeyFilterSelection(keyId: request.keyId!, keyName: request.keyName);
    _selectedKey = key;
    if (widget.keyFilter.value?.keyId != key?.keyId) {
      widget.keyFilter.removeListener(_onKeyFilterChanged);
      widget.keyFilter.value = key;
      widget.keyFilter.addListener(_onKeyFilterChanged);
    }
    _searchDebounce?.cancel();
    _search.text = request.query;
    _query = request.query;
    _model = request.model;
    _days = request.days;
    _beginReset();
    _reload();
  }

  void _onKeyFilterChanged() {
    final value = widget.keyFilter.value;
    if (value == _selectedKey) return;
    _selectedKey = value;
    _beginReset();
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
      } else {
        // Reload when the user scrolls back to the top; advancing the marker
        // here used to leave the list stale until the next sync.
        _pendingSyncReload = true;
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_pendingSyncReload && _scroll.offset <= 80) {
      _pendingSyncReload = false;
      _reload();
      return;
    }
    if (_loading || _loadingMore || _error != null) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  void _jumpToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _beginReset() {
    _pendingSyncReload = false;
    _failedReset = false;
    setState(() {
      _page = 0;
      _total = 0;
      _items.clear();
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    _jumpToTop();
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
    if (_failedReset) {
      _reload();
    } else {
      _loadMore();
    }
  }

  void _scheduleAutoLoadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _loadingMore || _error != null) return;
      if (_items.length >= _total) return;
      final position = _scroll.hasClients ? _scroll.position : null;
      if (position == null || position.maxScrollExtent <= 0) {
        _loadMore();
      }
    });
  }

  Future<void> _fetchPage(int page, {required bool reset}) async {
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    final requestId = ++_requestId;
    if (reset) _jumpToTop();
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
        _failedReset = false;
      });
      _scheduleAutoLoadMore();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
        _failedReset = reset;
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
      _query = next;
      _beginReset();
      _reload();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    if (_query.isEmpty) return;
    _query = '';
    _beginReset();
    _reload();
  }

  void _setDays(String value) {
    final days = value == 'all' ? null : int.tryParse(value);
    if (days == _days) return;
    _days = days;
    _beginReset();
    _reload();
  }

  void _clearKeyFilter() {
    widget.keyFilter.value = null;
  }

  bool get _hasFilters =>
      _query.isNotEmpty ||
      _model.isNotEmpty ||
      _days != null ||
      _selectedKey != null;

  void _clearFilters() {
    _searchDebounce?.cancel();
    _search.clear();
    _query = '';
    _model = '';
    _days = null;
    final hadKey = widget.keyFilter.value != null;
    // The notifier listener resets and reloads; only do it here when no key
    // filter was set, otherwise a duplicate request would be issued.
    widget.keyFilter.value = null;
    if (!hadKey) {
      _beginReset();
      _reload();
    }
  }

  Future<void> _exportRecords() async {
    if (_exporting) return;
    final state = context.read<AppState>();
    final account = state.activeAccount;
    if (account == null) return;
    setState(() => _exporting = true);
    try {
      final service = ExportService(db: state.db.db, usage: state.usageRepo);
      final file = await service.exportRecordsCsv(
        account.id,
        state.keyNames,
        model: _model.isEmpty ? null : _model,
        days: _days,
        keyId: _selectedKey?.keyId,
        query: _query.isEmpty ? null : _query,
      );
      if (!mounted) return;
      await saveOrShareExport(
        context,
        file: file,
        shareText: 'QuotaRoom · ${account.name} records',
      );
    } catch (e) {
      if (mounted) showExportError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickModel() async {
    final l10n = context.read<AppState>().l10n;
    final selected = await showFormSheet<String>(
      context: context,
      props: const SheetProps(detents: [0.5, 0.85]),
      builder: (sheetContext) =>
          _ModelPicker(models: _models, selected: _model, l10n: l10n),
    );
    if (selected == null || !mounted) return;
    _model = selected;
    _beginReset();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final l10n = state.l10n;
    final scheme = context.colorScheme;
    final header = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: l10n.t('searchHint'),
              prefixIcon: const GlyphIcon(AppGlyphs.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.t('clearSearch'),
                      icon: const GlyphIcon(AppGlyphs.clearField, size: 17),
                      onPressed: _clearSearch,
                    ),
              isDense: true,
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
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                onPressed: _exporting ? null : _exportRecords,
                tooltip: l10n.t('exportRecords'),
                icon: _exporting
                    ? const ActivityIndicator(size: 16)
                    : const GlyphIcon(AppGlyphs.export, size: 18),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: OutlinedButton.icon(
                  onPressed: _pickModel,
                  icon: const GlyphIcon(AppGlyphs.filter, size: 15),
                  label: Text(
                    _model.isEmpty ? l10n.t('allModels') : _model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              child: Chip(
                label: _selectedKey!.keyName.isEmpty
                    ? l10n.t('unassigned')
                    : _selectedKey!.keyName,
                onDeleted: _clearKeyFilter,
              ),
            ),
          ),
      ],
    );

    // The header stays mounted while loading or when a query errors. The old
    // build replaced the whole tab with a skeleton/error, which blurred the
    // search field and made filters impossible to clear after a failure.
    final Widget body;
    if (_items.isEmpty) {
      if (_loading) {
        body = const ListSkeleton();
      } else if (_error != null) {
        body = ErrorState(
          message: '${l10n.t('loadFailed')}: $_error',
          retryLabel: l10n.t('retry'),
          onRetry: _reload,
        );
      } else {
        body = ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + context.bottomInset),
          children: [
            EmptyState(
              glyph: AppGlyphs.requests,
              title: l10n.t(_hasFilters ? 'emptyFiltered' : 'emptyRecords'),
              subtitle: l10n.t(_hasFilters ? 'emptyFilteredHint' : 'syncHint'),
              action: _hasFilters
                  ? OutlinedButton(
                      onPressed: _clearFilters,
                      child: Text(l10n.t('clearFilters')),
                    )
                  : FilledButton(
                      onPressed: _refresh,
                      child: Text(l10n.t('refresh')),
                    ),
            ),
          ],
        );
      }
    } else {
      body = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + context.bottomInset),
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
      );
    }
    return Column(
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.models,
    required this.selected,
    required this.l10n,
  });

  final List<String> models;
  final String selected;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('modelFilter'),
            style: AppTextStyle.title2
                .of(context, emphasized: true)
                .copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                _ModelRow(
                  label: l10n.t('allModels'),
                  selected: selected.isEmpty,
                  onTap: () => Navigator.of(context).pop(''),
                ),
                if (models.isNotEmpty) const Divider(height: 1, thickness: 1),
                for (final model in models)
                  _ModelRow(
                    label: model,
                    model: model,
                    selected: selected == model,
                    onTap: () => Navigator.of(context).pop(model),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.model,
  });

  final String label;
  final String? model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      onPressed: onTap,
      child: Row(
        children: [
          if (model != null) ...[
            ModelIcon(model: model!, size: 20),
            const SizedBox(width: 10),
          ] else
            const SizedBox(width: 30),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context, emphasized: selected)
                  .copyWith(color: scheme.onSurface),
            ),
          ),
          if (selected)
            GlyphIcon(AppGlyphs.check, size: 18, color: scheme.primary),
        ],
      ),
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
    final scheme = context.colorScheme;
    final l10n = state.l10n;
    final plan = planBadge(record.plan);
    final keyLabel = record.keyId.isEmpty
        ? l10n.t('unassigned')
        : (keyName.isNotEmpty ? keyName : truncateMiddle(record.keyId, 16));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ModelIcon(model: record.model, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  record.model.isEmpty ? '—' : record.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
              ),
              if (plan.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: ShapeDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: AppShape.all(AppCorner.xs),
                  ),
                  child: Text(
                    plan,
                    style: AppTextStyle.caption2
                        .of(context, emphasized: true)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                fmtDateTimeShort(record.createdAt),
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(
                      color: scheme.onSurfaceVariant,
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
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                fmtMoney(
                  record.costUsd,
                  currency: state.currency,
                  rate: state.usdCny,
                ),
                style: AppTextStyle.caption1
                    .of(context, emphasized: true)
                    .copyWith(
                      color: const Color(0xFFD97706),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
    final scheme = context.colorScheme;
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 30, 16, 24 + context.bottomInset),
        children: [
          EmptyState(
            glyph: AppGlyphs.key,
            title: l10n.t('noData'),
            subtitle: l10n.t('syncHint'),
            action: FilledButton(
              onPressed: _refresh,
              child: Text(l10n.t('refresh')),
            ),
          ),
        ],
      );
    }
    final totalTokens = _stats.fold<int>(
      0,
      (sum, stat) => sum + stat.totalTokens,
    );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 2, 16, 16 + context.bottomInset),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.t('keysTotal', {'n': _stats.length}),
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              l10n.t('keyUsageDesc'),
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
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
    final scheme = context.colorScheme;
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
      child: PressSurface(
        fill: const Color(0x00000000),
        shape: AppShape.all(0),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onPressed: () => onSelectKey(stat.keyId, keyName),
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
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .copyWith(color: scheme.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  fmtMoney(
                    stat.totalCostUsd,
                    currency: state.currency,
                    rate: state.usdCny,
                  ),
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(
                        color: const Color(0xFFD97706),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
                const SizedBox(width: 2),
                GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            if (showId) ...[
              const SizedBox(height: 2),
              Text(
                displayId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption2
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            _ShareBar(value: share, color: color),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${(share * 100).toStringAsFixed(1)}%',
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  '${l10n.t('colLastUsed')} $last',
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
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
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.value, required this.color});

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
