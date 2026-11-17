/// Data models shared by the API client, SQLite repositories and UI.
class WorkspaceRef {
  const WorkspaceRef({required this.id, required this.name});

  final String id;
  final String name;
}

class QuotaWindow {
  const QuotaWindow({
    required this.label,
    required this.used,
    required this.remaining,
    required this.total,
    required this.unit,
    required this.resetAt,
    required this.resetInSec,
  });

  final String label;
  final double used;
  final double remaining;
  final double total;
  final String unit;
  final DateTime? resetAt;
  final int resetInSec;

  Map<String, Object?> toJson() => {
    'label': label,
    'used': used,
    'remaining': remaining,
    'total': total,
    'unit': unit,
    'reset_at': resetAt?.toUtc().toIso8601String(),
    'reset_in_sec': resetInSec,
  };

  factory QuotaWindow.fromJson(Map<String, Object?> json) {
    return QuotaWindow(
      label: (json['label'] ?? '').toString(),
      used: (json['used'] as num?)?.toDouble() ?? 0,
      remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 100,
      unit: (json['unit'] ?? '%').toString(),
      resetAt: parseDateTime(json['reset_at']),
      resetInSec: (json['reset_in_sec'] as num?)?.toInt() ?? 0,
    );
  }
}

class QuotaResult {
  const QuotaResult({
    required this.name,
    required this.workspaceId,
    required this.success,
    required this.updatedAt,
    this.windows = const [],
    this.error,
  });

  final String name;
  final String workspaceId;
  final bool success;
  final DateTime updatedAt;
  final List<QuotaWindow> windows;
  final String? error;

  Map<String, Object?> toJson() => {
    'name': name,
    'workspace_id': workspaceId,
    'success': success,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    if (windows.isNotEmpty) 'windows': windows.map((w) => w.toJson()).toList(),
    if (error != null) 'error': error,
  };

  factory QuotaResult.fromJson(Map<String, Object?> json) {
    final rawWindows = json['windows'];
    return QuotaResult(
      name: (json['name'] ?? '').toString(),
      workspaceId: (json['workspace_id'] ?? '').toString(),
      success: json['success'] == true,
      updatedAt: parseDateTime(json['updated_at']) ?? DateTime.now().toUtc(),
      windows: rawWindows is List
          ? rawWindows
                .whereType<Map>()
                .map((e) => QuotaWindow.fromJson(e.cast<String, Object?>()))
                .toList()
          : const [],
      error: json['error']?.toString(),
    );
  }
}

class UsageRecord {
  const UsageRecord({
    required this.usgId,
    required this.createdAt,
    required this.model,
    this.provider = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWrite5mTokens = 0,
    this.cacheWrite1hTokens = 0,
    this.costRaw = 0,
    this.costUsd = 0,
    this.keyId = '',
    this.sessionId = '',
    this.plan,
  });

  final String usgId;
  final DateTime createdAt;
  final String model;
  final String provider;
  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheReadTokens;
  final int cacheWrite5mTokens;
  final int cacheWrite1hTokens;
  final int costRaw;
  final double costUsd;
  final String keyId;
  final String sessionId;
  final String? plan;

  int get createdMs => createdAt.millisecondsSinceEpoch;
  int get cacheWriteTokens => cacheWrite5mTokens + cacheWrite1hTokens;
  int get totalInputTokens =>
      inputTokens + cacheReadTokens + cacheWriteTokens;
  int get totalTokens => totalInputTokens + outputTokens + reasoningTokens;

  Map<String, Object?> toDbMap({
    required int accountId,
    required String syncedAt,
  }) => {
    'usg_id': usgId,
    'account_id': accountId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'created_ms': createdMs,
    'model': model,
    'provider': provider,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'reasoning_tokens': reasoningTokens,
    'cache_read_tokens': cacheReadTokens,
    'cache_write_5m_tokens': cacheWrite5mTokens,
    'cache_write_1h_tokens': cacheWrite1hTokens,
    'cost_raw': costRaw,
    'cost_usd': costUsd,
    'key_id': keyId,
    'session_id': sessionId,
    'plan': plan,
    'synced_at': syncedAt,
  };

  factory UsageRecord.fromDbMap(Map<String, Object?> row) {
    final createdMs = (row['created_ms'] as num?)?.toInt() ?? 0;
    final createdAt = createdMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true)
        : (parseDateTime(row['created_at']) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    return UsageRecord(
      usgId: (row['usg_id'] ?? '').toString(),
      createdAt: createdAt,
      model: (row['model'] ?? '').toString(),
      provider: (row['provider'] ?? '').toString(),
      inputTokens: (row['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (row['output_tokens'] as num?)?.toInt() ?? 0,
      reasoningTokens: (row['reasoning_tokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (row['cache_read_tokens'] as num?)?.toInt() ?? 0,
      cacheWrite5mTokens:
          (row['cache_write_5m_tokens'] as num?)?.toInt() ?? 0,
      cacheWrite1hTokens:
          (row['cache_write_1h_tokens'] as num?)?.toInt() ?? 0,
      costRaw: (row['cost_raw'] as num?)?.toInt() ?? 0,
      costUsd: (row['cost_usd'] as num?)?.toDouble() ?? 0,
      keyId: (row['key_id'] ?? '').toString(),
      sessionId: (row['session_id'] ?? '').toString(),
      plan: row['plan']?.toString(),
    );
  }
}

class UsagePage {
  const UsagePage({
    this.records = const [],
    this.nextCursor,
    this.retentionDays,
  });

  final List<UsageRecord> records;
  final String? nextCursor;
  final int? retentionDays;
}

class Totals {
  const Totals({
    this.requestCount = 0,
    this.sessionCount = 0,
    this.totalInputTokens = 0,
    this.uncachedInputTokens = 0,
    this.totalReasoningTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCostUsd = 0,
    this.hitRate = 0,
  });

  final int requestCount;
  final int sessionCount;
  final int totalInputTokens;
  final int uncachedInputTokens;
  final int totalReasoningTokens;
  final int cacheHitTokens;
  final int cacheWriteTokens;
  final int totalOutputTokens;
  final double totalCostUsd;
  final double hitRate;

  int get totalTokens =>
      totalInputTokens + totalOutputTokens + totalReasoningTokens;

  static const zero = Totals();
}

class ModelStat {
  const ModelStat({
    required this.model,
    this.requestCount = 0,
    this.sessionCount = 0,
    this.totalInputTokens = 0,
    this.uncachedInputTokens = 0,
    this.totalReasoningTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCostUsd = 0,
    this.hitRate = 0,
  });

  final String model;
  final int requestCount;
  final int sessionCount;
  final int totalInputTokens;
  final int uncachedInputTokens;
  final int totalReasoningTokens;
  final int cacheHitTokens;
  final int cacheWriteTokens;
  final int totalOutputTokens;
  final double totalCostUsd;
  final double hitRate;

  int get totalTokens =>
      totalInputTokens + totalOutputTokens + totalReasoningTokens;
}

class DailyStat {
  const DailyStat({
    required this.date,
    this.totalInputTokens = 0,
    this.uncachedInputTokens = 0,
    this.totalReasoningTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCostUsd = 0,
    this.requestCount = 0,
    this.hitRate = 0,
  });

  /// Local date in `yyyy-MM-dd`.
  final String date;
  final int totalInputTokens;
  final int uncachedInputTokens;
  final int totalReasoningTokens;
  final int cacheHitTokens;
  final int cacheWriteTokens;
  final int totalOutputTokens;
  final double totalCostUsd;
  final int requestCount;
  final double hitRate;

  int get totalTokens =>
      totalInputTokens + totalOutputTokens + totalReasoningTokens;

  DateTime get day {
    final parts = date.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.tryParse(parts[0]) ?? 1970,
        int.tryParse(parts[1]) ?? 1,
        int.tryParse(parts[2]) ?? 1,
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class HourPoint {
  const HourPoint({
    required this.hour,
    this.input = 0,
    this.output = 0,
    this.reasoning = 0,
  });

  final int hour;
  final int input;
  final int output;
  final int reasoning;

  String get label => '${hour.toString().padLeft(2, '0')}:00';
  int get total => input + output + reasoning;
}

class SessionStat {
  const SessionStat({
    required this.sessionId,
    this.keyId = '',
    this.requestCount = 0,
    this.totalInputTokens = 0,
    this.uncachedInputTokens = 0,
    this.totalOutputTokens = 0,
    this.totalReasoningTokens = 0,
    this.totalCostUsd = 0,
    this.lastAt,
  });

  final String sessionId;
  final String keyId;
  final int requestCount;
  final int totalInputTokens;
  final int uncachedInputTokens;
  final int totalOutputTokens;
  final int totalReasoningTokens;
  final double totalCostUsd;
  final DateTime? lastAt;

  int get totalTokens =>
      totalInputTokens + totalOutputTokens + totalReasoningTokens;
}

class SyncState {
  const SyncState({
    this.lastSyncAt,
    this.lastSyncStatus,
    this.lastSyncError,
    this.lastInsertedCount = 0,
    this.totalRecords = 0,
    this.oldestRecordAt,
    this.newestRecordAt,
  });

  final DateTime? lastSyncAt;
  final String? lastSyncStatus;
  final String? lastSyncError;
  final int lastInsertedCount;
  final int totalRecords;
  final DateTime? oldestRecordAt;
  final DateTime? newestRecordAt;

  static const empty = SyncState();
}

class SyncProgress {
  const SyncProgress({
    this.running = false,
    this.mode = '',
    this.page = 0,
    this.inserted = 0,
    this.phase = 'idle',
    this.message = '',
    this.account = '',
  });

  final bool running;
  final String mode;
  final int page;
  final int inserted;
  final String phase;
  final String message;
  final String account;

  static const idle = SyncProgress();

  SyncProgress copyWith({
    bool? running,
    String? mode,
    int? page,
    int? inserted,
    String? phase,
    String? message,
    String? account,
  }) => SyncProgress(
    running: running ?? this.running,
    mode: mode ?? this.mode,
    page: page ?? this.page,
    inserted: inserted ?? this.inserted,
    phase: phase ?? this.phase,
    message: message ?? this.message,
    account: account ?? this.account,
  );
}

class Settings {
  const Settings({
    this.syncIntervalSec = 300,
    this.windowDays = 60,
    this.autoSync = true,
    this.showAccountsPanel = false,
  });

  final int syncIntervalSec;
  final int? windowDays;
  final bool autoSync;
  final bool showAccountsPanel;

  Settings copyWith({
    int? syncIntervalSec,
    int? windowDays,
    bool clearWindowDays = false,
    bool? autoSync,
    bool? showAccountsPanel,
  }) => Settings(
    syncIntervalSec: syncIntervalSec ?? this.syncIntervalSec,
    windowDays: clearWindowDays ? null : (windowDays ?? this.windowDays),
    autoSync: autoSync ?? this.autoSync,
    showAccountsPanel: showAccountsPanel ?? this.showAccountsPanel,
  );

  factory Settings.fromJson(Map<String, Object?> json) {
    final interval = (json['sync_interval_sec'] as num?)?.toInt() ?? 300;
    final window = json['window_days'];
    final windowDays = switch (window) {
      null => null,
      final num n => n.toInt().clamp(1, 3650).toInt(),
      _ => _parseWindowDays(window.toString()),
    };
    return Settings(
      syncIntervalSec: interval.clamp(30, 3600).toInt(),
      windowDays: windowDays,
      autoSync: json['auto_sync'] != false,
      showAccountsPanel: json['show_accounts_panel'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'sync_interval_sec': syncIntervalSec,
    'window_days': windowDays,
    'auto_sync': autoSync,
    'show_accounts_panel': showAccountsPanel,
  };
}

class Account {
  const Account({
    required this.id,
    required this.name,
    this.workspaceHint = 'Default',
    this.resolvedWorkspaceId,
    this.hasToken = false,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String workspaceHint;
  final String? resolvedWorkspaceId;
  final bool hasToken;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Account copyWith({
    String? name,
    String? workspaceHint,
    String? resolvedWorkspaceId,
    bool? hasToken,
  }) => Account(
    id: id,
    name: name ?? this.name,
    workspaceHint: workspaceHint ?? this.workspaceHint,
    resolvedWorkspaceId: resolvedWorkspaceId ?? this.resolvedWorkspaceId,
    hasToken: hasToken ?? this.hasToken,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory Account.fromDbMap(Map<String, Object?> row, {bool hasToken = false}) {
    return Account(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: (row['name'] ?? 'Default').toString(),
      workspaceHint: (row['workspace_id'] ?? 'Default').toString(),
      resolvedWorkspaceId: row['resolved_workspace_id']?.toString(),
      hasToken: hasToken,
      createdAt: parseDateTime(row['created_at']),
      updatedAt: parseDateTime(row['updated_at']),
    );
  }
}

class DashboardData {
  const DashboardData({
    this.range = 'today',
    this.totals = Totals.zero,
    this.today = Totals.zero,
    this.daily7 = const [],
    this.trend30 = const [],
    this.todayTrend = const [],
    this.models = const [],
    this.quota,
    this.sync = SyncState.empty,
    this.accountName = '',
  });

  final String range;
  final Totals totals;
  final Totals today;
  final List<DailyStat> daily7;
  final List<DailyStat> trend30;
  final List<HourPoint> todayTrend;
  final List<ModelStat> models;
  final QuotaResult? quota;
  final SyncState sync;
  final String accountName;

  DashboardData copyWith({QuotaResult? quota}) => DashboardData(
    range: range,
    totals: totals,
    today: today,
    daily7: daily7,
    trend30: trend30,
    todayTrend: todayTrend,
    models: models,
    quota: quota ?? this.quota,
    sync: sync,
    accountName: accountName,
  );
}

class AccountOverview {
  const AccountOverview({
    required this.account,
    this.quota,
    this.today = Totals.zero,
    this.todayTrend = const [],
    this.daily7 = const [],
    this.lastSyncAt,
    this.lastSyncStatus,
  });

  final Account account;
  final QuotaResult? quota;
  final Totals today;
  final List<HourPoint> todayTrend;
  final List<DailyStat> daily7;
  final DateTime? lastSyncAt;
  final String? lastSyncStatus;
}

class RecordsPageResult {
  const RecordsPageResult({this.records = const [], this.total = 0});

  final List<UsageRecord> records;
  final int total;
}

class SessionsPageResult {
  const SessionsPageResult({this.records = const [], this.total = 0});

  final List<SessionStat> records;
  final int total;
}

class SyncResult {
  const SyncResult({
    required this.ok,
    this.inserted = 0,
    this.pages = 0,
    this.error,
    this.partial = false,
  });

  final bool ok;
  final int inserted;
  final int pages;
  final String? error;
  final bool partial;
}

class LoginResult {
  const LoginResult({
    required this.token,
    required this.workspaceId,
    this.workspaceName = '',
  });

  final String token;
  final String workspaceId;
  final String workspaceName;
}

DateTime? parseDateTime(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  try {
    return DateTime.parse(text).toUtc();
  } catch (_) {
    return null;
  }
}

int? _parseWindowDays(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty || text == 'all') return null;
  final n = int.tryParse(text);
  if (n == null) return null;
  return n.clamp(1, 3650).toInt();
}
