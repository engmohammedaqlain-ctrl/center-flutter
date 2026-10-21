import 'package:center_mobile/data/app_installs.dart';
import 'package:flutter_test/flutter_test.dart';

InstallRow _row({
  String? tenant = 't1',
  String code = 'MISTER',
  String name = 'المستر',
  String channel = 'school',
  String version = '2.9.0',
  int patch = 0,
  int devices = 1,
  DateTime? seen,
}) =>
    InstallRow(
      tenantId: tenant,
      code: code,
      name: name,
      channel: channel,
      platform: 'android',
      version: version,
      patch: patch,
      devices: devices,
      recent: devices,
      lastSeen: seen,
    );

void main() {
  test('نوع النسخة: المتجر أولاً، ثم نسخة المدرسة، ثم العامة', () {
    expect(installChannel(play: true, schoolBuild: true), 'play');
    expect(installChannel(play: false, schoolBuild: true), 'school');
    expect(installChannel(play: false, schoolBuild: false), 'general');
  });

  test('مقارنة الإصدارات بالأجزاء', () {
    expect(compareVersions('2.10.0', '2.9.0') > 0, isTrue);
    expect(compareVersions('2.9', '2.9.0'), 0);
    expect(compareVersions('2.8.0', '2.9') < 0, isTrue);
    expect(installLabel('2.9.0', 0), '2.9');
    expect(installLabel('2.9.0', 3), '2.9.3');
  });

  test('تنزيلات GitHub لكل مدرسة وأحدث إصدار فيه حزمة', () {
    final parsed = parseGithubReleases([
      {
        'tag_name': 'v2.9',
        'assets': [
          {'name': 'center-2.9-MISTER.apk', 'download_count': 86},
          {'name': 'center-2.9.apk', 'download_count': 2},
          {'name': 'mobile-latest.json', 'download_count': 301},
        ],
      },
      {'tag_name': 'v2.9.1', 'assets': [{'name': 'mobile-silent.json', 'download_count': 0}]},
      {
        'tag_name': 'v2.8',
        'assets': [
          {'name': 'center-2.8-MISTER.apk', 'download_count': 179},
          {'name': 'center-2.8-AQSA.apk', 'download_count': 1},
        ],
      },
    ]);
    expect(parsed.downloads['MISTER'], 265);
    expect(parsed.downloads['AQSA'], 1);
    expect(parsed.downloads[''], 2);
    expect(parsed.latest, '2.9');
  });

  test('تجميع الأجهزة لكل مدرسة وتمييز القديم', () {
    final old = DateTime(2026, 10, 1);
    final recent = DateTime(2026, 10, 20);
    final result = groupInstalls(
      [
        _row(devices: 5, seen: recent),
        _row(version: '2.9.0', patch: 2, devices: 1, seen: old),
        _row(version: '2.8.0', devices: 3, seen: old),
        _row(channel: 'play', devices: 2, seen: old),
        _row(tenant: 't2', code: 'AQSA', name: 'الأقصى', channel: '', version: '', devices: 0),
        _row(tenant: null, code: '', name: '', channel: 'general', devices: 1),
      ],
      pageDownloads: {'t1': 40},
      githubDownloads: {'MISTER': 265, 'AQSA': 1},
      latest: '2.9',
    );

    expect(result.latest, '2.9');
    final names = [for (final s in result.schools) s.name];
    // الأقصى بلا أجهزة لكن له تنزيلات؛ المستر أولاً بعدد أجهزته
    expect(names, ['المستر', 'بلا مدرسة', 'الأقصى']);

    final mister = result.schools.first;
    expect(mister.devices, 11);
    expect(mister.outdated, 3);
    expect(mister.oldVersions, {'2.8'});
    expect(mister.versions.keys.toList(), ['2.9.2', '2.9', '2.8']);
    expect(mister.versions['2.9'], 7);
    expect(mister.channels, {'school': 9, 'play': 2});
    expect(mister.lastSeen, recent);
    expect(mister.pageDownloads, 40);
    expect(mister.githubDownloads, 265);
  });

  test('بلا إصدار منشور: الأحدث مما بلّغت عنه الأجهزة', () {
    final result = groupInstalls([
      _row(version: '2.10.0', devices: 1),
      _row(version: '2.9.0', devices: 4),
    ]);
    expect(result.latest, '2.10.0');
    expect(result.schools.single.outdated, 4);
  });
}
