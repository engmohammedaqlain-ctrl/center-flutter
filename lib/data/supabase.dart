import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// إعدادات الاتصال بـ Supabase — المقابل لـ `lib/supabase.ts`.
///
/// النسخة المكتبية تقرأ العنوان والمفتاح من `.env` مع إمكانية تجاوزهما من
/// localStorage. تثبيتهما في الكود هنا كان يمنع أي تغيير بعد البناء.
class SupabaseConfig {
  static const defaultUrl = 'https://tmybbunguiurisdcvrqo.supabase.co';
  static const defaultKey = 'sb_publishable_TowjoMRcd5BJtaUqmCs6Sw_IHhVd3Jj';

  static const urlSettingKey = 'supabase_custom_url';
  static const keySettingKey = 'supabase_custom_key';

  static String url = defaultUrl;
  static String key = defaultKey;

  static void applyOverrides(Map<String, String> settings) {
    final u = settings[urlSettingKey]?.trim();
    final k = settings[keySettingKey]?.trim();
    url = (u == null || u.isEmpty) ? defaultUrl : u;
    key = (k == null || k.isEmpty) ? defaultKey : k;
  }

  static bool get isCustom => url != defaultUrl || key != defaultKey;

  static Map<String, String> get headers => {
        'apikey': key,
        // توكن الجلسة إن وُجد: هو ما تقرأ منه سياسات RLS دورَ صاحبه ومنشأته.
        // المفتاح المنشور وحده يعني زائراً بلا صلاحيات على القاعدة المحمية.
        'Authorization': 'Bearer ${SupabaseAuth.accessToken ?? key}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };
}

/// جلسة الدخول السحابية — المقابل لـ `lib/auth.ts`.
///
/// كلمة المرور لا تصل الجهاز ولا تُقارن فيه: السحابة تتحقق منها وتُصدر توكناً
/// يحمل في `app_metadata` دورَ صاحبه ومنشأته، وسياسات RLS تحكم به الوصول.
abstract final class SupabaseAuth {
  /// يطابق `LOGIN_EMAIL_DOMAIN` في النسخة المكتبية ودوال السيرفر.
  static const emailDomain = 'login.center-system.app';

  static String? accessToken;
  static String? refreshToken;
  static DateTime? expiresAt;

  /// `app_metadata`: الدور والمنشأة وحساب البوابة.
  static Map<String, dynamic> claims = const {};

  /// يُستدعى بعد كل تغيّر في الجلسة لتُحفظ على القرص — يضبطه المتجر.
  ///
  /// السحابة تُدوّر توكن التجديد مع كل تجديد: بقاء الجديد في الذاكرة وحدها كان
  /// يعني أن الإقلاع التالي يستعيد توكناً مستهلكاً، فيفشل التجديد ويُرفض كل طلب
  /// بـ «JWT expired» — والحذف يبقى عالقاً في الطابور — حتى يُعاد تسجيل الدخول.
  static Future<void> Function()? onSessionChanged;

  /// يُستدعى حين ترفض السحابة توكن التجديد نفسه: الجلسة انتهت فعلاً ولا سبيل
  /// إلا الدخول من جديد. انقطاع الشبكة ليس رفضاً فلا يُستدعى له.
  static Future<void> Function()? onSessionInvalid;

  static bool get signedIn => (accessToken ?? '').isNotEmpty;

  static String get role => '${claims['role'] ?? ''}';

  static String get tenantId => '${claims['tenant_id'] ?? ''}';

  static bool get isDeveloper => role == 'developer';

  /// اسم المستخدم يصير بريداً داخلياً ثابت الصيغة لا تُرسل إليه رسالة.
  static String emailFor(String username) => '${username.trim().toLowerCase()}@$emailDomain';

  /// أحرف إنجليزية صغيرة وأرقام و`. _ -`، والبادئات المحجوزة لحسابات البوابات.
  static bool isValidUsername(String username) {
    final u = username.trim().toLowerCase();
    return RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(u) && !RegExp(r'^(student|teacher|parent)-').hasMatch(u);
  }

  static void clear() {
    accessToken = null;
    refreshToken = null;
    expiresAt = null;
    claims = const {};
  }

  static void restore({String? access, String? refresh, DateTime? expiry, Map<String, dynamic>? savedClaims}) {
    accessToken = (access ?? '').isEmpty ? null : access;
    refreshToken = (refresh ?? '').isEmpty ? null : refresh;
    expiresAt = expiry;
    claims = savedClaims ?? const {};
  }

  /// اعتماد جلسة أعادتها السحابة (دخول برمز لمرة واحدة مثلاً).
  static void applySession(Map<String, dynamic> body) => _apply(body);

  static void _apply(Map<String, dynamic> body) {
    accessToken = '${body['access_token'] ?? ''}'.isEmpty ? null : '${body['access_token']}';
    refreshToken = '${body['refresh_token'] ?? ''}'.isEmpty ? null : '${body['refresh_token']}';
    final seconds = (body['expires_in'] as num?)?.toInt() ?? 3600;
    expiresAt = DateTime.now().add(Duration(seconds: seconds));
    final user = body['user'];
    claims = user is Map && user['app_metadata'] is Map
        ? Map<String, dynamic>.from(user['app_metadata'] as Map)
        : const {};
    unawaited(onSessionChanged?.call());
  }

  /// تجديد التوكن قبل انتهائه بدقيقة، فلا يُرفض طلب في منتصف العمل.
  ///
  /// الجلسة المستعادة من القرص قد تصل بلا تاريخ انتهاء — من إصدار أقدم لم يحفظه
  /// أو من قراءة فاشلة — فكان الطلب يُرسل بتوكن منتهٍ وتردّ القاعدة
  /// «JWT expired». المجهولة تُجدَّد احتياطاً ما دام معها توكن تجديد.
  static Future<void> ensureFresh() async {
    if (!signedIn) return;
    final expiry = expiresAt;
    if (expiry == null) {
      await refreshSession();
      return;
    }
    if (DateTime.now().isBefore(expiry.subtract(const Duration(minutes: 1)))) return;
    await refreshSession();
  }

  /// هل رُفض الطلب لانتهاء التوكن؟ — `PGRST303` من PostgREST، و401 من GoTrue.
  static bool isExpiredResponse(int status, String body) {
    if (status != 401 && status != 403) {
      return body.contains('PGRST303') || body.toLowerCase().contains('jwt expired');
    }
    return true;
  }

  /// تجديد الجلسة ثم إعادة المحاولة مرة واحدة حين يُرفض الطلب لانتهاء التوكن.
  ///
  /// جلسةٌ انتهت أثناء العمل — الجهاز نائم أو الرفع طويل — كانت تُسقط العملية
  /// وتُبقيها في الطابور بخطأ خام، فيظن المستخدم أن الحذف لا يعمل.
  static Future<T> withRetryOnExpiry<T>(Future<T> Function() send, {required bool Function(T) expired}) async {
    final first = await send();
    if (!expired(first) || !await refreshSession()) return first;
    return send();
  }

  /// هل رفضت السحابة توكن التجديد نفسه؟ — `invalid_grant` وما في معناه.
  ///
  /// التمييز مقصود: خطأ شبكة أو عطل مؤقت في السيرفر لا يُنهي جلسة صالحة.
  static bool _rejectsRefreshToken(int status, String body) {
    if (status >= 500) return false;
    final raw = body.toLowerCase();
    return raw.contains('invalid_grant') ||
        raw.contains('refresh_token_not_found') ||
        raw.contains('invalid refresh token') ||
        raw.contains('already used');
  }

  static Future<bool> refreshSession() async {
    final token = refreshToken;
    if (token == null) {
      await onSessionInvalid?.call();
      return false;
    }
    try {
      final res = await http.post(
        Uri.parse('${SupabaseConfig.url}/auth/v1/token?grant_type=refresh_token'),
        headers: {'apikey': SupabaseConfig.key, 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': token}),
      );
      if (res.statusCode >= 400) {
        // لا يُخرج المستخدم إلا حين ترفض السحابة التوكن نفسه صراحةً؛ عطلٌ مؤقت
        // أو ردٌّ بلا سبب تُعاد المحاولة بعده والجلسة كما هي
        if (_rejectsRefreshToken(res.statusCode, res.body)) await onSessionInvalid?.call();
        return false;
      }
      _apply(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
      return signedIn;
    } catch (_) {
      // انقطاع شبكة: الجلسة تبقى كما هي حتى يعود الاتصال
      return false;
    }
  }
}

/// نتيجة محاولة دخول: مطالبات التوكن أو رسالة خطأ جاهزة للعرض.
typedef SignInResult = ({Map<String, dynamic>? claims, String? error});

const _invalidCredentials = 'اسم المستخدم أو كلمة المرور غير صحيحة';
const _offlineMessage = 'هذه العملية تحتاج اتصالاً بالإنترنت';

/// دخول الإدارة أو المطور — المقابل لـ `signInWithUsername`.
Future<SignInResult> supabaseSignIn(String username, String password) async {
  if (!SupabaseAuth.isValidUsername(username) || password.isEmpty) {
    return (claims: null, error: _invalidCredentials);
  }
  try {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.url}/auth/v1/token?grant_type=password'),
      headers: {'apikey': SupabaseConfig.key, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': SupabaseAuth.emailFor(username), 'password': password}),
    );
    if (res.statusCode >= 400) {
      final body = res.body.toLowerCase();
      if (res.statusCode == 429 || body.contains('rate limit')) {
        return (claims: null, error: 'محاولات كثيرة، انتظر دقائق ثم أعد المحاولة');
      }
      return (claims: null, error: _invalidCredentials);
    }
    SupabaseAuth._apply(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    if (!SupabaseAuth.signedIn) return (claims: null, error: _invalidCredentials);
    return (claims: SupabaseAuth.claims, error: null);
  } catch (_) {
    return (claims: null, error: _offlineMessage);
  }
}

/// استدعاء دالة سيرفر (Edge Function) — `supabase.functions.invoke`.
///
/// يعيد جسم الرد، ويضع رسالة الخطأ التي تعيدها الدالة نفسها في `error` —
/// «رقم الهوية أو كلمة المرور غير صحيحة» لا «HTTP 401».
/// [anonymous] للدوال التي تُستدعى قبل تسجيل الدخول — دخول البوابات مثلاً.
/// إرسال توكن إدارة قديم معها يجعل بوابة الدوال ترفض الطلب قبل أن يصل الدالة.
Future<Map<String, dynamic>> supabaseInvoke(
  String function,
  Map<String, dynamic> body, {
  bool anonymous = false,
}) async {
  if (!anonymous) await SupabaseAuth.ensureFresh();
  try {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.url}/functions/v1/$function'),
      headers: anonymous
          ? {
              'apikey': SupabaseConfig.key,
              'Authorization': 'Bearer ${SupabaseConfig.key}',
              'Content-Type': 'application/json',
            }
          : SupabaseConfig.headers,
      body: jsonEncode(body),
    );
    final decoded = res.body.isEmpty ? null : _tryJson(res.body);
    final data = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (res.statusCode >= 400 && data['error'] == null) {
      // السبب الحقيقي يُعرض: «تعذّر الاتصال» كان يُقال حتى لخطأ صريح من السيرفر
      final detail = data['message'] ?? data['msg'] ?? (res.body.length <= 120 ? res.body.trim() : '');
      data['error'] = 'تعذّر تنفيذ الطلب (${res.statusCode})${detail == '' ? '' : ': $detail'}';
    }
    return data;
  } on http.ClientException catch (e) {
    return {'error': '$_offlineMessage (${e.message})'};
  } catch (e) {
    // خطأ ليس انقطاع شبكة: يُعرض كما هو بدل نسبته إلى الإنترنت
    return {'error': 'تعذّر تنفيذ الطلب: $e'};
  }
}

/// فكّ JSON بلا رمي: بوابة الدوال قد تردّ نصاً أو HTML عند الأعطال.
Object? _tryJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

/// استبدال رمز الدخول لمرة واحدة بجلسة — `supabase.auth.verifyOtp`.
Future<bool> supabaseVerifyTokenHash(String tokenHash) async {
  try {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.url}/auth/v1/verify'),
      headers: {'apikey': SupabaseConfig.key, 'Content-Type': 'application/json'},
      body: jsonEncode({'type': 'email', 'token_hash': tokenHash}),
    );
    if (res.statusCode >= 400) return false;
    SupabaseAuth.applySession(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    return SupabaseAuth.signedIn;
  } catch (_) {
    return false;
  }
}

/// إنهاء الجلسة على هذا الجهاز. تعذّر إبلاغ السحابة لا يمنع محو التوكن محلياً.
Future<void> supabaseSignOut() async {
  final token = SupabaseAuth.accessToken;
  SupabaseAuth.clear();
  if (token == null) return;
  try {
    await http.post(
      Uri.parse('${SupabaseConfig.url}/auth/v1/logout?scope=local'),
      headers: {'apikey': SupabaseConfig.key, 'Authorization': 'Bearer $token'},
    );
  } catch (_) {
    // دون اتصال: التوكن مُحي محلياً على أي حال
  }
}

/// استدعاء دالة في القاعدة — `supabase.rpc`. يعيد `null` عند الفشل.
Future<dynamic> supabaseRpc(String function, Map<String, dynamic> args) async {
  await SupabaseAuth.ensureFresh();
  try {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.url}/rest/v1/rpc/$function'),
      headers: {...SupabaseConfig.headers, 'Prefer': 'return=representation'},
      body: jsonEncode(args),
    );
    if (res.statusCode >= 400) return null;
    return res.body.isEmpty ? null : jsonDecode(res.body);
  } catch (_) {
    return null;
  }
}

/// كـ [supabaseRpc] لكن يعيد سبب الفشل، أو `null` عند النجاح.
///
/// دالةٌ لا تُرجع شيئاً (`VOID`) يلتبس نجاحها بفشلها حين يكون `null` جواب
/// الحالتين — `set_admin_password` مثلاً.
Future<String?> supabaseRpcError(String function, Map<String, dynamic> args) async {
  await SupabaseAuth.ensureFresh();
  try {
    final res = await http.post(
      Uri.parse('${SupabaseConfig.url}/rest/v1/rpc/$function'),
      headers: SupabaseConfig.headers,
      body: jsonEncode(args),
    );
    if (res.statusCode < 400) return null;
    return describeCloudError(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  } on http.ClientException catch (e) {
    return '$_offlineMessage (${e.message})';
  }
}

/// سبب رفض السحابة بكلام يُقرأ، من جسم رد PostgREST أو من استثناء يحمله.
///
/// كان يُعرض JSON خاماً: `{"code":"42501","details":null,...}`.
String describeCloudError(Object error) {
  var text = '$error'.trim();
  if (text.startsWith('Exception: ')) text = text.substring('Exception: '.length);
  final decoded = _tryJson(text);
  if (decoded is Map) {
    // 42501: سياسات RLS منعت العملية لهذا الحساب
    if ('${decoded['code']}' == '42501') return 'السحابة رفضت العملية: لا صلاحية لهذا الحساب عليها';
    final message = decoded['error'] ?? decoded['message'] ?? decoded['msg'];
    if (message != null) return 'تعذّر الحفظ في السحابة: $message';
  }
  return text.isEmpty ? 'تعذّر الحفظ في السحابة' : text;
}

/// استعلام `select` عام على أي جدول.
Future<List<Map<String, dynamic>>?> supabaseSelect(
  String table, {
  Map<String, String> filters = const {},
  String columns = '*',
  String? order,
  int? limit,
  Map<String, String> extraHeaders = const {},
}) async {
  await SupabaseAuth.ensureFresh();
  final params = <String, String>{'select': columns, ...filters};
  if (order != null) params['order'] = order;
  if (limit != null) params['limit'] = '$limit';
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(queryParameters: params);
  try {
    final res = await http.get(uri, headers: {...SupabaseConfig.headers, ...extraHeaders});
    if (res.statusCode >= 400) return null;
    final data = jsonDecode(res.body);
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (_) {
    return null;
  }
}

/// إدراج أو تحديث صفوف. [onConflict] يحدّد عمود التصالح حين يختلف المفتاح
/// الطبيعي عن `id` — مثل `attendance` وقيده على (الجلسة، الطالب).
Future<void> supabaseUpsert(
  String table,
  List<Map<String, dynamic>> rows, {
  String onConflict = 'id',
}) async {
  await SupabaseAuth.ensureFresh();
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(
    queryParameters: {'on_conflict': onConflict},
  );
  final res = await http.post(
    uri,
    headers: {
      ...SupabaseConfig.headers,
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: jsonEncode(rows),
  );
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
}

Future<void> supabaseDelete(String table, Map<String, String> filters) async {
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(queryParameters: filters);
  final res = await http.delete(uri, headers: SupabaseConfig.headers);
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
}

/// تعديل حقول بعينها في الصفوف المطابقة — `update().eq()` في النسخة المكتبية.
Future<void> supabaseUpdate(String table, Map<String, String> filters, Map<String, dynamic> patch) async {
  await SupabaseAuth.ensureFresh();
  final uri = Uri.parse('${SupabaseConfig.url}/rest/v1/$table').replace(queryParameters: filters);
  final res = await http.patch(uri, headers: SupabaseConfig.headers, body: jsonEncode(patch));
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
}

// ── التخزين السحابي (Supabase Storage) ─────────────────────────────────────

/// الرابط العام لملف في حاوية عامة — `getPublicUrl`.
String storagePublicUrl(String bucket, String path) =>
    '${SupabaseConfig.url}/storage/v1/object/public/$bucket/$path';

/// رفع ملف إلى حاوية. يُعيد الرابط العام، ويرمي عند الرفض.
Future<String> storageUpload(String bucket, String path, List<int> bytes, String contentType) async {
  final uri = Uri.parse('${SupabaseConfig.url}/storage/v1/object/$bucket/$path');
  final res = await http.post(
    uri,
    headers: {
      'apikey': SupabaseConfig.key,
      'Authorization': 'Bearer ${SupabaseConfig.key}',
      'Content-Type': contentType,
      // سنة كاملة: الملف لا يتغيّر بعد رفعه، اسمه فريد بالوقت
      'cache-control': 'max-age=31536000',
      'x-upsert': 'false',
    },
    body: bytes,
  );
  if (res.statusCode >= 400) {
    throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
  }
  return storagePublicUrl(bucket, path);
}

/// حذف ملفات من حاوية. الفشل لا يوقف حذف السجل نفسه، فيُبتلع.
Future<void> storageRemove(String bucket, List<String> paths) async {
  if (paths.isEmpty) return;
  try {
    final uri = Uri.parse('${SupabaseConfig.url}/storage/v1/object/$bucket');
    await http.delete(uri, headers: SupabaseConfig.headers, body: jsonEncode({'prefixes': paths}));
  } catch (_) {
    // ملف يتيم في التخزين أهون من سجل لا يُحذف
  }
}
