import '../models/models.dart';
import 'supabase.dart';

/// نتيجة إضافة منشأة: المنشأة كما حفظتها السحابة، أو رسالة جاهزة للعرض.
typedef TenantCreation = ({Tenant? tenant, String? error});

/// إدارة المنشآت والاشتراكات — المقابل لـ `lib/tenantService.ts`.
///
/// القراءة من السحابة، والقائمة المحلية احتياط عند انقطاع الاتصال حتى يبقى
/// الدخول ممكناً على جهاز عمل بلا إنترنت. الكتابة لا تكون إلا في السحابة:
/// سياسات القاعدة لا تسمح بإدراج صف في `tenants` ولا بحذفه من التطبيق، فتمرّ
/// الإضافة والحذف بدالة السيرفر `admin-tenants`، والتعديل بـ PATCH بصلاحية المطور.
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

  /// إضافة منشأة مع حساب دخولها — `createTenant`.
  ///
  /// إنشاء حساب في Supabase Auth يحتاج مفتاح الخدمة، فتنفّذه دالة السيرفر.
  /// [adminPassword] لتعيين أدوار الأجهزة، منفصلة عن كلمة الدخول.
  Future<TenantCreation> create(Tenant t, {required String password, required String adminPassword}) async {
    final data = await supabaseInvoke('admin-tenants', {
      'action': 'create_tenant',
      'tenant': {
        'name': t.name,
        'code': t.code,
        'plan_type': t.planType,
        'expires_at': t.isLifetime ? null : t.expiresAt.toUtc().toIso8601String(),
        'owner_name': t.ownerName,
        'owner_phone': t.ownerPhone,
        'notes': t.notes,
      },
      'username': t.username,
      'password': password,
      'admin_password': adminPassword,
    });
    final error = data['error'];
    if (error != null) return (tenant: null, error: '$error');
    final row = data['tenant'];
    if (row is! Map) return (tenant: null, error: 'فشلت إضافة الاشتراك');
    return (tenant: Tenant.fromCloud(Map<String, dynamic>.from(row)), error: null);
  }

  /// تعديل منشأة — `updateTenant`. يعيد رسالة الخطأ، أو `null` عند النجاح.
  ///
  /// [fields] أعمدة `tenants` كما في السحابة. بيانات الدخول لا تُرسل إلا عند
  /// تغييرها: [username] اسم جديد، و[newPassword] و[newAdminPassword] فارغتان
  /// لإبقاء الحاليتين.
  Future<String?> update(
    String id,
    Map<String, dynamic> fields, {
    String? username,
    String? newPassword,
    String? newAdminPassword,
  }) async {
    if (fields.isNotEmpty) {
      try {
        await supabaseUpdate(
          'tenants',
          {'id': 'eq.$id'},
          {...fields, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        );
      } catch (e) {
        return describeCloudError(e);
      }

      // اسم الاشتراك وحده لا يغيّر ما يظهر في المدرسة: ذاك يُقرأ من
      // institution_settings، فيُحدَّث معه ليصل الاسم فعلاً لأجهزتها
      final name = fields['name'];
      if (name is String && name.trim().isNotEmpty) {
        try {
          await supabaseUpsert('institution_settings', [
            {'id': id, 'tenant_id': id, 'institution_name': name.trim()},
          ]);
        } catch (_) {}
      }
    }

    final password = newPassword?.trim() ?? '';
    if (username != null || password.isNotEmpty) {
      final data = await supabaseInvoke('admin-tenants', {
        'action': 'set_credentials',
        'tenant_id': id,
        'username': ?username,
        if (password.isNotEmpty) 'password': password,
      });
      if (data['error'] != null) return '${data['error']}';
    }

    final adminPassword = newAdminPassword?.trim() ?? '';
    if (adminPassword.isNotEmpty) {
      final error = await supabaseRpcError('set_admin_password', {
        'p_tenant_id': id,
        'p_password': adminPassword,
      });
      if (error != null) return error;
    }
    return null;
  }

  /// حذف منشأة مع حساب دخولها — `deleteTenant`. يعيد رسالة الخطأ أو `null`.
  Future<String?> remove(String id) async {
    final data = await supabaseInvoke('admin-tenants', {'action': 'delete_tenant', 'tenant_id': id});
    return data['error'] == null ? null : '${data['error']}';
  }

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

const _offlineManagement = 'إدارة المنشآت تحتاج اتصالاً بالسحابة';

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
  Future<TenantCreation> create(Tenant t, {required String password, required String adminPassword}) async =>
      (tenant: null, error: _offlineManagement);

  @override
  Future<String?> update(
    String id,
    Map<String, dynamic> fields, {
    String? username,
    String? newPassword,
    String? newAdminPassword,
  }) async =>
      _offlineManagement;

  @override
  Future<String?> remove(String id) async => _offlineManagement;
}
