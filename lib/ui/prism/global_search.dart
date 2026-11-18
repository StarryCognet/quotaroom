import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../core/formatters.dart';
import '../../core/i18n.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/records_navigation.dart';
import 'app_glyphs.dart';

/// Ctrl+K command palette across records, sessions, keys, models and accounts.
Future<void> showGlobalSearch(BuildContext context, AppState state) {
  return showFloatingDialog<void>(
    context: context,
    child: _GlobalSearch(state: state),
  );
}

class _GlobalSearch extends StatefulWidget {
  const _GlobalSearch({required this.state});

  final AppState state;

  @override
  State<_GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends State<_GlobalSearch> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  String _query = '';
  String? _error;
  List<UsageRecord> _records = const [];
  List<SessionStat> _sessions = const [];
  List<KeyStat> _keys = const [];
  List<String> _models = const [];
  List<Account> _accounts = const [];

  L10n get _l10n => widget.state.l10n;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    final account = widget.state.activeAccount;
    if (query.isEmpty || account == null) {
      if (mounted) {
        setState(() {
          _query = query;
          _loading = false;
          _error = null;
          _records = const [];
          _sessions = const [];
          _keys = const [];
          _models = const [];
          _accounts = const [];
        });
      }
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final recordsFuture = widget.state.usageRepo.recordsPage(
        account.id,
        pageSize: 6,
        query: query,
      );
      final sessionsFuture = widget.state.usageRepo.sessionsPage(
        account.id,
        pageSize: 4,
        query: query,
      );
      final keysFuture = widget.state.usageRepo.keyStats(account.id);
      final modelsFuture = widget.state.usageRepo.models(account.id);
      final records = await recordsFuture;
      final sessions = await sessionsFuture;
      final keys = await keysFuture;
      final models = await modelsFuture;
      if (!mounted || requestId != _requestId) return;
      final lower = query.toLowerCase();
      final keyNames = widget.state.keyNames;
      setState(() {
        _records = records.records;
        _sessions = sessions.records;
        _keys = keys
            .where(
              (key) =>
                  key.keyId.toLowerCase().contains(lower) ||
                  (keyNames[key.keyId] ?? '').toLowerCase().contains(lower),
            )
            .take(4)
            .toList();
        _models = models
            .where((model) => model.toLowerCase().contains(lower))
            .take(4)
            .toList();
        _accounts = widget.state.accounts
            .where(
              (account) =>
                  account.name.toLowerCase().contains(lower) ||
                  (account.resolvedWorkspaceId ?? account.workspaceHint)
                      .toLowerCase()
                      .contains(lower),
            )
            .take(4)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  void _openRecord(UsageRecord record) {
    _close();
    widget.state.navigateRecords(
      RecordsNavigationRequest(tabIndex: 1, query: record.usgId),
    );
  }

  void _openSession(SessionStat session) {
    _close();
    widget.state.navigateRecords(
      RecordsNavigationRequest(
        tabIndex: 1,
        query: session.sessionId.isEmpty ? session.keyId : session.sessionId,
      ),
    );
  }

  void _openKey(KeyStat key) {
    _close();
    widget.state.navigateRecords(
      RecordsNavigationRequest(
        tabIndex: 1,
        keyId: key.keyId,
        keyName: widget.state.keyNames[key.keyId] ?? '',
      ),
    );
  }

  void _openModel(String model) {
    _close();
    widget.state.navigateRecords(
      RecordsNavigationRequest(tabIndex: 1, model: model),
    );
  }

  Future<void> _openAccount(Account account) async {
    _close();
    await widget.state.switchAccount(account.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          decoration: ShapeDecoration(
            color: scheme.surface,
            shape: AppShape.all(AppCorner.xl),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: (value) => unawaited(_search(value)),
                decoration: InputDecoration(
                  hintText: _l10n.t('searchEverything'),
                  prefixIcon: const GlyphIcon(AppGlyphs.search, size: 19),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: _l10n.t('clearSearch'),
                          onPressed: () {
                            _controller.clear();
                            unawaited(_search(''));
                          },
                          icon: const GlyphIcon(AppGlyphs.clearField, size: 17),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: SingleChildScrollView(child: _buildResults(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final scheme = context.colorScheme;
    if (_query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            GlyphIcon(
              AppGlyphs.search,
              size: 30,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              _l10n.t('searchEverything'),
              textAlign: TextAlign.center,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              _l10n.t('searchShortcutHint'),
              textAlign: TextAlign.center,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '${_l10n.t('loadFailed')}: $_error',
          textAlign: TextAlign.center,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: scheme.error),
        ),
      );
    }
    final children = <Widget>[
      if (_records.isNotEmpty) ...[
        _section(context, _l10n.t('recordsTab')),
        for (final record in _records) _recordRow(context, record),
      ],
      if (_sessions.isNotEmpty) ...[
        _section(context, _l10n.t('sessionUsage')),
        for (final session in _sessions) _sessionRow(context, session),
      ],
      if (_keys.isNotEmpty) ...[
        _section(context, _l10n.t('keyUsage')),
        for (final key in _keys) _keyRow(context, key),
      ],
      if (_models.isNotEmpty) ...[
        _section(context, _l10n.t('modelUsage')),
        for (final model in _models)
          _row(
            context,
            glyph: AppGlyphs.dataUsage,
            title: model,
            subtitle: _l10n.t('filterByModel'),
            onTap: () => _openModel(model),
          ),
      ],
      if (_accounts.isNotEmpty) ...[
        _section(context, _l10n.t('accountsTab')),
        for (final account in _accounts)
          _row(
            context,
            glyph: AppGlyphs.account,
            title: account.name,
            subtitle: maskWorkspace(
              account.resolvedWorkspaceId ?? account.workspaceHint,
            ),
            onTap: () => unawaited(_openAccount(account)),
          ),
      ],
    ];
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            GlyphIcon(
              AppGlyphs.requests,
              size: 28,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              _l10n.t('searchNoResults'),
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(
              color: context.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
      ),
    );
  }

  Widget _recordRow(BuildContext context, UsageRecord record) {
    final keyName = widget.state.keyNames[record.keyId] ?? '';
    final key = keyName.isNotEmpty
        ? keyName
        : (record.keyId.isEmpty
              ? _l10n.t('unassigned')
              : truncateMiddle(record.keyId, 20));
    final session = record.sessionId.isEmpty
        ? _l10n.t('unassigned')
        : truncateMiddle(record.sessionId, 22);
    final time = fmtRelative(
      record.createdAt.toLocal(),
      never: _l10n.t('never'),
      justNow: _l10n.t('justNow'),
      minAgo: _l10n.t('minAgo'),
      hrAgo: _l10n.t('hrAgo'),
      dayAgo: _l10n.t('dayAgo'),
    );
    return _row(
      context,
      glyph: AppGlyphs.requests,
      title: record.model.isEmpty ? _l10n.t('unassigned') : record.model,
      subtitle: '$key · $session · $time',
      onTap: () => _openRecord(record),
    );
  }

  Widget _sessionRow(BuildContext context, SessionStat session) {
    final keyName = widget.state.keyNames[session.keyId] ?? '';
    final label = session.sessionId.isEmpty
        ? _l10n.t('unassigned')
        : truncateMiddle(session.sessionId, 28);
    return _row(
      context,
      glyph: AppGlyphs.requests,
      title: label,
      subtitle:
          '${keyName.isEmpty ? (session.keyId.isEmpty ? _l10n.t('unassigned') : truncateMiddle(session.keyId, 20)) : keyName} · ${fmtInt(session.requestCount)} ${_l10n.t('requests')}',
      onTap: () => _openSession(session),
    );
  }

  Widget _keyRow(BuildContext context, KeyStat key) {
    final name = widget.state.keyNames[key.keyId] ?? '';
    return _row(
      context,
      glyph: AppGlyphs.key,
      title: name.isEmpty ? truncateMiddle(key.keyId, 28) : name,
      subtitle:
          '${fmtInt(key.requestCount)} ${_l10n.t('requests')} · ${fmtTokens(key.totalTokens)}',
      onTap: () => _openKey(key),
    );
  }

  Widget _row(
    BuildContext context, {
    required Glyph glyph,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = context.colorScheme;
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.all(AppCorner.md),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      onPressed: onTap,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: ShapeDecoration(
              color: scheme.primaryContainer,
              shape: AppShape.all(AppCorner.xs),
            ),
            child: Center(
              child: GlyphIcon(
                glyph,
                size: 16,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
