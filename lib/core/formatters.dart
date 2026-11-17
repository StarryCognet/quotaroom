import 'package:intl/intl.dart';

/// Compact token counts: 1.23B / 4.56M / 7.8k / 900.
String fmtTokens(num value) {
  final n = value.isFinite ? value.toDouble() : 0;
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(2)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(2)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}k';
  return n.round().toString();
}

String fmtInt(num value) {
  return NumberFormat.decimalPattern('en_US').format(value.round());
}

/// Desktop parity: CNY shows 2 decimals above 1, 4 below; USD shows 4 below 1.
String fmtMoney(double usd, {required String currency, required double rate}) {
  final value = usd.isFinite ? usd : 0.0;
  if (currency == 'CNY') {
    final v = value * rate;
    return '¥${v >= 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(4)}';
  }
  if (value >= 1) return '\$${value.toStringAsFixed(2)}';
  if (value > 0) return '\$${value.toStringAsFixed(4)}';
  return '\$0';
}

String fmtDur(
  int seconds, {
  required String dUnit,
  required String hUnit,
  required String mUnit,
  required String soon,
}) {
  final sec = seconds < 0 ? 0 : seconds;
  final d = sec ~/ 86400;
  final h = (sec % 86400) ~/ 3600;
  final m = (sec % 3600) ~/ 60;
  if (d > 0) return '$d $dUnit $h $hUnit';
  if (h > 0) return '$h $hUnit $m $mUnit';
  if (m > 0) return '$m $mUnit';
  return soon;
}

String fmtDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final local = dt.toLocal();
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(local);
}

String fmtDateShort(DateTime dt) {
  return DateFormat('MM-dd').format(dt.toLocal());
}

String fmtHour(DateTime dt) {
  return DateFormat('HH:mm').format(dt.toLocal());
}

String fmtRelative(
  DateTime? dt, {
  required String never,
  required String justNow,
  required String minAgo,
  required String hrAgo,
  required String dayAgo,
}) {
  if (dt == null) return never;
  final diff = DateTime.now().difference(dt.toLocal()).inSeconds;
  if (diff < 0) return justNow;
  if (diff < 60) return justNow;
  if (diff < 3600) return '${diff ~/ 60} $minAgo';
  if (diff < 86400) return '${diff ~/ 3600} $hrAgo';
  return '${diff ~/ 86400} $dayAgo';
}

String fmtSyncTime(DateTime? dt) {
  if (dt == null) return '—';
  return fmtDateTime(dt);
}

/// Middle-truncate long ids, keeping both ends readable.
String truncateMiddle(String text, int max) {
  if (text.length <= max) return text;
  final keep = (max - 1) ~/ 2;
  return '${text.substring(0, keep)}…${text.substring(text.length - keep)}';
}

String maskWorkspace(String? id) {
  final value = id ?? '';
  if (value.length <= 12) return value;
  return '${value.substring(0, 8)}…';
}

/// `lite` / `sub` -> GO, `byok` -> BYOK.
String planBadge(String? plan) {
  final p = (plan ?? '').toLowerCase();
  if (p == 'lite' || p == 'sub') return 'GO';
  if (p == 'byok') return 'BYOK';
  return (plan ?? '').isEmpty ? '' : (plan ?? '').toUpperCase();
}

String quotaLabel(String label) => switch (label) {
  '5h Rolling' => 'rolling',
  'Weekly' => 'weekly',
  'Monthly' => 'monthly',
  _ => label,
};
