import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/student_detail_screen.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

Future<void> _pump(WidgetTester tester, AppStore s, Widget screen) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: screen)),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('حالة الطالب', () {
    test('التسميات مطابقة للنسخة المكتبية، و«غير نشط» تُقرأ «منسحب»', () {
      expect(studentStatusLabel('active'), 'نشط');
      expect(studentStatusLabel('pending'), 'بانتظار التأكيد');
      expect(studentStatusLabel('withdrawn'), 'منسحب');
      expect(studentStatusLabel('archived'), 'مؤرشف');
      expect(studentStatusLabel('inactive'), 'منسحب', reason: 'الحالة القديمة أُدمجت');
    });

    test('الترحيل يحوّل «غير نشط» إلى «منسحب» ويرفعها، ولا يعمل مرتين', () async {
      final s = _seeded();
      final student = s.students.first..status = 'inactive';

      expect(await s.migrateWithdrawnStatus(), 1);
      expect(student.status, 'withdrawn');
      expect(student.syncStatus, 'pending');
      expect(
        s.pendingSyncs.any((p) => p.tableName == 'students' && p.recordId == student.id),
        isTrue,
        reason: 'التغيير يصل بقية الأجهزة',
      );

      s.students.first.status = 'inactive';
      expect(await s.migrateWithdrawnStatus(), 0, reason: 'العلامة محفوظة');
      expect(s.db.settings[withdrawnStatusMigrationKey], 'true');
    });

    testWidgets('ملف الطالب يعرض الحالة، والشارة للمنسحب وحده', (tester) async {
      final s = _seeded();
      final student = s.students.first..status = 'withdrawn';

      await _pump(tester, s, StudentDetailScreen(studentId: student.id));
      expect(find.byType(StudentStatusChip), findsOneWidget, reason: 'شارة في ترويسة الملف');
      expect(find.text('حالة الطالب'), findsOneWidget);
      expect(find.text('منسحب'), findsWidgets);

      // النشط لا شارة له: الحالة الطبيعية لا تستحق تنبيهاً
      student.status = 'active';
      s.notifyListeners();
      await tester.pump();
      expect(find.byType(StudentStatusChip), findsNothing);
      expect(find.text('نشط'), findsOneWidget, reason: 'تبقى ضمن بيانات الطالب');

      await s.flush();
    });

    testWidgets('التعديل يغيّر الحالة، و«بانتظار التأكيد» لا تُختار يدوياً', (tester) async {
      final s = _seeded();
      final student = s.students.first..status = 'active';

      await _pump(tester, s, StudentFormScreen(student: student));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('حالة الطالب'), 250, scrollable: list);

      await tester.tap(find.text('نشط'));
      await tester.pumpAndSettle();
      expect(find.text('بانتظار التأكيد'), findsNothing, reason: 'يضعها الترفيع السنوي وحده');
      await tester.tap(find.text('منسحب').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('حفظ التعديل'));
      await tester.pumpAndSettle();

      expect(s.studentById(student.id)!.status, 'withdrawn');
      await s.flush();
    });
  });
}
