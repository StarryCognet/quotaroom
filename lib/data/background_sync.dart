import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/platform.dart';
import '../state/app_state.dart' show AppState;
import 'account_repository.dart';
import 'app_database.dart';
import 'fx_service.dart';
import 'models.dart';
import 'notification_service.dart';
import 'opencode_api.dart';
import 'prefs.dart';
import 'settings_repository.dart';
import 'sync_service.dart';
import 'token_store.dart';
import 'usage_repository.dart';
import 'widget_service.dart';

const String backgroundSyncTask = 'quotaroom.backgroundSync';
const String backgroundSyncUnique = 'quotaroom.periodicSync';

/// Registers the WorkManager dispatcher on Android. Desktop relies on the
/// in-app timer in `AppState` instead, so this is a no-op there.
Future<void> initBackgroundSync() async {
  if (!supportsAndroidIntegrations) return;
  try {
    await Workmanager().initialize(backgroundSyncDispatcher);
  } catch (e) {
    debugPrint('QuotaRoom WorkManager init failed: $e');
  }
}

/// WorkManager entry point. Runs in a background Flutter isolate; plugin
/// registration is provided by the WorkManager engine.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundSync();
      return true;
    } catch (e, stack) {
      debugPrint('QuotaRoom background sync failed: $e\n$stack');
      return false;
    }
  });
}

/// Syncs all signed-in accounts, then refreshes quota, notifications and the
/// home-screen widget. Safe to call from a background isolate.
Future<void> runBackgroundSync() async {
  if (!supportsAndroidIntegrations) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final database = await AppDatabase.open();
  try {
    final prefs = await Prefs.load();
    final settingsRepo = SettingsRepository(database.db);
    final settings = await settingsRepo.getSettings();
    if (!settings.autoSync) return;

    final api = OpenCodeApi();
    final accountRepo = AccountRepository(
      db: database.db,
      tokens: SecureTokenStore(),
      settings: settingsRepo,
    );
    final active = await accountRepo.activeAccount();
    if (active == null || !active.hasToken) return;

    final usageRepo = UsageRepository(database.db);
    final syncService = SyncService(
      accounts: accountRepo,
      usage: usageRepo,
      settings: settingsRepo,
      api: api,
    );
    final result = await syncService.syncIncremental();
    await settingsRepo.addSyncLog({
      'at': DateTime.now().toUtc().toIso8601String(),
      'mode': 'background',
      'ok': result.ok,
      'partial': result.partial,
      'inserted': result.inserted,
      'error': result.error ?? '',
      'account': active.name,
    });

    QuotaResult? quota;
    try {
      quota = await syncService.quotaFor(active, force: true);
    } catch (_) {
      quota = null;
    }
    final today = await usageRepo.totals(active.id, 'today');
    final fx = FxService(settings: settingsRepo, api: api);
    final rate = await fx.usdCny();

    final notifications = NotificationService();
    await notifications.evaluate(
      enabled: settings.notificationsEnabled,
      language: prefs.language,
      accountName: active.name,
      quota: quota,
      today: today,
      dailyBudgetUsd: settings.dailyBudgetUsd,
      currency: prefs.currency,
      usdCny: rate,
    );
    await WidgetService().update(
      accountName: active.name,
      quota: quota,
      today: today,
      language: prefs.language,
      currency: prefs.currency,
      usdCny: rate,
      syncError: result.ok ? null : result.error,
    );
    syncService.dispose();
  } finally {
    await database.close();
  }
}

/// Registers or cancels the periodic background sync according to user
/// settings. WorkManager's minimum interval is 15 minutes.
class BackgroundSyncScheduler {
  static Future<void> configure({
    required bool enabled,
    required int syncIntervalSec,
  }) async {
    if (!supportsAndroidIntegrations) return;
    try {
      if (!enabled) {
        await Workmanager().cancelByUniqueName(backgroundSyncUnique);
        return;
      }
      final seconds = syncIntervalSec < 900 ? 900 : syncIntervalSec;
      await Workmanager().registerPeriodicTask(
        backgroundSyncUnique,
        backgroundSyncTask,
        frequency: Duration(seconds: seconds),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (e) {
      debugPrint('QuotaRoom background schedule failed: $e');
    }
  }
}

/// Keeps `AppState` and the scheduler in sync; used from the main isolate.
Future<void> configureBackgroundSync(AppState state) {
  return BackgroundSyncScheduler.configure(
    enabled: state.settings.autoSync && state.hasLoggedInAccount,
    syncIntervalSec: state.settings.syncIntervalSec,
  );
}
