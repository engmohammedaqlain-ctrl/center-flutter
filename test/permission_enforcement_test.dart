import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/student_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// متجر بجهاز مثبَّت باسم سكرتير يحمل [sections] — أو قالب دوره إن لم تُمرَّر.
Future<AppStore> clerkDevice({List<String>? sections}) async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
  if (sections != null) clerk.capabilities = sections;
  await s.setDeviceIdentity(clerk, '');
  s.pendingSyncs.clear();
  return s;
}

void main() {
  group('المتجر يرفض ما لا يتيحه تبويب المستخدم مهما كان المسار', () {
    test('السكرتير لا يسجّل مصروفاً ولا يترك أثراً', () async {
      final s = await clerkDevice();

      expect(
        () => s.addExpense(category: 'أخرى', description: 'قرطاسية', amount: 20, expenseDate: '2026-09-10'),
        throwsA(isA<StoreException>()),
      );
      expect(s.expenses, isEmpty);
      expect(s.pendingSyncs, isEmpty, reason: 'لا شيء يُرفع لعملية مرفوضة');
    });

    test('رسالة الرفض تذكر التبويب باسمه المعروض', () async {
      final s = await clerkDevice();
      try {
        s.addExpense(category: 'أخرى', description: 'قرطاسية', amount: 20, expenseDate: '2026-09-10');
        fail('كان يجب أن يُرفض');
      } on StoreException catch (e) {
        expect(e.message, contains('المصروفات وصرف الأجور'));
      }
    });

    test('ما يتيحه قالب السكرتير يمرّ كما هو', () async {
      final s = await clerkDevice();
      final student = s.students.first;

      s.setAttendance(student.id, '2026-09-10', 'present');
      expect(s.attendanceRecord(student.id, '2026-09-10')?.status, 'present');
    });

    test('قائمة بلا الحضور ترفض الرصد', () async {
      final s = await clerkDevice(sections: ['students']);
      final student = s.students.first;

      expect(() => s.setAttendance(student.id, '2026-09-10', 'present'), throwsA(isA<StoreException>()));
      expect(s.attendanceRecord(student.id, '2026-09-10'), isNull);
    });

    test('قائمة بلا الطلاب لا تحذف طالباً', () async {
      final s = await clerkDevice(sections: ['finance']);
      final student = s.students.first;

      expect(() => s.deleteStudent(student.id), throwsA(isA<StoreException>()));
      expect(s.studentById(student.id), isNotNull);
    });

    test('قائمة بلا الصفوف لا تعدّل المجموعات', () async {
      final s = await clerkDevice(sections: ['students']);
      expect(() => s.deleteGroup('any'), throwsA(isA<StoreException>()));
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

    test('الصفوف تُحفظ من تبويب الصفوف أو من الإعدادات', () async {
      final s = await clerkDevice(sections: ['settings']);
      expect(() => s.upsertRoom(s.rooms.first), returnsNormally);

      final none = await clerkDevice(sections: ['students']);
      expect(() => none.upsertRoom(none.rooms.first), throwsA(isA<StoreException>()));
    });
  });

  group('ملف الطالب يخفي ما لا يتيحه التبويب', () {
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

    testWidgets('بلا المالية: لا رصيد ولا دفعات، والتعديل متاح', (tester) async {
      final s = await clerkDevice(sections: ['students']);
      final debtor = s.students.firstWhere((x) => x.isDebtor);
      await pumpDetail(tester, s, debtor);

      expect(find.text('تسديد دفعة'), findsNothing);
      expect(find.textContaining('سجل الدفعات'), findsNothing);
      expect(find.text('الرصيد المالي الحالي:'), findsNothing);
      expect(find.text('تعديل البيانات'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await s.flush();
    });

    testWidgets('بقالب السكرتير: يرى المالية ويقبض ويعدّل', (tester) async {
      final s = await clerkDevice();
      final debtor = s.students.firstWhere((x) => x.isDebtor);
      await pumpDetail(tester, s, debtor);

      expect(find.text('تسديد دفعة'), findsOneWidget);
      expect(find.textContaining('سجل الدفعات'), findsOneWidget);
      expect(find.text('تعديل البيانات'), findsOneWidget);
      await s.flush();
    });

    testWidgets('من لا يرى الطلاب لا يفتح الملف ولو وصل إليه من شاشة أخرى', (tester) async {
      final s = await clerkDevice(sections: ['finance']);
      await pumpDetail(tester, s, s.students.first);

      expect(find.text('تعديل البيانات'), findsNothing);
      expect(find.textContaining('سجل الدفعات'), findsNothing);
      expect(find.text(s.students.first.fullName), findsNothing);
      await s.flush();
    });
  });
}
