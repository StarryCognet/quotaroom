import 'package:flutter_test/flutter_test.dart';
import 'package:quotaroom/data/update_service.dart';

void main() {
  test('release payload picks APK asset and detects newer version', () {
    final info = UpdateService.parseRelease({
      'tag_name': 'v2.1.0',
      'html_url':
          'https://github.com/StarryCognet/quotaroom/releases/tag/v2.1.0',
      'body': '## 更新\n\n- 新增自动更新\n- 彩带动效',
      'assets': [
        {'name': 'SHA256SUMS.txt', 'size': 87},
        {
          'name': 'QuotaRoom-v2.1.0.apk',
          'size': 61846511,
          'browser_download_url': 'https://github.com/StarryCognet/quotaroom/releases/download/v2.1.0/QuotaRoom-v2.1.0.apk',
        },
      ],
    }, current: '2.0.0');
    expect(info.hasUpdate, isTrue);
    expect(info.latest, 'v2.1.0');
    expect(info.apkSize, 61846511);
    expect(info.apkUrl, endsWith('QuotaRoom-v2.1.0.apk'));
    expect(info.notes, contains('新增自动更新'));
    expect(info.notes, isNot(contains('##')));
    expect(info.notes, isNot(contains('- ')));
  });

  test('same version and releases without APK are handled', () {
    final info = UpdateService.parseRelease({
      'tag_name': 'v2.0.0',
      'html_url': 'https://example.com/release',
      'body': '',
      'assets': <Object?>[],
    }, current: '2.0.0');
    expect(info.hasUpdate, isFalse);
    expect(info.hasApk, isFalse);
    expect(info.notes, isEmpty);
  });

  test('release payload picks the Windows portable zip', () {
    final info = UpdateService.parseRelease({
      'tag_name': 'v2.2.0',
      'html_url':
          'https://github.com/StarryCognet/quotaroom/releases/tag/v2.2.0',
      'body': 'Desktop support',
      'assets': [
        {
          'name': 'QuotaRoom-v2.2.0-windows-x64.zip',
          'size': 24117248,
          'browser_download_url': 'https://github.com/StarryCognet/quotaroom/releases/download/v2.2.0/QuotaRoom-v2.2.0-windows-x64.zip',
        },
        {
          'name': 'QuotaRoom-v2.2.0.apk',
          'size': 61846511,
          'browser_download_url': 'https://github.com/StarryCognet/quotaroom/releases/download/v2.2.0/QuotaRoom-v2.2.0.apk',
        },
      ],
    }, current: '2.1.1');
    expect(info.hasWindowsPackage, isTrue);
    expect(info.windowsUrl, endsWith('QuotaRoom-v2.2.0-windows-x64.zip'));
    expect(info.windowsSize, 24117248);
    expect(info.hasApk, isTrue);
  });

  test('release payload prefers the Windows installer and checksums', () {
    final info = UpdateService.parseRelease({
      'tag_name': 'v2.4.0',
      'html_url':
          'https://github.com/StarryCognet/quotaroom/releases/tag/v2.4.0',
      'body': 'Desktop update',
      'assets': [
        {
          'name': 'QuotaRoom-v2.4.0-windows-x64-setup.exe',
          'size': 42000000,
          'browser_download_url':
              'https://example.test/QuotaRoom-v2.4.0-windows-x64-setup.exe',
        },
        {
          'name': 'QuotaRoom-v2.4.0-windows-x64.zip',
          'size': 24000000,
          'browser_download_url':
              'https://example.test/QuotaRoom-v2.4.0-windows-x64.zip',
        },
        {
          'name': 'QuotaRoom-v2.4.0-windows-x64-single.exe',
          'size': 30000000,
          'browser_download_url':
              'https://example.test/QuotaRoom-v2.4.0-windows-x64-single.exe',
        },
        {
          'name': 'SHA256SUMS-windows.txt',
          'size': 200,
          'browser_download_url': 'https://example.test/SHA256SUMS-windows.txt',
        },
        {
          'name': 'SHA256SUMS.txt',
          'size': 100,
          'browser_download_url': 'https://example.test/SHA256SUMS.txt',
        },
      ],
    }, current: '2.3.0');
    expect(info.hasWindowsInstaller, isTrue);
    expect(info.windowsUrl, endsWith('setup.exe'));
    expect(info.windowsSize, 42000000);
    expect(info.windowsPortableUrl, endsWith('.zip'));
    expect(info.windowsSingleUrl, endsWith('single.exe'));
    expect(info.windowsChecksumsUrl, endsWith('SHA256SUMS-windows.txt'));
    expect(info.checksumsUrl, endsWith('SHA256SUMS.txt'));
  });

  test('cleanNotes removes markdown while keeping bullets', () {
    final cleaned = UpdateService.cleanNotes(
      '### 标题\n\n- **一**\n- [链接](https://example.com)\n`code`',
    );
    expect(cleaned, '标题\n• 一\n• 链接\ncode');
  });
}
