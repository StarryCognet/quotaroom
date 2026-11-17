import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/formatters.dart';
import 'models.dart';

/// Pushes a compact snapshot to the native Android home-screen widget.
/// Failures are swallowed: a missing widget must never break the dashboard.
class WidgetService {
  static const String provider =
      'com.starrycognet.quotaroom.QuotaRoomWidgetProvider';

  Future<void> update({
    required String accountName,
    required QuotaResult? quota,
    required Totals today,
    required String language,
    required String currency,
    required double usdCny,
    String? syncError,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final zh = language != 'en';
    try {
      final windows = quota?.windows ?? const <QuotaWindow>[];
      final values = <String, Object?>{
        'qr_account': accountName.isEmpty ? 'QuotaRoom' : accountName,
        'qr_updated': quota == null
            ? (syncError != null
                  ? (zh ? '额度获取失败' : 'Quota unavailable')
                  : (zh ? '尚未同步' : 'Not synced yet'))
            : '${zh ? '更新' : 'Updated'} ${fmtDateTimeShort(quota.updatedAt)}',
        'qr_today_label': zh ? '今日' : 'Today',
        'qr_today_cost': fmtMoney(
          today.totalCostUsd,
          currency: currency,
          rate: usdCny,
        ),
        'qr_today_tokens': fmtTokens(today.totalTokens),
        'qr_today_meta':
            '${fmtInt(today.requestCount)} ${zh ? '请求' : 'requests'}',
      };
      for (var i = 0; i < 3; i++) {
        final slot = i + 1;
        final window = i < windows.length ? windows[i] : null;
        final total = window == null || window.total <= 0
            ? 100.0
            : window.total;
        final usedPct = window == null
            ? 0.0
            : (window.used / total * 100).clamp(0, 100).toDouble();
        values['qr_q${slot}_label'] = window == null
            ? '—'
            : _windowLabel(window.label, zh);
        values['qr_q${slot}_pct'] = window == null
            ? '--'
            : '${usedPct.round()}%';
        values['qr_q${slot}_progress'] = usedPct.round();
        values['qr_q${slot}_left'] = window == null
            ? ''
            : '${zh ? '剩' : 'left'} ${window.remaining.toStringAsFixed(0)}%';
      }
      for (final entry in values.entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    } catch (e) {
      debugPrint('QuotaRoom widget update failed: $e');
    }
  }

  Future<void> clear({String language = 'zh'}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final zh = language != 'en';
    try {
      final values = <String, Object?>{
        'qr_account': 'QuotaRoom',
        'qr_updated': zh ? '未登录' : 'Not signed in',
        'qr_today_label': zh ? '今日' : 'Today',
        'qr_today_cost': '—',
        'qr_today_tokens': '—',
        'qr_today_meta': '',
      };
      for (var i = 1; i <= 3; i++) {
        values['qr_q${i}_label'] = '—';
        values['qr_q${i}_pct'] = '--';
        values['qr_q${i}_progress'] = 0;
        values['qr_q${i}_left'] = '';
      }
      for (final entry in values.entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    } catch (e) {
      debugPrint('QuotaRoom widget clear failed: $e');
    }
  }

  static String _windowLabel(String label, bool zh) {
    return switch (label) {
      '5h Rolling' => zh ? '5h' : '5h',
      'Weekly' => zh ? '周' : 'Week',
      'Monthly' => zh ? '月' : 'Month',
      _ => label,
    };
  }
}
