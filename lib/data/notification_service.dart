import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/formatters.dart';
import 'models.dart';

/// Local quota / budget alerts. Everything stays on-device; the service only
/// turns already-synced values into Android notifications.
class NotificationService {
  NotificationService();

  static const String channelId = 'quotaroom_alerts';
  static const String channelName = '额度与预算提醒';
  static const String _seenKey = 'quotaroom_notification_seen';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static final AndroidNotificationDetails _details =
      const AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: '配额即将用完、每日预算超支时提醒',
        icon: 'ic_stat_quotaroom',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
      );

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_quotaroom'),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('QuotaRoom notifications init failed: $e');
    }
  }

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns true when the app may
  /// post notifications afterwards.
  Future<bool> requestPermission() async {
    await init();
    if (!_initialized) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? await areEnabled();
    } catch (e) {
      debugPrint('QuotaRoom notification permission failed: $e');
      return false;
    }
  }

  Future<bool> areEnabled() async {
    await init();
    if (!_initialized) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showTest({String language = 'zh'}) async {
    final granted = await requestPermission();
    if (!granted) return false;
    return _show(
      key: 'test:${DateTime.now().millisecondsSinceEpoch}',
      title: language == 'en' ? 'QuotaRoom alerts work' : 'QuotaRoom 提醒已开启',
      body: language == 'en'
          ? 'You will be notified when quota or daily budget runs low.'
          : '额度或每日预算不足时，会在这里提醒你。',
    );
  }

  /// Evaluates quota and daily-budget thresholds, de-duplicating each alert per
  /// reset window / calendar day so the user is not spammed every sync.
  Future<void> evaluate({
    required bool enabled,
    required String language,
    required String accountName,
    required QuotaResult? quota,
    required Totals today,
    required double? dailyBudgetUsd,
    required String currency,
    required double usdCny,
  }) async {
    if (!enabled) return;
    if (!await areEnabled()) return;
    final zh = language != 'en';
    final windows = quota?.windows ?? const <QuotaWindow>[];
    for (final window in windows) {
      final total = window.total > 0 ? window.total : 100;
      final remainingPct = window.unit == '%'
          ? window.remaining
          : (window.remaining / total * 100).clamp(0, 100).toDouble();
      final threshold = remainingPct <= 10 ? 10 : (remainingPct <= 20 ? 20 : 0);
      if (threshold == 0) continue;
      final resetKey =
          window.resetAt?.millisecondsSinceEpoch ?? window.resetInSec;
      final label = _windowLabel(window.label, zh);
      final reset = window.resetAt == null
          ? ''
          : (zh
                ? ' · ${fmtResetAt(window.resetAt)} 重置'
                : ' · resets ${fmtResetAt(window.resetAt)}');
      final remaining = remainingPct
          .clamp(0, 100)
          .toStringAsFixed(remainingPct < 10 ? 1 : 0);
      await _show(
        key: 'quota:$accountName:${window.label}:$resetKey:$threshold',
        title: zh ? '$label额度即将用完' : '$label quota running low',
        body: zh
            ? '仅剩 $remaining%$reset。打开 QuotaRoom 查看消耗节奏。'
            : 'Only $remaining% left$reset. Open QuotaRoom to check pacing.',
      );
    }

    final budget = dailyBudgetUsd;
    if (budget != null && budget > 0) {
      final now = DateTime.now();
      final day =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final ratio = today.totalCostUsd / budget;
      final used = fmtMoney(
        today.totalCostUsd,
        currency: currency,
        rate: usdCny,
      );
      final limit = fmtMoney(budget, currency: currency, rate: usdCny);
      if (ratio >= 1) {
        await _show(
          key: 'budget-over:$accountName:$day',
          title: zh ? '今日预算已超出' : 'Daily budget exceeded',
          body: zh
              ? '今日已花费 $used，超过预算 $limit。'
              : 'Spent $used today, over your $limit budget.',
        );
      } else if (ratio >= 0.8) {
        await _show(
          key: 'budget-80:$accountName:$day',
          title: zh ? '今日预算已用 80%' : '80% of daily budget used',
          body: zh
              ? '今日已花费 $used / $limit，注意控制用量。'
              : 'Spent $used of $limit today. Keep an eye on usage.',
        );
      }
    }
  }

  Future<bool> _show({
    required String key,
    required String title,
    required String body,
  }) async {
    await init();
    if (!_initialized) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toList();
      if (seen.contains(key)) return false;
      await _plugin.show(
        id: key.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: _details),
      );
      seen.add(key);
      if (seen.length > 120) {
        seen.removeRange(0, seen.length - 120);
      }
      await prefs.setStringList(_seenKey, seen);
      return true;
    } catch (e) {
      debugPrint('QuotaRoom notification failed: $e');
      return false;
    }
  }

  static String _windowLabel(String label, bool zh) {
    return switch (label) {
      '5h Rolling' => zh ? '5 小时' : '5-hour',
      'Weekly' => zh ? '周' : 'Weekly',
      'Monthly' => zh ? '月' : 'Monthly',
      _ => label,
    };
  }
}
