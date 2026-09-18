import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  test('first login shows the cloud year data, not a placeholder year made before login', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());

    s.tenants.add(Tenant(
      id: 'tn1',
      name: 'مدرسة',
      code: 'T-1',
      username: 'amal',
      password: 'amal2026',
      expiresAt: DateTime.now().add(const Duration(days: 100)),
    ));
    await s.login('amal', 'amal2026');

    // ما يصل من السحابة في السحب الأولي
    s.putRows('academic_years', [
      {
        'id': 'ay_tn1_2025',
        'label': '2025 / 2026',
        'starts_on': '2025-08-01',
        'ends_on': '2026-07-31',
        'status': 'open',
        'is_current': true,
        'sync_status': 'synced',
      }
    ]);
    s.putRows('students', [
      {
        'id': 'st1',
        'first_name': 'أحمد',
        'last_name': 'علي',
        'grade_level': 'العاشر',
        'status': 'active',
        'academic_year_id': 'ay_tn1_2025',
        'sync_status': 'synced',
      }
    ]);

    await s.settleAcademicYears(); // ما يجري بعد كل سحب

    expect(s.viewedAcademicYearId, 'ay_tn1_2025');
    expect(s.studentsInViewedYear.map((e) => e.id), ['st1']);
    expect(s.academicYears.map((y) => y.id), ['ay_tn1_2025']);
    expect(s.pendingSyncs.where((p) => p.tableName == 'academic_years'), isEmpty);
  });

  test('a device that already made a placeholder year drops it and moves its rows', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    s.tenants.add(Tenant(
      id: 'tn1',
      name: 'مدرسة',
      code: 'T-1',
      username: 'amal',
      password: 'amal2026',
      expiresAt: DateTime.now().add(const Duration(days: 100)),
    ));
    await s.login('amal', 'amal2026');

    // عام مؤقت وصل من إصدار سابق، وطالب خُتم به
    s.putRows('academic_years', [
      {'id': 'ay_local_2026', 'label': '2026 / 2027', 'starts_on': '2026-08-01', 'ends_on': '2027-07-31', 'status': 'open', 'is_current': true, 'sync_status': 'synced'},
      {'id': 'ay_tn1_2025', 'label': '2025 / 2026', 'starts_on': '2025-08-01', 'ends_on': '2026-07-31', 'status': 'open', 'is_current': true, 'sync_status': 'synced'},
    ]);
    s.putRows('students', [
      {'id': 'st1', 'first_name': 'أ', 'last_name': 'ب', 'status': 'active', 'academic_year_id': 'ay_tn1_2025', 'sync_status': 'synced'},
      {'id': 'st2', 'first_name': 'ج', 'last_name': 'د', 'status': 'active', 'academic_year_id': 'ay_local_2026', 'sync_status': 'synced'},
    ]);

    await s.settleAcademicYears();

    expect(s.viewedAcademicYearId, 'ay_tn1_2025');
    expect(s.studentsInViewedYear.map((e) => e.id).toSet(), {'st1', 'st2'});
    expect(
      s.pendingSyncs.any((p) => p.tableName == 'academic_years' && p.recordId == 'ay_local_2026' && p.action == 'DELETE'),
      isTrue,
    );
  });

  test('a new school with no year in the cloud gets its own year after the pull', () async {
    final s = AppStore.forTesting();
    await s.bootstrap(FakeDisk());
    expect(s.academicYears, isEmpty, reason: 'لا عام قبل الدخول');
    s.tenants.add(Tenant(
      id: 'tn1',
      name: 'مدرسة',
      code: 'T-1',
      username: 'amal',
      password: 'amal2026',
      expiresAt: DateTime.now().add(const Duration(days: 100)),
    ));
    await s.login('amal', 'amal2026');
    await s.settleAcademicYears();

    expect(s.academicYears.single.id, startsWith('ay_tn1_'));
    expect(s.viewedAcademicYearId, s.academicYears.single.id);
  });
}
