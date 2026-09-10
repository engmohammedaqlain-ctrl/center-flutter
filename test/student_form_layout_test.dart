import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';
import 'package:center_mobile/screens/student_form_screen.dart';
import 'package:center_mobile/theme/app_colors.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('شريط العنوان يتبع ألوان الهوية بعد وصولها لا الافتراضية', (tester) async {
    // السمة كانت تُبنى مرة عند الإقلاع قبل وصول الألوان، فبقي كل شريط عنوان كحلياً
    AppColors.reset();
    addTearDown(AppColors.reset);
    final s = AppStore.forTesting();

    await tester.pumpWidget(StoreScope(store: s, child: const CenterApp()));
    await tester.pump();
    Color? appBar() => Theme.of(tester.element(find.byType(Navigator))).appBarTheme.backgroundColor;
    expect(appBar(), const Color(0xFF0B2545));

    AppColors.apply(const InstitutionColors(sidebarBg: '#1C3124', primaryButton: '#1C3124', actionButton: '#15803D'));
    s.notifyListeners();
    // MaterialApp ينتقل إلى السمة الجديدة بحركة قصيرة لا في الإطار نفسه
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(appBar(), const Color(0xFF1C3124), reason: 'لون القائمة الجانبية للهوية');
  });

  testWidgets('نموذج الطالب: بلا بطاقات، المقدمة يسار الرقم، والحفظ ثابت أسفل الشاشة', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await tester.pumpWidget(StoreScope(
      store: s,
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: StudentFormScreen()),
      ),
    ));
    await tester.pump();

    expect(find.byType(AppCard), findsNothing, reason: 'الحقول على الصفحة مباشرة');

    // الرقم يُقرأ من اليسار: المقدمة قبل بقية الرقم
    final prefix = tester.getCenter(find.text('059').first);
    final number = tester.getCenter(find.widgetWithText(TextField, '7 أرقام').first);
    expect(prefix.dx, lessThan(number.dx));

    // العدّاد داخل حقل الهوية لا سطر مستقل
    expect(find.descendant(of: find.byType(TextField), matching: find.text('0/9')), findsOneWidget);

    final save = tester.getCenter(find.text('تسجيل الطالب'));
    expect(save.dy, greaterThan(800 * 0.85), reason: 'زر الحفظ مثبّت أسفل الشاشة');
    expect(tester.takeException(), isNull);

    await s.flush();
  });
}
