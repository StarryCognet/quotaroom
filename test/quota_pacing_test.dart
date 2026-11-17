import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/core/quota_pacing.dart';
import 'package:quotaroom/data/models.dart';

QuotaWindow _window({
  required String label,
  required double used,
  required DateTime resetAt,
}) {
  return QuotaWindow(
    label: label,
    used: used,
    remaining: 100 - used,
    total: 100,
    unit: '%',
    resetAt: resetAt,
    resetInSec: resetAt.difference(DateTime.now().toUtc()).inSeconds,
  );
}

void main() {
  final now = DateTime.utc(2026, 11, 17, 12);

  test('steady 5h spend has pace 1 and no early exhaustion', () {
    final pacing = computeQuotaPacing(
      _window(
        label: '5h Rolling',
        used: 50,
        resetAt: now.add(const Duration(hours: 2, minutes: 30)),
      ),
      now: now,
    );
    expect(pacing, isNotNull);
    expect(pacing!.elapsedFraction, closeTo(0.5, 0.001));
    expect(pacing.pace, closeTo(1.0, 0.01));
    expect(pacing.etaSeconds, closeTo(9000, 60));
    expect(pacing.willExhaustBeforeReset, isFalse);
  });

  test('fast weekly spend predicts exhaustion before reset', () {
    final pacing = computeQuotaPacing(
      _window(
        label: 'Weekly',
        used: 90,
        resetAt: now.add(const Duration(hours: 48)),
      ),
      now: now,
    );
    expect(pacing, isNotNull);
    // 120h elapsed of 168h = 71%, so 90% used is ~1.26x the elapsed pace.
    expect(pacing!.pace, closeTo(1.26, 0.01));
    expect(pacing.etaSeconds, closeTo(48000, 60));
    expect(pacing.willExhaustBeforeReset, isTrue);
  });

  test('unused quota has no ETA', () {
    final pacing = computeQuotaPacing(
      _window(
        label: 'Monthly',
        used: 0,
        resetAt: now.add(const Duration(days: 20)),
      ),
      now: now,
    );
    expect(pacing, isNotNull);
    expect(pacing!.pace, 0);
    expect(pacing.etaSeconds, isNull);
    expect(pacing.willExhaustBeforeReset, isFalse);
  });

  test('expired or future reset windows produce no pacing', () {
    expect(
      computeQuotaPacing(
        _window(
          label: '5h Rolling',
          used: 50,
          resetAt: now.subtract(const Duration(minutes: 1)),
        ),
        now: now,
      ),
      isNull,
    );
    expect(
      computeQuotaPacing(
        _window(
          label: '5h Rolling',
          used: 50,
          resetAt: now.add(const Duration(hours: 6)),
        ),
        now: now,
      ),
      isNull,
    );
  });
}
