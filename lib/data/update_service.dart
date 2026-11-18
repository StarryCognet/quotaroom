import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.hasUpdate,
    required this.releaseUrl,
    required this.notes,
    this.apkUrl,
    this.apkSize = 0,
    this.windowsUrl,
    this.windowsSize = 0,
  });

  final String current;
  final String latest;
  final bool hasUpdate;
  final String releaseUrl;
  final String notes;
  final String? apkUrl;
  final int apkSize;
  final String? windowsUrl;
  final int windowsSize;

  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;

  bool get hasWindowsPackage => windowsUrl != null && windowsUrl!.isNotEmpty;
}

class UpdateService {
  static const String repo = 'StarryCognet/quotaroom';

  Future<UpdateInfo> check() async {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'QuotaRoom',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub HTTP ${response.statusCode}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map) throw Exception('Invalid release payload');
    final package = await PackageInfo.fromPlatform();
    return parseRelease(data.cast<String, Object?>(), current: package.version);
  }

  /// Parses the `/releases/latest` payload. Kept pure for unit tests.
  static UpdateInfo parseRelease(
    Map<String, Object?> data, {
    required String current,
  }) {
    final tag = (data['tag_name'] ?? '').toString();
    final url = (data['html_url'] ?? '').toString();
    final rawNotes = (data['body'] ?? '').toString();

    String? apkUrl;
    var apkSize = 0;
    String? windowsUrl;
    var windowsSize = 0;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] ?? '').toString().toLowerCase();
        final downloadUrl = (asset['browser_download_url'] ?? '').toString();
        final size = (asset['size'] as num?)?.toInt() ?? 0;
        if (apkUrl == null && name.endsWith('.apk')) {
          apkUrl = downloadUrl;
          apkSize = size;
        } else if (windowsUrl == null &&
            name.endsWith('.zip') &&
            name.contains('windows')) {
          windowsUrl = downloadUrl;
          windowsSize = size;
        }
      }
    }

    return UpdateInfo(
      current: current,
      latest: tag,
      hasUpdate: _isNewer(tag, current),
      releaseUrl: url,
      notes: cleanNotes(rawNotes),
      apkUrl: apkUrl,
      apkSize: apkSize,
      windowsUrl: windowsUrl,
      windowsSize: windowsSize,
    );
  }

  /// Downloads the release APK into the cache while reporting progress.
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Release has no APK asset');
    }
    final dir = await getTemporaryDirectory();
    final safeVersion = info.latest.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final file = File('${dir.path}/QuotaRoom-$safeVersion.apk');
    if (await file.exists()) {
      await file.delete();
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'QuotaRoom';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('Download HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? info.apkSize;
      final sink = file.openWrite();
      var received = 0;
      var lastPercent = -1;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 45),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final percent = (received * 100 / total).clamp(0, 100).toInt();
            if (percent != lastPercent) {
              lastPercent = percent;
              onProgress?.call(received, total);
            }
          } else {
            onProgress?.call(received, 0);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received < 1024 * 1024) {
        throw Exception('Downloaded APK is incomplete');
      }
      final raf = await file.open();
      try {
        final header = await raf.read(2);
        if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
          throw Exception('Downloaded file is not an APK');
        }
      } finally {
        await raf.close();
      }
      return file;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Trims GitHub markdown so release notes read well in a dialog.
  static String cleanNotes(String raw) {
    return raw
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]*\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static bool _isNewer(String latest, String current) {
    final a = _parts(latest);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _parts(String version) {
    return RegExp(r'\d+')
        .allMatches(version)
        .take(3)
        .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .toList();
  }
}
