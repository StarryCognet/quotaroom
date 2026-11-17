import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/models.dart';

void main() {
  test('Settings.fromJson clamps values and accepts all/null window', () {
    expect(
      Settings.fromJson({'sync_interval_sec': 5}).syncIntervalSec,
      30,
    );
    expect(
      Settings.fromJson({'sync_interval_sec': 99999}).syncIntervalSec,
      3600,
    );
    expect(Settings.fromJson({'window_days': 'all'}).windowDays, isNull);
    expect(Settings.fromJson({'window_days': null}).windowDays, isNull);
    expect(Settings.fromJson({'window_days': 0}).windowDays, 1);
    expect(Settings.fromJson({'window_days': 30}).windowDays, 30);
    expect(Settings.fromJson({'auto_sync': false}).autoSync, isFalse);
    expect(
      Settings.fromJson({'show_accounts_panel': true}).showAccountsPanel,
      isTrue,
    );
  });

  test('UsageRecord token totals include cache and reasoning', () {
    final record = UsageRecord(
      usgId: 'x',
      createdAt: DateTime.utc(2026, 1, 1),
      model: 'm',
      inputTokens: 10,
      outputTokens: 5,
      reasoningTokens: 2,
      cacheReadTokens: 3,
      cacheWrite5mTokens: 4,
    );
    expect(record.cacheWriteTokens, 4);
    expect(record.totalInputTokens, 17);
    expect(record.totalTokens, 24);
  });
}
