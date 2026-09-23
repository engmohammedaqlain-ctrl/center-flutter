import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/grade_plan_sync.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

void _plan(AppStore s, String grade, {double amount = 100, int count = 3}) {
  final fee = s.gradeFees.where((f) => f.gradeName == grade).firstOrNull!;
  fee.planItems = [
    for (var i = 0; i < count; i++)
      PlanItem(
        id: 'sync_item_$i',
        title: 'القسط ${i + 1}',
        amount: amount,
        dueDate: isoDate(DateTime.now().add(Duration(days: 30 * (i + 1)))),
      ),
  ];
}

Student _student(AppStore s) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب المزامنة',
    gradeLevel: 'عاشر',
    section: 'أ',
    phone: '0599000111',
    parentName: 'ولي',
    parentPhone: '0598000111',
    balance: 0,
    nationalId: '987654321',
  );
  s.students.add(student);
  return student;
}

void main() {
  group('GradePlanSync', () {
    test('يبني الخطة لمن بلا أقساط ويضيف البنود الناقصة', () {
      final s = _seeded();
      _plan(s, 'عاشر', count: 2);
      final student = _student(s);

      final preview = s.syncGradePlan('عاشر');
      expect(preview.build.students, 1);
      expect(preview.build.installments, 2);

      final done = s.syncGradePlan('عاشر', apply: true);
      expect(done.build.students, 1);
      expect(s.installments.where((i) => i.studentId == student.id).length, 2);

      // بند جديد في الخطة بتاريخ بعد أول قسط قائم → يُضاف
      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [
        ...fee.planItems,
        PlanItem(
          id: 'sync_item_extra',
          title: 'قسط إضافي',
          amount: 50,
          dueDate: isoDate(DateTime.now().add(const Duration(days: 120))),
        ),
      ];
      final addPreview = s.syncGradePlan('عاشر');
      expect(addPreview.add.installments, 1);
      s.syncGradePlan('عاشر', apply: true);
      expect(s.installments.where((i) => i.studentId == student.id).length, 3);
    });

    test('يحذف بنداً سقط من الخطة إن لم يُدفع منه', () {
      final s = _seeded();
      _plan(s, 'عاشر', count: 2);
      final student = _student(s);
      s.syncGradePlan('عاشر', apply: true);

      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [fee.planItems.first];

      final preview = s.syncGradePlan('عاشر');
      expect(preview.remove.installments, 1);

      s.syncGradePlan('عاشر', apply: true);
      expect(
        s.installments.where((i) => i.studentId == student.id && isStagePlanInstallmentId(i.id)).length,
        1,
      );
    });

    test('يعيد تسعير الأقساط القادمة ويحفظ خصم الطالب', () {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 100, count: 2);
      final student = Student(
        id: s.newId(),
        fullName: 'طالب المزامنة',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599000111',
        parentName: 'ولي',
        parentPhone: '0598000111',
        balance: 0,
        nationalId: '987654321',
      );
      s.upsertStudent(
        student,
        isNew: true,
        discount: const PlanDiscount.percent(10),
      );

      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [
        for (final i in fee.planItems)
          PlanItem(id: i.id, title: i.title, amount: 200, dueDate: i.dueDate),
      ];

      final preview = s.syncGradePlan('عاشر');
      expect(preview.reprice.installments, greaterThan(0));

      s.syncGradePlan('عاشر', apply: true);
      final own = s.installments
          .where((i) => i.studentId == student.id && isStagePlanInstallmentId(i.id))
          .toList();
      expect(own.map((i) => i.amount), everyElement(180));
      expect(own.map((i) => i.originalAmount), everyElement(200));
    });

    test('يحدّث تاريخ وعنوان القسط القادم غير المدفوع (reschedule)', () {
      final s = _seeded();
      _plan(s, 'عاشر', count: 2);
      final student = _student(s);
      s.syncGradePlan('عاشر', apply: true);

      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      final first = fee.planItems.first;
      final newDue = isoDate(DateTime.now().add(const Duration(days: 45)));
      fee.planItems = [
        PlanItem(id: first.id, title: 'قسط معدَّل', amount: first.amount, dueDate: newDue),
        ...fee.planItems.skip(1),
      ];

      final preview = s.syncGradePlan('عاشر');
      expect(preview.reschedule.installments, greaterThan(0));

      s.syncGradePlan('عاشر', apply: true);
      final row = s.installments.firstWhere(
        (i) => i.studentId == student.id && i.id.contains(first.id),
      );
      expect(row.title, 'قسط معدَّل');
      expect(isoDate(row.dueDate), newDue);
    });

    test('lockedPlanItemIds يقفل المستحق والمدفوع منه', () {
      final s = _seeded();
      final past = PlanItem(
        id: 'due_item',
        title: 'قديم',
        amount: 100,
        dueDate: isoDate(DateTime.now().subtract(const Duration(days: 5))),
      );
      final future = PlanItem(
        id: 'future_item',
        title: 'قادم',
        amount: 100,
        dueDate: isoDate(DateTime.now().add(const Duration(days: 40))),
      );
      expect(lockedPlanItemIds(s, [past, future]), {'due_item'});

      final student = _student(s);
      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [future];
      s.syncGradePlan('عاشر', apply: true);
      final inst = s.installments.firstWhere((i) => i.studentId == student.id);
      inst.paidAmount = 10;
      expect(lockedPlanItemIds(s, [future]), {'future_item'});
    });
  });
}
