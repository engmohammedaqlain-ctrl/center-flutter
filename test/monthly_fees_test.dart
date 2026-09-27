import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/fee_plan.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// الرسوم الشهرية داخل فصول المرحلة — مطابق لـ `monthlyFees.test.ts` في الويب:
/// أول دفعة يوم التسجيل كاملة، ثم اليوم نفسه كل شهر، وآخر دفعة في الفصل بقدر
/// أيامه الباقية (÷ 30). الفصل التالي يبدأ من يوم بدايته.

const _t1 = FeeTerm('term_1', '2026-09-01', '2026-12-31');
const _t2 = FeeTerm('term_2', '2027-01-01', '2027-06-30');

List<String> _view(Iterable<PlanItem> items) => [for (final i in items) '${i.dueDate}:${trimNum(i.amount)}'];

double _round(double n) => (n * 100).round() / 100;

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// مرحلة «عاشر» برسوم شهرية وفصول خاصة في المستقبل: لا شيء فيها حلّ موعده.
GradeFee _monthly(AppStore s, {double amount = 200}) {
  final now = DateTime.now();
  final start = DateTime(now.year + 1, 9, 1);
  final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر')
    ..feeMode = 'monthly'
    ..monthlyFee = amount
    ..term1Start = isoDate(start)
    ..term1End = '${start.year}-12-31'
    ..term2Start = '${start.year + 1}-01-01'
    ..term2End = '${start.year + 1}-06-30';
  return fee;
}

Student _student(AppStore s, DateTime enrolled) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب شهري',
    gradeLevel: 'عاشر',
    section: 'أ',
    phone: '0599000222',
    parentName: 'ولي',
    parentPhone: '0598000222',
    balance: 0,
    nationalId: '987650001',
    enrolledAt: enrolled,
  );
  s.students.add(student);
  return student;
}

List<Installment> _planRows(AppStore s, String studentId) =>
    s.installments.where((i) => i.studentId == studentId && isStagePlanInstallmentId(i.id)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

void main() {
  group('بنود الرسوم الشهرية', () {
    test('مثال المدرسة: سجّل 15/3 والفصل ينتهي 30/4 ← 15/3 كاملة و15/4 نصف', () {
      final items = monthlyPlanItems(
        amount: 200,
        enrollmentDate: '2027-03-15',
        terms: const [FeeTerm('term_2', '2027-02-01', '2027-04-30')],
      );
      expect(_view(items), ['2027-03-15:200', '2027-04-15:100']);
      expect(items.last.title, 'رسوم شهر أبريل (15 يوم)');
    });

    test('الفصل التالي يبدأ من يوم بدايته، وآخر الفصل الأول بقدر أيامه', () {
      final items = monthlyPlanItems(amount: 300, enrollmentDate: '2026-09-10', terms: const [_t1, _t2]);
      expect(_view(items), [
        '2026-09-10:300', '2026-10-10:300', '2026-11-10:300',
        '2026-12-10:210', // 21 يوماً حتى 31/12
        '2027-01-01:300', '2027-02-01:300', '2027-03-01:300', '2027-04-01:300', '2027-05-01:300', '2027-06-01:300',
      ]);
      expect(items.first.id, 'monthly_2027_term_1_1');
      expect(items.first.title, 'رسوم شهر سبتمبر');
    });

    test('الفصل الذي ينتهي قبل يوم الموعد التالي بيوم يُحسب شهره كاملاً', () {
      final items = monthlyPlanItems(
        amount: 200,
        enrollmentDate: '2027-03-01',
        terms: const [FeeTerm('term_2', '2027-01-01', '2027-05-31')],
      );
      expect(_view(items), ['2027-03-01:200', '2027-04-01:200', '2027-05-01:200']);
    });

    test('أول دفعة كاملة ولو قرب نهاية الفصل', () {
      final items = monthlyPlanItems(amount: 200, enrollmentDate: '2026-12-20', terms: const [_t1, _t2]);
      expect(_view(items.take(1)), ['2026-12-20:200']);
      expect(items[1].dueDate, '2027-01-01');
    });

    test('المسجّل بين الفصلين يبدأ من بداية الفصل الثاني، ومن سجّل قبل الفصل الأول من بدايته', () {
      expect(
        monthlyPlanItems(amount: 100, enrollmentDate: '2026-12-31', terms: const [FeeTerm('term_1', '2026-09-01', '2026-12-20'), _t2]).first.dueDate,
        '2027-01-01',
      );
      expect(monthlyPlanItems(amount: 100, enrollmentDate: '2026-08-15', terms: const [_t1, _t2]).first.dueDate, '2026-09-01');
    });

    test('معرّفات العام التالي لا تصطدم بمعرّفات العام الماضي', () {
      final last = monthlyPlanItems(amount: 100, enrollmentDate: '2025-09-10', terms: const [
        FeeTerm('term_1', '2025-09-01', '2025-12-31'),
        FeeTerm('term_2', '2026-01-01', '2026-06-30'),
      ]);
      final next = monthlyPlanItems(amount: 100, enrollmentDate: '2025-09-10', terms: const [_t1, _t2]);
      expect(next.first.dueDate, '2026-09-01');
      final lastIds = {for (final i in last) i.id};
      expect(next.any((i) => lastIds.contains(i.id)), isFalse);
    });

    test('فصول المرحلة تغلب فصول العام، والفارغ منها يُؤخذ من العام', () {
      final year = AcademicYear(
        id: 'y',
        label: '2026 / 2027',
        startsOn: '2026-08-01',
        endsOn: '2027-07-31',
        term1Start: _t1.start,
        term1End: _t1.end,
        term2Start: _t2.start,
        term2End: _t2.end,
      );
      final grade = GradeFee(id: 'g', gradeName: 'تمهيدي', monthlyFee: 200, term2End: '2027-05-15');
      expect(feeTermsFor(grade, year), const [_t1, FeeTerm('term_2', '2027-01-01', '2027-05-15')]);
      final bare = AcademicYear(id: 'y2', label: '', startsOn: '2026-08-01', endsOn: '2027-07-31');
      expect(feeTermsFor(null, bare), const [FeeTerm('year', '2026-08-01', '2027-07-31')]);
    });

    test('بلا مبلغ لا بنود، والمرحلة بالأقساط تبقى على خطتها', () {
      expect(monthlyPlanItems(amount: 0, enrollmentDate: '2026-09-10', terms: const [_t1]), isEmpty);
      const fixed = [PlanItem(id: 'a', title: 'قسط', amount: 300, dueDate: '2026-10-01')];
      final grade = GradeFee(id: 'g', gradeName: 'روضة', monthlyFee: 200, planItems: fixed);
      expect(gradePlanItemsFor(grade, enrollmentDate: '2026-09-10', today: '2026-09-10'), same(fixed));
    });

    test('fee_mode يُقرأ ويُكتب مع المرحلة، والغائب أقساط', () {
      final g = GradeFee.fromCloud({'id': 'g', 'grade_name': 'روضة', 'monthly_fee': 200, 'fee_mode': 'monthly'});
      expect(isMonthlyGrade(g), isTrue);
      expect(g.toCloud()['fee_mode'], 'monthly');
      expect(GradeFee.fromCloud({'id': 'g', 'grade_name': 'روضة'}).feeMode, 'installments');
    });
  });

  group('مرحلة برسوم شهرية', () {
    test('تسجيل طالب: أقساطه من يوم تسجيله داخل فصول المرحلة', () {
      final s = _seeded();
      final fee = _monthly(s, amount: 300);
      final enrolled = DateTime(DateTime.now().year + 1, 9, 10);
      final student = Student(
        id: s.newId(),
        fullName: 'طالب جديد',
        gradeLevel: 'عاشر',
        section: 'أ',
        phone: '0599000333',
        parentName: 'ولي',
        parentPhone: '0598000333',
        balance: 0,
        nationalId: '987650002',
        enrolledAt: enrolled,
      );
      s.upsertStudent(student, isNew: true, enrollmentMode: EnrollmentPlanMode.fromEnrollment);

      final expected = monthlyPlanItems(amount: 300, enrollmentDate: isoDate(enrolled), terms: feeTermsFor(fee, null));
      final rows = _planRows(s, student.id);
      expect([for (final r in rows) '${isoDate(r.dueDate)}:${trimNum(r.amount)}'], _view(expected));
      expect(rows.first.dueDate, enrolled);
    });

    test('طالبان في المرحلة نفسها لكل منهما مواعيده، والتطبيق الثاني لا يكرر شيئاً', () {
      final s = _seeded();
      _monthly(s);
      final y = DateTime.now().year + 1;
      final a = _student(s, DateTime(y, 9, 10));
      final b = _student(s, DateTime(y, 9, 18));
      s.syncGradePlan('عاشر', apply: true);

      expect(isoDate(_planRows(s, a.id)[1].dueDate), '$y-10-10');
      expect(isoDate(_planRows(s, b.id)[1].dueDate), '$y-10-18');

      final before = _planRows(s, a.id).length;
      expect(s.syncGradePlan('عاشر').isEmpty, isTrue);
      s.syncGradePlan('عاشر', apply: true);
      expect(_planRows(s, a.id).length, before);
    });

    test('تغيير المبلغ الشهري يسري على القادمة، والناقصة تتبع السعر الجديد', () {
      final s = _seeded();
      final fee = _monthly(s, amount: 300);
      final y = DateTime.now().year + 1;
      final a = _student(s, DateTime(y, 9, 10));
      s.syncGradePlan('عاشر', apply: true);

      fee.monthlyFee = 330;
      s.syncGradePlan('عاشر', apply: true);
      final rows = _planRows(s, a.id);
      expect(rows[0].amount, 330);
      expect(rows[3].amount, _round(330 / 30 * 21)); // 10/12 حتى 31/12
    });

    test('التحويل من أقساط إلى شهري يستبدل الخطة كلها', () {
      final s = _seeded();
      final y = DateTime.now().year + 1;
      final fee = s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر')
        ..planItems = [
          PlanItem(id: 'old1', title: 'قسط 1', amount: 200, dueDate: '$y-09-01'),
          PlanItem(id: 'old2', title: 'قسط 2', amount: 200, dueDate: '$y-10-01'),
        ];
      final a = _student(s, DateTime(y, 9, 1));
      s.syncGradePlan('عاشر', apply: true);
      expect(_planRows(s, a.id).map((r) => r.id), everyElement(contains('old')));

      _monthly(s, amount: 200);
      expect(fee.feeMode, 'monthly');
      s.syncGradePlan('عاشر', apply: true, removePaid: true);
      final rows = _planRows(s, a.id);
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.id.contains(monthlyItemPrefix)), isTrue);
      expect(isoDate(rows.first.dueDate), '$y-09-01');
    });

    test('المدفوع من الخطة القديمة لا يضيع ولا يُطالَب بالشهر مرتين', () {
      final s = _seeded();
      final y = DateTime.now().year + 1;
      s.gradeFees.firstWhere((f) => f.gradeName == 'عاشر').planItems = [
        PlanItem(id: 'old1', title: 'قسط 1', amount: 200, dueDate: '$y-09-01'),
        PlanItem(id: 'old2', title: 'قسط 2', amount: 200, dueDate: '$y-10-01'),
      ];
      final a = _student(s, DateTime(y, 9, 1));
      s.syncGradePlan('عاشر', apply: true);
      s.addPayment(studentId: a.id, amount: 200, method: 'cash', date: DateTime.now());

      _monthly(s, amount: 200);
      // ما تفعله نافذة التحويل: حذف المدفوع من الخطة القديمة دائماً
      s.syncGradePlan('عاشر', apply: true, removePaid: true);

      final rows = _planRows(s, a.id);
      expect(rows.every((r) => r.id.contains(monthlyItemPrefix)), isTrue);
      expect(rows.first.paidAmount, 200);
      expect(rows.fold<double>(0, (sum, r) => sum + r.paidAmount), 200);
      expect(s.payments.where((p) => p.studentId == a.id && !p.cancelled), hasLength(1));
    });
  });
}
