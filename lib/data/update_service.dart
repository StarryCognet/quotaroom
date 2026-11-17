import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.current,
    required this.latest,
    required this.hasUpdate,
    required this.releaseUrl,
    required this.notes,
  });

  final String current;
  final String latest;
  final bool hasUpdate;
  final String releaseUrl;
  final String notes;
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
    final tag = (data['tag_name'] ?? '').toString();
    final url = (data['html_url'] ?? '').toString();
    final notes = (data['body'] ?? '').toString();
    final package = await PackageInfo.fromPlatform();
    final current = package.version;
    return UpdateInfo(
      current: current,
      latest: tag,
      hasUpdate: _isNewer(tag, current),
      releaseUrl: url,
      notes: notes,
    );
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
