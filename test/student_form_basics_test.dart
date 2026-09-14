import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:center_mobile/widgets/form_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// عنوان حقل — `FieldLabel` نصٌّ منسّق تُلحق به نجمة المطلوب، فلا يطابقه
/// `find.text` الذي يقارن نصاً بسيطاً.
Finder _label(String text) => find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final plain = w.data ?? w.textSpan?.toPlainText() ?? '';
      return plain == text || plain == '$text *';
    }, description: 'عنوان الحقل «$text»');

/// النموذج المبسّط: الأساسي وحده ظاهر، والباقي تحت «بيانات إضافية».
Future<AppStore> _pumpForm(WidgetTester tester, {double width = 360, void Function(AppStore store)? setup}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final s = AppStore.forTesting();
  injectDemoData(s);
  setup?.call(s);
  // إدخال بيانات العرض يجدول كتابةً على القرص: تُنجز قبل الاختبار كي لا يبقى مؤقت
  await s.flush();
  await tester.pumpWidget(StoreScope(
    store: s,
    child: const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: StudentFormScreen()),
    ),
  ));
  await tester.pump();
  return s;
}

/// تمرير حتى يظهر [target] — القائمة تُعيد بناء ما تحت الطيّة عند كل تمريرة.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 14 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -260));
    await tester.pump();
  }
}

void main() {
  testWidgets('الأساسي وحده ظاهر عند الفتح', (tester) async {
    await _pumpForm(tester);

    for (final label in ['اسم الطالب الرباعي', 'رقم الهوية', 'المرحلة', 'الشعبة', 'تاريخ التسجيل']) {
      expect(_label(label), findsOneWidget, reason: label);
    }
    // ما لا يُسأل عنه عند التسجيل نزل تحت «بيانات إضافية»
    for (final hidden in ['كلمة مرور الطالب', 'اسم ولي الأمر', 'الحي الأساسي', 'مكان الولادة']) {
      expect(_label(hidden), findsNothing, reason: hidden);
    }
    await _scrollTo(tester, find.text('بيانات إضافية'));
    expect(find.text('بيانات إضافية'), findsOneWidget);
  });

  testWidgets('الأساسي يُملأ دون تمرير طويل على هاتف بعرض ٣٦٠', (tester) async {
    await _pumpForm(tester);

    // «ملاحظات» آخر الحقول الأساسية: يصلها المستخدم بتمريرة واحدة
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -420));
    await tester.pump();
    expect(_label('ملاحظات'), findsOneWidget);
  });

  testWidgets('حقلا الصف الواحد بعرض واحد', (tester) async {
    await _pumpForm(tester);

    // صفوف الأساسي: الهوية والمرحلة، الشعبة والتاريخ، المصدر والحالة
    final pairs = find.byType(FieldPair);
    expect(pairs, findsWidgets);
    for (final pair in tester.widgetList<FieldPair>(pairs)) {
      expect(pair.startFlex, pair.endFlex, reason: 'عمودان متساويان في كل صف');
    }
  });

  testWidgets('بيانات إضافية تُفتح بلمسة وتحمل ما نُقل إليها', (tester) async {
    await _pumpForm(tester);

    await _scrollTo(tester, find.text('بيانات إضافية'));
    await tester.tap(find.text('عرض'));
    await tester.pump();

    for (final label in ['كلمة مرور الطالب', 'اسم ولي الأمر', 'الحي الأساسي']) {
      await _scrollTo(tester, _label(label));
      expect(_label(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('لا قيم مفترضة: الاختيار يبدأ فارغاً', (tester) async {
    await _pumpForm(tester);

    // «من أين عرفتنا» كانت تبدأ على أول خيار فتُحفظ عمّن لم يُسأل
    expect(find.text('اختر'), findsWidgets);
    expect(find.text('اختر المرحلة'), findsOneWidget);

    await _scrollTo(tester, find.text('بيانات إضافية'));
    await tester.tap(find.text('عرض'));
    await tester.pump();

    // مكان الولادة والجنسية بلا قيمة مكتوبة سلفاً
    await _scrollTo(tester, _label('مكان الولادة'));
    final birthPlace = tester.widget<TextField>(
      find.ancestor(of: find.text('غزة'), matching: find.byType(TextField)).first,
    );
    expect(birthPlace.controller?.text, isEmpty, reason: '«غزة» تلميح لا قيمة');
  });

  testWidgets('الخروج ببيانات لم تُحفظ يسأل أولاً', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(find.byType(TextField).first, 'محمد أحمد النجار');
    await tester.pump();

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('تجاهل ما أُدخل؟'), findsOneWidget);

    // «تجاهل» وحده يُغلق النموذج، والنموذج نفسه يبقى بما كُتب فيه حتى تُقال
    await tester.tap(find.text('تجاهل'));
    await tester.pumpAndSettle();
    expect(find.text('تجاهل ما أُدخل؟'), findsNothing, reason: 'السؤال أُجيب');
  });

  testWidgets('الخروج بلا تعديل لا يسأل', (tester) async {
    await _pumpForm(tester);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('تجاهل ما أُدخل؟'), findsNothing);
  });
  group('الشعبة تُختار من شعب المرحلة', () {
    testWidgets('بلا مرحلة: القائمة تطلب المرحلة أولاً', (tester) async {
      await _pumpForm(tester);
      expect(find.text('اختر المرحلة أولاً'), findsOneWidget);
    });

    testWidgets('اختيار المرحلة يعرض شعبها وحدها', (tester) async {
      final s = await _pumpForm(tester);
      final room = s.rooms.first;
      final other = s.rooms.firstWhere((r) => r.gradeLevel != room.gradeLevel);

      await tester.tap(find.text('اختر المرحلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(room.gradeLevel).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('اختر الشعبة'));
      await tester.pumpAndSettle();
      expect(find.text(room.name), findsWidgets);
      expect(find.text(other.name), findsNothing, reason: 'شعبة مرحلة أخرى');

      await tester.tap(find.text(room.name).last);
      await tester.pumpAndSettle();
      expect(find.text(room.name), findsOneWidget);
    });

    testWidgets('مرحلة بلا شعب تقول ذلك', (tester) async {
      final s = await _pumpForm(tester, setup: (store) => store.rooms.clear());
      final grade = s.gradeOptions.first;

      await tester.tap(find.text('اختر المرحلة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(grade).last);
      await tester.pumpAndSettle();

      expect(find.text('لا شعب لهذه المرحلة'), findsOneWidget);
    });
  });
}
