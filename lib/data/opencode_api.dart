import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

class OpenCodeApiException implements Exception {
  const OpenCodeApiException(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

class AuthException extends OpenCodeApiException {
  const AuthException([super.message = '登录已过期，请重新登录'])
    : super(retryable: false);
}

/// Direct client for opencode.ai's `/console/api` endpoints.
///
/// Ported from the desktop app's `app/opencode_api.py`.
class OpenCodeApi {
  OpenCodeApi({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  static const String consoleOrigin = 'https://opencode.ai';
  static const String loginUrl =
      'https://opencode.ai/console/login?next=%2Fconsole%2F';
  static const String apiBase = 'https://opencode.ai/console/api';
  static const String sessionCookie = '__Host-console_session';
  static const String legacySessionCookie = 'auth';
  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Gecko/20100101 Firefox/148.0';
  static const List<int> _retryBackoffMs = [500, 1500, 3000];

  final http.Client _client;
  final Duration requestTimeout;

  Future<void> close() async => _client.close();

  // ---------------------------------------------------------------------------
  // Cookie helpers
  // ---------------------------------------------------------------------------

  /// Normalises a stored token into a `Cookie` request header value.
  ///
  /// Accepts a full cookie string, a `Cookie:`-prefixed string, an arbitrary
  /// `name=value` pair, or a bare session value.
  static String buildCookieHeader(String token) {
    var raw = token.trim();
    if (raw.toLowerCase().startsWith('cookie:')) {
      raw = raw.substring(7).trim();
    }
    if (raw.isEmpty) return '';
    for (final part in raw.split(';')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final name = p.substring(0, eq).trim().toLowerCase();
      if (name == sessionCookie.toLowerCase() || name == legacySessionCookie) {
        return p;
      }
    }
    if (RegExp(r'^[A-Za-z0-9_.\-]+\s*=\s*\S+$').hasMatch(raw)) {
      return raw;
    }
    return '$sessionCookie=$raw';
  }

  /// Extracts the session cookie pair from a raw `CookieManager` header.
  static String? extractSessionCookie(String? cookieHeader) {
    for (final part in (cookieHeader ?? '').split(';')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final name = p.substring(0, eq).trim();
      if (name == sessionCookie || name == legacySessionCookie) return p;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // HTTP core
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> _getJson(
    String path,
    String token, {
    String? orgId,
    Map<String, Object?>? params,
    Duration? timeout,
    int retries = 3,
  }) async {
    final decoded = await _getJsonAny(
      path,
      token,
      orgId: orgId,
      params: params,
      timeout: timeout,
      retries: retries,
    );
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
    throw const OpenCodeApiException('接口返回非 JSON 对象');
  }

  Future<Object?> _getJsonAny(
    String path,
    String token, {
    String? orgId,
    Map<String, Object?>? params,
    Duration? timeout,
    int retries = 3,
  }) async {
    final cookie = buildCookieHeader(token);
    if (cookie.isEmpty) {
      throw const OpenCodeApiException('token 为空', retryable: false);
    }
    var uri = Uri.parse('$apiBase$path');
    if (params != null) {
      final query = <String, String>{};
      params.forEach((key, value) {
        if (value != null) query[key] = value.toString();
      });
      if (query.isNotEmpty) uri = uri.replace(queryParameters: query);
    }
    final headers = <String, String>{
      'Cookie': cookie,
      'Accept': 'application/json',
      'User-Agent': userAgent,
      'Origin': consoleOrigin,
      'Referer': '$consoleOrigin/console/',
      if (orgId != null && orgId.isNotEmpty) 'x-org-id': orgId,
    };
    final response = await _request(
      uri,
      headers,
      timeout: timeout ?? requestTimeout,
      retries: retries,
    );
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const OpenCodeApiException('接口返回非 JSON 数据');
    }
  }

  Future<http.Response> _request(
    Uri uri,
    Map<String, String> headers, {
    required Duration timeout,
    required int retries,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: headers)
            .timeout(timeout);
        final code = response.statusCode;
        if (code == 401) {
          throw const AuthException();
        }
        if (code == 403) {
          throw const OpenCodeApiException(
            '无访问权限 (HTTP 403)',
            retryable: false,
          );
        }
        if (code == 404) {
          throw const OpenCodeApiException(
            '工作区不存在或接口不可用 (HTTP 404)',
            retryable: false,
          );
        }
        if (code >= 200 && code < 300) return response;
        if (code >= 400 &&
            code < 500 &&
            code != 408 &&
            code != 425 &&
            code != 429) {
          throw OpenCodeApiException('请求返回 HTTP $code', retryable: false);
        }
        lastError = OpenCodeApiException('请求返回 HTTP $code');
      } on AuthException {
        rethrow;
      } on OpenCodeApiException catch (e) {
        if (!e.retryable) rethrow;
        lastError = e;
      } on TimeoutException {
        lastError = const OpenCodeApiException('请求超时');
      } on SocketException catch (e) {
        lastError = OpenCodeApiException('网络错误: ${e.message}');
      } on http.ClientException catch (e) {
        lastError = OpenCodeApiException('网络错误: ${e.message}');
      } on HandshakeException catch (e) {
        lastError = OpenCodeApiException('TLS 错误: ${e.message}');
      }
      if (attempt < retries - 1) {
        final delay =
            _retryBackoffMs[attempt < _retryBackoffMs.length
                ? attempt
                : _retryBackoffMs.length - 1];
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    if (lastError is OpenCodeApiException) throw lastError;
    throw OpenCodeApiException('网络错误: $lastError');
  }

  // ---------------------------------------------------------------------------
  // Workspaces
  // ---------------------------------------------------------------------------

  Future<List<WorkspaceRef>> fetchWorkspaceRefs(String token) async {
    final data = await _getJsonAny('/orgs', token);
    // Some deployments wrap the list in an object.
    final raw = data is Map && data['items'] is List ? data['items'] : data;
    final refs = <WorkspaceRef>[];
    final seen = <String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final id = (item['id'] ?? '').toString().trim();
        if (id.isEmpty || !seen.add(id)) continue;
        refs.add(
          WorkspaceRef(id: id, name: (item['name'] ?? '').toString().trim()),
        );
      }
    }
    if (refs.isEmpty) {
      throw const OpenCodeApiException('无法获取工作区列表 (账号下没有工作区)');
    }
    return refs;
  }

  /// Resolves a workspace hint (id / name / `Default`) into a `wrk_...` id.
  Future<WorkspaceRef> resolveWorkspace(String hint, String token) async {
    final trimmed = hint.trim();
    final direct = extractWorkspaceId(trimmed);
    if (direct.isNotEmpty) {
      return WorkspaceRef(id: direct, name: '');
    }
    final refs = await fetchWorkspaceRefs(token);
    final lower = trimmed.toLowerCase();
    if (lower.isNotEmpty) {
      for (final ref in refs) {
        if (ref.id.toLowerCase() == lower || ref.name.toLowerCase() == lower) {
          return ref;
        }
      }
    }
    return refs.first;
  }

  Future<String> resolveWorkspaceId(String hint, String token) async {
    return (await resolveWorkspace(hint, token)).id;
  }

  static String extractWorkspaceId(String raw) {
    final value = raw.trim();
    if (value.startsWith('wrk_') && value.length > 4) return value;
    final match = RegExp(r'wrk_[A-Za-z0-9]+').firstMatch(value);
    return match?.group(0) ?? '';
  }

  // ---------------------------------------------------------------------------
  // Quota
  // ---------------------------------------------------------------------------

  Future<QuotaResult> fetchQuota(
    String token, {
    String workspaceHint = 'Default',
  }) async {
    final now = DateTime.now().toUtc();
    final updatedAt = now;
    final hint = workspaceHint.trim().isEmpty
        ? 'Default'
        : workspaceHint.trim();
    if (token.trim().isEmpty) {
      return QuotaResult(
        name: 'Default',
        workspaceId: hint,
        success: false,
        updatedAt: updatedAt,
        error: '未配置 token',
      );
    }
    var name = hint;
    try {
      final workspace = await resolveWorkspace(hint, token);
      if (workspace.name.isNotEmpty) name = workspace.name;
      final payload = await _getJson(
        '/go/status',
        token,
        orgId: workspace.id,
        timeout: const Duration(seconds: 20),
        retries: 2,
      );
      final windows = parseGoStatus(payload, now: now);
      if (windows.isEmpty) {
        throw const OpenCodeApiException('账号未订阅 OpenCode Go (接口无额度数据)');
      }
      return QuotaResult(
        name: name,
        workspaceId: workspace.id,
        success: true,
        updatedAt: updatedAt,
        windows: windows,
      );
    } catch (e) {
      return QuotaResult(
        name: name,
        workspaceId: hint,
        success: false,
        updatedAt: updatedAt,
        error: e.toString(),
      );
    }
  }

  /// Parses `/go/status` into the three quota windows.
  static List<QuotaWindow> parseGoStatus(
    Map<String, Object?>? payload, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now().toUtc();
    final access = payload?['access'];
    if (access is! Map) return const [];
    final meters = access['meters'];
    if (meters is! Map) return const [];
    final periodEnd = _parseIsoUtc(access['endsAt']);
    final windows = <QuotaWindow>[];
    const labels = {
      'fiveHour': '5h Rolling',
      'week': 'Weekly',
      'month': 'Monthly',
    };
    for (final entry in labels.entries) {
      final meter = meters[entry.key];
      if (meter is! Map) continue;
      final limit = _asDouble(meter['limitMicroCents']);
      final usedRaw = _asDouble(meter['usedMicroCents']);
      if (limit <= 0) continue;
      final used = _round2((usedRaw / limit * 100).clamp(0, 100).toDouble());
      final resetAt = _parseIsoUtc(meter['resetsAt']) ?? periodEnd;
      final resetIn = resetAt == null
          ? 0
          : (resetAt.difference(current).inSeconds).clamp(0, 1 << 31).toInt();
      windows.add(
        QuotaWindow(
          label: entry.value,
          used: used,
          remaining: _round2(100 - used),
          total: 100,
          unit: '%',
          resetAt: resetAt,
          resetInSec: resetIn,
        ),
      );
    }
    return windows;
  }

  // ---------------------------------------------------------------------------
  // Usage logs
  // ---------------------------------------------------------------------------

  Future<UsagePage> fetchUsagePage(
    String token,
    String workspaceId, {
    String? cursor,
    int limit = 100,
    int? sinceMs,
  }) async {
    final params = <String, Object?>{'limit': limit.clamp(1, 100).toInt()};
    if (cursor != null && cursor.isNotEmpty) params['cursor'] = cursor;
    if (sinceMs != null && sinceMs > 0) params['since'] = sinceMs;
    final payload = await _getJson(
      '/request-logs',
      token,
      orgId: workspaceId,
      params: params,
    );
    return parseRequestLogs(payload);
  }

  static UsagePage parseRequestLogs(Map<String, Object?> payload) {
    final items = payload['items'];
    final records = <UsageRecord>[];
    final rawItemCount = items is List ? items.length : 0;
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final mapped = item.cast<String, Object?>();
        if ((mapped['category'] ?? '').toString().toLowerCase() !=
            'inference') {
          continue;
        }
        final usgId = (mapped['id'] ?? '').toString().trim();
        final startedAt = _asInt(mapped['startedAt']);
        if (usgId.isEmpty || startedAt <= 0) continue;
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          startedAt,
          isUtc: true,
        );
        final cost = _asDouble(mapped['cost']);
        final costRaw = (cost * 100000000).round();
        final plan = (mapped['product'] ?? '').toString().trim();
        records.add(
          UsageRecord(
            usgId: usgId,
            createdAt: createdAt,
            model: (mapped['model'] ?? '').toString().trim(),
            provider: (mapped['provider'] ?? '').toString().trim(),
            inputTokens: _asInt(mapped['inputTokens']),
            outputTokens: _asInt(mapped['outputTokens']),
            reasoningTokens: _asInt(mapped['reasoningTokens']),
            cacheReadTokens: _asInt(mapped['cacheReadTokens']),
            cacheWrite5mTokens: _asInt(mapped['cacheWriteTokens']),
            cacheWrite1hTokens: 0,
            costRaw: costRaw,
            costUsd: costRaw / 100000000.0,
            keyId: (mapped['serviceAPIKeyID'] ?? '').toString().trim(),
            sessionId: (mapped['sessionID'] ?? '').toString().trim(),
            plan: plan.isEmpty ? null : plan,
          ),
        );
      }
    }
    final cursor = payload['nextCursor']?.toString();
    final retention = payload['retentionDays'];
    return UsagePage(
      records: records,
      nextCursor: cursor == null || cursor.isEmpty ? null : cursor,
      retentionDays: retention == null ? null : _asInt(retention),
      rawItemCount: rawItemCount,
    );
  }

  Future<int?> fetchRetentionDays(String token, String workspaceId) async {
    final page = await fetchUsagePage(token, workspaceId, limit: 1);
    return page.retentionDays;
  }

  // ---------------------------------------------------------------------------
  // Service account key names
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> fetchKeyNames(
    String token,
    String workspaceId,
  ) async {
    try {
      final payload = await _getJson(
        '/service-accounts',
        token,
        orgId: workspaceId,
        timeout: const Duration(seconds: 15),
        retries: 2,
      );
      final items = payload['items'];
      final names = <String, String>{};
      if (items is List) {
        for (final entry in items) {
          if (entry is! Map) continue;
          final keys = entry['keys'];
          if (keys is! List) continue;
          for (final key in keys) {
            if (key is! Map) continue;
            final id = (key['id'] ?? '').toString().trim();
            final name = (key['name'] ?? '').toString().trim();
            if (id.isNotEmpty && name.isNotEmpty) {
              names.putIfAbsent(id, () => name);
            }
          }
        }
      }
      return names;
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // FX
  // ---------------------------------------------------------------------------

  Future<double> fetchUsdCny() async {
    final uri = Uri.parse('https://open.er-api.com/v6/latest/USD');
    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent': 'QuotaRoom/2.0',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeApiException('汇率接口 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map) {
      final rates = decoded['rates'];
      if (rates is Map) {
        final cny = _asDouble(rates['CNY']);
        if (cny > 0) return cny;
      }
    }
    throw const OpenCodeApiException('汇率接口返回无效数据');
  }
}

// ---------------------------------------------------------------------------
// Parsing helpers (numeric values may arrive as strings)
// ---------------------------------------------------------------------------

int _asInt(Object? value, [int fallback = 0]) {
  if (value == null || value == '') return fallback;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value.toString());
  if (parsed != null) return parsed;
  final asDouble = double.tryParse(value.toString());
  return asDouble?.toInt() ?? fallback;
}

double _asDouble(Object? value, [double fallback = 0]) {
  if (value == null || value == '') return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

DateTime? _parseIsoUtc(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  try {
    final hasZone =
        text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
    final parsed = DateTime.parse(text);
    if (hasZone) return parsed.toUtc();
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  } catch (_) {
    return null;
  }
}

double _round2(double value) => (value * 100).round() / 100;
