import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore yearStore() {
  final store = AppStore.forTesting();
  injectDemoData(store);
  return store;
}

void main() {
  test(
    'ensureCurrentAcademicYear creates one deterministic current year',
    () async {
      final store = yearStore();
      store.academicYears.clear();

      final year = await store.ensureCurrentAcademicYear();
      final start = int.parse(year.startsOn.substring(0, 4));

      expect(year.id, 'ay_${store.tenantId ?? 'local'}_$start');
      expect(year.label, '$start / ${start + 1}');
      expect(year.isCurrent, isTrue);
      expect(store.academicYears.where((y) => y.isCurrent), hasLength(1));
    },
  );

  test('filterByYear includes selected and legacy unscoped rows', () async {
    final store = yearStore();
    final viewed = await store.ensureCurrentAcademicYear();
    final other = AcademicYear(
      id: 'other',
      label: '2020 / 2021',
      startsOn: '2020-08-01',
      endsOn: '2021-07-31',
    );
    store.academicYears.add(other);

    final selected = Installment(
      id: 'selected',
      studentId: 's',
      title: 'قسط',
      amount: 10,
      dueDate: DateTime(2026),
      academicYearId: viewed.id,
    );
    final legacy = Installment(
      id: 'legacy',
      studentId: 's',
      title: 'قسط',
      amount: 10,
      dueDate: DateTime(2026),
    );
    final hidden = Installment(
      id: 'hidden',
      studentId: 's',
      title: 'قسط',
      amount: 10,
      dueDate: DateTime(2026),
      academicYearId: other.id,
    );

    expect(store.filterByYear([selected, legacy, hidden]).map((e) => e.id), [
      'selected',
      'legacy',
    ]);
  });

  test(
    'new student plan installments are stamped with operational year',
    () async {
      final store = yearStore();
      final year = await store.ensureCurrentAcademicYear();
      store.gradeFees.add(
        GradeFee(
          id: 'year-plan',
          gradeName: 'مرحلة اختبار العام',
          monthlyFee: 100,
          planItems: const [
            PlanItem(
              id: 'plan-one',
              title: 'القسط الأول',
              amount: 100,
              dueDate: '2026-09-01',
            ),
          ],
        ),
      );
      final student = Student(
        id: 'year-student',
        fullName: 'طالب اختبار العام',
        gradeLevel: 'مرحلة اختبار العام',
        section: '',
        phone: '0599555777',
        parentName: 'ولي الأمر',
        parentPhone: '0598555777',
        balance: 0,
        nationalId: '987654321',
      );

      store.upsertStudent(student, isNew: true);

      expect(student.academicYearId, year.id);
      expect(store.installmentsOf(student.id), isNotEmpty);
      expect(
        store
            .installmentsOf(student.id)
            .every((i) => i.academicYearId == year.id),
        isTrue,
      );
    },
  );
}
