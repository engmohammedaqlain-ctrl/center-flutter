import 'package:center_mobile/widgets/auth_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// إطار شاشات الدخول بعنوان فرعي وتذييل وحقل — نفس شكل شاشة تسجيل الدخول.
Widget _frame(TextEditingController controller) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AuthFrame(
          title: 'مدرسة الاختبار',
          subtitle: 'بوابة تسجيل الدخول الرسمية',
          footer: const Text('الإصدار 1.0.0'),
          children: [
            AuthCard(
              child: TextField(controller: controller, decoration: authFieldDecoration('اسم المستخدم', Icons.person)),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('فتح لوحة المفاتيح لا يُفقد الحقل تركيزه ولا كتابته', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_frame(controller));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'noon');
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.hasFocus, isTrue);

    // لوحة المفاتيح تفتح: الإطار يتقلّص وتختفي الحواشي
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    // كان حذف العنوان الفرعي والتذييل من القائمة يزيح الحقل فيُبنى من جديد،
    // فيفقد التركيز وتنغلق لوحة المفاتيح فور فتحها
    expect(FocusManager.instance.primaryFocus, same(focused), reason: 'التركيز باقٍ على الحقل نفسه');
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(controller.text, 'noon', reason: 'ما كُتب لا يضيع');
    expect(find.text('بوابة تسجيل الدخول الرسمية'), findsNothing, reason: 'الحاشية تنطوي مع لوحة المفاتيح');
    expect(find.text('الإصدار 1.0.0'), findsNothing);

    // وتُغلق: يعود العنوان الفرعي والتذييل
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(find.text('بوابة تسجيل الدخول الرسمية'), findsOneWidget);
    expect(find.text('الإصدار 1.0.0'), findsOneWidget);
    expect(controller.text, 'noon');
  });
}
