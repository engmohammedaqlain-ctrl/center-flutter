import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مأذون تُرصد وتُلغى كبقية الحالات', () {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final student = s.students.first;
    const date = '2026-09-10';

    s.setAttendance(student.id, date, 'excused');
    expect(s.attendanceRecord(student.id, date)?.status, 'excused');

    s.setAttendance(student.id, date, null);
    expect(s.attendanceRecord(student.id, date), isNull);
  });

  testWidgets('صف الطالب يعرض الأزرار الثلاثة بلا طفح على شاشة 320', (tester) async {
    // Center يعرض حاضر وغائب ومأذون؛ ثلاثة أزرار على أضيق هاتف قد تطفح
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AttendanceScreen()),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('مأذون'), findsWidgets);
    expect(find.text('حاضر'), findsWidgets);
    expect(find.text('غائب'), findsWidgets);
    expect(find.byKey(const ValueKey('legend-excused')), findsOneWidget, reason: 'العدد يظهر ولو كان صفراً');
    expect(tester.takeException(), isNull);

    await s.flush();
  });

  testWidgets('مفتاح الرصد يحفظ الحالة ويحدّث الملخص — عرض 360', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    s.attendance.clear();

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AttendanceScreen()),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // الأول في الملخص، والثاني في مفتاح أول طالب
    await tester.tap(find.text('غائب').at(1));
    await tester.pump(const Duration(milliseconds: 500));

    expect(s.attendance.any((a) => a.status == 'absent'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('زر الصف يفتح ورقة الاختيار ويبدّل الشعبة', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    final grade = s.roomsInViewedYear.first.gradeLevel;
    final rooms = s.roomsInViewedYear.where((r) => r.gradeLevel == grade).toList();

    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: AttendanceScreen()),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    expect(find.text('المرحلة'), findsOneWidget);

    final target = rooms.last;
    await tester.tap(find.text(target.name).last);
    await tester.pumpAndSettle();

    expect(find.textContaining(target.name), findsOneWidget, reason: 'زر الصف يعرض الشعبة المختارة');
    expect(tester.takeException(), isNull);
  });
}
