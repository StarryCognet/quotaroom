import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/i18n.dart';
import '../data/account_repository.dart';
import '../data/app_database.dart';
import '../data/background_sync.dart';
import '../data/export_service.dart';
import '../data/fx_service.dart';
import '../data/models.dart';
import '../data/notification_service.dart';
import '../data/opencode_api.dart';
import '../data/prefs.dart';
import '../data/settings_repository.dart';
import '../data/sync_service.dart';
import '../data/update_service.dart';
import '../data/usage_repository.dart';
import '../data/widget_service.dart';

/// Single app-wide state holder. Repositories stay synchronous/awaited; this
/// class exposes the data each page needs and notifies listeners.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({
    required this.db,
    required this.api,
    required this.prefs,
    required this.settingsRepo,
    required this.accountRepo,
    required this.usageRepo,
    required this.syncService,
    required this.fxService,
    NotificationService? notifications,
    WidgetService? widgetService,
    UpdateService? updateService,
  }) : notifications = notifications ?? NotificationService(),
       widgetService = widgetService ?? WidgetService(),
       updateService = updateService ?? UpdateService();

  final AppDatabase db;
  final OpenCodeApi api;
  final Prefs prefs;
  final SettingsRepository settingsRepo;
  final AccountRepository accountRepo;
  final UsageRepository usageRepo;
  final SyncService syncService;
  final FxService fxService;
  final NotificationService notifications;
  final WidgetService widgetService;
  final UpdateService updateService;

  bool initialized = false;
  bool loading = true;
  bool loadingDashboard = false;
  String? errorMessage;
  String? initError;

  List<Account> accounts = const [];
  Account? activeAccount;
  Settings settings = const Settings();
  DashboardData? dashboard;
  List<AccountOverview> overviews = const [];
  Map<String, String> keyNames = const {};
  SyncProgress progress = SyncProgress.idle;
  SyncResult? lastSyncResult;
  List<Map<String, Object?>> syncLog = const [];
  UpdateInfo? availableUpdate;
  bool checkingUpdate = false;
  String? updateError;
  DateTime? lastUpdateCheck;

  String dashboardRange = 'today';
  String language = 'zh';
  String themeMode = 'system';
  String currency = 'CNY';
  double usdCny = 7.2;
  String databasePath = '';

  Timer? _autoSyncTimer;
  StreamSubscription<SyncProgress>? _progressSubscription;

  L10n get l10n => L10n(language);

  bool get hasLoggedInAccount => accounts.any((account) => account.hasToken);

  bool get isLoggedIn => activeAccount?.hasToken == true;

  bool get syncing => progress.running || (syncService.running);

  bool get autoSync => settings.autoSync;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    language = prefs.language;
    themeMode = prefs.themeMode;
    currency = prefs.currency;
    lastUpdateCheck = prefs.updateCheckedAt;
    databasePath = db.db.path;
    try {
      settings = await settingsRepo.getSettings();
      keyNames = await settingsRepo.getKeyNames();
      syncLog = await settingsRepo.getSyncLog();
      await notifications.init();
      await reloadAccounts();
      await _ensureActiveLoggedIn();
      unawaited(configureBackgroundSync(this));
      _progressSubscription = syncService.progressStream.listen((value) {
        progress = value;
        notifyListeners();
      });
      // Show the shell/login immediately; quota/dashboard refresh in the
      // background so a slow network never blocks app startup.
      initialized = true;
      loading = false;
      loadingDashboard = hasLoggedInAccount;
      notifyListeners();
      try {
        usdCny = await fxService.usdCny();
      } catch (_) {
        usdCny = FxService.fallbackRate;
      }
      if (hasLoggedInAccount) {
        await refreshDashboard();
        try {
          await refreshOverviews();
        } catch (_) {
          // Overview is secondary; the dashboard is already usable.
        }
        startAutoSync();
      } else {
        unawaited(widgetService.clear(language: language));
      }
      initError = null;
    } catch (e) {
      initError = e.toString();
    }
    initialized = true;
    loading = false;
    notifyListeners();
  }

  Future<void> reloadAccounts() async {
    accounts = await accountRepo.listAccounts();
    final activeId = await accountRepo.activeAccountId();
    activeAccount = null;
    for (final account in accounts) {
      if (account.id == activeId) {
        activeAccount = account;
        break;
      }
    }
    if (activeAccount == null) {
      for (final account in accounts) {
        if (account.hasToken) {
          activeAccount = account;
          break;
        }
      }
    }
    activeAccount ??= accounts.isEmpty ? null : accounts.first;
  }

  Future<void> refreshDashboard({bool forceQuota = false}) async {
    final account = activeAccount;
    if (account == null || !account.hasToken) {
      dashboard = null;
      loadingDashboard = false;
      notifyListeners();
      return;
    }
    loadingDashboard = true;
    notifyListeners();
    try {
      // Local aggregates first so a slow quota request never blocks the page.
      final totals = await usageRepo.totals(account.id, dashboardRange);
      final today = await usageRepo.totals(account.id, 'today');
      final daily7 = fillDays(await usageRepo.dailyStats(account.id, 7), 7);
      final trend30 = fillDays(await usageRepo.dailyStats(account.id, 30), 30);
      final todayTrend = await usageRepo.todayTrend(account.id);
      final models = await usageRepo.modelStats(account.id, dashboardRange);
      final sync = await usageRepo.syncState(account.id);
      final previous = _previousRange();
      final previousTotals = previous.fromMs != null
          ? await usageRepo.totalsBetween(
              account.id,
              fromMs: previous.fromMs,
              toMs: previous.toMs,
            )
          : Totals.zero;
      final modelKeys = await usageRepo.modelKeyStats(
        account.id,
        dashboardRange,
      );
      final topExpensive = await usageRepo.topExpensive(
        account.id,
        dashboardRange,
      );
      dashboard = DashboardData(
        range: dashboardRange,
        totals: totals,
        today: today,
        daily7: daily7,
        trend30: trend30,
        todayTrend: todayTrend,
        models: models,
        modelKeys: modelKeys,
        topExpensive: topExpensive,
        previousTotals: previousTotals,
        previousRange: previous.label,
        quota: syncService.peekQuota(account.id),
        sync: sync,
        accountName: account.name,
      );
      errorMessage = null;
      loadingDashboard = false;
      notifyListeners();
      unawaited(_publishWidget());
      unawaited(_evaluateNotifications());
      unawaited(_refreshQuota(account, forceQuota));
    } catch (e) {
      loadingDashboard = false;
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _publishWidget() async {
    final data = dashboard;
    final account = activeAccount;
    if (data == null || account == null) return;
    await widgetService.update(
      accountName: account.name,
      quota: data.quota,
      today: data.today,
      language: language,
      currency: currency,
      usdCny: usdCny,
      syncError: errorMessage,
    );
  }

  Future<void> _evaluateNotifications() async {
    if (!settings.notificationsEnabled) return;
    final data = dashboard;
    final account = activeAccount;
    if (data == null || account == null) return;
    await notifications.evaluate(
      enabled: true,
      language: language,
      accountName: account.name,
      quota: data.quota,
      today: data.today,
      dailyBudgetUsd: settings.dailyBudgetUsd,
      currency: currency,
      usdCny: usdCny,
    );
  }

  Future<void> _refreshQuota(Account account, bool force) async {
    try {
      final quota = await syncService.quotaFor(account, force: force);
      if (activeAccount?.id != account.id) return;
      final current = dashboard;
      if (current == null) return;
      dashboard = current.copyWith(quota: quota);
      notifyListeners();
      unawaited(_publishWidget());
      unawaited(_evaluateNotifications());
    } catch (_) {
      // Keep the cached quota; a transient quota error must not blank the page.
    }
  }

  Future<void> refreshOverviews() async {
    final result = <AccountOverview>[];
    for (final account in accounts) {
      if (!account.hasToken) continue;
      try {
        final quota = await syncService.quotaFor(account);
        final today = await usageRepo.totals(account.id, 'today');
        final todayTrend = await usageRepo.todayTrend(account.id);
        final daily7 = fillDays(await usageRepo.dailyStats(account.id, 7), 7);
        final sync = await usageRepo.syncState(account.id);
        result.add(
          AccountOverview(
            account: account,
            quota: quota,
            today: today,
            todayTrend: todayTrend,
            daily7: daily7,
            lastSyncAt: sync.lastSyncAt,
            lastSyncStatus: sync.lastSyncStatus,
          ),
        );
      } catch (_) {
        // One broken account must not hide the others.
      }
    }
    overviews = result;
    notifyListeners();
  }

  /// If the configured active account is signed out but another account is
  /// still signed in, switch to the signed-in one instead of showing an empty
  /// dashboard.
  Future<void> _ensureActiveLoggedIn() async {
    final current = activeAccount;
    if (current != null && current.hasToken) return;
    for (final account in accounts) {
      if (account.hasToken) {
        await accountRepo.setActive(account.id);
        await reloadAccounts();
        return;
      }
    }
  }

  Future<void> setRange(String range) async {
    if (dashboardRange == range) return;
    dashboardRange = range;
    notifyListeners();
    await refreshDashboard();
  }

  Future<SyncResult> syncNow({bool full = false}) async {
    if (syncing) {
      return const SyncResult(ok: false, error: '已有同步任务进行中');
    }
    final result = full
        ? await syncService.syncFull()
        : await syncService.syncIncremental();
    await _logSync(result, full ? 'full' : 'incremental');
    lastSyncResult = result;
    if (result.ok) {
      try {
        keyNames = await settingsRepo.getKeyNames();
        await refreshDashboard(forceQuota: true);
        await refreshOverviews();
      } catch (e) {
        errorMessage = e.toString();
      }
    } else {
      errorMessage = result.error;
    }
    notifyListeners();
    return result;
  }

  Future<void> addAccountWithToken(String rawToken, {String? name}) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw const OpenCodeApiException('Cookie 为空');
    }
    final workspace = await api.resolveWorkspace('Default', token);
    final account = await accountRepo.addAccount(
      token: token,
      workspaceId: workspace.id,
      name: name == null || name.trim().isEmpty
          ? (workspace.name.isEmpty ? null : workspace.name)
          : name.trim(),
    );
    await accountRepo.setActive(account.id);
    await reloadAccounts();
    keyNames = await settingsRepo.getKeyNames();
    syncService.clearQuotaCache();
    notifyListeners();
    await refreshDashboard(forceQuota: true);
    await refreshOverviews();
    startAutoSync();
    // First login pulls the 30-day history in the background.
    unawaited(_backgroundFullSync());
  }

  Future<void> reloginActiveWithToken(String rawToken) async {
    final account = activeAccount;
    if (account == null) {
      throw const OpenCodeApiException('没有可重新登录的账号');
    }
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw const OpenCodeApiException('Cookie 为空');
    }
    final workspace = await api.resolveWorkspace('Default', token);
    await accountRepo.saveToken(account.id, token);
    await accountRepo.saveWorkspace(
      account.id,
      hint: workspace.id,
      resolved: workspace.id,
    );
    await reloadAccounts();
    keyNames = await settingsRepo.getKeyNames();
    syncService.clearQuotaCache(account.id);
    notifyListeners();
    await refreshDashboard(forceQuota: true);
    startAutoSync();
    unawaited(_backgroundFullSync());
  }

  Future<void> _backgroundFullSync() async {
    try {
      final result = await syncService.syncFull();
      await _logSync(result, 'full');
      lastSyncResult = result;
      if (result.ok) {
        keyNames = await settingsRepo.getKeyNames();
        await refreshDashboard(forceQuota: true);
        await refreshOverviews();
      } else {
        errorMessage = result.error;
      }
    } catch (e) {
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> switchAccount(int accountId) async {
    await accountRepo.setActive(accountId);
    await reloadAccounts();
    syncService.clearQuotaCache();
    await refreshDashboard(forceQuota: true);
    await refreshOverviews();
    notifyListeners();
  }

  Future<void> renameAccount(int accountId, String name) async {
    await accountRepo.rename(accountId, name);
    await reloadAccounts();
    notifyListeners();
  }

  Future<void> deleteAccount(int accountId) async {
    await accountRepo.deleteAccount(accountId);
    syncService.clearQuotaCache(accountId);
    await reloadAccounts();
    await _ensureActiveLoggedIn();
    if (hasLoggedInAccount) {
      await refreshDashboard(forceQuota: true);
    } else {
      dashboard = null;
      unawaited(widgetService.clear(language: language));
    }
    await refreshOverviews();
    startAutoSync();
    notifyListeners();
  }

  Future<void> logoutActive() async {
    final account = activeAccount;
    if (account == null) return;
    await logoutAccount(account.id);
  }

  Future<void> logoutAccount(int accountId) async {
    await accountRepo.logoutAccount(accountId);
    syncService.clearQuotaCache(accountId);
    await reloadAccounts();
    await _ensureActiveLoggedIn();
    if (hasLoggedInAccount) {
      await refreshDashboard(forceQuota: true);
      await refreshOverviews();
    } else {
      dashboard = null;
      overviews = const [];
      unawaited(widgetService.clear(language: language));
    }
    startAutoSync();
    notifyListeners();
  }

  Future<void> updateSettings({
    int? syncIntervalSec,
    int? windowDays,
    bool? autoSync,
    bool? showAccountsPanel,
  }) async {
    final next = settings.copyWith(
      syncIntervalSec: syncIntervalSec,
      windowDays: windowDays,
      autoSync: autoSync,
      showAccountsPanel: showAccountsPanel,
    );
    settings = await settingsRepo.saveSettings(next);
    startAutoSync();
    notifyListeners();
  }

  ({int? fromMs, int? toMs, String? label}) _previousRange() {
    final now = DateTime.now();
    switch (dashboardRange) {
      case 'today':
        final todayStart = DateTime(now.year, now.month, now.day);
        final prevStart = todayStart.subtract(const Duration(days: 1));
        return (
          fromMs: prevStart.millisecondsSinceEpoch,
          toMs: todayStart.millisecondsSinceEpoch,
          label: 'yesterday',
        );
      case '7d':
        return (
          fromMs: now.subtract(const Duration(days: 14)).millisecondsSinceEpoch,
          toMs: now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
          label: 'prev7d',
        );
      case '30d':
        return (
          fromMs: now.subtract(const Duration(days: 60)).millisecondsSinceEpoch,
          toMs: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
          label: 'prev30d',
        );
      default:
        return (fromMs: null, toMs: null, label: null);
    }
  }

  Future<void> _logSync(SyncResult result, String mode) async {
    try {
      await settingsRepo.addSyncLog({
        'at': DateTime.now().toUtc().toIso8601String(),
        'mode': mode,
        'ok': result.ok,
        'partial': result.partial,
        'inserted': result.inserted,
        'error': result.error ?? '',
        'account': activeAccount?.name ?? '',
      });
      syncLog = await settingsRepo.getSyncLog();
    } catch (_) {
      // Logging must never break the sync flow.
    }
  }

  /// Merges usage history from a `.db` backup into the active account. Tokens
  /// stay untouched because backups never contain credentials.
  Future<int> restoreUsageFromBackup(List<int> bytes) async {
    final account = activeAccount;
    if (account == null) {
      throw const OpenCodeApiException('没有可恢复数据的账号');
    }
    final service = ExportService(db: db.db, usage: usageRepo);
    final restored = await service.restoreUsageFromBytes(account.id, bytes);
    syncService.clearQuotaCache(account.id);
    keyNames = await settingsRepo.getKeyNames();
    await refreshDashboard(forceQuota: true);
    await refreshOverviews();
    notifyListeners();
    return restored;
  }

  /// Checks GitHub at most once per 24h unless [force] is set. Throws on
  /// network errors so the manual "check update" row can show the reason.
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    if (!force && !shouldAutoCheckUpdate) return null;
    checkingUpdate = true;
    updateError = null;
    notifyListeners();
    try {
      final info = await updateService.check();
      lastUpdateCheck = DateTime.now();
      await prefs.setUpdateCheckedAt(lastUpdateCheck!);
      availableUpdate = info.hasUpdate ? info : null;
      return info;
    } catch (e) {
      updateError = e.toString();
      rethrow;
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  bool get shouldAutoCheckUpdate {
    final last = lastUpdateCheck;
    return last == null ||
        DateTime.now().difference(last) >= const Duration(hours: 24);
  }

  bool isUpdateDismissed(String version) =>
      prefs.dismissedUpdateVersion == version;

  Future<void> dismissUpdate(String version) =>
      prefs.setDismissedUpdateVersion(version);

  Future<void> setDailyBudget(double? usd) async {
    final value = usd != null && usd > 0 ? usd : null;
    final next = settings.copyWith(
      dailyBudgetUsd: value,
      clearDailyBudget: value == null,
    );
    settings = await settingsRepo.saveSettings(next);
    notifyListeners();
  }

  Future<bool> setNotificationsEnabled(bool value) async {
    var enabled = value;
    if (value && !await notifications.requestPermission()) {
      enabled = false;
    }
    final next = settings.copyWith(notificationsEnabled: enabled);
    settings = await settingsRepo.saveSettings(next);
    notifyListeners();
    return enabled;
  }

  Future<bool> sendTestNotification() {
    return notifications.showTest(language: language);
  }

  Future<void> setAmoled(bool value) async {
    final next = settings.copyWith(amoled: value);
    settings = await settingsRepo.saveSettings(next);
    notifyListeners();
  }

  Future<void> setWindowDays(int? value) async {
    final next = settings.copyWith(
      windowDays: value,
      clearWindowDays: value == null,
    );
    settings = await settingsRepo.saveSettings(next);
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value == 'en' ? 'en' : 'zh';
    await prefs.setLanguage(language);
    notifyListeners();
    unawaited(_publishWidget());
  }

  Future<void> setThemeMode(String value) async {
    themeMode = switch (value) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    };
    await prefs.setThemeMode(themeMode);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    final isDark =
        themeMode == 'dark' ||
        (themeMode == 'system' &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    await setThemeMode(isDark ? 'light' : 'dark');
  }

  Future<void> setCurrency(String value) async {
    currency = value == 'USD' ? 'USD' : 'CNY';
    await prefs.setCurrency(currency);
    notifyListeners();
    unawaited(_publishWidget());
  }

  Future<void> refreshFx({bool force = false}) async {
    usdCny = await fxService.usdCny(force: force);
    notifyListeners();
  }

  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    unawaited(configureBackgroundSync(this));
    if (!settings.autoSync || !hasLoggedInAccount) return;
    final seconds = settings.syncIntervalSec.clamp(30, 3600).toInt();
    _autoSyncTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (syncing || !hasLoggedInAccount) return;
      unawaited(syncNow());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshAfterResume());
  }

  Future<void> _refreshAfterResume() async {
    if (!hasLoggedInAccount) return;
    try {
      syncLog = await settingsRepo.getSyncLog();
      notifyListeners();
    } catch (_) {
      // Keep the last known log.
    }
    final account = activeAccount;
    if (account == null) return;
    try {
      final persisted = await usageRepo.syncState(account.id);
      final current = dashboard?.sync.lastSyncAt;
      if (current == null ||
          (persisted.lastSyncAt?.isAfter(current) ?? false)) {
        await refreshDashboard();
      }
    } catch (_) {
      // The regular sync below will retry.
    }
    if (!settings.autoSync || syncing) return;
    final last = dashboard?.sync.lastSyncAt;
    final interval = Duration(
      seconds: settings.syncIntervalSec.clamp(30, 3600).toInt(),
    );
    if (last == null || DateTime.now().difference(last) >= interval) {
      unawaited(syncNow());
    }
  }

  /// Fills missing local dates with zero rows so charts have a continuous axis.
  static List<DailyStat> fillDays(List<DailyStat> stats, int days) {
    final byDate = {for (final stat in stats) stat.date: stat};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <DailyStat>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final key =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      result.add(byDate[key] ?? DailyStat(date: key));
    }
    return result;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _progressSubscription?.cancel();
    syncService.dispose();
    super.dispose();
  }
}
