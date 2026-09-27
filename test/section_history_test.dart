import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/sync.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// سجل شعب الطالب — المقابل لـ `sectionHistory.ts` في الويب: فترة لكل شعبة،
/// والمفتوحة هي الحالية.
void main() {
  AppStore seeded() {
    final s = AppStore.forTesting();
    injectDemoData(s);
    return s;
  }

  Student active(AppStore s) => s.students.firstWhere((x) => x.status == 'active' && x.section.trim().isNotEmpty);

  test('الجدول يُزامَن بأعمدة الويب', () {
    expect(syncedTables, contains('student_sections'));
    expect(tableAllowedColumns['student_sections'], containsAll(['student_id', 'from_date', 'to_date', 'section']));
  });

  test('أول فترة من يوم التسجيل، ولا تتكرر لشعبة لم تتغير', () {
    final s = seeded();
    final st = active(s);
    s.syncStudentRoomEnrollments([st.id]);
    s.syncStudentRoomEnrollments([st.id]);

    final periods = s.sectionPeriodsOf(st.id);
    expect(periods, hasLength(1));
    expect(periods.single['from_date'], isoDate(st.enrollmentDate));
    expect(periods.single['to_date'], isNull);
    expect(s.pendingSyncs.where((p) => p.tableName == 'student_sections'), hasLength(1));
  });

  test('تغيير الشعبة في اليوم نفسه تصحيح لا انتقال', () {
    final s = seeded();
    final st = active(s);
    s.syncStudentRoomEnrollments([st.id]);
    st.section = '${st.section} ب';
    s.syncStudentRoomEnrollments([st.id]);

    final periods = s.sectionPeriodsOf(st.id);
    // الفترة الأولى بدأت يوم التسجيل (قبل اليوم): تُغلق اليوم وتُفتح الجديدة
    final open = periods.where((p) => p['to_date'] == null).toList();
    expect(open, hasLength(1));
    expect(open.single['section'], st.section);
  });

  test('الترقية تغلق الفترة المفتوحة، وحذف الطالب يحذف سجله', () {
    final s = seeded();
    final st = active(s);
    s.syncStudentRoomEnrollments([st.id]);

    s.promoteStudents({st.gradeLevel: 'الصف التالي'});
    expect(s.sectionPeriodsOf(st.id).every((p) => p['to_date'] != null), isTrue);

    final fresh = Student(
      id: s.newId(),
      fullName: 'طالب للحذف',
      gradeLevel: st.gradeLevel,
      section: 'أ',
      phone: '0599000444',
      parentName: 'ولي',
      parentPhone: '0598000444',
      balance: 0,
      nationalId: '987650044',
    );
    s.students.add(fresh);
    s.syncStudentRoomEnrollments([fresh.id]);
    expect(s.sectionPeriodsOf(fresh.id), hasLength(1));
    s.deleteStudent(fresh.id);
    expect(s.sectionPeriodsOf(fresh.id), isEmpty);
  });
}
