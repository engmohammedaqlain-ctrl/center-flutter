import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/attendance_screen.dart';
import 'package:center_mobile/screens/classes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppStore> _store() async {
  final s = AppStore.forTesting();
  injectDemoData(s);
    // البيانات في الذاكرة: بوابة التحميل الكسول ليس لها ما تنتظره
    s.loadedTables.addAll(AppStore.deferredTables);
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
  testWidgets('إعدادات الحضور تنزّل كشف الأسبوع، ولا زرّ لحضور فترة', (tester) async {
    final s = await _store();
    await _pump(tester, s, const Scaffold(body: AttendanceScreen()));

    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('تنزيل كشف الأسبوع'), findsOneWidget);

    await s.flush();
  });

  testWidgets('صفحة الصف: رصد الحضور ومعلمو المواد', (tester) async {
    final s = await _store();
    final room = s.rooms.first;
    await _pump(tester, s, const Scaffold(body: ClassesScreen()));

    await tester.tap(find.text(room.name).first);
    await tester.pumpAndSettle();

    expect(find.text('رصد الحضور'), findsOneWidget);
    expect(find.text('المواد والمعلمون'), findsOneWidget);
    expect(find.text('تعديل'), findsOneWidget, reason: 'تعديل المواد ظاهر بلا فتح البطاقة');

    // البطاقة تُفتح شبكةَ مواد بلا طفح
    await tester.tap(find.text('المواد والمعلمون'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

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
