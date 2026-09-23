import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

/// فتح تبويب المالية على مدرسة كبيرة: كم يقعد المستخدم أمام المؤشر؟
void main() {
  test('BENCH فتح المالية', () async {
    final disk = FakeDisk();
    const n = 60000;
    await disk.saveTable('payments', [
      for (var i = 0; i < n; i++)
        {'id': 'p$i', 'student_id': 's${i % 2000}', 'amount': 100, 'payment_date': '2026-01-01', 'method': 'cash'},
    ]);
    await disk.saveTable('installments', [
      for (var i = 0; i < n; i++)
        {'id': 'i$i', 'student_id': 's${i % 2000}', 'amount': 100, 'due_date': '2026-01-01', 'status': 'pending'},
    ]);

    final store = AppStore.forTesting();
    await store.bootstrap(disk);

    final sw = Stopwatch()..start();
    await store.ensureTables(const ['payments', 'installments']);
    sw.stop();
    // ignore: avoid_print
    print('BENCH ensureTables(payments+installments) ${2 * n} صفاً: ${sw.elapsedMilliseconds}ms');
    expect(store.tablesReady(const ['payments', 'installments']), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
