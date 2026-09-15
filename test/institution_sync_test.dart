import 'dart:convert';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/payment_methods.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/system_features.dart';
import 'package:flutter_test/flutter_test.dart';

AppStore _store() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  s.currentTenant = s.tenants.first;
  return s;
}

/// صف `institution_settings` كما يكتبه سطح المكتب في السحابة.
void _cloudRow(AppStore s, Map<String, dynamic> colors, {Map<String, dynamic>? settings}) {
  s.extraCloud['institution_settings'] = [
    {
      'id': s.tenantId,
      'institution_type': 'school',
      'institution_name': 'مدرسة الأمل النموذجية',
      'logo': null,
      'colors': colors,
      'settings': ?settings,
      'updated_at': '2026-09-13T10:00:00.000Z',
    },
  ];
}

void main() {
  group('إعدادات المنشأة تصل من سطح المكتب إلى الجوال', () {
    test('رسم حجز المقعد يُستعاد من عمود الإعدادات', () async {
      final s = _store();
      expect(s.seatReservationFee, 0);

      _cloudRow(s, {}, settings: {'seat_fee': 50, 'seat_fee_mode': 'separate'});
      await s.hydrateInstitution();

      expect(s.seatReservationFee, 50, reason: 'كان يبقى محلياً على الجهاز الذي ضبطه');
      expect(s.deductsSeatFee, isFalse, reason: 'مطالبة مستقلة فوق الأقساط');
    });

    test('سجلٌّ قديم بلا عمود إعدادات يُقرأ من مفاتيح الألوان', () async {
      final s = _store();
      _cloudRow(s, {AppStore.seatFeeColorKey: 50});
      await s.hydrateInstitution();

      expect(s.seatReservationFee, 50, reason: 'جهازٌ لم يُحدَّث بعد ما زال يكتب هناك');
      expect(s.db.settings[seatReservationFeeKey], '50');
    });

    test('الرسوم الإضافية تُستعاد من عمود الإعدادات', () async {
      final s = _store();
      _cloudRow(s, {}, settings: {
        'fee_items': [
          {'id': 'fee-1', 'name': 'الزي المدرسي', 'amount': 100, 'due_date': '2026-09-15'},
        ],
      });
      await s.hydrateInstitution();

      expect(s.feeItems.single.name, 'الزي المدرسي');
      expect(s.feeItems.single.amount, 100);
    });

    test('الميزات وقواعد الخصم ووسائل الدفع تُستعاد كذلك', () async {
      final s = _store();
      _cloudRow(s, {
        '__system_features': const SystemFeatures(enableEvaluations: false).toMap(),
        '__discount_rules': const SchoolDiscountRules(autoSuggestExcellence: true, excellenceMinGpa: 85).toMap(),
        customPaymentMethodsColorKey: [
          {'id': 'cash', 'name': 'نقداً', 'type': 'cash', 'enabled': true},
          {'id': 'bank', 'name': 'بنك القدس', 'type': 'bank', 'enabled': true},
        ],
      });

      await s.hydrateInstitution();

      expect(s.features.enableEvaluations, isFalse);
      expect(s.discountRules.autoSuggestExcellence, isTrue);
      expect(s.discountRules.excellenceMinGpa, 85);
      expect(s.paymentMethods.map((m) => m.name), contains('بنك القدس'));
    });
  });

  group('ما يُضبط على الجوال يصل بقية الأجهزة', () {
    Map<String, dynamic> rowOf(AppStore s) =>
        s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);

    Map<String, dynamic> colorsOf(AppStore s) => Map<String, dynamic>.from(rowOf(s)['colors'] as Map);

    Map<String, dynamic> settingsOf(AppStore s) => Map<String, dynamic>.from(rowOf(s)['settings'] as Map);

    test('رسم الحجز وطريقته يُكتبان في عمود الإعدادات', () async {
      final s = _store();
      await s.setSeatReservationFee(75, deduct: false);

      expect(settingsOf(s)['seat_fee'], 75.0);
      expect(settingsOf(s)['seat_fee_mode'], 'separate');
    });

    test('الميزات وقواعد الخصم كذلك', () async {
      final s = _store();
      await s.saveFeatures(enableExpenses: false);
      await s.saveDiscountRules(const SchoolDiscountRules(autoSuggestExcellence: true));

      final colors = colorsOf(s);
      expect((colors['__system_features'] as Map)['enableExpenses'], isFalse);
      expect((colors['__discount_rules'] as Map)['autoSuggestExcellence'], isTrue);
    });

    test('الكتابة لا تمسح إعدادات كتبتها نسخة أخرى في العمود نفسه', () async {
      final s = _store();
      await s.db.setSetting(institutionColorsKey, jsonEncode({'__unknown_setting': 'يبقى'}));
      // نظام الرصد تكتبه النسخة المكتبية في العمود نفسه ولا تقرؤه هذه
      await s.db.setSetting(institutionSettingsKey, jsonEncode({'grading': {'mode': 'monthly'}}));

      await s.setSeatReservationFee(20);

      expect(colorsOf(s)['__unknown_setting'], 'يبقى');
      expect(settingsOf(s)['seat_fee'], 20.0);
      expect((settingsOf(s)['grading'] as Map)['mode'], 'monthly');
    });
  });
}
