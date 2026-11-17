import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../data/account_repository.dart';
import '../data/app_database.dart';
import '../data/fx_service.dart';
import '../data/models.dart';
import '../data/opencode_api.dart';
import '../data/prefs.dart';
import '../data/settings_repository.dart';
import '../data/sync_service.dart';
import '../data/usage_repository.dart';

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
  });

  final AppDatabase db;
  final OpenCodeApi api;
  final Prefs prefs;
  final SettingsRepository settingsRepo;
  final AccountRepository accountRepo;
  final UsageRepository usageRepo;
  final SyncService syncService;
  final FxService fxService;

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

  String dashboardRange = 'today';
  String language = 'zh';
  String themeMode = 'system';
  String currency = 'CNY';
  double usdCny = 7.2;
  String databasePath = '';

  Timer? _autoSyncTimer;
  StreamSubscription<SyncProgress>? _progressSubscription;

  L10n get l10n => L10n(language);

  bool get hasLoggedInAccount =>
      accounts.any((account) => account.hasToken);

  bool get isLoggedIn => activeAccount?.hasToken == true;

  bool get syncing => progress.running || (syncService.running);

  bool get autoSync => settings.autoSync;

  ThemeMode get themeModeValue => switch (themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    language = prefs.language;
    themeMode = prefs.themeMode;
    currency = prefs.currency;
    databasePath = db.db.path;
    try {
      settings = await settingsRepo.getSettings();
      keyNames = await settingsRepo.getKeyNames();
      await reloadAccounts();
      await _ensureActiveLoggedIn();
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
        await refreshOverviews();
        startAutoSync();
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
      final quota = await syncService.quotaFor(account, force: forceQuota);
      final totals = await usageRepo.totals(account.id, dashboardRange);
      final today = await usageRepo.totals(account.id, 'today');
      final daily7 = fillDays(
        await usageRepo.dailyStats(account.id, 7),
        7,
      );
      final trend30 = fillDays(
        await usageRepo.dailyStats(account.id, 30),
        30,
      );
      final todayTrend = await usageRepo.todayTrend(account.id);
      final models = await usageRepo.modelStats(account.id, dashboardRange);
      final sync = await usageRepo.syncState(account.id);
      dashboard = DashboardData(
        range: dashboardRange,
        totals: totals,
        today: today,
        daily7: daily7,
        trend30: trend30,
        todayTrend: todayTrend,
        models: models,
        quota: quota,
        sync: sync,
        accountName: account.name,
      );
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString();
    }
    loadingDashboard = false;
    notifyListeners();
  }

  Future<void> refreshOverviews() async {
    final result = <AccountOverview>[];
    for (final account in accounts) {
      if (!account.hasToken) continue;
      final quota = await syncService.quotaFor(account);
      final today = await usageRepo.totals(account.id, 'today');
      final todayTrend = await usageRepo.todayTrend(account.id);
      final daily7 = fillDays(
        await usageRepo.dailyStats(account.id, 7),
        7,
      );
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
    lastSyncResult = result;
    if (result.ok) {
      keyNames = await settingsRepo.getKeyNames();
      await refreshDashboard(forceQuota: true);
      await refreshOverviews();
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
    final result = await syncService.syncFull();
    lastSyncResult = result;
    if (result.ok) {
      keyNames = await settingsRepo.getKeyNames();
      await refreshDashboard(forceQuota: true);
      await refreshOverviews();
    } else {
      errorMessage = result.error;
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
    final isDark = themeMode == 'dark' ||
        (themeMode == 'system' &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    await setThemeMode(isDark ? 'light' : 'dark');
  }

  Future<void> setCurrency(String value) async {
    currency = value == 'USD' ? 'USD' : 'CNY';
    await prefs.setCurrency(currency);
    notifyListeners();
  }

  Future<void> refreshFx({bool force = false}) async {
    usdCny = await fxService.usdCny(force: force);
    notifyListeners();
  }

  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
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
    if (!settings.autoSync || !hasLoggedInAccount || syncing) return;
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
