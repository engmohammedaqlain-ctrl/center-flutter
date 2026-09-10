import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/system_features.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

void main() {
  group('أعلام الميزات', () {
    test('كل الميزات مفعّلة قبل أن يمسّها أحد', () {
      const f = SystemFeatures.defaults;
      expect(f.enableExpenses, isTrue);
      expect(f.enableEvaluations, isTrue);
      expect(f.enableStudentPortal, isTrue);
    });

    test('المفتاح والحقول مطابقة لما يكتبه سطح المكتب', () {
      // النسخة المكتبية تقرأ `center_system_features` من localStorage بهذه
      // الأسماء حرفياً؛ اختلاف حرف يجعل ما يضبطه أحدهما غير مقروء عند الآخر
      expect(systemFeaturesKey, 'center_system_features');
      expect(
        const SystemFeatures().toMap().keys.toList(),
        ['enableExpenses', 'enableEvaluations', 'enableStudentPortal'],
      );
    });

    test('العلم يمرّ عبر النص بلا فقدان', () {
      const f = SystemFeatures(enableExpenses: false, enableEvaluations: true, enableStudentPortal: false);
      expect(SystemFeatures.decode(f.encode()), f);
    });

    test('الحقل الناقص يعود لقيمته الافتراضية لا لـ false', () {
      final f = SystemFeatures.decode('{"enableExpenses":false}');
      expect(f.enableExpenses, isFalse);
      expect(f.enableEvaluations, isTrue, reason: 'الحقل الغائب لا يُعطّل ميزة');
      expect(f.enableStudentPortal, isTrue);
    });

    test('الإعداد التالف لا يُعطّل شيئاً', () {
      expect(SystemFeatures.decode('}{ليس json'), SystemFeatures.defaults);
      expect(SystemFeatures.decode(''), SystemFeatures.defaults);
      expect(SystemFeatures.decode(null), SystemFeatures.defaults);
      expect(SystemFeatures.decode('[1,2,3]'), SystemFeatures.defaults);
    });

    test('الحفظ الجزئي لا يمسّ بقية الأعلام', () async {
      final s = AppStore.forTesting();
      await s.bootstrap(FakeDisk());

      await s.saveFeatures(enableExpenses: false);
      expect(s.features.enableExpenses, isFalse);
      expect(s.features.enableEvaluations, isTrue);

      await s.saveFeatures(enableEvaluations: false);
      expect(s.features.enableExpenses, isFalse, reason: 'حفظ علم لا يعيد غيره لافتراضيه');
      expect(s.features.enableEvaluations, isFalse);
      expect(s.features.enableStudentPortal, isTrue);
    });

    test('الأعلام تعيش عبر إعادة التشغيل', () async {
      final disk = FakeDisk();
      final first = AppStore.forTesting();
      await first.bootstrap(disk);
      await first.saveFeatures(enableEvaluations: false);
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.features.enableEvaluations, isFalse);
    });
  });
}
