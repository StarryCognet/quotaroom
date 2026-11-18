import '../data/models.dart';

/// Window length used only for pacing; the exact reset time still comes from
/// the API's `resetAt`.
Duration quotaWindowDuration(String label) => switch (label) {
  '5h Rolling' => const Duration(hours: 5),
  'Weekly' => const Duration(days: 7),
  'Monthly' => const Duration(days: 30),
  _ => const Duration(days: 30),
};

class QuotaPacing {
  const QuotaPacing({
    required this.elapsedFraction,
    required this.pace,
    this.etaSeconds,
    required this.willExhaustBeforeReset,
  });

  /// 0..1 of the window that has already elapsed.
  final double elapsedFraction;

  /// used% / elapsed%. >1 means spending faster than time.
  final double pace;

  /// Estimated seconds until the quota is exhausted at the current rate.
  final int? etaSeconds;

  /// True when the ETA is earlier than the reset time.
  final bool willExhaustBeforeReset;
}

QuotaPacing? computeQuotaPacing(QuotaWindow window, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final duration = quotaWindowDuration(window.label);
  final durationSeconds = duration.inSeconds;
  final resetAt = window.resetAt?.toUtc();
  final int resetSeconds;
  if (resetAt != null) {
    resetSeconds = resetAt.difference(current).inSeconds;
  } else {
    resetSeconds = window.resetInSec;
  }
  if (resetSeconds <= 0) return null;
  final elapsedSeconds = durationSeconds - resetSeconds;
  if (elapsedSeconds <= 0) return null;
  final elapsedFraction = (elapsedSeconds / durationSeconds)
      .clamp(0.02, 1.0)
      .toDouble();
  final usedFraction = (window.used / 100).clamp(0.0, 1.0).toDouble();
  if (usedFraction <= 0) {
    return QuotaPacing(
      elapsedFraction: elapsedFraction,
      pace: 0,
      etaSeconds: null,
      willExhaustBeforeReset: false,
    );
  }
  final pace = usedFraction / elapsedFraction;
  final ratePerSecond = usedFraction / elapsedSeconds;
  final etaSeconds = ratePerSecond > 0
      ? ((1 - usedFraction) / ratePerSecond).round()
      : null;
  return QuotaPacing(
    elapsedFraction: elapsedFraction,
    pace: pace,
    etaSeconds: etaSeconds,
    willExhaustBeforeReset: etaSeconds != null && etaSeconds < resetSeconds,
  );
}
