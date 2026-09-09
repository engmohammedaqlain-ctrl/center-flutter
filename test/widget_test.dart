import 'package:flutter_test/flutter_test.dart';

import 'package:center_mobile/main.dart';
import 'package:center_mobile/data/store.dart';

void main() {
  testWidgets('login screen renders', (tester) async {
    await tester.pumpWidget(
      StoreScope(store: AppStore.instance, child: const CenterApp()),
    );
    expect(find.text('نظام الإدارة المدرسي'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}
