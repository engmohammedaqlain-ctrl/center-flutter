import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
// `Evaluation` اسمٌ في `flutter_test` أيضاً، فيُخفى هنا
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Student _cleanStudent(AppStore s, {String grade = 'عاشر', String nationalId = '123123123'}) {
  return Student(
    id: s.newId(),
    fullName: 'طالب مطابقة الويب',
    gradeLevel: grade,
    section: 'بلا شعبة',
    phone: '0599111222',
    parentName: 'ولي الأمر',
    parentPhone: '0598111222',
    balance: 0,
    nationalId: nationalId,
    status: 'active',
  );
}

void _plan(AppStore s, String grade, {double amount = 100, int count = 3}) {
  final fee = s.gradeFees.where((f) => f.gradeName == grade).firstOrNull;
  final items = [
    for (var i = 0; i < count; i++)
      PlanItem(
        id: 'item_$i',
        title: 'القسط ${i + 1}',
        amount: amount,
        dueDate: isoDate(DateTime.now().add(Duration(days: 30 * (i + 1)))),
      ),
  ];
  if (fee == null) {
    s.gradeFees.add(GradeFee(id: s.newId(), gradeName: grade, monthlyFee: amount, planItems: items));
  } else {
    fee.planItems = items;
    fee.monthlyFee = amount;
  }
}

void main() {
  group('خصم التسجيل على الأقساط', () {
    test('upsertStudent يوزّع PlanDiscount على أقساط الخطة', () {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 100, count: 2);
      final student = _cleanStudent(s);

      s.upsertStudent(student, isNew: true, discount: const PlanDiscount.percent(10));

      final own = s.installments.where((i) => i.studentId == student.id && i.title != seatTitle).toList();
      expect(own, hasLength(2));
      expect(own.map((i) => i.amount), everyElement(90));
      expect(own.map((i) => i.originalAmount), everyElement(100));
    });
  });

  group('repriceGradePlan', () {
    test('يحدّث الأقساط المستقبلية غير المدفوعة فقط ويحفظ نسبة الخصم', () {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 100, count: 2);
      final student = _cleanStudent(s);
      s.upsertStudent(student, isNew: true, discount: const PlanDiscount.percent(10));

      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [
        for (final i in fee.planItems) PlanItem(id: i.id, title: i.title, amount: 200, dueDate: i.dueDate),
      ];

      final preview = s.repriceGradePlan('عاشر');
      expect(preview.installments, 2);
      expect(preview.students, 1);

      final done = s.repriceGradePlan('عاشر', apply: true);
      expect(done.installments, 2);

      final own = s.installments.where((i) => i.studentId == student.id && i.title != seatTitle).toList();
      expect(own.map((i) => i.amount), everyElement(180));
      expect(own.map((i) => i.originalAmount), everyElement(200));
    });

    test('لا يمسّ قسطاً مستحقاً أو مدفوعاً منه', () {
      final s = _seeded();
      _plan(s, 'عاشر', amount: 100, count: 1);
      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر');
      fee.planItems = [
        PlanItem(id: 'due_item', title: 'قسط حالّ', amount: 100, dueDate: isoDate(DateTime.now())),
      ];
      final student = _cleanStudent(s);
      s.upsertStudent(student, isNew: true);

      fee.planItems = [
        PlanItem(id: 'due_item', title: 'قسط حالّ', amount: 250, dueDate: isoDate(DateTime.now())),
      ];
      final preview = s.repriceGradePlan('عاشر');
      expect(preview.installments, 0);
    });
  });

  group('خصم الدفعة', () {
    test('النقد = المسدَّد − الخصم، والائتمان يشمل الخصم', () {
      final s = _seeded();
      final student = _cleanStudent(s, nationalId: '321321321');
      s.students.add(student);
      s.installments.add(Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قسط',
        amount: 200,
        dueDate: DateTime.now().subtract(const Duration(days: 1)),
      ));

      final p = s.addPayment(
        studentId: student.id,
        amount: 150,
        method: 'cash',
        date: DateTime.now(),
        discountAmount: 50,
        originalAmount: 200,
        totalDueAtPayment: 200,
      );

      expect(p.amount, 150);
      expect(p.discountAmount, 50);
      expect(p.originalAmount, 200);
      expect(p.totalDueAtPayment, 200);
      expect(p.remainingAfter, 0);
      expect(paymentAdvance(p), 0);
      expect(s.computeStudentBalance(student.id), closeTo(0, 0.01));
    });
  });

  group('معدل لكل مادة', () {
    test('subjectGradeSummaries يفصل المواد ولا يخلطها', () {
      final scheme = const GradingScheme(
        term1: [GradingComponent(id: 'mid', name: 'نصفي', weight: 100)],
      );
      final evals = [
        Evaluation(id: '1', studentId: 's', title: 'نصفي عربي', score: 80, subjectId: 'ar', term: 'term_1', componentId: 'mid'),
        Evaluation(id: '2', studentId: 's', title: 'نصفي رياضيات', score: 40, subjectId: 'math', term: 'term_1', componentId: 'mid'),
      ];

      final summaries = subjectGradeSummaries(evals, scheme, (id) => id == 'ar' ? 'عربي' : 'رياضيات');
      expect(summaries, hasLength(2));
      final ar = summaries.firstWhere((s) => s.subjectId == 'ar');
      final math = summaries.firstWhere((s) => s.subjectId == 'math');
      expect(ar.term1.total, closeTo(80, 0.01));
      expect(math.term1.total, closeTo(40, 0.01));
    });
  });

  group('إلغاء الأقساط المستقبلية عند الأرشفة', () {
    test('الأرشفة تحذف القسط المجدول غير المدفوع وتعيد الرصيد', () {
      final s = _seeded();
      final student = _cleanStudent(s, nationalId: '111222333');
      s.students.add(student);
      final due = Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'مستحق',
        amount: 100,
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
      );
      final future = Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قادم',
        amount: 100,
        dueDate: DateTime.now().add(const Duration(days: 30)),
      );
      s.installments.addAll([due, future]);
      s.recalculateAllBalances();
      expect(s.computeStudentBalance(student.id), closeTo(-200, 0.01));

      s.archiveStudent(student.id);
      expect(s.studentById(student.id)?.status, 'archived');
      expect(s.installments.any((i) => i.id == future.id), isFalse);
      expect(s.installments.any((i) => i.id == due.id), isTrue);
      expect(s.computeStudentBalance(student.id), closeTo(-100, 0.01));
    });
  });

  group('إعفاء القسط والتحاق من تاريخ التسجيل', () {
    test('القسط المعفى لا يدخل الرصيد ولا المستحق', () {
      final s = _seeded();
      final student = _cleanStudent(s, nationalId: '555666777');
      s.students.add(student);
      final inst = Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قسط',
        amount: 200,
        dueDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      s.installments.add(inst);
      s.recalculateAllBalances();
      expect(s.computeStudentBalance(student.id), closeTo(-200, 0.01));

      s.setInstallmentExempt(inst, exempt: true, reason: 'منحة');
      expect(s.computeStudentBalance(student.id), closeTo(0, 0.01));
      expect(s.outstandingDue(student.id), 0);
    });

    test('from_enrollment يستبعد أقساط ما قبل يوم التسجيل', () {
      final items = [
        PlanItem(id: 'a', title: '1', amount: 100, dueDate: '2026-01-01'),
        PlanItem(id: 'b', title: '2', amount: 100, dueDate: '2026-06-01'),
        PlanItem(id: 'c', title: '3', amount: 100, dueDate: '2026-09-01'),
      ];
      final kept = filterPlanFromEnrollment(items, '2026-06-01');
      expect(kept.map((i) => i.id), ['b', 'c']);
      final rows = buildStudentPlan(
        items,
        'stu',
        enrollmentDate: '2026-06-01',
        enrollmentMode: EnrollmentPlanMode.fromEnrollment,
      );
      expect(rows.where((r) => r.title != seatTitle).map((r) => r.title), ['2', '3']);
    });
  });
}
