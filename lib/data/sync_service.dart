import 'dart:async';

import 'account_repository.dart';
import 'models.dart';
import 'opencode_api.dart';
import 'settings_repository.dart';
import 'usage_repository.dart';

class _QuotaCacheEntry {
  const _QuotaCacheEntry(this.result, this.at);

  final QuotaResult result;
  final DateTime at;
}

/// Port of the desktop app's per-account sync engine (`app/server.py`).
class SyncService {
  SyncService({
    required this.accounts,
    required this.usage,
    required this.settings,
    required this.api,
  });

  final AccountRepository accounts;
  final UsageRepository usage;
  final SettingsRepository settings;
  final OpenCodeApi api;

  static const int pageLimit = 100;
  static const int maxFullPages = 1000;
  static const int maxPageRetries = 2;
  static const int incrementalOverlapMs = 3600 * 1000;
  static const int quotaCacheSeconds = 30;

  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();
  final Map<int, _QuotaCacheEntry> _quotaCache = {};
  final Map<int, QuotaResult> _lastGoodQuota = {};
  final Map<int, Future<QuotaResult>> _quotaInFlight = {};
  final Map<int, Object> _quotaGenerations = {};

  SyncProgress _state = SyncProgress.idle;
  bool _running = false;
  final String _leaseOwner =
      'sync-${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';

  SyncProgress get state => _state;
  bool get running => _running || _state.running;
  Stream<SyncProgress> get progressStream => _progressController.stream;

  void dispose() {
    _progressController.close();
  }

  void _emit(SyncProgress next) {
    _state = next;
    if (!_progressController.isClosed) _progressController.add(next);
  }

  static const SyncResult _busy = SyncResult(ok: false, error: '已有同步任务进行中');

  Future<SyncResult> syncIncremental() async {
    // The guard must happen synchronously: checking the emitted state after an
    // await lets a timer and a manual tap enter the same sync concurrently.
    if (_running || _state.running) return _busy;
    _running = true;
    var leaseHeld = false;
    try {
      final targets = (await accounts.listAccounts())
          .where((account) => account.hasToken)
          .toList();
      if (targets.isEmpty) {
        return const SyncResult(ok: false, error: '未登录');
      }
      final activeId = (await accounts.activeAccount())?.id;
      if (!await usage.acquireSyncLease(_leaseOwner)) {
        return const SyncResult(ok: false, error: '另一个同步任务正在进行（可能来自后台任务）');
      }
      leaseHeld = true;
      final currentSettings = await settings.getSettings();
      _emit(
        const SyncProgress(running: true, mode: 'incremental', phase: 'usage'),
      );
      var totalInserted = 0;
      var totalPages = 0;
      var successes = 0;
      var partial = false;
      var authRequired = false;
      final failures = <String>[];
      for (final account in targets) {
        final result = await _syncOne(
          account,
          'incremental',
          currentSettings.windowDays,
        );
        totalInserted += result.inserted;
        totalPages += result.pages;
        if (result.ok) {
          successes++;
          partial = partial || result.partial;
        } else {
          // One expired cookie must not stop every later account from
          // syncing. Keep going and report an aggregate result.
          failures.add('${account.name}: ${result.error ?? '同步失败'}');
          // Only offer the active account's re-login action; other expired
          // accounts are visible in the accounts page with their own status.
          authRequired =
              authRequired || (result.authRequired && account.id == activeId);
        }
      }
      if (failures.isEmpty) {
        _emit(
          _state.copyWith(
            running: false,
            phase: 'done',
            message: '同步完成, 新增 $totalInserted 条',
            inserted: totalInserted,
          ),
        );
        return SyncResult(
          ok: true,
          inserted: totalInserted,
          pages: totalPages,
          partial: partial,
        );
      }
      final message = '部分账号同步失败: ${failures.join('；')}';
      if (successes > 0) {
        _emit(
          _state.copyWith(
            running: false,
            phase: 'done',
            message: message,
            inserted: totalInserted,
          ),
        );
        return SyncResult(
          ok: true,
          inserted: totalInserted,
          pages: totalPages,
          partial: true,
          error: message,
          authRequired: authRequired,
        );
      }
      _emit(_state.copyWith(running: false, phase: 'error', message: message));
      return SyncResult(
        ok: false,
        error: message,
        inserted: totalInserted,
        pages: totalPages,
        authRequired: authRequired,
      );
    } catch (e) {
      _emit(
        _state.copyWith(running: false, phase: 'error', message: e.toString()),
      );
      return SyncResult(ok: false, error: e.toString());
    } finally {
      if (leaseHeld) await usage.releaseSyncLease(_leaseOwner);
      _running = false;
    }
  }

  Future<SyncResult> syncFull() async {
    if (_running || _state.running) return _busy;
    _running = true;
    var leaseHeld = false;
    try {
      final active = await accounts.activeAccount();
      if (active == null || !active.hasToken) {
        return const SyncResult(ok: false, error: '未登录');
      }
      if (!await usage.acquireSyncLease(_leaseOwner)) {
        return const SyncResult(ok: false, error: '另一个同步任务正在进行（可能来自后台任务）');
      }
      leaseHeld = true;
      final currentSettings = await settings.getSettings();
      _emit(
        SyncProgress(
          running: true,
          mode: 'full',
          phase: 'usage',
          account: active.name,
        ),
      );
      final result = await _syncOne(active, 'full', currentSettings.windowDays);
      _emit(
        _state.copyWith(
          running: false,
          phase: result.ok ? 'done' : 'error',
          message: result.ok
              ? '全量同步完成, 新增 ${result.inserted} 条'
              : (result.error ?? '同步失败'),
        ),
      );
      return result;
    } catch (e) {
      _emit(
        _state.copyWith(running: false, phase: 'error', message: e.toString()),
      );
      return SyncResult(ok: false, error: e.toString());
    } finally {
      if (leaseHeld) await usage.releaseSyncLease(_leaseOwner);
      _running = false;
    }
  }

  Future<SyncResult> _syncOne(
    Account account,
    String mode,
    int? windowDays,
  ) async {
    final token = await accounts.tokenFor(account.id);
    if (token == null || token.trim().isEmpty) {
      return const SyncResult(ok: false, error: '未登录');
    }
    var workspaceId = account.resolvedWorkspaceId ?? account.workspaceHint;
    if (!workspaceId.startsWith('wrk_')) {
      try {
        final resolved = await api.resolveWorkspace(workspaceId, token);
        workspaceId = resolved.id;
        await accounts.saveWorkspace(
          account.id,
          hint: resolved.id,
          resolved: resolved.id,
        );
      } catch (e) {
        await usage.updateSyncState(
          account.id,
          status: 'error',
          error: e.toString(),
        );
        return SyncResult(
          ok: false,
          error: e.toString(),
          authRequired: e is AuthException,
        );
      }
    }

    var totalInserted = 0;
    var totalPages = 0;
    var page = 0;
    String? cursor;
    final seenCursors = <String>{};
    var emptyRawPages = 0;
    var failedPages = 0;
    var pageRetryCount = 0;
    var boundaryReached = false;
    var cursorLoop = false;
    var truncated = false;
    var stoppedOnEmpty = false;
    var leaseLost = false;

    int? sinceMs;
    if (mode != 'full') {
      final state = await usage.syncState(account.id);
      final newest = state.newestRecordAt;
      if (newest != null) {
        final stamp = newest.millisecondsSinceEpoch - incrementalOverlapMs;
        if (stamp > 0) sinceMs = stamp;
      }
    }

    // Incremental and full syncs both page until the cursor is exhausted. The
    // old incremental cap silently lost records whenever an hour contained
    // more than 1,000 rows; the cap is now only a safety valve and hitting it
    // is reported as a partial (not successful) sync.
    final maxPages = maxFullPages;
    while (page < maxPages) {
      _emit(
        _state.copyWith(
          running: true,
          mode: mode,
          page: page,
          inserted: totalInserted,
          phase: 'usage',
          account: account.name,
        ),
      );
      UsagePage usagePage;
      try {
        usagePage = await api.fetchUsagePage(
          token,
          workspaceId,
          cursor: cursor,
          limit: pageLimit,
          sinceMs: sinceMs,
        );
      } on AuthException catch (e) {
        await usage.updateSyncState(
          account.id,
          status: 'error',
          error: e.message,
        );
        return SyncResult(
          ok: false,
          error: e.message,
          inserted: totalInserted,
          pages: totalPages,
          authRequired: true,
        );
      } on OpenCodeApiException catch (e) {
        if (page == 0) {
          await usage.updateSyncState(
            account.id,
            status: 'error',
            error: e.message,
          );
          return SyncResult(ok: false, error: e.message);
        }
        if (pageRetryCount < maxPageRetries) {
          pageRetryCount++;
          await Future<void>.delayed(
            Duration(milliseconds: 1500 * pageRetryCount),
          );
          continue;
        }
        failedPages++;
        break;
      }

      page++;
      totalPages++;
      pageRetryCount = 0;
      if (!await usage.renewSyncLease(_leaseOwner)) {
        leaseLost = true;
        break;
      }
      final records = usagePage.records;
      if (usagePage.hasRawItems) {
        emptyRawPages = 0;
        if (records.isNotEmpty) {
          if (mode == 'full' && windowDays != null) {
            final earliest = records
                .map((record) => record.createdAt)
                .reduce((a, b) => a.isBefore(b) ? a : b);
            final boundary = DateTime.now().toUtc().subtract(
              Duration(days: windowDays),
            );
            if (earliest.isBefore(boundary)) boundaryReached = true;
          }
          totalInserted += await usage.insertUsageRecords(records, account.id);
        }
      } else {
        // An empty page is only evidence of the end when the server also has
        // no next cursor. A page can be empty locally because it only
        // contained non-inference rows while still advancing the cursor.
        emptyRawPages++;
      }

      final nextCursor = usagePage.nextCursor;
      if (nextCursor == null) {
        cursor = null;
        break;
      }
      if (!seenCursors.add(nextCursor)) {
        cursorLoop = true;
        break;
      }
      cursor = nextCursor;
      if (boundaryReached) break;
      if (emptyRawPages >= 2) {
        stoppedOnEmpty = true;
        break;
      }
    }
    if (page >= maxPages && cursor != null) truncated = true;

    if (windowDays != null) {
      await usage.pruneOldRecords(account.id, windowDays);
    }
    await usage.refreshSyncTotals(account.id);

    try {
      final names = await api.fetchKeyNames(token, workspaceId);
      await settings.mergeKeyNames(names);
    } catch (_) {
      // Key names are cosmetic; never fail a sync because of them.
    }

    final reasons = <String>[
      if (failedPages > 0) '部分页面重试后仍失败',
      if (truncated) '达到单次同步页数上限, 数据可能不完整',
      if (cursorLoop) '接口返回了重复游标, 数据可能不完整',
      if (stoppedOnEmpty) '连续空页但仍有游标, 数据可能不完整',
      if (leaseLost) '同步锁已失效, 数据可能不完整',
    ];
    final partial = reasons.isNotEmpty;
    if (partial) {
      final message = '完成, 但${reasons.join('；')} (可再次全量同步补全)';
      await usage.updateSyncState(
        account.id,
        status: 'partial',
        error: message,
        inserted: totalInserted,
      );
      return SyncResult(
        ok: true,
        partial: true,
        inserted: totalInserted,
        pages: totalPages,
        error: message,
      );
    }
    await usage.updateSyncState(
      account.id,
      status: 'ok',
      inserted: totalInserted,
    );
    return SyncResult(ok: true, inserted: totalInserted, pages: totalPages);
  }

  Object _generationFor(int accountId) =>
      _quotaGenerations.putIfAbsent(accountId, Object.new);

  /// Last known quota (possibly stale) for instant UI rendering.
  QuotaResult? peekQuota(int accountId) =>
      _lastGoodQuota[accountId] ?? _quotaCache[accountId]?.result;

  /// Quota is cached per account for 30 seconds, failures included, matching
  /// the desktop server's retry-storm protection. A failed refresh keeps the
  /// last successful windows so one network hiccup cannot blank the card.
  Future<QuotaResult> quotaFor(Account account, {bool force = false}) async {
    final cached = _quotaCache[account.id];
    final now = DateTime.now();
    if (!force &&
        cached != null &&
        now.difference(cached.at).inSeconds < quotaCacheSeconds) {
      return _lastGoodQuota[account.id] ?? cached.result;
    }
    final inFlight = _quotaInFlight[account.id];
    if (inFlight != null) return inFlight;
    final generation = _generationFor(account.id);
    final future = _fetchQuota(account, now, generation);
    _quotaInFlight[account.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_quotaInFlight[account.id], future)) {
        _quotaInFlight.remove(account.id);
      }
    }
  }

  Future<QuotaResult> _fetchQuota(
    Account account,
    DateTime now,
    Object generation,
  ) async {
    final token = await accounts.tokenFor(account.id);
    if (token == null || token.trim().isEmpty) {
      final result = QuotaResult(
        name: account.name,
        workspaceId: account.workspaceHint,
        success: false,
        updatedAt: now.toUtc(),
        error: '未登录',
      );
      _cacheQuota(account.id, result, now, generation);
      return result;
    }
    final result = await api.fetchQuota(
      token,
      workspaceHint: account.resolvedWorkspaceId ?? account.workspaceHint,
    );
    if (!identical(_generationFor(account.id), generation)) {
      // The token/workspace changed while this request was in flight. Never
      // let the previous identity's quota land in the new cache.
      return _lastGoodQuota[account.id] ?? result;
    }
    _cacheQuota(account.id, result, now, generation);
    if (result.success) _lastGoodQuota[account.id] = result;
    if (!result.success && _lastGoodQuota[account.id] != null) {
      return _lastGoodQuota[account.id]!;
    }
    return result;
  }

  void _cacheQuota(
    int accountId,
    QuotaResult result,
    DateTime at,
    Object generation,
  ) {
    if (!identical(_generationFor(accountId), generation)) return;
    _quotaCache[accountId] = _QuotaCacheEntry(result, at);
  }

  void clearQuotaCache([int? accountId]) {
    if (accountId == null) {
      _quotaCache.clear();
      _lastGoodQuota.clear();
      _quotaInFlight.clear();
      for (final id in _quotaGenerations.keys.toList()) {
        _quotaGenerations[id] = Object();
      }
    } else {
      _quotaCache.remove(accountId);
      _lastGoodQuota.remove(accountId);
      _quotaInFlight.remove(accountId);
      _quotaGenerations[accountId] = Object();
    }
  }
}
