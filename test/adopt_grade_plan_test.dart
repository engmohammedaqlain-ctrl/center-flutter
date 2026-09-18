import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void _plan(AppStore s, String grade, {required List<PlanItem> items}) {
  final fee = s.gradeFees.where((f) => f.gradeName == grade).firstOrNull!;
  fee.planItems = items;
}

Student _student(AppStore s, {String grade = 'عاشر', bool custom = false}) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب الخطة',
    gradeLevel: grade,
    section: 'أ',
    phone: '0599000222',
    parentName: 'ولي',
    parentPhone: '0598000222',
    balance: 0,
    nationalId: '123123123',
    usesCustomPlan: custom,
    status: 'active',
  );
  s.students.add(student);
  return student;
}

void main() {
  group('adoptGradePlan', () {
    test('معاينة إرجاع من مخصصة: يزيل غير المدفوع ويضيف المستقبلية فقط', () {
      final s = _seeded();
      final past = isoDate(DateTime.now().subtract(const Duration(days: 40)));
      final future1 = isoDate(DateTime.now().add(const Duration(days: 30)));
      final future2 = isoDate(DateTime.now().add(const Duration(days: 60)));
      _plan(s, 'عاشر', items: [
        PlanItem(id: 'p0', title: 'سابق', amount: 100, dueDate: past),
        PlanItem(id: 'p1', title: 'قادم 1', amount: 100, dueDate: future1),
        PlanItem(id: 'p2', title: 'قادم 2', amount: 100, dueDate: future2),
      ]);

      final student = _student(s, custom: true);
      s.installments.addAll([
        Installment(
          id: customInstallmentId('a', student.id),
          studentId: student.id,
          title: 'مخصص غير مدفوع',
          amount: 80,
          dueDate: DateTime.now().add(const Duration(days: 10)),
        ),
        Installment(
          id: customInstallmentId('b', student.id),
          studentId: student.id,
          title: 'مخصص مدفوع',
          amount: 50,
          paidAmount: 50,
          dueDate: DateTime.now().subtract(const Duration(days: 5)),
          status: 'paid',
        ),
      ]);

      final preview = s.returnCustomStudentsToGradePlan(
        studentIds: [student.id],
        planScope: 'future',
      );
      expect(preview.students, 1);
      expect(preview.removed, 1);
      expect(preview.added, 2);
      expect(student.usesCustomPlan, isTrue);

      final done = s.returnCustomStudentsToGradePlan(
        studentIds: [student.id],
        planScope: 'future',
        apply: true,
      );
      expect(done.added, 2);
      expect(student.usesCustomPlan, isFalse);
      expect(
        s.installments.where((i) => i.studentId == student.id && isCustomInstallmentId(i.id)).length,
        1,
      );
      expect(
        s.installments.where((i) => i.studentId == student.id && isStagePlanInstallmentId(i.id)).length,
        2,
      );
    });

    test('نقل مرحلة يزيل أقساط الخطة القديمة غير المدفوعة ويغيّر المرحلة', () {
      final s = _seeded();
      final future = isoDate(DateTime.now().add(const Duration(days: 20)));
      _plan(s, 'عاشر', items: [
        PlanItem(id: 'old1', title: 'قديم', amount: 90, dueDate: future),
      ]);
      _plan(s, 'حادي عشر علمي', items: [
        PlanItem(id: 'new1', title: 'جديد', amount: 120, dueDate: future),
      ]);

      final student = _student(s);
      s.installments.add(
        Installment(
          id: planInstallmentId('old1', student.id),
          studentId: student.id,
          title: 'قديم',
          amount: 90,
          dueDate: DateTime.now().add(const Duration(days: 20)),
        ),
      );

      final preview = s.transferStudentsToGrade(
        studentIds: [student.id],
        newGradeName: 'حادي عشر علمي',
        planScope: 'all',
      );
      expect(preview.students, 1);
      expect(preview.removed, 1);
      expect(preview.added, 1);

      s.transferStudentsToGrade(
        studentIds: [student.id],
        newGradeName: 'حادي عشر علمي',
        planScope: 'all',
        apply: true,
      );
      expect(student.gradeLevel, 'حادي عشر علمي');
      expect(
        s.installments.any((i) => i.id == planInstallmentId('old1', student.id)),
        isFalse,
      );
      expect(
        s.installments.any((i) => i.id == planInstallmentId('new1', student.id)),
        isTrue,
      );
    });
  });
}
