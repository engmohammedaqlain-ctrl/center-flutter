import 'dart:convert';

import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/payment_methods.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

Future<AppStore> _store() async {
  final s = AppStore.forTesting();
  await s.bootstrap(FakeDisk());
  return s;
}

void main() {
  group('وسائل الدفع', () {
    test('المعرّفات والأسماء مطابقة لما تكتبه النسخة المكتبية', () {
      expect(customPaymentMethodsKey, 'custom_payment_methods');
      expect(discountRulesKey, 'school_discount_rules');
      expect(customPaymentMethodsColorKey, '__custom_payment_methods');
      // «تحويل بنكي» و«أخرى» أُزيلتا: وسيلة بلا جهة معروفة لا تقول من أين ورد المبلغ
      expect(
        defaultPaymentMethods.map((m) => m.id).toList(),
        ['cash', 'bop', 'palpay', 'jawwal_pay'],
      );
      expect(defaultPaymentMethods.every((m) => m.isDefault && m.enabled), isTrue);
      // وأسماؤهما تبقى معروفة لسندات قديمة سُجّلت بهما
      expect(paymentMethodNames['bank_transfer'], 'تحويل بنكي');
      expect(paymentMethodNames['other'], 'أخرى');
    });

    test('بلا ضبط: الوسائل الأساسية', () async {
      final s = await _store();
      expect(s.paymentMethods.map((m) => m.id), defaultPaymentMethods.map((m) => m.id));
      expect(s.paymentMethodLabel('cash'), 'نقداً');
    });

    test('الضبط يُقرأ ويعيش عبر إعادة التشغيل', () async {
      final disk = FakeDisk();
      final first = AppStore.forTesting();
      await first.bootstrap(disk);
      await first.savePaymentMethods([
        ...defaultPaymentMethods.where((m) => m.id != 'palpay'),
        const PaymentMethodItem(id: 'custom_1', name: 'بنك القدس', type: 'bank'),
      ]);
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.paymentMethodLabel('custom_1'), 'بنك القدس');
      expect(second.paymentMethods.any((m) => m.id == 'palpay'), isFalse);
    });

    test('الوسيلة المعطَّلة تختفي من القبض ويبقى اسمها في السندات القديمة', () async {
      final s = await _store();
      await s.savePaymentMethods([
        for (final m in defaultPaymentMethods) m.id == 'bop' ? m.copyWith(enabled: false) : m,
      ]);

      expect(s.activePaymentMethods.any((m) => m.id == 'bop'), isFalse);
      expect(s.paymentMethods.any((m) => m.id == 'bop'), isTrue);
      expect(s.paymentMethodLabel('bop'), 'بنك فلسطين', reason: 'سند قديم يبقى مقروءاً');
    });

    test('وسيلة حُذفت لا تترك معرّفاً خاماً في الوصل', () async {
      final s = await _store();
      await s.savePaymentMethods(defaultPaymentMethods.where((m) => m.id != 'jawwal_pay').toList());
      expect(s.paymentMethodLabel('jawwal_pay'), 'محفظة جوال بي');
      expect(s.paymentMethodLabel(''), '-');
    });

    test('الضبط يُنسخ في ألوان المنشأة كي يصل بقية الأجهزة', () async {
      final s = await _store();
      await s.savePaymentMethods([const PaymentMethodItem(id: 'cash', name: 'كاش', type: 'cash', isDefault: true)]);

      final colors = jsonDecode(s.db.settings[institutionColorsKey]!) as Map<String, dynamic>;
      final mirrored = colors[customPaymentMethodsColorKey];
      expect(mirrored, isA<List>());
      expect(decodePaymentMethods(mirrored).single.name, 'كاش');
      // الألوان نفسها لا تُمسح بالكتابة فوق العمود
      expect(s.institutionColors.sidebarBg, isNotEmpty);
    });

    test('القائمة التالفة أو الفارغة لا تترك المنشأة بلا وسيلة قبض', () {
      expect(decodePaymentMethods('}{ليس json').length, defaultPaymentMethods.length);
      expect(decodePaymentMethods('[]').length, defaultPaymentMethods.length);
      expect(decodePaymentMethods(null).length, defaultPaymentMethods.length);
      expect(decodePaymentMethods('[{"id":"","name":""}]').length, defaultPaymentMethods.length);
    });

    test('الحقل الغائب يعني وسيلة مفعّلة', () {
      final parsed = decodePaymentMethods('[{"id":"x","name":"وسيلة"}]').single;
      expect(parsed.enabled, isTrue);
      expect(parsed.isDefault, isFalse);
      expect(parsed.type, 'other');
    });
  });

  group('قواعد الخصم', () {
    test('معطّلة افتراضياً بنسب مطابقة للنسخة المكتبية', () {
      const r = SchoolDiscountRules.defaults;
      expect(r.autoSuggestExcellence, isFalse);
      expect(r.excellenceMinGpa, 90);
      expect(r.excellenceDiscountRate, 10);
    });

    test('أسماء الحقول حرفية كما يقرأها سطح المكتب', () {
      expect(
        const SchoolDiscountRules().toMap().keys.toList(),
        [
          'autoSuggestExcellence',
          'excellenceMinGpa',
          'excellenceDiscountRate',
        ],
      );
    });

    test('الحفظ والقراءة عبر إعادة التشغيل', () async {
      final disk = FakeDisk();
      final first = AppStore.forTesting();
      await first.bootstrap(disk);
      await first.saveDiscountRules(
        SchoolDiscountRules.defaults.copyWith(autoSuggestExcellence: true, excellenceDiscountRate: 15),
      );
      await first.flush();

      final second = AppStore.forTesting();
      await second.bootstrap(disk);
      expect(second.discountRules.autoSuggestExcellence, isTrue);
      expect(second.discountRules.excellenceDiscountRate, 15);
      expect(second.discountRules.excellenceMinGpa, 90, reason: 'بقية القواعد على حالها');
    });

    test('الحقل الناقص يعود لافتراضيه لا إلى صفر', () {
      final r = SchoolDiscountRules.decode('{"autoSuggestExcellence":true}');
      expect(r.autoSuggestExcellence, isTrue);
      expect(r.excellenceMinGpa, 90);
      expect(r.excellenceDiscountRate, 10);
    });

    test('الإعداد التالف لا يُفعّل قاعدة', () {
      expect(SchoolDiscountRules.decode('}{'), SchoolDiscountRules.defaults);
      expect(SchoolDiscountRules.decode(null), SchoolDiscountRules.defaults);
      expect(SchoolDiscountRules.decode('[1,2]'), SchoolDiscountRules.defaults);
    });
  });
}
