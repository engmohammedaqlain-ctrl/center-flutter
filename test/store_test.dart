import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('school login accepts tenant credentials', () {
    final s = AppStore.instance;
    expect(s.login('', ''), isNotNull);
    expect(s.login('wrong', 'x'), 'اسم المستخدم أو كلمة المرور غير صحيحة');
    expect(s.login('amal', 'amal2026'), isNull);
    expect(s.loggedIn, isTrue);
    expect(s.isMasterAdmin, isFalse);
    s.logout();
  });

  test('master login opens developer mode', () {
    final s = AppStore.instance;
    expect(s.login('anas', 'anas2026'), isNull);
    expect(s.isMasterAdmin, isTrue);
    s.logout();
  });

  test('payment updates balance and cancel reverts it', () {
    final s = AppStore.instance;
    s.login('amal', 'amal2026');
    final student = s.students.firstWhere((e) => e.balance < 0);
    final before = student.balance;
    final p = s.addPayment(
      studentId: student.id,
      amount: 50,
      method: 'cash',
      date: DateTime.now(),
    );
    expect(student.balance, before + 50);
    expect(p.receiptNumber.contains('/'), isTrue);
    s.cancelPayment(p);
    expect(student.balance, before);
    expect(p.cancelled, isTrue);
    s.logout();
  });

  test('student national id must be unique 9 digits', () {
    final s = AppStore.instance;
    expect(
      () => s.upsertStudent(
        Student(
          id: s.newId(),
          fullName: 'تجربة',
          gradeLevel: 'عاشر',
          section: 'عاشر (أ)',
          phone: '0599111222',
          parentName: 'أب',
          parentPhone: '0598111222',
          balance: 0,
          nationalId: '12',
        ),
        isNew: true,
      ),
      throwsA(isA<StoreException>()),
    );
  });

  test('due items exclude paid installments', () {
    final s = AppStore.instance;
    final dues = s.dueItems();
    expect(dues.every((d) => d.amount > 0), isTrue);
  });
}
