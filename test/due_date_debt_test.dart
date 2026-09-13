import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// طالب بلا أقساط ولا سندات ولا تسجيلات — لوحة نظيفة لاختبار قاعدة الاستحقاق.
Student _cleanStudent(AppStore s) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب قاعدة الاستحقاق',
    gradeLevel: 'عاشر',
    section: 'بلا شعبة',
    phone: '0599000111',
    parentName: 'ولي الأمر',
    parentPhone: '0598000111',
    balance: 0,
    nationalId: '987654321',
  );
  s.students.add(student);
  return student;
}

Installment _installment(AppStore s, Student student, {required int daysFromNow, double amount = 200}) {
  final inst = Installment(
    id: s.newId(),
    studentId: student.id,
    title: 'قسط',
    amount: amount,
    dueDate: DateTime.now().add(Duration(days: daysFromNow)),
  );
  s.installments.add(inst);
  return inst;
}

/// المستحق على الطالب اليوم — ما حلّ موعده ولم يُسدَّد.
double _overdue(AppStore s, Student student) =>
    overdueByStudent(s.installments.where((i) => i.studentId == student.id))[student.id] ?? 0;

void main() {
  group('الرصيد يتبع المستحق حتى اليوم', () {
    test('القسط المجدول ليس ديناً: لم يدرس شهره بعد', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: 2);

      expect(s.computeStudentBalance(student.id), 0, reason: 'لا يُطالَب بما لم يحن موعده');
      expect(_overdue(s, student), 0);
    });

    test('من سدّد ما استُحق عليه رصيده صفر رغم قسط قادم', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -10);
      _installment(s, student, daysFromNow: 20);

      s.addPayment(studentId: student.id, amount: 200, method: 'cash', date: DateTime.now());
      expect(s.computeStudentBalance(student.id), closeTo(0, 0.01), reason: 'خالص حتى اليوم');
      expect(student.isDebtor, isFalse);
      expect(_overdue(s, student), 0);
    });

    test('الدفع فوق المستحق يظهر «له»، ويُخصم من القسط القادم حين يحلّ', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -10);
      final next = _installment(s, student, daysFromNow: 20);

      // قسطان قيمتهما 400 والمستحق اليوم 200: دفع 400 يعني 200 له
      s.addPayment(studentId: student.id, amount: 400, method: 'cash', date: DateTime.now());
      expect(s.computeStudentBalance(student.id), closeTo(200, 0.01), reason: 'الفائض رصيد له');
      expect(next.paidAmount, closeTo(200, 0.01), reason: 'الفائض نزل على القسط القادم');
      expect(next.status, 'paid');

      // حلّ موعد القادم: صار مستحقاً، والرصيد يعود صفراً بلا دفعة جديدة
      next.dueDate = DateTime.now().subtract(const Duration(days: 1));
      expect(s.computeStudentBalance(student.id), closeTo(0, 0.01));
      expect(_overdue(s, student), 0, reason: 'مسدَّد سلفاً');
    });

    test('المستحق اليوم والمتأخر كلاهما دين', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: 0);
      _installment(s, student, daysFromNow: -30);

      expect(s.computeStudentBalance(student.id), closeTo(-400, 0.01));
      expect(_overdue(s, student), closeTo(400, 0.01));
    });

    test('حلول موعد القسط يزيد الدين', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -60);
      _installment(s, student, daysFromNow: -30);
      final future = _installment(s, student, daysFromNow: 15);

      expect(s.computeStudentBalance(student.id), closeTo(-400, 0.01), reason: 'المستحق قسطان');
      expect(_overdue(s, student), closeTo(400, 0.01));

      future.dueDate = DateTime.now().subtract(const Duration(days: 1));
      expect(s.computeStudentBalance(student.id), closeTo(-600, 0.01));
      expect(_overdue(s, student), closeTo(600, 0.01));
    });

    test('إعادة حساب الأرصدة تعطي ما يعطيه حساب الطالب الواحد', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -5);
      _installment(s, student, daysFromNow: 5);
      student.balance = -999;

      s.recalculateAllBalances();
      expect(student.balance, closeTo(-200, 0.01), reason: 'المستحق قسط واحد');
      expect(student.balance, closeTo(s.computeStudentBalance(student.id), 0.01));
    });

    test('في المركز لا تدخل الأقساط الرصيد، بل رسوم التسجيلات', () async {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -5);

      await s.saveInstitution(type: 'center');
      expect(s.computeStudentBalance(student.id), 0, reason: 'مطالبة المركز في تسجيلاته');

      s.enrollments.add(StudentEnrollment(
        id: s.newId(),
        studentId: student.id,
        groupId: 'g-x',
        appliedPrice: 150,
      ));
      expect(s.computeStudentBalance(student.id), closeTo(-150, 0.01));
    });
  });

  group('توزيع السندات على الأقساط', () {
    test('السند المربوط يُسدِّد قسطه، والفائض ينزل على الأقدم استحقاقاً', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      final first = _installment(s, student, daysFromNow: -30);
      final second = _installment(s, student, daysFromNow: -1);

      // سند بمبلغ قسطين مربوط بالثاني: يسدّده ثم يفيض على الأول
      s.payments.add(Payment(
        id: s.newId(),
        receiptNumber: '2026/1900',
        studentId: student.id,
        amount: 400,
        method: 'cash',
        date: DateTime.now(),
        installmentId: second.id,
        createdAt: DateTime.now().toIso8601String(),
      ));

      final paid = allocatePaymentsToInstallments(
        s.installments.where((i) => i.studentId == student.id),
        s.payments.where((p) => p.studentId == student.id),
      );
      expect(paid[second.id], closeTo(200, 0.01));
      expect(paid[first.id], closeTo(200, 0.01));

      s.recalculateAllBalances();
      expect(first.status, 'paid');
      expect(second.status, 'paid');
      expect(student.balance, closeTo(0, 0.01));
    });

    test('السند الملغى لا يُحتسب، والمسدَّد يعود إلى ما كان', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      final inst = _installment(s, student, daysFromNow: -3);
      s.payments.add(Payment(
        id: s.newId(),
        receiptNumber: '2026/1901',
        studentId: student.id,
        amount: 200,
        method: 'cash',
        date: DateTime.now(),
        cancelled: true,
        createdAt: DateTime.now().toIso8601String(),
      ));

      s.recalculateAllBalances();
      expect(inst.paidAmount, 0);
      expect(inst.status, 'unpaid');
      expect(student.balance, closeTo(-200, 0.01));
    });

    test('الخصم المرافق للسند يُحتسب سداداً كما في النسخة المكتبية', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      final inst = _installment(s, student, daysFromNow: -3);
      s.payments.add(Payment(
        id: s.newId(),
        receiptNumber: '2026/1902',
        studentId: student.id,
        amount: 150,
        method: 'cash',
        date: DateTime.now(),
        discountAmount: 50,
        discountReason: 'خصم إخوة',
        createdAt: DateTime.now().toIso8601String(),
      ));

      s.recalculateAllBalances();
      expect(inst.paidAmount, closeTo(200, 0.01));
      expect(inst.status, 'paid');
      expect(student.balance, closeTo(0, 0.01));
    });
  });

  group('بند المستحقات', () {
    test('يميّز المجدول عمّا حان موعده', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      final later = _installment(s, student, daysFromNow: 9);
      final late = _installment(s, student, daysFromNow: -9);

      final items = s.dueItems().where((d) => d.student.id == student.id).toList();
      final scheduled = items.firstWhere((d) => d.installmentId == later.id);
      final overdue = items.firstWhere((d) => d.installmentId == late.id);

      expect(scheduled.scheduled, isTrue);
      expect(scheduled.late, isFalse);
      expect(scheduled.stageLabel, 'مجدول');
      expect(overdue.scheduled, isFalse);
      expect(overdue.late, isTrue);
      expect(overdue.stageLabel, 'متأخر عن السداد');
    });
  });
}
