import '../models/models.dart';
import 'supabase.dart';

/// إدارة المنشآت والاشتراكات — المقابل لـ `lib/tenantService.ts`.
///
/// المصدر الأول هو السحابة؛ القائمة المحلية احتياط عند انقطاع الاتصال، حتى
/// يبقى الدخول ممكناً على جهاز عمل بلا إنترنت.
class TenantService {
  const TenantService();

  /// حساب المطور العام. لا يُكتب في الكود: يُمرَّر عند البناء بـ
  /// `--dart-define=DEV_USERNAME=... --dart-define=DEV_PASSWORD=...`،
  /// فلا يقرأه من يفكّ الـ APK من مصدر المشروع ولا من تاريخه.
  ///
  /// نسخة بُنيت بلا تمريرهما تخرج بلا حساب مطور أصلاً — وهو الوضع الآمن
  /// للنسخ التي توزَّع على المدارس.
  ///
  /// متغيّران لا ثابتان كي تضبط الاختبارات حسابها الخاص بلا أسرار حقيقية.
  static String masterUsername = const String.fromEnvironment('DEV_USERNAME');
  static String masterPassword = const String.fromEnvironment('DEV_PASSWORD');

  /// هل تحمل هذه النسخة حساب مطور.
  static bool get hasMasterAccount =>
      masterUsername.trim().isNotEmpty && masterPassword.trim().isNotEmpty;

  /// جلب كل المنشآت من السحابة. يعيد `null` عند تعذّر الاتصال.
  Future<List<Tenant>?> fetchAll() async {
    final rows = await supabaseSelect('tenants', order: 'created_at.desc');
    if (rows == null) return null;
    return rows.map(Tenant.fromCloud).toList();
  }

  /// جلب منشأة بمعرّفها — بعد الدخول يحمل التوكن معرّف المنشأة لا اسمها.
  Future<Tenant?> findById(String id) async {
    if (id.trim().isEmpty) return null;
    final rows = await supabaseSelect('tenants', filters: {'id': 'eq.${id.trim()}'}, limit: 1);
    if (rows == null || rows.isEmpty) return null;
    return Tenant.fromCloud(rows.first);
  }

  /// البحث عن منشأة بالكود (للتحقق عند تهيئة جهاز جديد).
  Future<Tenant?> findByCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return null;
    final rows = await supabaseSelect('tenants', filters: {'code': 'ilike.$clean'}, limit: 1);
    if (rows == null || rows.isEmpty) return null;
    return Tenant.fromCloud(rows.first);
  }

  Future<void> save(Tenant t) => supabaseUpsert('tenants', [t.toCloud()]);

  Future<void> remove(String id) => supabaseDelete('tenants', {'id': 'eq.$id'});

  /// توليد كود منشأة من اسمها — مطابق لسلوك `handleNameChange`.
  static String codeFromName(String name, int existingCount) {
    final letters = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.characters1)
        .join();
    final base = letters.isEmpty ? 'CTR' : letters.toUpperCase();
    return '$base-${(existingCount + 1).toString().padLeft(2, '0')}';
  }
}

extension on String {
  String get characters1 {
    final t = trim();
    if (t.isEmpty) return '';
    // الحروف اللاتينية تُؤخذ كما هي؛ العربية تُترجم صوتياً للحرف المقابل.
    final c = t.substring(0, 1);
    return _arabicToLatin[c] ?? c;
  }
}

const _arabicToLatin = {
  'ا': 'A', 'أ': 'A', 'إ': 'A', 'آ': 'A', 'ب': 'B', 'ت': 'T', 'ث': 'TH',
  'ج': 'J', 'ح': 'H', 'خ': 'KH', 'د': 'D', 'ذ': 'TH', 'ر': 'R', 'ز': 'Z',
  'س': 'S', 'ش': 'SH', 'ص': 'S', 'ض': 'D', 'ط': 'T', 'ظ': 'Z', 'ع': 'A',
  'غ': 'GH', 'ف': 'F', 'ق': 'Q', 'ك': 'K', 'ل': 'L', 'م': 'M', 'ن': 'N',
  'ه': 'H', 'و': 'W', 'ي': 'Y', 'ى': 'Y', 'ة': 'H',
};

/// خدمة بلا شبكة — للاختبارات ولوضع العمل دون اتصال.
class OfflineTenantService implements TenantService {
  const OfflineTenantService();

  @override
  Future<List<Tenant>?> fetchAll() async => null;

  @override
  Future<Tenant?> findById(String id) async => null;

  @override
  Future<Tenant?> findByCode(String code) async => null;

  @override
  Future<void> save(Tenant t) async {}

  @override
  Future<void> remove(String id) async {}
}
