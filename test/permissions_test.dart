import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/permissions.dart';
import 'package:center_mobile/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `lib/__tests__/permissions.test.ts`.
void main() {
  group('قوالب الأدوار', () {
    test('المدير يرى كل التبويبات', () {
      for (final section in allSections) {
        expect(roleCanAccess('admin', section), isTrue, reason: section);
      }
    });

    test('المحاسب: المالية بمصروفاتها والطلاب والصفوف فقط', () {
      expect(roles['accountant']!.sections.toSet(), {'classes', 'finance', 'finance.expenses', 'students'});
    });

    test('السكرتير يرى الحضور ولا يرى المصروفات — رواتب الموظفين لا تخصه', () {
      expect(roleCanAccess('receptionist', 'attendance'), isTrue);
      expect(roleCanAccess('receptionist', 'finance'), isTrue);
      expect(roleCanAccess('receptionist', 'finance.expenses'), isFalse);
      expect(roleCanAccess('accountant', 'attendance'), isFalse);
    });

    test('لا دور غير المدير يرى المستخدمين أو النسخ الاحتياطي', () {
      for (final role in ['accountant', 'receptionist']) {
        expect(roleCanAccess(role, 'settings'), isFalse);
        expect(roleCanAccess(role, 'settings.users'), isFalse);
        expect(roleCanAccess(role, 'settings.backup'), isFalse);
      }
    });

    test('أي دور مجهول يُعامل سكرتيراً لا مديراً', () {
      expect(normalizeRole('superuser'), 'receptionist');
      expect(normalizeRole(null), 'receptionist');
      expect(normalizeRole('مدير النظام'), 'admin');
      expect(normalizeRole('محاسب'), 'accountant');
      expect(roleCanAccess('superuser', 'settings'), isFalse);
    });

    test('لكل دور اسم معروض', () {
      expect(roleLabel('admin'), 'مدير');
      expect(roleLabel('accountant'), 'محاسب');
      expect(roleLabel('receptionist'), 'سكرتير');
      expect(roleList, hasLength(3));
    });
  });

  group('صلاحيات الحساب', () {
    test('القائمة الخاصة تتقدّم على قالب الدور — ولو كان مديراً', () {
      expect(effectiveSections(['students'], 'admin'), ['students']);
    });

    test('حساب بلا قائمة يرجع إلى قالب دوره', () {
      expect(effectiveSections(null, 'accountant'), roles['accountant']!.sections);
    });

    test('قائمة فارغة صريحة تعني لا شيء، لا رجوعاً إلى القالب', () {
      expect(effectiveSections(const [], 'admin'), isEmpty);
    });

    test('القيم المجهولة في القائمة تُتجاهل ولا تُسقط الباقي', () {
      expect(effectiveSections(['students', 'not_a_section'], 'admin'), ['students']);
    });
  });

  group('ترجمة القوائم القديمة', () {
    test('القدرات القديمة تُترجم إلى تبويباتها فلا يفقد حساب قائم وصوله', () {
      expect(
        normalizeSections(['students.view', 'students.edit', 'finance.view', 'finance.collect']),
        ['students', 'finance'],
      );
    });

    test('صلاحية الجداول القديمة كانت تفتح المودل أيضاً، والحضور يفتح التقييمات', () {
      expect(normalizeSections(['schedule.view']), ['classes', 'moodle']);
      expect(normalizeSections(['attendance.view']), ['attendance', 'evaluations']);
    });

    test('صلاحيات الإعدادات والمصروفات القديمة تجلب أصلها', () {
      expect(normalizeSections(['settings.users']), ['settings', 'settings.users']);
      expect(normalizeSections(['settings.backup']), ['settings', 'settings.backup']);
      expect(normalizeSections(['finance.expenses']), ['finance', 'finance.expenses']);
    });

    test('«ورديات الصندوق» القديمة على الجوال تُقرأ مصروفات', () {
      expect(normalizeSections(['finance.cashbox']), ['finance', 'finance.expenses']);
    });

    test('من كان يملك المالية دون المصروفات يبقى كذلك بعد الترقية', () {
      expect(normalizeSections(['finance.view', 'finance.collect']), ['finance']);
    });

    test('صلاحيات المزامنة القديمة لا تقابل تبويباً فتسقط بلا أثر', () {
      expect(normalizeSections(['sync.push', 'sync.pull']), isEmpty);
    });

    test('الترتيب ثابت على ترتيب التبويبات مهما كان ترتيب الإدخال', () {
      expect(normalizeSections(['finance', 'students', 'attendance']), ['students', 'attendance', 'finance']);
    });
  });

  group('تبديل التبويبات في المحرّر', () {
    test('الإضافة والإزالة تعملان', () {
      expect(toggleSection(const [], 'students'), ['students']);
      expect(toggleSection(['students', 'finance'], 'students'), ['finance']);
    });

    test('إتاحة تبويب فرعي تتيح أصله تلقائياً', () {
      expect(toggleSection(const [], 'settings.users'), ['settings', 'settings.users']);
    });

    test('سحب تبويب الإعدادات يسحب فروعه معه', () {
      expect(toggleSection(['settings', 'settings.users', 'settings.backup'], 'settings'), isEmpty);
    });

    test('لا تكرار مهما تكرّر التبديل', () {
      var list = toggleSection(const [], 'finance');
      list = toggleSection(list, 'finance');
      list = toggleSection(list, 'finance');
      expect(list, ['finance']);
    });
  });

  group('ربط المسارات بالتبويبات', () {
    test('«الجداول» و«الصفوف» تبويب واحد', () {
      expect(resolveSection('schedule'), 'classes');
      expect(resolveSection('classes'), 'classes');
    });

    test('المسار غير المعروف لا يُحرس بتبويب', () {
      expect(resolveSection('developer'), isNull);
      expect(resolveSection(null), isNull);
    });

    test('قوالب الأدوار لا تمنح فرعاً بلا أصله', () {
      for (final role in roleList) {
        for (final section in accessSections) {
          if (section.parent != null && role.sections.contains(section.id)) {
            expect(role.sections, contains(section.parent), reason: role.label);
          }
        }
      }
    });
  });

  group('المتجر يطبّق التبويبات', () {
    AppStore seeded() {
      final s = AppStore.forTesting();
      injectDemoData(s);
      return s;
    }

    test('جهاز بلا هوية مثبَّتة يرى كل شيء', () {
      final s = seeded();
      expect(s.can('settings.users'), isTrue);
      expect(s.canOpenSection('finance'), isTrue);
    });

    test('جهاز السكرتير يفقد تبويبات المدير', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      await s.setDeviceIdentity(clerk, '');
      expect(s.can('students'), isTrue);
      expect(s.can('finance'), isTrue);
      expect(s.can('finance.expenses'), isFalse);
      expect(s.can('settings.users'), isFalse);
      expect(s.canOpenSection('settings'), isFalse);
    });

    test('القائمة المخصّصة تتقدّم على قالب الدور', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      clerk.capabilities = ['students'];
      await s.setDeviceIdentity(clerk, '');
      expect(s.canOpenSection('students'), isTrue);
      expect(s.canOpenSection('finance'), isFalse);
      expect(s.canOpenSection('attendance'), isFalse);
    });

    test('الحساب الموقوف لا يرى شيئاً', () async {
      final s = seeded();
      final clerk = s.users.firstWhere((u) => u.role == 'receptionist');
      clerk.isActive = false;
      await s.setDeviceIdentity(clerk, '');
      expect(s.mySections, isEmpty);
      expect(s.canOpenSection('students'), isFalse);
    });
  });
}
