import 'dart:convert';

import 'package:center_mobile/data/backup.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  const service = BackupService();

  Future<AppStore> seeded() async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    injectDemoData(s);
    return s;
  }

  test('an export carries every table plus the settings', () async {
    final s = await seeded();
    await s.saveInstitution(name: 'مدرسة الاختبار');

    final decoded = jsonDecode(service.encode(s)) as Map<String, dynamic>;
    expect(decoded['format_version'], BackupService.formatVersion);
    expect(decoded['institution_name'], 'مدرسة الاختبار');

    final data = decoded['data'] as Map<String, dynamic>;
    for (final table in BackupService.tablesOf(s)) {
      expect(data.containsKey(table), isTrue, reason: 'جدول مفقود من النسخة: $table');
    }
    expect((data['students'] as List).length, s.students.length);
    expect((data['payments'] as List).length, s.payments.length);
  });

  test('the file name carries the institution and stays filesystem-safe', () async {
    final s = await seeded();
    await s.saveInstitution(name: 'مدرسة/الأمل: الخاصة');
    final name = service.fileNameFor(s);
    expect(name, endsWith('.json'));
    for (final bad in [r'\', '/', ':', '*', '?', '"', '<', '>', '|']) {
      expect(name.contains(bad), isFalse, reason: 'الاسم يحوي $bad');
    }
  });

  test('a restore replaces local data with the backup contents', () async {
    final source = await seeded();
    final json = service.encode(source);
    final studentCount = source.students.length;
    final paymentCount = source.payments.length;
    final firstName = source.students.first.fullName;

    // جهاز آخر بمحتوى مختلف
    final target = AppStore.forTesting();
    await target.bootstrap(FakeDisk());
    expect(target.students, isEmpty);

    final restored = await service.restore(target, json);
    expect(restored, greaterThan(0));
    expect(target.students.length, studentCount);
    expect(target.payments.length, paymentCount);
    expect(target.students.any((s) => s.fullName == firstName), isTrue);
    expect(target.tenants.length, source.tenants.length);
  });

  test('a restore wipes what was there before', () async {
    final source = await seeded();
    final json = service.encode(source);

    final target = await seeded();
    // بيانات إضافية لا وجود لها في النسخة
    final extraId = target.newId();
    target.upsertSubject(SubjectItem(id: extraId, name: 'مادة إضافية', code: 'EXT'));
    expect(target.subjects.any((x) => x.id == extraId), isTrue);

    await service.restore(target, json);
    expect(target.subjects.any((x) => x.id == extraId), isFalse, reason: 'الاسترجاع يستبدل ولا يدمج');
  });

  test('the session is never restored from a file', () async {
    final source = await seeded();
    await source.login('amal', 'amal2026');
    final json = service.encode(source);

    final target = AppStore.forTesting();
    await target.bootstrap(FakeDisk());
    await service.restore(target, json);
    expect(target.loggedIn, isFalse);
    expect(target.db.settings.containsKey('session_logged_in'), isFalse);
  });

  test('a malformed file is rejected instead of wiping data', () async {
    final s = await seeded();
    final before = s.students.length;
    expect(() => service.restore(s, '{"nope": 1}'), throwsA(isA<FormatException>()));
    expect(() => service.summarize('not json at all'), throwsA(isA<Object>()));
    expect(s.students.length, before);
  });

  test('summarize reports the row counts a user will see', () async {
    final s = await seeded();
    final counts = service.summarize(service.encode(s));
    expect(counts['students'], s.students.length);
    expect(counts['teachers'], s.teachers.length);
    expect(counts.containsKey('expenses'), isFalse, reason: 'الجداول الفارغة لا تُعرض');
  });

  test('wipeAllData clears every list and the pending queue', () async {
    final s = await seeded();
    expect(s.students, isNotEmpty);
    await s.wipeAllData();
    expect(s.students, isEmpty);
    expect(s.payments, isEmpty);
    expect(s.installments, isEmpty);
    expect(s.attendance, isEmpty);
    expect(s.teachers, isEmpty);
    expect(s.subjects, isEmpty);
    expect(s.rooms, isEmpty);
    expect(s.gradeFees, isEmpty);
    expect(s.users, isEmpty);
    expect(s.groups, isEmpty);
    expect(s.enrollments, isEmpty);
    expect(s.sessions, isEmpty);
    expect(s.pendingSyncs, isEmpty);
  });
}
