import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Creates directory junctions for Windows plugins when symbolic links are not
/// available (Windows Developer Mode off).
///
/// Flutter skips a plugin link that already exists, so running this once before
/// `flutter build windows` is enough. Enable Developer Mode instead if you
/// prefer Flutter to manage the links itself.
///
/// Usage:
///   dart run tool/windows_plugin_links.dart
Future<void> main() async {
  if (!Platform.isWindows) {
    stdout.writeln('windows_plugin_links: nothing to do on this platform.');
    return;
  }
  final root = Directory.current.absolute;
  final config = File(p.join(root.path, '.flutter-plugins-dependencies'));
  if (!config.existsSync()) {
    stderr.writeln(
      'Missing .flutter-plugins-dependencies — run flutter pub get first.',
    );
    exitCode = 1;
    return;
  }
  final decoded = jsonDecode(config.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('Unexpected .flutter-plugins-dependencies format.');
    exitCode = 1;
    return;
  }
  final plugins = (decoded['plugins'] as Map?)?['windows'];
  if (plugins is! List) {
    stdout.writeln('windows_plugin_links: no Windows plugins registered.');
    return;
  }
  final linkDirectory = Directory(
    p.join(root.path, 'windows', 'flutter', 'ephemeral', '.plugin_symlinks'),
  )..createSync(recursive: true);

  var failures = 0;
  for (final entry in plugins) {
    if (entry is! Map) continue;
    final name = entry['name'];
    final target = entry['path'];
    if (name is! String || target is! String) continue;
    final link = Link(p.join(linkDirectory.path, name));
    if (link.existsSync()) continue;
    final result = Process.runSync('cmd', [
      '/c',
      'mklink',
      '/J',
      _winPath(link.path),
      _winPath(target),
    ], runInShell: true);
    if (result.exitCode != 0) {
      failures++;
      stderr.writeln('Failed to link $name: ${result.stderr}');
    } else {
      stdout.writeln('Linked $name');
    }
  }
  if (failures > 0) {
    exitCode = 1;
  } else {
    stdout.writeln('Windows plugin links ready.');
  }
}

String _winPath(String path) {
  var value = path.replaceAll('/', '\\');
  while (value.length > 3 && value.endsWith('\\')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
