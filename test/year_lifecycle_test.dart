import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Student _student({
  required String id,
  required String grade,
  required String yearId,
  String status = 'active',
}) => Student(
  id: id,
  fullName: 'طالب دورة العام',
  gradeLevel: grade,
  section: 'أ',
  phone: '0599000111',
  parentName: 'ولي الأمر',
  parentPhone: '0598000111',
  balance: 0,
  nationalId: '123456789',
  status: status,
  academicYearId: yearId,
);

void main() {
  test(
    'promotion snapshots the previous academic year before mutation',
    () async {
      final store = AppStore.forTesting();
      final oldYear = await store.ensureCurrentAcademicYear();
      final student =
          _student(id: 'student-promote', grade: 'عاشر', yearId: oldYear.id)
            ..usesCustomPlan = true
            ..planDiscountType = 'percentage'
            ..planDiscountValue = 15
            ..planDiscountReason = 'أشقاء';
      store.students.add(student);

      final years = await store.closeCurrentAndOpenNext();
      final result = store.promoteStudents({'عاشر': 'حادي عشر'});

      expect(result.promoted, 1);
      expect(student.academicYearId, years.opened.id);
      expect(student.gradeLevel, 'حادي عشر');
      expect(student.status, 'pending');
      expect(student.usesCustomPlan, isFalse);
      expect(student.planDiscountType, isNull);
      expect(store.studentYears, hasLength(1));
      expect(store.studentYears.single.academicYearId, oldYear.id);
      expect(store.studentYears.single.gradeLevel, 'عاشر');
      expect(store.studentYears.single.planDiscountValue, 15);
    },
  );

  test('closing clones grade plan with dates shifted one year', () async {
    final store = AppStore.forTesting();
    final oldYear = await store.ensureCurrentAcademicYear();
    store.gradeFees.add(
      GradeFee(
        id: 'old-fee',
        gradeName: 'عاشر',
        monthlyFee: 100,
        term1Start: '2026-09-01',
        term1End: '2026-12-31',
        planItems: const [
          PlanItem(
            id: 'old-item',
            title: 'القسط الأول',
            amount: 100,
            dueDate: '2026-09-05',
          ),
        ],
        academicYearId: oldYear.id,
      ),
    );

    final years = await store.closeCurrentAndOpenNext();
    final cloned = store.gradeFees.singleWhere(
      (f) => f.academicYearId == years.opened.id,
    );

    expect(cloned.id, isNot('old-fee'));
    expect(cloned.term1Start, '2027-09-01');
    expect(cloned.term1End, '2027-12-31');
    expect(cloned.planItems.single.id, isNot('old-item'));
    expect(cloned.planItems.single.dueDate, '2027-09-05');
  });

  test(
    'confirming a pending student builds current-year installments',
    () async {
      final store = AppStore.forTesting();
      final year = await store.ensureCurrentAcademicYear();
      store.gradeFees.add(
        GradeFee(
          id: 'current-fee',
          gradeName: 'حادي عشر',
          monthlyFee: 120,
          planItems: const [
            PlanItem(
              id: 'current-item',
              title: 'القسط الأول',
              amount: 120,
              dueDate: '2027-09-05',
            ),
          ],
          academicYearId: year.id,
        ),
      );
      final student = _student(
        id: 'student-confirm',
        grade: 'حادي عشر',
        yearId: year.id,
        status: 'pending',
      );
      store.students.add(student);

      final result = store.confirmPendingStudent(student.id);

      expect(student.status, 'active');
      expect(result.planBuilt, isTrue);
      expect(
        store.installments.where((i) => i.studentId == student.id),
        hasLength(1),
      );
      expect(store.installments.single.academicYearId, year.id);
    },
  );
}
