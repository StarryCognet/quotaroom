import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    this.checksumsUrl,
    this.windowsChecksumsUrl,
    this.windowsSetupUrl,
    this.windowsSetupSize = 0,
    this.windowsPortableUrl,
    this.windowsPortableSize = 0,
    this.windowsSingleUrl,
    this.windowsSingleSize = 0,
  });

  final String current;
  final String latest;
  final bool hasUpdate;
  final String releaseUrl;
  final String notes;
  final String? apkUrl;
  final int apkSize;
  final String? checksumsUrl;
  final String? windowsChecksumsUrl;
  final String? windowsSetupUrl;
  final int windowsSetupSize;
  final String? windowsPortableUrl;
  final int windowsPortableSize;
  final String? windowsSingleUrl;
  final int windowsSingleSize;

  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;

  bool get hasWindowsPackage => windowsUrl != null;

  bool get hasWindowsInstaller =>
      windowsSetupUrl != null && windowsSetupUrl!.isNotEmpty;

  /// Prefer the installer for installed users, then the portable zip, then
  /// the single-file build.
  String? get windowsUrl =>
      windowsSetupUrl ?? windowsPortableUrl ?? windowsSingleUrl;

  int get windowsSize {
    if (windowsSetupUrl != null) return windowsSetupSize;
    if (windowsPortableUrl != null) return windowsPortableSize;
    return windowsSingleSize;
  }
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
    String? checksumsUrl;
    String? windowsChecksumsUrl;
    String? setupUrl;
    var setupSize = 0;
    String? portableUrl;
    var portableSize = 0;
    String? singleUrl;
    var singleSize = 0;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = (asset['name'] ?? '').toString().toLowerCase();
        final downloadUrl = (asset['browser_download_url'] ?? '').toString();
        final size = (asset['size'] as num?)?.toInt() ?? 0;
        if (downloadUrl.isEmpty) continue;
        if (apkUrl == null && name.endsWith('.apk')) {
          apkUrl = downloadUrl;
          apkSize = size;
        } else if (name.contains('sha256sums-windows') &&
            name.endsWith('.txt')) {
          windowsChecksumsUrl = downloadUrl;
        } else if (name.contains('sha256sums') && name.endsWith('.txt')) {
          checksumsUrl = downloadUrl;
        } else if (name.contains('windows') &&
            name.endsWith('.exe') &&
            name.contains('setup')) {
          setupUrl ??= downloadUrl;
          if (setupUrl == downloadUrl) setupSize = size;
        } else if (name.contains('windows') &&
            name.endsWith('.exe') &&
            name.contains('single')) {
          singleUrl ??= downloadUrl;
          if (singleUrl == downloadUrl) singleSize = size;
        } else if (name.contains('windows') && name.endsWith('.zip')) {
          portableUrl ??= downloadUrl;
          if (portableUrl == downloadUrl) portableSize = size;
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
      checksumsUrl: checksumsUrl,
      windowsChecksumsUrl: windowsChecksumsUrl,
      windowsSetupUrl: setupUrl,
      windowsSetupSize: setupSize,
      windowsPortableUrl: portableUrl,
      windowsPortableSize: portableSize,
      windowsSingleUrl: singleUrl,
      windowsSingleSize: singleSize,
    );
  }

  /// Downloads and verifies the release APK into the cache.
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Release has no APK asset');
    }
    final safeVersion = _safeVersion(info.latest);
    return _downloadVerified(
      url: url,
      fileName: 'QuotaRoom-$safeVersion.apk',
      checksumName: _assetName(url),
      expectedSize: info.apkSize,
      checksumsUrl: info.checksumsUrl,
      magic: const [0x50, 0x4B],
      onProgress: onProgress,
    );
  }

  /// Downloads and verifies the Windows installer (Inno Setup).
  Future<File> downloadWindowsSetup(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = info.windowsSetupUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Release has no Windows installer');
    }
    final safeVersion = _safeVersion(info.latest);
    return _downloadVerified(
      url: url,
      fileName: 'QuotaRoom-$safeVersion-windows-setup.exe',
      checksumName: _assetName(url),
      expectedSize: info.windowsSetupSize,
      checksumsUrl: info.windowsChecksumsUrl,
      magic: const [0x4D, 0x5A],
      onProgress: onProgress,
    );
  }

  /// Runs the verified installer silently and closes the running app. The
  /// installer is detached so it can replace files after this process exits.
  static Future<void> runWindowsInstaller(File file) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows installer is only supported on Windows');
    }
    await Process.start(file.path, const [
      '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
  }

  Future<File> _downloadVerified({
    required String url,
    required String fileName,
    required String checksumName,
    required int expectedSize,
    required String? checksumsUrl,
    required List<int> magic,
    void Function(int received, int total)? onProgress,
  }) async {
    String? expectedHash;
    if (checksumsUrl != null && checksumsUrl.isNotEmpty) {
      final checksums = await _fetchText(checksumsUrl);
      expectedHash = _expectedHash(checksums, checksumName);
      if (expectedHash == null) {
        throw Exception('Checksum entry missing for $checksumName');
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) await file.delete();

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
      final total = response.contentLength ?? expectedSize;
      final sink = file.openWrite();
      final digestSink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      var received = 0;
      var lastPercent = -1;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 45),
        )) {
          sink.add(chunk);
          digestInput.add(chunk);
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
        digestInput.close();
      }
      if (received < 1024 * 1024) {
        throw Exception('Downloaded file is incomplete');
      }
      if (expectedSize > 0 && received != expectedSize) {
        throw Exception('Downloaded size does not match the release asset');
      }
      final actualHash = digestSink.value?.toString();
      if (expectedHash != null && actualHash != expectedHash) {
        throw Exception('SHA-256 verification failed');
      }
      final raf = await file.open();
      try {
        final header = await raf.read(magic.length);
        if (header.length < magic.length ||
            !List.generate(
              magic.length,
              (index) => header[index] == magic[index],
            ).every((matches) => matches)) {
          throw Exception('Downloaded file has an unexpected format');
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

  Future<String> _fetchText(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: const {'User-Agent': 'QuotaRoom'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Checksum download HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static String _assetName(String url) {
    final segments = Uri.parse(url).pathSegments;
    return segments.isEmpty
        ? url.split('/').last
        : Uri.decodeComponent(segments.last);
  }

  static String? _expectedHash(String checksums, String fileName) {
    for (final line in checksums.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts.last.replaceFirst('*', '');
      if (name == fileName &&
          RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(parts.first)) {
        return parts.first.toLowerCase();
      }
    }
    return null;
  }

  static String _safeVersion(String version) =>
      version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');

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

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
