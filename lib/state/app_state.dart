import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/desktop_shell.dart';
import '../core/i18n.dart';
import '../core/platform.dart';
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
import 'records_navigation.dart';

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
  bool authRequired = false;
  bool _errorFromSync = false;
  bool _initializing = false;
  int _dashboardRequest = 0;
  int _overviewRequest = 0;

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

  /// One-shot navigation request consumed by the records page.
  final ValueNotifier<RecordsNavigationRequest?> recordsNavigation =
      ValueNotifier<RecordsNavigationRequest?>(null);

  String dashboardRange = 'today';
  DateTime? customRangeFrom;
  DateTime? customRangeTo;
  String languagePreference = 'system';
  String language = 'zh';
  String themeMode = 'system';
  String currency = 'CNY';
  double usdCny = 7.2;
  String databasePath = '';

  Timer? _autoSyncTimer;
  StreamSubscription<SyncProgress>? _progressSubscription;

  L10n get l10n => L10n(language);

  String? get customRangeLabel {
    final from = customRangeFrom;
    final to = customRangeTo;
    if (from == null || to == null) return null;
    String fmt(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return '${fmt(from)} – ${fmt(to)}';
  }

  bool get hasLoggedInAccount => accounts.any((account) => account.hasToken);

  bool get isLoggedIn => activeAccount?.hasToken == true;

  bool get syncing => progress.running || (syncService.running);

  bool get autoSync => settings.autoSync;

  Future<void> init() async {
    if (_initializing) return;
    _initializing = true;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    languagePreference = prefs.language;
    language = _resolveLanguage(languagePreference);
    themeMode = prefs.themeMode;
    currency = prefs.currency;
    lastUpdateCheck = prefs.updateCheckedAt;
    databasePath = db.db.path;
    try {
      settings = await settingsRepo.getSettings();
      keyNames = await settingsRepo.getKeyNames();
      syncLog = await settingsRepo.getSyncLog();
      await notifications.init(
        onTap: () {
          if (isDesktop) unawaited(DesktopShell.instance.showWindow());
        },
      );
      await reloadAccounts();
      await _ensureActiveLoggedIn();
      if (isDesktop) {
        unawaited(
          DesktopShell.instance.attach(
            onSync: () async {
              await syncNow();
            },
            language: () => language,
          ),
        );
      }
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
    _initializing = false;
    notifyListeners();
  }

  String _resolveLanguage(String preference) {
    if (preference == 'zh' || preference == 'en') return preference;
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode
        .toLowerCase();
    // Chinese locales get Chinese; every other locale gets English instead of
    // being locked into Chinese on first run.
    return code.startsWith('zh') ? 'zh' : 'en';
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
      _dashboardRequest++;
      dashboard = null;
      loadingDashboard = false;
      notifyListeners();
      return;
    }
    // Capture the request identity before the first await. A slow read for
    // account A / range "30d" must never overwrite a newer account/range.
    final requestId = ++_dashboardRequest;
    final accountId = account.id;
    final accountVersion = account.updatedAt;
    final range = dashboardRange;
    final rangeFrom = customRangeFrom;
    final rangeTo = customRangeTo;
    final bounds = _rangeBounds(range, rangeFrom, rangeTo);
    loadingDashboard = true;
    notifyListeners();
    try {
      // Local aggregates first so a slow quota request never blocks the page.
      final totals = await usageRepo.totalsBetween(
        account.id,
        fromMs: bounds.fromMs,
        toMs: bounds.toMs,
      );
      final today = await usageRepo.totals(account.id, 'today');
      final daily7 = fillDays(await usageRepo.dailyStats(account.id, 7), 7);
      final trend30 = fillDays(await usageRepo.dailyStats(account.id, 30), 30);
      final todayTrend = await usageRepo.todayTrend(account.id);
      final models = await usageRepo.modelStats(
        account.id,
        range,
        rangeFromMs: bounds.fromMs,
        rangeToMs: bounds.toMs,
      );
      final sync = await usageRepo.syncState(account.id);
      final previous = _previousRange(
        range,
        customFrom: rangeFrom,
        customTo: rangeTo,
      );
      final previousTotals = previous.fromMs != null
          ? await usageRepo.totalsBetween(
              account.id,
              fromMs: previous.fromMs,
              toMs: previous.toMs,
            )
          : Totals.zero;
      final modelKeys = await usageRepo.modelKeyStats(
        account.id,
        range,
        rangeFromMs: bounds.fromMs,
        rangeToMs: bounds.toMs,
      );
      final topExpensive = await usageRepo.topExpensive(
        account.id,
        range,
        rangeFromMs: bounds.fromMs,
        rangeToMs: bounds.toMs,
      );
      if (!_dashboardStillCurrent(
        requestId,
        accountId,
        accountVersion,
        range,
        rangeFrom,
        rangeTo,
      )) {
        return;
      }
      dashboard = DashboardData(
        range: range,
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
      // A local dashboard read must not silently clear a sync/auth error.
      if (!_errorFromSync) errorMessage = null;
      loadingDashboard = false;
      notifyListeners();
      unawaited(_publishWidget());
      unawaited(_evaluateNotifications());
      unawaited(_refreshQuota(account, forceQuota));
    } catch (e) {
      if (!_dashboardStillCurrent(
        requestId,
        accountId,
        accountVersion,
        range,
        rangeFrom,
        rangeTo,
      )) {
        return;
      }
      loadingDashboard = false;
      errorMessage = e.toString();
      _errorFromSync = false;
      notifyListeners();
    }
  }

  String _accountsSignature() => accounts
      .map(
        (account) =>
            '${account.id}:${account.updatedAt?.millisecondsSinceEpoch}',
      )
      .join(',');

  bool _dashboardStillCurrent(
    int requestId,
    int accountId,
    DateTime? accountVersion,
    String range,
    DateTime? rangeFrom,
    DateTime? rangeTo,
  ) {
    final account = activeAccount;
    return requestId == _dashboardRequest &&
        account?.id == accountId &&
        account?.updatedAt == accountVersion &&
        account?.hasToken == true &&
        dashboardRange == range &&
        customRangeFrom == rangeFrom &&
        customRangeTo == rangeTo;
  }

  ({int? fromMs, int? toMs}) _rangeBounds(
    String range,
    DateTime? customFrom,
    DateTime? customTo,
  ) {
    final now = DateTime.now();
    switch (range) {
      case 'today':
        return (
          fromMs: DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
          toMs: null,
        );
      case '7d':
        return (
          fromMs: now.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
          toMs: null,
        );
      case '30d':
        return (
          fromMs: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
          toMs: null,
        );
      case 'custom':
        if (customFrom == null || customTo == null) {
          return (fromMs: null, toMs: null);
        }
        return (
          fromMs: DateTime(
            customFrom.year,
            customFrom.month,
            customFrom.day,
          ).millisecondsSinceEpoch,
          toMs: DateTime(
            customTo.year,
            customTo.month,
            customTo.day + 1,
          ).millisecondsSinceEpoch,
        );
      default:
        return (fromMs: null, toMs: null);
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
      quotaAlertPercent: settings.quotaAlertPercent,
      budgetAlertPercent: settings.budgetAlertPercent,
      quietHoursEnabled: settings.quietHoursEnabled,
    );
  }

  Future<void> _refreshQuota(Account account, bool force) async {
    final accountVersion = account.updatedAt;
    try {
      final quota = await syncService.quotaFor(account, force: force);
      if (activeAccount?.id != account.id ||
          activeAccount?.updatedAt != accountVersion) {
        return;
      }
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
    final requestId = ++_overviewRequest;
    final signature = _accountsSignature();
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
            lastSyncAt: sync.lastSuccessOrAttempt,
            lastSyncStatus: sync.lastSyncStatus,
          ),
        );
      } catch (_) {
        // One broken account must not hide the others.
      }
    }
    if (requestId != _overviewRequest || signature != _accountsSignature()) {
      return;
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

  void navigateRecords(RecordsNavigationRequest request) {
    recordsNavigation.value = request;
  }

  Future<void> setRange(String range) async {
    if (dashboardRange == range) return;
    dashboardRange = range;
    notifyListeners();
    await refreshDashboard();
  }

  Future<void> setCustomRange(DateTime from, DateTime to) async {
    var start = DateTime(from.year, from.month, from.day);
    var end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) {
      final swap = start;
      start = end;
      end = swap;
    }
    customRangeFrom = start;
    customRangeTo = end;
    dashboardRange = 'custom';
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
      authRequired = false;
      if (result.partial && result.error != null) {
        errorMessage = result.error;
        _errorFromSync = true;
      } else {
        errorMessage = null;
        _errorFromSync = false;
      }
      try {
        keyNames = await settingsRepo.getKeyNames();
        await refreshDashboard(forceQuota: true);
        await refreshOverviews();
      } catch (e) {
        errorMessage = e.toString();
        _errorFromSync = false;
      }
    } else {
      errorMessage = result.error;
      _errorFromSync = true;
      authRequired = result.authRequired;
    }
    notifyListeners();
    return result;
  }

  Future<void> addAccountWithToken(String rawToken, {String? name}) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw const OpenCodeApiException('Cookie 为空');
    }
    authRequired = false;
    errorMessage = null;
    _errorFromSync = false;
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
    authRequired = false;
    errorMessage = null;
    _errorFromSync = false;
    final workspace = await api.resolveWorkspace('Default', token);
    final currentWorkspace =
        account.resolvedWorkspaceId ?? account.workspaceHint;
    if (account.resolvedWorkspaceId != null &&
        currentWorkspace != workspace.id) {
      // Never merge a different workspace's history into this account. The
      // login UI catches this and offers to add a separate account.
      throw WorkspaceChangedException(
        currentWorkspaceId: currentWorkspace,
        nextWorkspaceId: workspace.id,
      );
    }
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
        authRequired = false;
        if (result.partial && result.error != null) {
          errorMessage = result.error;
          _errorFromSync = true;
        } else {
          errorMessage = null;
          _errorFromSync = false;
        }
        keyNames = await settingsRepo.getKeyNames();
        await refreshDashboard(forceQuota: true);
        await refreshOverviews();
      } else {
        errorMessage = result.error;
        _errorFromSync = true;
        authRequired = result.authRequired;
      }
    } catch (e) {
      errorMessage = e.toString();
      _errorFromSync = true;
    }
    notifyListeners();
  }

  Future<void> switchAccount(int accountId) async {
    authRequired = false;
    errorMessage = null;
    _errorFromSync = false;
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
    authRequired = false;
    errorMessage = null;
    _errorFromSync = false;
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
    authRequired = false;
    errorMessage = null;
    _errorFromSync = false;
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
    // Apply locally before awaiting so two quick toggles build on each other
    // instead of both starting from the previous snapshot.
    settings = next;
    startAutoSync();
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  ({int? fromMs, int? toMs, String? label}) _previousRange(
    String range, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final now = DateTime.now();
    if (range == 'custom' && customFrom != null && customTo != null) {
      final start = DateTime(customFrom.year, customFrom.month, customFrom.day);
      final end = DateTime(customTo.year, customTo.month, customTo.day + 1);
      final span = end.difference(start);
      return (
        fromMs: start.subtract(span).millisecondsSinceEpoch,
        toMs: start.millisecondsSinceEpoch,
        label: 'previousPeriod',
      );
    }
    switch (range) {
      case 'today':
        final todayStart = DateTime(now.year, now.month, now.day);
        // Calendar arithmetic, not Duration(days: 1): DST days are 23/25
        // hours long and can land on the wrong local date.
        final prevStart = DateTime(now.year, now.month, now.day - 1);
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
  Future<int> databaseSizeBytes() async {
    var total = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      try {
        final file = File('${db.db.path}$suffix');
        if (await file.exists()) total += await file.length();
      } catch (_) {
        // A missing sidecar file is normal.
      }
    }
    return total;
  }

  Future<int> cleanupTempFiles() async {
    final dir = await getTemporaryDirectory();
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('quotaroom-')) continue;
      try {
        await entity.delete();
        deleted++;
      } catch (_) {
        // A file still held by the share sheet can be skipped.
      }
    }
    return deleted;
  }

  Future<String> checkDatabaseIntegrity() async {
    final rows = await db.db.rawQuery('PRAGMA integrity_check');
    if (rows.isEmpty) return 'unknown';
    return rows.first.values.first?.toString() ?? 'unknown';
  }

  Future<void> compactDatabase() async {
    await db.db.execute('VACUUM');
  }

  Future<int> clearActiveAccountUsage() async {
    final account = activeAccount;
    if (account == null) {
      throw const OpenCodeApiException('没有可清理数据的账号');
    }
    if (syncing) {
      throw const OpenCodeApiException('同步进行中，请稍后再清理');
    }
    final deleted = await db.db.transaction((txn) async {
      final count = await txn.delete(
        'usage_records',
        where: 'account_id = ?',
        whereArgs: [account.id],
      );
      await txn.delete(
        'usage_sync_state',
        where: 'account_id = ?',
        whereArgs: [account.id],
      );
      return count;
    });
    syncService.clearQuotaCache(account.id);
    errorMessage = null;
    _errorFromSync = false;
    await refreshDashboard(forceQuota: true);
    await refreshOverviews();
    notifyListeners();
    return deleted;
  }

  Future<int> restoreUsageFromBackup(List<int> bytes) async {
    final account = activeAccount;
    if (account == null) {
      throw const OpenCodeApiException('没有可恢复数据的账号');
    }
    if (syncing) {
      throw const OpenCodeApiException('同步进行中，请稍后再恢复备份');
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
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<bool> setNotificationsEnabled(bool value) async {
    var enabled = value;
    if (value && !await notifications.requestPermission()) {
      enabled = false;
    }
    final next = settings.copyWith(notificationsEnabled: enabled);
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
    return enabled;
  }

  Future<bool> sendTestNotification() {
    return notifications.showTest(language: language);
  }

  Future<void> setQuotaAlertPercent(int value) async {
    final next = settings.copyWith(
      quotaAlertPercent: value.clamp(1, 90).toInt(),
    );
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<void> setBudgetAlertPercent(int value) async {
    final next = settings.copyWith(
      budgetAlertPercent: value.clamp(1, 100).toInt(),
    );
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    final next = settings.copyWith(quietHoursEnabled: value);
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<void> setAmoled(bool value) async {
    final next = settings.copyWith(amoled: value);
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<void> setWindowDays(int? value) async {
    final next = settings.copyWith(
      windowDays: value,
      clearWindowDays: value == null,
    );
    settings = next;
    notifyListeners();
    await settingsRepo.saveSettings(next);
  }

  Future<void> setLanguage(String value) async {
    languagePreference = switch (value) {
      'en' => 'en',
      'zh' => 'zh',
      _ => 'system',
    };
    language = _resolveLanguage(languagePreference);
    await prefs.setLanguage(languagePreference);
    notifyListeners();
    unawaited(DesktopShell.instance.refreshTray());
    unawaited(_publishWidget());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (languagePreference != 'system') return;
    final next = _resolveLanguage('system');
    if (next == language) return;
    language = next;
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
    if (state == AppLifecycleState.resumed) {
      startAutoSync();
      unawaited(_refreshAfterResume());
      return;
    }
    // Android's WorkManager owns background sync. Keeping the foreground
    // timer alive while paused only duplicates API traffic.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
    }
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
      final current = dashboard?.sync.lastSuccessOrAttempt;
      if (current == null ||
          (persisted.lastSuccessOrAttempt?.isAfter(current) ?? false)) {
        await refreshDashboard();
      }
    } catch (_) {
      // The regular sync below will retry.
    }
    if (!settings.autoSync || syncing) return;
    final last = dashboard?.sync.lastSuccessOrAttempt;
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
      final day = DateTime(today.year, today.month, today.day - i);
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
    recordsNavigation.dispose();
    syncService.dispose();
    super.dispose();
  }
}
