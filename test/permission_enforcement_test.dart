import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/student_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجر بجهاز مثبَّت باسم سكرتير يحمل [caps] — أو قالب دوره إن لم تُمرَّر.
Future<AppStore> clerkDevice({List<String>? caps}) async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
  if (caps != null) clerk.capabilities = caps;
  await s.setDeviceIdentity(clerk, '');
  s.pendingSyncs.clear();
  return s;
}

void main() {
  group('المتجر يرفض ما لا يملكه المستخدم مهما كان المسار', () {
    test('السكرتير لا يحذف طالباً ولا يترك أثراً', () async {
      final s = await clerkDevice();
      final student = s.students.first;

      expect(() => s.deleteStudent(student.id), throwsA(isA<StoreException>()));
      expect(s.studentById(student.id), isNotNull);
      expect(s.pendingSyncs, isEmpty, reason: 'لا شيء يُرفع لعملية مرفوضة');
    });

    test('السكرتير لا يلغي سند قبض', () async {
      final s = await clerkDevice();
      final payment = s.payments.firstWhere((p) => !p.cancelled);

      expect(() => s.cancelPayment(payment), throwsA(isA<StoreException>()));
      expect(payment.cancelled, isFalse);
    });

    test('السكرتير لا يسجّل مصروفاً ولا يعدّل المجموعات', () async {
      final s = await clerkDevice();

      expect(
        () => s.addExpense(category: 'أخرى', description: 'قرطاسية', amount: 20, expenseDate: '2026-09-10'),
        throwsA(isA<StoreException>()),
      );
      expect(s.expenses, isEmpty);
      expect(() => s.deleteGroup('any'), throwsA(isA<StoreException>()));
    });

    test('رسالة الرفض تذكر الصلاحية باسمها المعروض', () async {
      final s = await clerkDevice();
      try {
        s.deleteStudent(s.students.first.id);
        fail('كان يجب أن يُرفض الحذف');
      } on StoreException catch (e) {
        expect(e.message, contains('حذف الطلاب'));
      }
    });

    test('ما يملكه السكرتير يمرّ كما هو', () async {
      final s = await clerkDevice();
      final student = s.students.first;

      s.setAttendance(student.id, '2026-09-10', 'present');
      expect(s.attendanceRecord(student.id, '2026-09-10')?.status, 'present');
    });

    test('قائمة مخصّصة بلا رصد الحضور ترفض الرصد', () async {
      final s = await clerkDevice(caps: ['students.view', 'attendance.view']);
      final student = s.students.first;

      expect(() => s.setAttendance(student.id, '2026-09-10', 'present'), throwsA(isA<StoreException>()));
      expect(s.attendanceRecord(student.id, '2026-09-10'), isNull);
    });

    test('حساب موقوف لا يكتب شيئاً', () async {
      final s = AppStore.forTesting();
      injectDemoData(s);
      final admin = s.users.firstWhere((u) => u.role == 'admin');
      admin.isActive = false;
      await s.setDeviceIdentity(admin, '');

      expect(() => s.deleteStudent(s.students.first.id), throwsA(isA<StoreException>()));
      expect(() => s.setAttendance(s.students.first.id, '2026-09-10', 'present'), throwsA(isA<StoreException>()));
    });

    test('الصفوف تُحفظ من شاشة الصفوف أو من تبويب القاعات', () async {
      // العملية نفسها تخدم الصفوف (تعديل الجداول) والقاعات (الإعدادات)
      final s = await clerkDevice(caps: ['settings.view']);
      final room = s.rooms.first;
      expect(() => s.upsertRoom(room), returnsNormally);

      final none = await clerkDevice(caps: ['students.view']);
      expect(() => none.upsertRoom(none.rooms.first), throwsA(isA<StoreException>()));
    });
  });

  group('ملف الطالب يخفي ما لا يملكه المستخدم', () {
    Future<void> pumpDetail(WidgetTester tester, AppStore s, Student student) async {
      tester.view.physicalSize = const Size(420, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(StoreScope(
        store: s,
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: StudentDetailScreen(studentId: student.id),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('بلا المالية ولا التعديل: لا رصيد ولا دفعات ولا تعديل ولا حذف', (tester) async {
      final s = await clerkDevice(caps: ['students.view']);
      final debtor = s.students.firstWhere((x) => x.isDebtor);
      await pumpDetail(tester, s, debtor);

      expect(find.text('تسديد دفعة'), findsNothing);
      expect(find.textContaining('سجل الدفعات'), findsNothing);
      expect(find.text('الرصيد المالي الحالي:'), findsNothing);
      expect(find.text('تعديل'), findsNothing);
      expect(find.text('حذف الطالب'), findsNothing);
      expect(tester.takeException(), isNull);
      await s.flush();
    });

    testWidgets('بقالب السكرتير: يرى المالية ويقبض ويعدّل، ولا يحذف', (tester) async {
      final s = await clerkDevice();
      final debtor = s.students.firstWhere((x) => x.isDebtor);
      await pumpDetail(tester, s, debtor);

      expect(find.text('تسديد دفعة'), findsOneWidget);
      expect(find.textContaining('سجل الدفعات'), findsOneWidget);
      expect(find.text('تعديل'), findsOneWidget);
      expect(find.text('حذف الطالب'), findsNothing, reason: 'الحذف ليس في قالب السكرتير');
      await s.flush();
    });

    testWidgets('من لا يملك عرض الطلاب لا يفتح الملف ولو وصل إليه من شاشة أخرى', (tester) async {
      final s = await clerkDevice(caps: ['finance.view']);
      await pumpDetail(tester, s, s.students.first);

      expect(find.text('تعديل'), findsNothing);
      expect(find.textContaining('سجل الدفعات'), findsNothing);
      expect(find.text(s.students.first.fullName), findsNothing);
      await s.flush();
    });
  });
}
