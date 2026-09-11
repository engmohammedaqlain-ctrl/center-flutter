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

void main() {
  group('القسط لا يصير ديناً قبل موعده', () {
    test('قسط بعد يومين لا يُحتسب على الطالب', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: 2);

      expect(s.computeStudentBalance(student.id), 0, reason: 'القسط القادم ليس ديناً بعد');
    });

    test('من سدّد ما استُحق عليه رصيده صفر رغم وجود قسط قادم', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -10);
      _installment(s, student, daysFromNow: 20);

      s.addPayment(studentId: student.id, amount: 200, method: 'cash', date: DateTime.now());
      expect(s.computeStudentBalance(student.id), closeTo(0, 0.01));
      expect(student.isDebtor, isFalse, reason: 'لا شيء عليه اليوم');
    });

    test('القسط المستحق اليوم دين، والمتأخر كذلك', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: 0);
      _installment(s, student, daysFromNow: -30);

      expect(s.computeStudentBalance(student.id), closeTo(-400, 0.01));
    });

    test('آخر قسطين غير مدفوعين يصيران مطلوبين بعد فوات موعدهما', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -60);
      _installment(s, student, daysFromNow: -30);
      final future = _installment(s, student, daysFromNow: 15);

      expect(s.computeStudentBalance(student.id), closeTo(-400, 0.01));

      // حلّ موعد الثالث: صار مطلوباً هو الآخر
      future.dueDate = DateTime.now().subtract(const Duration(days: 1));
      expect(s.computeStudentBalance(student.id), closeTo(-600, 0.01));
    });

    test('إعادة حساب الأرصدة تتبع القاعدة نفسها', () {
      final s = _seeded();
      final student = _cleanStudent(s);
      _installment(s, student, daysFromNow: -5);
      _installment(s, student, daysFromNow: 5);
      student.balance = -999;

      s.recalculateAllBalances();
      expect(student.balance, closeTo(-200, 0.01), reason: 'القسط القادم لا يدخل الإعادة');
    });

    test('بند المستحقات يميّز المجدول عمّا حان موعده', () {
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
