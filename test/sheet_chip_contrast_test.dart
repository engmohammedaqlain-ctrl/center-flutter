import 'package:center_mobile/theme/app_colors.dart';
import 'package:center_mobile/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// شريحة الورقة السفلية تُقرأ وهي مختارة.
///
/// `ChoiceChip` الخام كان يملأ نفسه بأخضر ماتيريال ويترك الكتابة داكنة فوقه،
/// فتختفي — وهو ما ظهر في «المرحلة» داخل ورقة نطاق الحضور.
void main() {
  Future<void> pump(WidgetTester tester, {required bool selected}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SheetChoiceChip(label: 'حادي عشر علمي', selected: selected, onTap: () {}),
          ),
        ),
      );

  testWidgets('المختارة: كتابة بيضاء على لون الثيم', (tester) async {
    await pump(tester, selected: true);

    final text = tester.widget<Text>(find.text('حادي عشر علمي'));
    expect(text.style?.color, Colors.white);

    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((box.decoration! as BoxDecoration).color, AppColors.heading);
  });

  testWidgets('غير المختارة: كتابة داكنة على خلفية فاتحة', (tester) async {
    await pump(tester, selected: false);

    final text = tester.widget<Text>(find.text('حادي عشر علمي'));
    expect(text.style?.color, AppColors.text);

    final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    expect((box.decoration! as BoxDecoration).color, AppColors.hover);
  });
}
