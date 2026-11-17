import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

UsageRecord _rec({
  required String id,
  required DateTime at,
  String model = 'deepseek-v4',
  String session = 's1',
  String key = 'sk_1',
  int input = 100,
  int output = 50,
  int reasoning = 10,
  int cacheRead = 0,
  int cacheWrite = 0,
  double cost = 0.001,
}) {
  return UsageRecord(
    usgId: id,
    createdAt: at,
    model: model,
    inputTokens: input,
    outputTokens: output,
    reasoningTokens: reasoning,
    cacheReadTokens: cacheRead,
    cacheWrite5mTokens: cacheWrite,
    costRaw: (cost * 100000000).round(),
    costUsd: cost,
    sessionId: session,
    keyId: key,
    plan: 'go',
  );
}

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late UsageRepository repo;
  const accountId = 1;

  setUp(() async {
    appDb = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = UsageRepository(appDb.db);
  });

  tearDown(() async {
    await appDb.close();
  });

  test('totals and hit rate follow desktop formulas', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, input: 100, cacheRead: 300, cacheWrite: 50),
      _rec(id: 'b', at: now, input: 200, cacheRead: 100),
    ], accountId);
    final totals = await repo.totals(accountId, 'all');
    expect(totals.requestCount, 2);
    expect(totals.totalInputTokens, 100 + 300 + 50 + 200 + 100);
    expect(totals.uncachedInputTokens, 300);
    expect(totals.cacheHitTokens, 400);
    expect(totals.cacheWriteTokens, 50);
    expect(totals.totalOutputTokens, 100);
    expect(totals.totalReasoningTokens, 20);
    // 400 / (400 + 300) = 57.14%
    expect(totals.hitRate, closeTo(57.14, 0.01));
  });

  test('today range excludes yesterday', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'today', at: now),
      _rec(id: 'old', at: now.subtract(const Duration(hours: 25))),
    ], accountId);
    expect((await repo.totals(accountId, 'today')).requestCount, 1);
    expect((await repo.totals(accountId, '7d')).requestCount, 2);
    expect((await repo.totals(accountId, 'all')).requestCount, 2);
  });

  test('model stats group and order by token volume', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'small', input: 10),
      _rec(id: 'b', at: now, model: 'big', input: 1000),
      _rec(id: 'c', at: now, model: 'big', input: 500),
    ], accountId);
    final stats = await repo.modelStats(accountId, 'all');
    expect(stats, hasLength(2));
    expect(stats.first.model, 'big');
    expect(stats.first.requestCount, 2);
    expect(stats.first.totalInputTokens, 1500);
  });

  test('daily stats and 24-hour trend use local buckets', () async {
    final now = DateTime.now();
    final noon = DateTime(now.year, now.month, now.day, 12);
    await repo.insertUsageRecords([
      _rec(id: 'a', at: noon, input: 10, output: 5),
    ], accountId);
    final daily = await repo.dailyStats(accountId, 7);
    expect(daily, hasLength(1));
    expect(daily.first.date, hasLength(10));
    expect(daily.first.requestCount, 1);
    final trend = await repo.todayTrend(accountId);
    expect(trend, hasLength(24));
    expect(trend[12].input, 10);
    expect(trend[12].output, 5);
    expect(trend[11].input, 0);
  });

  test('sessions group by session, then key, and blank key ids', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, session: 's1', key: 'sk_a', input: 100),
      _rec(id: 'b', at: now, session: 's1', key: 'sk_a', input: 50),
      _rec(id: 'c', at: now, session: '', key: 'sk_b', input: 10),
      _rec(id: 'd', at: now, session: '', key: '', input: 5),
    ], accountId);
    final sessions = await repo.sessionsPage(accountId, pageSize: 10);
    expect(sessions.total, 3);
    final s1 = sessions.records.firstWhere((s) => s.sessionId == 's1');
    expect(s1.requestCount, 2);
    expect(s1.totalInputTokens, 150);
    expect(sessions.records.any((s) => s.sessionId.isEmpty), isTrue);
  });

  test('records page filters by model and paginates', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now, model: 'm1'),
      _rec(id: 'b', at: now.subtract(const Duration(minutes: 1)), model: 'm2'),
      _rec(id: 'c', at: now.subtract(const Duration(minutes: 2)), model: 'm2'),
    ], accountId);
    final all = await repo.recordsPage(accountId, page: 1, pageSize: 2);
    expect(all.total, 3);
    expect(all.records, hasLength(2));
    expect(all.records.first.usgId, 'a');
    final filtered = await repo.recordsPage(accountId, model: 'm2');
    expect(filtered.total, 2);
    expect(await repo.models(accountId), ['m1', 'm2']);
  });

  test('duplicate usg_id refreshes usage fields without new row', () async {
    final now = DateTime.now();
    expect(
      await repo.insertUsageRecords([
        _rec(id: 'a', at: now, input: 100),
      ], accountId),
      1,
    );
    expect(
      await repo.insertUsageRecords([
        _rec(id: 'a', at: now, input: 999, output: 222),
      ], accountId),
      0,
    );
    final page = await repo.recordsPage(accountId);
    expect(page.total, 1);
    expect(page.records.first.inputTokens, 999);
    expect(page.records.first.outputTokens, 222);
  });

  test('prune removes rows outside the window', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'old', at: now.subtract(const Duration(days: 40))),
      _rec(id: 'new', at: now),
    ], accountId);
    final removed = await repo.pruneOldRecords(accountId, 30);
    expect(removed, 1);
    expect((await repo.recordsPage(accountId)).total, 1);
  });

  test('sync state accumulates inserted count and refreshes totals', () async {
    final now = DateTime.now();
    await repo.insertUsageRecords([
      _rec(id: 'a', at: now),
      _rec(id: 'b', at: now),
    ], accountId);
    await repo.updateSyncState(
      accountId,
      status: 'ok',
      inserted: 2,
    );
    final state = await repo.syncState(accountId);
    expect(state.lastSyncStatus, 'ok');
    expect(state.lastInsertedCount, 2);
    expect(state.totalRecords, 2);
    expect(state.newestRecordAt, isNotNull);
    expect(state.oldestRecordAt, isNotNull);
  });
}
