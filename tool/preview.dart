import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:quotaroom/app.dart';
import 'package:quotaroom/data/account_repository.dart';
import 'package:quotaroom/data/app_database.dart';
import 'package:quotaroom/data/background_sync.dart';
import 'package:quotaroom/data/fx_service.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/data/opencode_api.dart';
import 'package:quotaroom/data/prefs.dart';
import 'package:quotaroom/data/settings_repository.dart';
import 'package:quotaroom/data/sync_service.dart';
import 'package:quotaroom/data/token_store.dart';
import 'package:quotaroom/data/usage_repository.dart';
import 'package:quotaroom/state/app_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

/// Developer-only entry point: seeds a month of demo data so every page can be
/// inspected without a real opencode.ai account.
///
/// Run with:
///   flutter run -t tool/preview.dart -d `device`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
  } catch (_) {
    // Preview on desktop: WorkManager is Android-only.
  }
  final path = p.join(await getDatabasesPath(), 'quotaroom_preview.db');
  await deleteDatabase(path);
  final database = await AppDatabase.open(path: path);
  final api = _DemoApi();
  final settingsRepo = SettingsRepository(database.db);
  final tokens = MemoryTokenStore();
  final accountRepo = AccountRepository(
    db: database.db,
    tokens: tokens,
    settings: settingsRepo,
  );
  final usageRepo = UsageRepository(database.db);
  await settingsRepo.saveSettings(
    const Settings(
      autoSync: false,
      windowDays: 30,
      showAccountsPanel: true,
      syncIntervalSec: 300,
    ),
  );
  await settingsRepo.mergeKeyNames(const {
    'sk_demo_1': 'MacBook Pro',
    'sk_demo_2': 'Work Desktop',
    'sk_demo_3': 'CI Runner',
  });
  final account = await accountRepo.addAccount(
    token: 'demo-token',
    workspaceId: 'wrk_demo',
    name: '演示账号',
  );
  await accountRepo.setActive(account.id);
  await _seed(usageRepo, account.id);
  await usageRepo.updateSyncState(account.id, status: 'ok', inserted: 1);
  final syncService = SyncService(
    accounts: accountRepo,
    usage: usageRepo,
    settings: settingsRepo,
    api: api,
  );
  final fxService = FxService(settings: settingsRepo, api: api);
  final prefs = await Prefs.load();
  final state = AppState(
    db: database,
    api: api,
    prefs: prefs,
    settingsRepo: settingsRepo,
    accountRepo: accountRepo,
    usageRepo: usageRepo,
    syncService: syncService,
    fxService: fxService,
  );
  unawaited(state.init());
  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const QuotaRoomApp(),
    ),
  );
}

Future<void> _seed(UsageRepository repo, int accountId) async {
  final random = Random(42);
  final now = DateTime.now();
  const models = [
    'deepseek-v4.1-flash',
    'kimi-k3',
    'glm-4.6',
    'gpt-5.2',
    'qwen3-max',
    'minimax-m2',
  ];
  const keys = ['sk_demo_1', 'sk_demo_2', 'sk_demo_3'];
  final sessionIds = List.generate(12, (index) => 'sess_demo_${index + 1}');
  final records = <UsageRecord>[];
  var sequence = 0;
  for (var dayOffset = 29; dayOffset >= 0; dayOffset--) {
    final day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: dayOffset));
    final count = dayOffset == 0
        ? max(3, now.hour + 1)
        : 5 + random.nextInt(12);
    for (var i = 0; i < count; i++) {
      final hourLimit = dayOffset == 0 ? max(1, now.hour) : 23;
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        random.nextInt(hourLimit + 1),
        random.nextInt(60),
      );
      if (at.isAfter(now)) continue;
      final model = models[random.nextInt(models.length)];
      final input = 500 + random.nextInt(9000);
      final output = 80 + random.nextInt(1800);
      final reasoning = random.nextInt(700);
      final cacheRead = random.nextInt(90000);
      final cacheWrite = random.nextInt(6000);
      final session = random.nextInt(10) == 0
          ? ''
          : sessionIds[random.nextInt(sessionIds.length)];
      final key = keys[random.nextInt(keys.length)];
      final cost =
          input * 0.0000006 +
          output * 0.0000022 +
          cacheRead * 0.00000008 +
          cacheWrite * 0.0000005;
      records.add(
        UsageRecord(
          usgId: 'demo_${sequence++}',
          createdAt: at.toUtc(),
          model: model,
          provider: 'opencode',
          inputTokens: input,
          outputTokens: output,
          reasoningTokens: reasoning,
          cacheReadTokens: cacheRead,
          cacheWrite5mTokens: cacheWrite,
          costRaw: (cost * 100000000).round(),
          costUsd: cost,
          keyId: key,
          sessionId: session,
          plan: 'go',
        ),
      );
    }
  }
  await repo.insertUsageRecords(records, accountId);
}

class _DemoApi extends OpenCodeApi {
  @override
  Future<QuotaResult> fetchQuota(
    String token, {
    String workspaceHint = 'Default',
  }) async {
    final now = DateTime.now().toUtc();
    return QuotaResult(
      name: '演示账号',
      workspaceId: 'wrk_demo',
      success: true,
      updatedAt: now,
      windows: [
        QuotaWindow(
          label: '5h Rolling',
          used: 42.5,
          remaining: 57.5,
          total: 100,
          unit: '%',
          resetAt: now.add(const Duration(hours: 2, minutes: 14)),
          resetInSec: 2 * 3600 + 14 * 60,
        ),
        QuotaWindow(
          label: 'Weekly',
          used: 68.2,
          remaining: 31.8,
          total: 100,
          unit: '%',
          resetAt: now.add(const Duration(days: 3, hours: 8)),
          resetInSec: 3 * 86400 + 8 * 3600,
        ),
        QuotaWindow(
          label: 'Monthly',
          used: 31.8,
          remaining: 68.2,
          total: 100,
          unit: '%',
          resetAt: now.add(const Duration(days: 18, hours: 4)),
          resetInSec: 18 * 86400 + 4 * 3600,
        ),
      ],
    );
  }

  @override
  Future<UsagePage> fetchUsagePage(
    String token,
    String workspaceId, {
    String? cursor,
    int limit = 100,
    int? sinceMs,
  }) async => const UsagePage();

  @override
  Future<Map<String, String>> fetchKeyNames(
    String token,
    String workspaceId,
  ) async => const {};

  @override
  Future<double> fetchUsdCny() async => 7.18;
}
