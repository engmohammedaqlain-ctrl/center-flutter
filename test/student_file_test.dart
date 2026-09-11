import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/student_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _store() async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, String studentId) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: StudentDetailScreen(studentId: studentId)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('سجل الدفعات يُرتَّب من الأحدث إلى الأقدم', () async {
    final s = await _store();
    final student = s.students.firstWhere((x) => s.paymentsOf(x.id).length > 1);
    final dates = s.paymentsOf(student.id).map((p) => p.date).toList();
    for (var i = 1; i < dates.length; i++) {
      expect(dates[i].isAfter(dates[i - 1]), isFalse, reason: 'الأحدث أولاً');
    }
  });

  testWidgets('مبلغ السند يلتصق بطرف البلاطة بلا فجوة قبله', (tester) async {
    final s = await _store();
    final student = s.students.first;
    // مبلغ لا يتكرّر في سنداته: الباحث بالنص يجب أن يقع على بلاطة واحدة
    final payment = s.addPayment(studentId: student.id, amount: 1234.5, method: 'cash', date: DateTime.now());

    await _pump(tester, s, student.id);
    // بلا `.first` قبل التمرير: الباحث الفارغ يرمي داخل `scrollUntilVisible`.
    // والقائمة تُسمّى صراحةً لأن في الصفحة أكثر من عنصر قابل للتمرير.
    final amount = find.text(money(payment.amount));
    await tester.scrollUntilVisible(amount, 200, scrollable: find.byType(Scrollable).first);

    // أيقونة السند في طرف السطر الآخر: الحشوة نفسها على الجانبين، فالمسافة
    // المتوقّعة أمام المبلغ هي المسافة خلف الأيقونة نفسها.
    final rect = tester.getRect(amount);
    final iconRight = tester.getRect(find.byIcon(Icons.receipt_long_outlined).first).right;
    final padding = 360 - iconRight;
    expect(
      rect.left - padding,
      lessThan(6),
      reason: 'المرن بجوار Spacer كان يترك ثلث الفراغ قبل المبلغ',
    );

    await s.flush();
  });

  testWidgets('المدرسة ترى «الصفوف والمجموعات» في ملف الطالب', (tester) async {
    final s = await _store();
    expect(s.isSchool, isTrue);

    final room = s.rooms.first;
    final student = s.studentsOf(room).first;
    s.saveSectionSubjectAssignments(
      roomId: room.id,
      gradeLevel: room.gradeLevel,
      roomName: room.name,
      assignments: {s.subjects.first.id: s.teachers.first.id},
    );

    await _pump(tester, s, student.id);
    await tester.scrollUntilVisible(find.textContaining('الصفوف والمجموعات'), 200);
    expect(find.textContaining('الصفوف والمجموعات'), findsOneWidget);

    // المادة ومعلمها تحت اسم المجموعة، لا أيام دوام في المدرسة
    expect(find.textContaining(s.subjects.first.name), findsWidgets);

    await s.flush();
  });
}
