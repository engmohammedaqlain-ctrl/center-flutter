import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'persistence_test.dart' show FakeDisk;

const _red = InstitutionColors(
  sidebarBg: '#4A0E17',
  activeItem: '#DC2626',
  primaryButton: '#4A0E17',
  actionButton: '#B91C1C',
  appBg: '#FFF9F9',
);

Future<AppStore> school(FakeDisk disk) async {
  final s = AppStore.forTesting();
  await s.bootstrap(disk);
  injectDemoData(s);
  await s.login('amal', 'amal2026');
  return s;
}

void main() {
  setUp(AppColors.reset);
  tearDownAll(AppColors.reset);

  test('the palette follows the institution colours', () {
    expect(AppColors.amber, const Color(0xFFE88C15));

    AppColors.apply(_red);
    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'لون الإجراء');
    expect(AppColors.navy, const Color(0xFF4A0E17), reason: 'خلفية الترويسة');
    expect(AppColors.heading, const Color(0xFF4A0E17), reason: 'لون العناوين');
    expect(AppColors.bg, const Color(0xFFFFF9F9), reason: 'خلفية العمل');
  });

  test('derived shades stay in the same family as their base', () {
    AppColors.apply(_red);
    // الغامق أغمق من الأساس، والفاتح أفتح منه
    double lum(Color c) => c.computeLuminance();
    expect(lum(AppColors.navyDark), lessThan(lum(AppColors.navy)));
    expect(lum(AppColors.navyMid), greaterThan(lum(AppColors.navy)));
    expect(lum(AppColors.amberDark), lessThan(lum(AppColors.amber)));
  });

  test('the identity colours reach the interface the way Center draws them', () {
    AppColors.apply(_red);
    expect(AppColors.navy, const Color(0xFF4A0E17), reason: 'sidebarBg');
    expect(AppColors.heading, const Color(0xFF4A0E17), reason: 'primaryButton');
    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'actionButton');
    expect(AppColors.bg, const Color(0xFFFFF9F9), reason: 'appBg');
    // index.css يُحيل `text-[#E88C15]` و`text-[#F39C12]` و`bg-[#FFF7ED]` —
    // القسم المفتوح في الهاتف — إلى لون العمليات لا إلى activeItem
    expect(AppColors.accent, const Color(0xFFB91C1C), reason: 'التمييز يتبع لون العمليات');
  });

  test('اسم المنشأة في الترويسة رمادي ثابت لا يتبع لون الهوية', () {
    AppColors.apply(_red);
    expect(AppColors.headerMuted, const Color(0xFF94A3B8));
    expect(AppColors.headerMuted, isNot(AppColors.accent));
    // رمادي يُقرأ على الشريط الداكن: ما دون هذه الدرجة يذوب في الخلفية
    expect(
      AppColors.headerMuted.computeLuminance(),
      greaterThan(AppColors.navy.computeLuminance() * 3),
    );
  });

  test('activeItem is kept for the portals but does not recolour mobile highlights', () {
    // لا يُرسم إلا في قائمة سطح المكتب الجانبية والبوابات، فيبقى محفوظاً كما هو
    expect(InstitutionColors.fromMap(_red.toMap()).activeItem, '#DC2626');
    AppColors.apply(_red);
    expect(AppColors.accent, isNot(const Color(0xFFDC2626)));
  });

  test('a missing highlight falls back to the action colour', () {
    AppColors.apply(const InstitutionColors(actionButton: '#B91C1C', activeItem: ''));
    expect(AppColors.accent, const Color(0xFFB91C1C));
  });

  test('a three-digit value is read as CSS shorthand', () {
    // '#bad' لون صالح مختصر، لا قيمة فاسدة
    expect(parseHexColor('#bad'), const Color(0xFFBBAADD));
    expect(parseHexColor('#ZZZ'), isNull);
  });

  test('badge tints are mixed from the action colour, as index.css mixes them', () {
    // `color-mix(in srgb, var(--theme-action-btn) 10%, white)` للخلفية و25% للحدّ
    void near(Color actual, Color expected, String reason) {
      int ch(double v) => (v * 255).round();
      expect((ch(actual.r) - ch(expected.r)).abs(), lessThanOrEqualTo(1), reason: reason);
      expect((ch(actual.g) - ch(expected.g)).abs(), lessThanOrEqualTo(1), reason: reason);
      expect((ch(actual.b) - ch(expected.b)).abs(), lessThanOrEqualTo(1), reason: reason);
    }

    AppColors.apply(const InstitutionColors(actionButton: '#15803D'));
    near(AppColors.amberSoft, const Color(0xFFE8F2EC), 'خلفية فاتحة خضراء لا برتقالية');
    near(AppColors.amberBorder, const Color(0xFFC5DFCF), 'حدّ أخضر فاتح');
  });

  test('semantic colours never move', () {
    AppColors.apply(_red);
    expect(AppColors.success, const Color(0xFF16A34A));
    expect(AppColors.danger, const Color(0xFFDC2626));
    expect(AppColors.muted, const Color(0xFF64748B));
  });

  test('a bad colour value falls back instead of blanking the screen', () {
    AppColors.apply(const InstitutionColors(sidebarBg: 'not-a-colour', actionButton: '#ZZZZZZ'));
    expect(AppColors.navy, const Color(0xFF0B2545));
    expect(AppColors.amber, const Color(0xFFE88C15));
  });

  test('saving the identity repaints and reaches the cloud row', () async {
    final s = await school(FakeDisk());
    await s.saveInstitution(colors: _red);

    expect(AppColors.amber, const Color(0xFFB91C1C));

    final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
    expect((row['colors'] as Map)['actionButton'], '#B91C1C');
    expect(
      s.pendingSyncs.any((p) => p.tableName == 'institution_settings'),
      isTrue,
      reason: 'الهوية تُرفع لتصل بقية الأجهزة',
    );
  });

  test('saving the identity keeps colour keys another version stored', () async {
    // نسخة أخرى تحفظ طرق الدفع المخصّصة داخل كائن الألوان نفسه؛ رفعه بالألوان
    // الخمسة وحدها كان يمسحها من السحابة عند كل الأجهزة
    final s = await school(FakeDisk());
    final methods = [
      {'id': 'other', 'name': 'مالت شات', 'type': 'other', 'enabled': true},
    ];
    await s.db.setSetting(
      institutionColorsKey,
      jsonEncode({..._red.toMap(), '__custom_payment_methods': methods}),
    );

    await s.saveInstitution(colors: _red.copyWith(actionButton: '#15803D'));

    final row = s.extraCloud['institution_settings']!.firstWhere((e) => e['id'] == s.tenantId);
    final cloud = row['colors'] as Map;
    expect(cloud['actionButton'], '#15803D', reason: 'اللون الجديد يُرفع');
    expect(cloud['__custom_payment_methods'], methods, reason: 'وما لا نعرفه يبقى كما هو');
    expect(
      jsonDecode(s.db.settings[institutionColorsKey]!)['__custom_payment_methods'],
      methods,
      reason: 'ويبقى محلياً كي لا يُمسح في الحفظ التالي',
    );
  });

  test('colours arriving from another device are applied on pull', () async {
    final s = await school(FakeDisk());
    expect(AppColors.amber, const Color(0xFFE88C15));

    // صف الهوية كما يصل من السحابة بعد تغييره على سطح المكتب
    s.putRows('institution_settings', [
      {
        'id': s.tenantId,
        'institution_type': 'school',
        'institution_name': 'مدرسة آل الأشقر',
        'colors': _red.toMap(),
        'sync_status': 'synced',
      }
    ]);
    await s.onPulled();

    expect(AppColors.amber, const Color(0xFFB91C1C), reason: 'اللون يتبع الجهاز الآخر');
    expect(s.institutionName, 'مدرسة آل الأشقر');
  });

  test('the chosen palette survives a restart', () async {
    final disk = FakeDisk();
    final first = await school(disk);
    await first.saveInstitution(colors: _red);
    await first.flush();

    AppColors.reset();
    final second = AppStore.forTesting();
    await second.bootstrap(disk);

    expect(AppColors.amber, const Color(0xFFB91C1C));
    expect(jsonDecode(second.db.settings[institutionColorsKey]!)['sidebarBg'], '#4A0E17');
  });
}
