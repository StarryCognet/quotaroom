import 'package:package_info_plus/package_info_plus.dart';

Future<PackageInfo>? _cached;

/// Bundle metadata is static for the process; caching avoids rebuilding a
/// FutureBuilder every time AppState notifies (e.g. during a sync).
Future<PackageInfo> loadPackageInfo() {
  return _cached ??= _load();
}

Future<PackageInfo> _load() async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    _cached = null;
    rethrow;
  }
}
