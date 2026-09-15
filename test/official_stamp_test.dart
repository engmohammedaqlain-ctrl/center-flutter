import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/screens/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// صورة PNG حقيقية بحجم بكسل واحد — الوهمية لا تُفكّ فتفشل عند العرض.
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  test('الختم يُحفظ في إعدادات المنشأة كي يصل بقية الأجهزة', () async {
    final s = AppStore.forTesting();
    injectDemoData(s);

    await s.saveInstitutionStamp(_png);
    expect(s.institutionStamp, _png);
    expect(s.db.settings[institutionStampKey], _png);

    await s.saveInstitutionStamp('');
    expect(s.institutionStamp, isEmpty);
    await s.flush();
  });

  testWidgets('السند يطبع الختم مكان سطر التوقيع', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppStore.forTesting();
    injectDemoData(s);
    await s.saveInstitutionStamp(_png);
    await s.flush();
    final payment = s.payments.first;

    await tester.pumpWidget(StoreScope(
      store: s,
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ReceiptScreen.open(context, payment),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    expect(find.textContaining('التوقيع'), findsNothing, reason: 'الختم يحلّ محله');
    expect(tester.takeException(), isNull, reason: 'لا طفح في سطر السند');
    await s.flush();
  });
}
