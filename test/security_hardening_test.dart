import 'package:center_mobile/data/balance.dart';
import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// تشديد الحماية وسلامة المال — المقابل لـ `securityHardening.test.ts` في الويب.
void main() {
  test('علامة خارج حدودها ترفض الكشف كله', () {
    expect(() => checkScoreBounds([10, 21], 20), throwsA(isA<StoreException>()));
    expect(() => checkScoreBounds([-1], 20), throwsA(isA<StoreException>()));
    expect(() => checkScoreBounds([5], -3), throwsA(isA<StoreException>()));
    checkScoreBounds([0, 20], 20);
    checkScoreBounds([100], 0); // الفارغة تُعدّ 100
  });

  test('حذف طالب عليه رسوم يُسجَّل في سجل الحركات', () {
    final s = AppStore.forTesting();
    injectDemoData(s);
    final owing = s.students.firstWhere(
      (st) => s.countActivePayments(st.id) == 0 && s.installments.any((i) => i.studentId == st.id && unpaidOf(i) > 0),
    );
    s.deleteStudent(owing.id);
    expect(s.financeAudit.any((a) => a.action == 'student_deleted' && a.entityId == owing.id), isTrue);
    expect(financeAuditActionLabel('student_deleted'), 'حذف طالب عليه رسوم');
  });
}
