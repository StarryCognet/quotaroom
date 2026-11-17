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
  static const int incrementalPages = 10;
  static const int maxFullPages = 1000;
  static const int maxPageRetries = 2;
  static const int incrementalOverlapMs = 3600 * 1000;
  static const int quotaCacheSeconds = 30;

  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();
  final Map<int, _QuotaCacheEntry> _quotaCache = {};
  final Map<int, Future<QuotaResult>> _quotaInFlight = {};

  SyncProgress _state = SyncProgress.idle;
  SyncProgress get state => _state;
  bool get running => _state.running;
  Stream<SyncProgress> get progressStream => _progressController.stream;

  void dispose() {
    _progressController.close();
  }

  void _emit(SyncProgress next) {
    _state = next;
    if (!_progressController.isClosed) _progressController.add(next);
  }

  Future<SyncResult> syncIncremental() async {
    if (_state.running) {
      return const SyncResult(ok: false, error: '已有同步任务进行中');
    }
    final targets = (await accounts.listAccounts())
        .where((account) => account.hasToken)
        .toList();
    if (targets.isEmpty) {
      return const SyncResult(ok: false, error: '未登录');
    }
    final currentSettings = await settings.getSettings();
    _emit(
      const SyncProgress(
        running: true,
        mode: 'incremental',
        phase: 'usage',
      ),
    );
    var totalInserted = 0;
    var totalPages = 0;
    try {
      for (final account in targets) {
        final result = await _syncOne(
          account,
          'incremental',
          currentSettings.windowDays,
        );
        totalInserted += result.inserted;
        totalPages += result.pages;
        if (!result.ok) {
          _emit(
            _state.copyWith(
              running: false,
              phase: 'error',
              message: result.error ?? '同步失败',
            ),
          );
          return SyncResult(
            ok: false,
            error: result.error,
            inserted: totalInserted,
            pages: totalPages,
          );
        }
      }
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
      );
    } catch (e) {
      _emit(
        _state.copyWith(running: false, phase: 'error', message: e.toString()),
      );
      return SyncResult(ok: false, error: e.toString());
    }
  }

  Future<SyncResult> syncFull() async {
    if (_state.running) {
      return const SyncResult(ok: false, error: '已有同步任务进行中');
    }
    final active = await accounts.activeAccount();
    if (active == null || !active.hasToken) {
      return const SyncResult(ok: false, error: '未登录');
    }
    final currentSettings = await settings.getSettings();
    _emit(
      SyncProgress(
        running: true,
        mode: 'full',
        phase: 'usage',
        account: active.name,
      ),
    );
    try {
      final result = await _syncOne(
        active,
        'full',
        currentSettings.windowDays,
      );
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
        return SyncResult(ok: false, error: e.toString());
      }
    }

    var totalInserted = 0;
    var totalPages = 0;
    var page = 0;
    String? cursor;
    var emptyPages = 0;
    var failedPages = 0;
    var pageRetryCount = 0;
    var boundaryReached = false;

    int? sinceMs;
    if (mode != 'full') {
      final state = await usage.syncState(account.id);
      final newest = state.newestRecordAt;
      if (newest != null) {
        final stamp = newest.millisecondsSinceEpoch - incrementalOverlapMs;
        if (stamp > 0) sinceMs = stamp;
      }
    }

    final maxPages = mode == 'full' ? maxFullPages : incrementalPages;
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
      final records = usagePage.records;
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
        final inserted = await usage.insertUsageRecords(records, account.id);
        totalInserted += inserted;
        emptyPages = inserted == 0 ? emptyPages + 1 : 0;
      } else {
        emptyPages++;
      }

      cursor = usagePage.nextCursor;
      if (cursor == null) break;
      if (boundaryReached) break;
      if (mode == 'incremental' && emptyPages >= 2) break;
    }

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

    if (failedPages > 0) {
      const message = '完成, 但翻页中断 (数据不完整, 可再次全量同步补全)';
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
      );
    }
    await usage.updateSyncState(
      account.id,
      status: 'ok',
      inserted: totalInserted,
    );
    return SyncResult(
      ok: true,
      inserted: totalInserted,
      pages: totalPages,
    );
  }

  /// Last known quota (possibly stale) for instant UI rendering.
  QuotaResult? peekQuota(int accountId) => _quotaCache[accountId]?.result;

  /// Quota is cached per account for 30 seconds, failures included, matching
  /// the desktop server's retry-storm protection.
  Future<QuotaResult> quotaFor(
    Account account, {
    bool force = false,
  }) async {
    final cached = _quotaCache[account.id];
    final now = DateTime.now();
    if (!force &&
        cached != null &&
        now.difference(cached.at).inSeconds < quotaCacheSeconds) {
      return cached.result;
    }
    final inFlight = _quotaInFlight[account.id];
    if (inFlight != null) return inFlight;
    final future = _fetchQuota(account, now);
    _quotaInFlight[account.id] = future;
    try {
      return await future;
    } finally {
      _quotaInFlight.remove(account.id);
    }
  }

  Future<QuotaResult> _fetchQuota(Account account, DateTime now) async {
    final token = await accounts.tokenFor(account.id);
    if (token == null || token.trim().isEmpty) {
      final result = QuotaResult(
        name: account.name,
        workspaceId: account.workspaceHint,
        success: false,
        updatedAt: now.toUtc(),
        error: '未登录',
      );
      _quotaCache[account.id] = _QuotaCacheEntry(result, now);
      return result;
    }
    final result = await api.fetchQuota(
      token,
      workspaceHint: account.resolvedWorkspaceId ?? account.workspaceHint,
    );
    _quotaCache[account.id] = _QuotaCacheEntry(result, now);
    return result;
  }

  void clearQuotaCache([int? accountId]) {
    if (accountId == null) {
      _quotaCache.clear();
    } else {
      _quotaCache.remove(accountId);
    }
  }
}
