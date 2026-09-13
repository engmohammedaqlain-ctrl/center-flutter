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
    // البطاقات مطوية كما في النسخة المكتبية: تُفتح بالضغط على عنوانها
    final paymentsHeader = find.textContaining('سجل الدفعات');
    await tester.scrollUntilVisible(paymentsHeader, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(paymentsHeader);
    await tester.pumpAndSettle();

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

  testWidgets('المدرسة ترى «المواد والمعلمون» بلا ذكر رسوم', (tester) async {
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
    final header = find.textContaining('المواد والمعلمون');
    await tester.scrollUntilVisible(header, 200);
    expect(header, findsOneWidget);
    expect(find.textContaining('الصفوف والمجموعات'), findsNothing, reason: 'تسمية المركز لا تظهر في المدرسة');

    // القسم مطويّ كبقية أقسام الملف
    expect(find.textContaining(s.subjects.first.name), findsNothing);
    // العنوان يقف خلف شريط الإجراءات السفلي: نُصعده قليلاً ليُضغط
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();

    // المادة عنوان السطر ومعلمها تحتها، ولا رسوم على مجموعة مادة الشعبة
    await tester.scrollUntilVisible(find.textContaining(s.subjects.first.name).first, 200);
    expect(find.textContaining(s.subjects.first.name), findsWidgets);
    expect(find.text('بلا رسوم'), findsNothing);
    // الإسناد من صفحة الصفوف: لا تسجيل ولا إلغاء من ملف الطالب في المدرسة
    expect(find.text('تسجيل'), findsNothing);
    expect(find.byIcon(Icons.link_off), findsNothing);

    await s.flush();
  });

  testWidgets('أقسام الملف مطوية إلا الأقساط، وتُفتح بالضغط', (tester) async {
    final s = await _store();
    final student = s.students.firstWhere((x) => s.installmentsOf(x.id).isNotEmpty);

    await _pump(tester, s, student.id);

    // بيانات الدخول مطوية: كلمة المرور لا تظهر قبل فتح القسم
    expect(find.text('بيانات الدخول'), findsOneWidget);
    expect(find.text('كلمة مرور الطالب'), findsNothing);

    await tester.tap(find.text('بيانات الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('كلمة مرور الطالب'), findsOneWidget);
    expect(find.text('كلمة مرور ولي الأمر'), findsOneWidget);

    await s.flush();
  });

  testWidgets('الحضور يعرض آخر خمسة أيام مرصودة، الأحدث أولاً', (tester) async {
    final s = await _store();
    final student = s.students.first;
    // سبعة أيام مرصودة: الخمسة الأحدث تُعرض والباقي لا
    s.attendance.removeWhere((a) => a.studentId == student.id);
    final today = DateTime.now();
    for (var i = 0; i < 7; i++) {
      s.attendance.add(AttendanceMark(
        studentId: student.id,
        date: isoDate(today.subtract(Duration(days: i))),
        status: i.isEven ? 'present' : 'absent',
      ));
    }
    final dates = s.attendance.where((a) => a.studentId == student.id).map((a) => a.date).toList()
      ..sort((a, b) => b.compareTo(a));

    await _pump(tester, s, student.id);
    final header = find.textContaining('سجل الحضور والالتزام');
    await tester.scrollUntilVisible(header, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(header);
    await tester.pumpAndSettle();

    for (final date in dates.take(5)) {
      expect(find.text(date), findsOneWidget, reason: date);
    }
    expect(find.text(dates[5]), findsNothing, reason: 'السادس أقدم من أن يُعرض');

    await s.flush();
  });

  testWidgets('خصم الرسوم يظهر في ملف الطالب بنسبته وسببه وصافيه', (tester) async {
    final s = await _store();
    final student = s.students.first
      ..academicDiscountApplied = true
      ..academicDiscountRate = 10
      ..exceptionReason = 'خصم إخوة'
      ..customMonthlyFee = 162;

    await _pump(tester, s, student.id);

    expect(find.textContaining('خصم الرسوم'), findsOneWidget);
    expect(find.textContaining('10%'), findsOneWidget);
    expect(find.textContaining('خصم إخوة'), findsOneWidget);
    expect(find.textContaining('الصافي الشهري'), findsOneWidget);

    await s.flush();
  });

  testWidgets('من لا خصم له لا تظهر له الشارة', (tester) async {
    final s = await _store();
    final student = s.students.first
      ..academicDiscountApplied = false
      ..academicDiscountRate = 0
      ..customMonthlyFee = null;

    await _pump(tester, s, student.id);
    expect(find.textContaining('خصم الرسوم'), findsNothing);

    await s.flush();
  });
}
