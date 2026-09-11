import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/attendance_screen.dart';
import 'package:center_mobile/screens/classes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _store() async {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, Widget home, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: home)),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('زر التقويم يفتح حضور فترة بحصيلة كل طالب', (tester) async {
    final s = await _store();
    await _pump(tester, s, const Scaffold(body: AttendanceScreen()));

    final calendar = find.byIcon(Icons.calendar_month_outlined);
    expect(calendar, findsOneWidget, reason: 'التقويم بجوار اختيار الصف');

    await tester.tap(calendar);
    await tester.pumpAndSettle();

    expect(find.text('الحضور في فترة'), findsOneWidget);
    expect(find.text('من'), findsOneWidget);
    expect(find.text('إلى'), findsOneWidget);
    expect(find.text('آخر ٣٠ يوماً'), findsOneWidget);
    expect(find.text('نسبة الحضور'), findsOneWidget);
    expect(find.text('عرض يوم محدد للرصد'), findsOneWidget);

    await s.flush();
  });

  testWidgets('الفترة تحسب الحاضر والغائب في المدى المختار', (tester) async {
    final s = await _store();
    final room = s.rooms.first;
    final roster = s.studentsOf(room);
    final student = roster.first;
    // لوحة نظيفة: رصد العرض التجريبي يختلف بحسب يوم التشغيل
    s.attendance.removeWhere((a) => roster.any((x) => x.id == a.studentId));

    // الجمعة عطلة لا تدخل الفترة، فيُختار يوم دراسي مهما كان اليوم الحالي
    var when = DateTime.now().subtract(const Duration(days: 3));
    if (when.weekday == DateTime.friday) when = when.subtract(const Duration(days: 1));
    s.setAttendance(student.id, isoDate(when), 'absent', ownerId: room.id);

    await _pump(tester, s, const Scaffold(body: AttendanceScreen()));
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    // الأكثر غياباً في رأس قائمة الفترة
    expect(find.text(student.fullName), findsWidgets);
    expect(find.textContaining('غائب 1'), findsWidgets);

    await s.flush();
  });

  testWidgets('صفحة الصف: رصد الحضور ومعلمو المواد', (tester) async {
    final s = await _store();
    final room = s.rooms.first;
    await _pump(tester, s, const Scaffold(body: ClassesScreen()));

    await tester.tap(find.text(room.name).first);
    await tester.pumpAndSettle();

    expect(find.text('رصد الحضور'), findsOneWidget);
    expect(find.text('معلمو المواد'), findsOneWidget);
    expect(find.text('المعلمون'), findsOneWidget, reason: 'عدد معلمي الصف في أرقام الصفحة');

    await tester.tap(find.text('رصد الحضور'));
    await tester.pumpAndSettle();
    expect(find.byType(AttendanceScreen), findsOneWidget);

    await s.flush();
  });

  testWidgets('بطاقة الصف تُظهر عدد معلميه', (tester) async {
    final s = await _store();
    final room = s.rooms.firstWhere((r) => r.teacherId.isNotEmpty);
    s.saveSectionSubjectAssignments(
      roomId: room.id,
      gradeLevel: room.gradeLevel,
      roomName: room.name,
      assignments: {
        s.subjects[0].id: room.teacherId,
        s.subjects[1].id: s.teachers.firstWhere((t) => t.id != room.teacherId).id,
      },
    );

    await _pump(tester, s, const Scaffold(body: ClassesScreen()));
    expect(find.textContaining('معلمان'), findsWidgets);

    await s.flush();
  });
}
