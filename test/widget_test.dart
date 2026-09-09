import 'package:flutter_test/flutter_test.dart';

import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/main.dart';

void main() {
  testWidgets('login screen renders when no session is stored', (tester) async {
    await tester.pumpWidget(
      StoreScope(store: AppStore.forTesting(), child: const CenterApp()),
    );
    expect(find.text('نظام الإدارة المدرسي'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}
