import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/account_repository.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/data/opencode_api.dart';
import 'package:quotaroom/data/settings_repository.dart';
import 'package:quotaroom/data/sync_service.dart';
import 'package:quotaroom/data/token_store.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeApi extends OpenCodeApi {
  _FakeApi(this.pages, {this.authError = false});

  final Map<String, UsagePage> pages;
  final bool authError;
  final List<int?> sinceValues = [];
  final List<String?> cursors = [];
  int calls = 0;

  @override
  Future<WorkspaceRef> resolveWorkspace(String hint, String token) async {
    return const WorkspaceRef(id: 'wrk_test', name: 'Test');
  }

  @override
  Future<UsagePage> fetchUsagePage(
    String token,
    String workspaceId, {
    String? cursor,
    int limit = 100,
    int? sinceMs,
  }) async {
    calls++;
    sinceValues.add(sinceMs);
    cursors.add(cursor);
    if (authError) throw const AuthException();
    return pages[cursor ?? 'first'] ?? const UsagePage();
  }

  @override
  Future<Map<String, String>> fetchKeyNames(
    String token,
    String workspaceId,
  ) async => const {};
}

UsageRecord _rec(String id, DateTime at) => UsageRecord(
  usgId: id,
  createdAt: at,
  model: 'm',
  inputTokens: 10,
  outputTokens: 5,
  costUsd: 0.001,
  costRaw: 100000,
);

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late AccountRepository accounts;
  late UsageRepository usage;
  late SettingsRepository settings;
  late MemoryTokenStore tokens;

  setUp(() async {
    appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    settings = SettingsRepository(appDb.db);
    tokens = MemoryTokenStore();
    accounts = AccountRepository(
      db: appDb.db,
      tokens: tokens,
      settings: settings,
    );
    usage = UsageRepository(appDb.db);
    await tokens.write(1, 'st_test');
    await accounts.saveWorkspace(1, hint: 'wrk_test', resolved: 'wrk_test');
    await accounts.setActive(1);
  });

  tearDown(() async {
    await appDb.close();
  });

  test('first login reuses the seeded empty account', () async {
    await accounts.logoutAccount(1);
    final account = await accounts.addAccount(
      token: 'st_new',
      workspaceId: 'wrk_new',
      name: 'Main',
    );
    expect(account.id, 1);
    expect(account.name, 'Main');
    expect(account.hasToken, isTrue);
    final rows = await appDb.db.query('accounts');
    expect(rows, hasLength(1));
  });

  test(
    'incremental starts from newest minus one hour and stops on empty pages',
    () async {
      final now = DateTime.now().toUtc();
      final old = now.subtract(const Duration(hours: 2));
      await usage.insertUsageRecords([_rec('old', old)], 1);
      await usage.updateSyncState(1, status: 'ok');

      final api = _FakeApi({
        'first': UsagePage(records: [_rec('new1', now)], nextCursor: 'c1'),
        'c1': const UsagePage(nextCursor: 'c2'),
        'c2': const UsagePage(nextCursor: 'c3'),
      });
      final service = SyncService(
        accounts: accounts,
        usage: usage,
        settings: settings,
        api: api,
      );
      final result = await service.syncIncremental();

      expect(result.ok, isTrue);
      expect(result.inserted, 1);
      expect(api.calls, 3);
      expect(api.sinceValues.first, isNotNull);
      // newest (old) - 1h overlap
      expect(
        api.sinceValues.first,
        old.millisecondsSinceEpoch - SyncService.incrementalOverlapMs,
      );
      final state = await usage.syncState(1);
      // Cursor still points at older data after two empty pages, so the run
      // must be reported as partial rather than a clean success.
      expect(state.lastSyncStatus, 'partial');
      expect(state.totalRecords, 2);
    },
  );

  test('pages containing only filtered rows do not end the sync', () async {
    final now = DateTime.now().toUtc();
    final api = _FakeApi({
      'first': const UsagePage(rawItemCount: 1, nextCursor: 'c1'),
      'c1': UsagePage(records: [_rec('real', now)]),
    });
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final result = await service.syncIncremental();
    expect(result.ok, isTrue);
    expect(result.partial, isFalse);
    expect(result.inserted, 1);
    expect(api.calls, 2);
  });

  test('incremental sync does not stop at the old ten-page cap', () async {
    final now = DateTime.now().toUtc();
    final pages = <String, UsagePage>{};
    for (var i = 0; i < 12; i++) {
      pages[i == 0 ? 'first' : 'p$i'] = UsagePage(
        records: [_rec('p$i', now)],
        nextCursor: i < 11 ? 'p${i + 1}' : null,
      );
    }
    final api = _FakeApi(pages);
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final result = await service.syncIncremental();
    expect(result.ok, isTrue);
    expect(result.partial, isFalse);
    expect(result.inserted, 12);
    expect(api.calls, 12);
  });

  test('one expired account does not abort the remaining accounts', () async {
    await accounts.addAccount(
      token: 'st_bad',
      workspaceId: 'wrk_test',
      name: 'Expired',
    );
    final now = DateTime.now().toUtc();
    final api = _TokenAwareApi(now);
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final result = await service.syncIncremental();
    expect(result.ok, isTrue);
    expect(result.partial, isTrue);
    expect(result.authRequired, isTrue);
    expect(result.inserted, 1);
    expect((await usage.syncState(1)).lastSyncStatus, 'ok');
    expect((await usage.syncState(2)).lastSyncStatus, 'error');
  });

  test('full sync stops at the window boundary and prunes', () async {
    await settings.saveSettings(const Settings(windowDays: 30));
    final now = DateTime.now().toUtc();
    final tooOld = now.subtract(const Duration(days: 40));
    final api = _FakeApi({
      'first': UsagePage(
        records: [_rec('new', now), _rec('old', tooOld)],
        nextCursor: 'c1',
      ),
      'c1': UsagePage(records: [_rec('unreached', now)]),
    });
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final result = await service.syncFull();

    expect(result.ok, isTrue);
    expect(api.calls, 1, reason: 'boundary page is kept and then stops');
    final page = await usage.recordsPage(1);
    expect(page.total, 1);
    expect(page.records.first.usgId, 'new');
  });

  test('auth failure is reported and stored', () async {
    final api = _FakeApi(const {}, authError: true);
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final result = await service.syncIncremental();
    expect(result.ok, isFalse);
    expect(result.error, isNotEmpty);
    final state = await usage.syncState(1);
    expect(state.lastSyncStatus, 'error');
  });

  test('quota cache reuses the result for 30 seconds', () async {
    final api = _CountingQuotaApi();
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final account = (await accounts.getAccount(1))!;
    await service.quotaFor(account);
    await service.quotaFor(account);
    expect(api.quotaCalls, 1);
  });

  test('a failed quota refresh keeps the last successful windows', () async {
    final api = _FlakyQuotaApi();
    final service = SyncService(
      accounts: accounts,
      usage: usage,
      settings: settings,
      api: api,
    );
    final account = (await accounts.getAccount(1))!;
    final first = await service.quotaFor(account);
    expect(first.success, isTrue);
    final second = await service.quotaFor(account, force: true);
    expect(second.success, isTrue);
    expect(second.windows, isNotEmpty);
    expect(service.peekQuota(1)?.success, isTrue);
    // The short failure cache must not leak the failed result to callers
    // while a last-good value exists.
    final cached = await service.quotaFor(account);
    expect(cached.success, isTrue);
    expect(cached.windows, isNotEmpty);
  });
}

class _TokenAwareApi extends OpenCodeApi {
  _TokenAwareApi(this.now);

  final DateTime now;

  @override
  Future<WorkspaceRef> resolveWorkspace(String hint, String token) async {
    return const WorkspaceRef(id: 'wrk_test', name: 'Test');
  }

  @override
  Future<UsagePage> fetchUsagePage(
    String token,
    String workspaceId, {
    String? cursor,
    int limit = 100,
    int? sinceMs,
  }) async {
    if (token == 'st_bad') throw const AuthException();
    return UsagePage(records: [_rec('good', now)]);
  }

  @override
  Future<Map<String, String>> fetchKeyNames(
    String token,
    String workspaceId,
  ) async => const {};
}

class _FlakyQuotaApi extends OpenCodeApi {
  int calls = 0;

  @override
  Future<QuotaResult> fetchQuota(
    String token, {
    String workspaceHint = 'Default',
  }) async {
    calls++;
    if (calls > 1) {
      return QuotaResult(
        name: 'Test',
        workspaceId: 'wrk_test',
        success: false,
        updatedAt: DateTime.now().toUtc(),
        error: 'network down',
      );
    }
    return QuotaResult(
      name: 'Test',
      workspaceId: 'wrk_test',
      success: true,
      updatedAt: DateTime.now().toUtc(),
      windows: const [
        QuotaWindow(
          label: '5h Rolling',
          used: 1,
          remaining: 99,
          total: 100,
          unit: '%',
          resetAt: null,
          resetInSec: 100,
        ),
      ],
    );
  }
}

class _CountingQuotaApi extends OpenCodeApi {
  int quotaCalls = 0;

  @override
  Future<QuotaResult> fetchQuota(
    String token, {
    String workspaceHint = 'Default',
  }) async {
    quotaCalls++;
    return QuotaResult(
      name: 'Test',
      workspaceId: 'wrk_test',
      success: true,
      updatedAt: DateTime.now().toUtc(),
      windows: const [
        QuotaWindow(
          label: '5h Rolling',
          used: 1,
          remaining: 99,
          total: 100,
          unit: '%',
          resetAt: null,
          resetInSec: 100,
        ),
      ],
    );
  }
}
