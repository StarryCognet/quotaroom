import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/models.dart';
import 'package:quotaroom/state/app_state.dart';

void main() {
  test('fillDays zero-fills missing local dates and keeps the last one', () {
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final filled = AppState.fillDays(
      [DailyStat(date: today, requestCount: 3)],
      7,
    );
    expect(filled, hasLength(7));
    expect(filled.last.date, today);
    expect(filled.last.requestCount, 3);
    expect(filled.first.date, isNot(today));
    expect(filled.first.requestCount, 0);
  });
}
