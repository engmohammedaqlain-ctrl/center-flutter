import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// طالب نشط بلا أقساط ولا سندات — لوحة نظيفة لتوليد المستحقات.
Student _cleanStudent(AppStore s, {String grade = 'عاشر', double? customFee}) {
  final student = Student(
    id: s.newId(),
    fullName: 'طالب المستحقات',
    gradeLevel: grade,
    section: 'أ',
    phone: '0599000222',
    parentName: 'ولي الأمر',
    parentPhone: '0598000222',
    balance: 0,
    nationalId: '123123123',
    customMonthlyFee: customFee,
  );
  s.students.add(student);
  return student;
}

Future<void> _pumpSettings(WidgetTester tester, AppStore s) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SettingsScreen())),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('أشهر الدراسة', () {
    test('بلا أشهر محددة لا تُستحق رسوم، والحفظ يُنقّي المدخلات', () async {
      final s = _seeded();
      expect(s.studyMonths, isNull, reason: 'الافتراضي: الرسوم الشهرية متوقفة');

      await s.saveStudyMonths([9, 9, 13, 0, 1]);
      expect(s.studyMonths, [1, 9], reason: 'بلا تكرار ولا شهر خارج 1-12، ومرتّبة');

      await s.saveStudyMonths([]);
      expect(s.studyMonths, isNull);
    });

    test('الأشهر تُكتب في كائن المنشأة كي تصل بقية الأجهزة', () async {
      final s = _seeded();
      s.currentTenant = s.tenants.first;
      await s.saveStudyMonths([9, 10]);

      final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
      final colors = row['colors'] as Map<String, dynamic>;
      expect(colors[AppStore.studyMonthsColorKey], [9, 10]);
    });
  });

  group('توليد المستحق الشهري', () {
    test('يُنشأ مرة واحدة للشهر الجاري برسم مرحلة الطالب', () async {
      final s = _seeded();
      final student = _cleanStudent(s);
      final fee = s.feeFor('عاشر')!.monthlyFee;
      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);

      final first = s.generateMonthlyDues(now: now);
      expect(first.created, greaterThan(0));

      final due = s.installments.firstWhere((i) => i.studentId == student.id);
      expect(due.amount, fee);
      expect(due.dueDate.day, 1);
      expect(due.id.startsWith(AppStore.dueIdPrefix), isTrue, reason: 'معرّف حتمي لا يتكرر بين الأجهزة');

      // تشغيل ثانٍ لا يكرّر شيئاً
      expect(s.generateMonthlyDues(now: now).created, 0);
    });

    test('لا يُولَّد شيء خارج أشهر الدراسة ولا حين تكون متوقفة', () async {
      final s = _seeded();
      _cleanStudent(s);
      final now = DateTime.now();

      expect(s.generateMonthlyDues(now: now).created, 0, reason: 'بلا أشهر محددة');

      await s.saveStudyMonths([now.month == 12 ? 1 : now.month + 1]);
      expect(s.generateMonthlyDues(now: now).created, 0, reason: 'الشهر الجاري ليس شهر دراسة');
    });

    test('الرسم المخصص يسبق رسم المرحلة، والمعفى لا مستحق له', () async {
      final s = _seeded();
      final discounted = _cleanStudent(s, customFee: 120);
      final exempt = _cleanStudent(s, customFee: 0);
      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);

      s.generateMonthlyDues(now: now);
      expect(s.installments.firstWhere((i) => i.studentId == discounted.id).amount, 120);
      expect(s.installments.where((i) => i.studentId == exempt.id), isEmpty, reason: 'الصفر إعفاء');
    });

    test('من لا رسم لمرحلته يُحصى ولا يُولَّد له', () async {
      final s = _seeded();
      final orphan = _cleanStudent(s, grade: 'مرحلة بلا رسم');
      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);

      expect(s.studentsMissingFee, greaterThan(0));
      final result = s.generateMonthlyDues(now: now);
      expect(result.missingFee, greaterThan(0));
      expect(s.installments.where((i) => i.studentId == orphan.id), isEmpty);
    });

    test('رسم الحجز يُخصم من أول مستحق مرة واحدة', () async {
      final s = _seeded();
      final student = _cleanStudent(s);
      final fee = s.feeFor('عاشر')!.monthlyFee;
      s.installments.add(Installment(
        id: s.newId(),
        studentId: student.id,
        title: AppStore.seatInstallmentTitle,
        amount: 50,
        dueDate: DateTime.now().subtract(const Duration(days: 30)),
      ));

      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);
      s.generateMonthlyDues(now: now);

      final due = s.installments.firstWhere((i) => i.id.startsWith(AppStore.dueIdPrefix));
      expect(due.amount, fee - 50, reason: 'يُدفع مرة واحدة ويُخصم من أول مستحق');
    });

    test('صاحب خطة أقساط يدوية لا يُطالَب مرتين', () async {
      final s = _seeded();
      final student = _cleanStudent(s);
      s.installments.add(Installment(
        id: s.newId(),
        studentId: student.id,
        title: 'قسط يدوي',
        amount: 300,
        dueDate: DateTime.now(),
      ));

      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);
      s.generateMonthlyDues(now: now);
      expect(s.installments.where((i) => i.studentId == student.id && i.id.startsWith(AppStore.dueIdPrefix)), isEmpty);
    });
  });

  group('ترقية الطلاب', () {
    test('الصف ينتقل لتاليه، ومن لا صف بعده يُؤرشف، والشعبة تُمسح', () {
      final s = _seeded();
      final tenth = _cleanStudent(s);
      final last = _cleanStudent(s, grade: 'ثاني عشر علمي');

      final res = s.promoteStudents({'عاشر': 'حادي عشر علمي', 'ثاني عشر علمي': null});

      expect(res.promoted, greaterThan(0));
      expect(res.archived, greaterThan(0));
      expect(tenth.gradeLevel, 'حادي عشر علمي');
      expect(tenth.status, 'pending', reason: 'بانتظار التأكيد فلا تُستحق عليه رسوم');
      expect(tenth.section, '');
      expect(last.status, 'archived');
      expect(s.pendingSyncs.any((p) => p.tableName == 'students' && p.recordId == tenth.id), isTrue);
    });

    test('الطالب المؤرشف لا تُولَّد له مستحقات بعد الترقية', () async {
      final s = _seeded();
      final student = _cleanStudent(s);
      s.promoteStudents({'عاشر': null});

      final now = DateTime.now();
      await s.saveStudyMonths([now.month]);
      s.generateMonthlyDues(now: now);
      expect(s.installments.where((i) => i.studentId == student.id), isEmpty);
    });
  });

  group('شاشة المراحل والرسوم', () {
    testWidgets('تعرض رسم الحجز وأشهر الدراسة وزر الترقية', (tester) async {
      final s = _seeded();
      await s.login('amal', 'amal2026');
      await _pumpSettings(tester, s);
      // الشاشة تفتح على «المعلمون»: ننتقل إلى تبويب المراحل والرسوم
      await tester.tap(find.text('المراحل والرسوم'));
      await tester.pumpAndSettle();

      // أقسام التبويب مطوية: تُفتح بعناوينها
      await tester.tap(find.text('الحجز وأشهر الدراسة'));
      await tester.pumpAndSettle();
      expect(find.text('رسم حجز المقعد'), findsOneWidget);
      expect(find.text('يُدفع مرة واحدة ويُخصم من أول مستحق'), findsOneWidget);
      expect(find.text('أشهر الدراسة'), findsOneWidget);
      expect(find.text('الرسوم الشهرية متوقفة'), findsOneWidget);
      expect(find.text('سبتمبر'), findsOneWidget);
      await tester.tap(find.text('الترقية'));
      await tester.pumpAndSettle();
      expect(find.text('ترقية الطلاب'), findsOneWidget);

      await s.flush();
    });

    testWidgets('اختيار شهر وحفظه يعتمد أشهر الدراسة', (tester) async {
      final s = _seeded();
      await s.login('amal', 'amal2026');
      await _pumpSettings(tester, s);
      // الشاشة تفتح على «المعلمون»: ننتقل إلى تبويب المراحل والرسوم
      await tester.tap(find.text('المراحل والرسوم'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('الحجز وأشهر الدراسة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(gregorianMonths[DateTime.now().month - 1]));
      await tester.pump();
      await tester.tap(find.text('حفظ أشهر الدراسة'));
      await tester.pumpAndSettle();

      expect(s.studyMonths, [DateTime.now().month]);
      expect(find.text('الرسوم الشهرية متوقفة'), findsNothing);

      await s.flush();
    });
  });
}
