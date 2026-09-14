import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/tenant_service.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Student newStudent(AppStore s, {String nationalId = '123456789', String phone = '0599111222'}) {
  return Student(
    id: s.newId(),
    fullName: 'طالب تجريبي جديد',
    gradeLevel: 'عاشر',
    section: 'عاشر (أ)',
    phone: phone,
    parentName: 'ولي الأمر',
    parentPhone: '0598111222',
    balance: 0,
    nationalId: nationalId,
  );
}

void main() {
  // حساب المطور يُمرَّر عند البناء ولا يُكتب في الكود؛ الاختبار يضبط حسابه
  setUpAll(() {
    TenantService.masterUsername = 'dev-tester';
    TenantService.masterPassword = 'dev-tester-pass';
  });

  test('a fresh store carries no data until demo data is injected', () {
    final s = AppStore.forTesting();
    expect(s.students, isEmpty);
    expect(s.tenants, isEmpty);
    expect(s.users, isEmpty);
    expect(s.teachers, isEmpty);
  });

  test('school login accepts tenant credentials', () async {
    final s = seeded();
    expect(await s.login('', ''), isNotNull);
    expect(await s.login('amal', 'amal2026'), isNull);
    expect(s.loggedIn, isTrue);
    expect(s.isMasterAdmin, isFalse);
    expect(s.currentTenant?.code, 'AMAL-01');
    await s.logout();
  });

  test('master login opens developer mode', () async {
    final s = seeded();
    expect(await s.login('dev-tester', 'dev-tester-pass'), isNull);
    expect(s.isMasterAdmin, isTrue);
    await s.logout();
  });

  test('expired subscription is refused with a reason', () async {
    final s = seeded();
    final noor = s.tenants.firstWhere((t) => t.username == 'noor');
    noor.expiresAt = DateTime.now().subtract(const Duration(days: 1));
    final err = await s.login('noor', 'noor2026');
    expect(err, contains('انتهت'));
    expect(s.loggedIn, isFalse);
  });

  test('suspended subscription is refused', () async {
    final s = seeded();
    final noor = s.tenants.firstWhere((t) => t.username == 'noor');
    noor.active = false;
    final err = await s.login('noor', 'noor2026');
    expect(err, contains('إيقاف'));
    expect(s.loggedIn, isFalse);
  });

  test('lifetime plan never expires', () async {
    final s = seeded();
    final noor = s.tenants.firstWhere((t) => t.username == 'noor');
    noor.planType = 'lifetime';
    noor.expiresAt = DateTime.now().subtract(const Duration(days: 900));
    expect(s.subscriptionProblem(noor), isNull);
  });

  test('payment updates balance and cancel reverts it', () {
    final s = seeded();
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
  });

  test('balance is recomputed from records, not accumulated', () {
    final s = seeded();
    final student = s.students.firstWhere((e) => e.balance < 0);
    final correct = s.computeStudentBalance(student.id);

    // رقم غريب كما لو كتبه جهاز آخر كان يعمل بلا اتصال
    student.balance = 999;
    expect(s.recalculateAllBalances(), greaterThan(0));
    expect(student.balance, closeTo(correct, 0.01));
    expect(student.balance, lessThan(0), reason: 'أقساط المدرسة مديونية على الطالب');
  });

  test('student national id must be unique 9 digits', () {
    final s = seeded();
    expect(
      () => s.upsertStudent(newStudent(s, nationalId: '12'), isNew: true),
      throwsA(isA<StoreException>()),
    );
    final taken = s.students.first.nationalId;
    expect(
      () => s.upsertStudent(newStudent(s, nationalId: taken), isNew: true),
      throwsA(isA<StoreException>()),
    );
  });

  test('a new student gets no auto installments and starts at zero balance', () {
    final s = seeded();
    final before = s.installments.length;
    final stu = newStudent(s);
    s.upsertStudent(stu, isNew: true);
    expect(s.installments.length, before, reason: 'الأقساط لا تُولَّد تلقائياً');
    expect(s.installmentsOf(stu.id), isEmpty);
    expect(stu.balance, 0);
  });

  test('seat reservation fee is applied only when the admin sets one', () async {
    final s = seeded();
    final a = newStudent(s, nationalId: '111111111', phone: '0599111333')..seatReservationPaid = true;
    s.upsertStudent(a, isNew: true);
    expect(a.balance, 0, reason: 'الرسم الافتراضي صفر');

    await s.setSeatReservationFee(50);
    final b = newStudent(s, nationalId: '222222222', phone: '0599111444')..seatReservationPaid = true;
    s.upsertStudent(b, isNew: true);
    expect(b.balance, 50);
  });

  test('deleting a student with an active receipt is refused', () {
    final s = seeded();
    final student = s.students.firstWhere((e) => e.balance < 0);
    s.addPayment(studentId: student.id, amount: 10, method: 'cash', date: DateTime.now());
    expect(() => s.deleteStudent(student.id), throwsA(isA<StoreException>()));
    expect(s.studentById(student.id), isNotNull);
  });

  test('deleting a student is allowed once nothing is due', () {
    final s = seeded();
    final student = s.students.firstWhere((e) => e.balance < 0);
    // ما استُحق عليه حتى اليوم حُصِّل: يبقى القادم وحده فلا يمنع الحذف
    s.installments.removeWhere((i) => i.studentId == student.id);
    s.recalculateAllBalances();
    s.deleteStudent(student.id);
    expect(s.studentById(student.id), isNull);
    expect(s.installmentsOf(student.id), isEmpty);
    expect(s.attendanceOf(student.id, isoDate(DateTime.now())), isNull);
  });

  test('due items exclude paid installments', () {
    final s = seeded();
    final dues = s.dueItems();
    expect(dues.every((d) => d.amount > 0), isTrue);
  });
}
