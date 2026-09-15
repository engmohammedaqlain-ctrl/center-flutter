import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'supabase.dart';

/// مطابق لـ TABLE_ALLOWED_COLUMNS في sync.ts
const tableAllowedColumns = <String, List<String>>{
  'tenants': [
    'id', 'code', 'name', 'plan_type', 'status', 'expires_at',
    'owner_name', 'owner_phone', 'app_username', 'app_password', 'notes',
    'created_at', 'updated_at',
  ],
  'users': [
    'id', 'name', 'email', 'role', 'is_active', 'capabilities', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'subjects': [
    'id', 'name', 'code', 'grade_level', 'description', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'rooms': [
    'id', 'name', 'capacity', 'grade_level', 'stage_tier', 'homeroom_teacher_id',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'teachers': [
    'id', 'name', 'phone', 'email', 'subject_ids', 'payment_type', 'payment_rate',
    'national_id', 'portal_code',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'groups': [
    'id', 'name', 'subject_id', 'teacher_id', 'room_id', 'room_ids', 'grade_level',
    'price_per_month', 'max_students', 'days', 'start_time', 'end_time',
    'status', 'tenant_id', 'created_at', 'updated_at',
  ],
  'grade_fees': [
    'id', 'grade_name', 'monthly_fee', 'order_index', 'is_custom', 'stage_tier',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'students': [
    'id', 'first_name', 'last_name', 'full_name', 'phone', 'phone_prefix',
    'parent_name', 'guardian_relationship', 'parent_phone', 'parent_phone_prefix',
    'national_id', 'grade_level', 'gender', 'status', 'balance',
    'neighborhood', 'detailed_address', 'referral_source', 'section',
    'school_name', 'enrollment_date', 'birth_date', 'birth_place',
    'nationality', 'previous_school', 'gpa', 'housing_status', 'original_area',
    'health_status', 'medical_condition', 'parent_job', 'parent_secondary_phone',
    'email', 'guardian_declaration', 'initial_rating',
    'seat_reservation_paid', 'seat_reservation_discounted',
    'payment_plan', 'payment_status',
    'academic_discount_applied', 'academic_discount_rate',
    'exception_reason', 'custom_monthly_fee',
    'portal_code', 'parent_portal_code',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'student_attachments': [
    'id', 'student_id_photo_path', 'birth_certificate_path',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'institution_settings': [
    'id', 'institution_type', 'institution_name', 'logo', 'colors',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'enrollments': [
    'id', 'student_id', 'group_id', 'room_id', 'enrollment_date', 'enrolled_at',
    'custom_price', 'applied_price', 'discount_reason',
    'status', 'tenant_id', 'created_at', 'updated_at',
  ],
  'installments': [
    'id', 'student_id', 'title', 'amount', 'due_date', 'paid_amount',
    'status', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'payments': [
    'id', 'receipt_number', 'student_id', 'enrollment_id', 'group_id',
    'installment_id', 'amount', 'original_amount', 'discount_amount', 'discount_reason',
    'payment_method', 'payment_date',
    'received_by_user_id', 'payment_purpose', 'transfer_channel',
    'transfer_date', 'custom_method_notes',
    'sender_name', 'reference_number', 'total_due_at_payment',
    'remaining_balance_after', 'is_cancelled', 'cancelled_reason',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'sessions': [
    'id', 'group_id', 'teacher_id', 'substitute_teacher_id', 'room_id',
    'session_date', 'start_time', 'end_time', 'status', 'notes', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'attendance': [
    'id', 'session_id', 'student_id', 'status', 'marked_by_user_id', 'notes',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'teacher_payouts': [
    'id', 'teacher_id', 'group_id', 'amount', 'period_start',
    'period_end', 'payment_date', 'paid_by_user_id', 'payment_method',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'expenses': [
    'id', 'category', 'description', 'amount', 'expense_date',
    'recorded_by_user_id', 'payment_method', 'notes', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'class_announcements': [
    'id', 'tenant_id', 'teacher_id', 'group_id', 'title', 'content',
    'image_url', 'created_at',
  ],
  'student_evaluations': [
    'id', 'tenant_id', 'student_id', 'group_id', 'teacher_id', 'subject_id',
    'title', 'score', 'max_score', 'evaluation_date', 'type', 'notes',
    'term', 'component_id',
    'created_at', 'updated_at',
  ],
};

const nonTextColumns = <String, List<String>>{
  'attendance': ['created_at', 'tenant_id', 'updated_at'],
  'enrollments': [
    'applied_price', 'created_at', 'custom_price', 'enrolled_at', 'enrollment_date',
    'tenant_id', 'updated_at',
  ],
  'expenses': ['amount', 'created_at', 'expense_date', 'tenant_id', 'updated_at'],
  'grade_fees': ['created_at', 'is_custom', 'monthly_fee', 'order_index', 'tenant_id', 'updated_at'],
  'groups': [
    'created_at', 'days', 'end_time', 'max_students', 'price_per_month', 'room_ids', 'start_time',
    'tenant_id', 'updated_at',
  ],
  'installments': [
    'amount', 'created_at', 'due_date', 'paid_amount',
    'tenant_id', 'updated_at',
  ],
  'institution_settings': ['colors', 'created_at', 'tenant_id', 'updated_at'],
  'payments': [
    'amount', 'created_at', 'discount_amount', 'is_cancelled', 'original_amount', 'payment_date',
    'remaining_balance_after', 'tenant_id', 'total_due_at_payment', 'transfer_date', 'updated_at',
  ],
  'rooms': ['capacity', 'created_at', 'tenant_id', 'updated_at'],
  'sessions': ['created_at', 'end_time', 'session_date', 'start_time', 'tenant_id', 'updated_at'],
  'student_attachments': ['created_at', 'tenant_id', 'updated_at'],
  'students': [
    'academic_discount_applied', 'academic_discount_rate', 'balance', 'birth_date',
    'created_at', 'custom_monthly_fee', 'enrollment_date', 'guardian_declaration',
    'initial_rating', 'seat_reservation_discounted',
    'seat_reservation_paid', 'tenant_id', 'updated_at',
  ],
  'subjects': ['created_at', 'tenant_id', 'updated_at'],
  'teacher_payouts': [
    'amount', 'created_at', 'payment_date', 'period_end', 'period_start',
    'tenant_id', 'updated_at',
  ],
  'teachers': ['created_at', 'payment_rate', 'subject_ids', 'tenant_id', 'updated_at'],
  'tenants': ['created_at', 'expires_at', 'id', 'updated_at'],
  'users': ['capabilities', 'created_at', 'is_active', 'tenant_id', 'updated_at'],
  'class_announcements': ['created_at', 'id', 'tenant_id'],
  'student_evaluations': [
    'created_at', 'evaluation_date', 'id', 'max_score', 'score', 'tenant_id', 'updated_at',
  ],
};

const tableLabelsAr = <String, String>{
  'users': 'المستخدمون',
  'subjects': 'المواد',
  'rooms': 'الصفوف والقاعات',
  'teachers': 'المعلمون',
  'grade_fees': 'رسوم الصفوف',
  'groups': 'المجموعات',
  'students': 'الطلاب',
  'student_attachments': 'مرفقات الطلاب',
  'institution_settings': 'هوية المنشأة',
  'enrollments': 'التسجيلات',
  'installments': 'الأقساط',
  'payments': 'سندات القبض',
  'sessions': 'الحصص',
  'attendance': 'الحضور والغياب',
  'teacher_payouts': 'مستحقات المعلمين',
  'expenses': 'المصروفات',
  'class_announcements': 'إعلانات الصفوف',
  'student_evaluations': 'التقييمات والدرجات',
};

/// أسماء العمليات كما تُعرض — مطابق لـ `ACTION_LABELS` في SyncDetails.tsx
const actionLabelsAr = <String, String>{
  'INSERT': 'إضافة',
  'UPDATE': 'تعديل',
  'DELETE': 'حذف',
};

const syncedTables = [
  'users',
  'subjects',
  'rooms',
  'teachers',
  'grade_fees',
  'groups',
  'students',
  'student_attachments',
  'institution_settings',
  'enrollments',
  'installments',
  'payments',
  'sessions',
  'attendance',
  'teacher_payouts',
  'expenses',
  'student_evaluations',
];

/// عدد الجداول التي تُسأل عنها السحابة معاً. التتابع كان يجعل كل سحب ينتظر نحو
/// عشرين رحلة ذهاب وإياب واحدة بعد أخرى، فبدا السحب التلقائي بطيئاً.
const pullConcurrency = 6;

/// تشغيل [task] على [items] بحدٍّ أقصى [limit] معاً، والنتائج بترتيب العناصر.
Future<List<R>> mapPooled<T, R>(List<T> items, int limit, Future<R> Function(T item) task) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await task(items[i]);
    }
  }

  final workers = items.isEmpty ? 0 : limit.clamp(1, items.length);
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  return [for (final r in results) r as R];
}

/// هل ردّ الخادم أن الجدول غير موجود في القاعدة؟ (PostgREST: `PGRST205`)
///
/// يحدث حين تُضاف ميزة في الكود ولم تُطبَّق هجرتها على قاعدة المنشأة بعد —
/// كجدول `class_announcements`. يُميَّز عن بقية الأعطال لأنه لا يُصلَح بإعادة المحاولة.
bool isMissingTableError(int status, String body) => status == 404 && body.contains('PGRST205');

/// بصمة أعمدة المزامنة — تتغير متى أُضيف جدول أو عمود إلى [tableAllowedColumns].
///
/// السحب التزايدي لا يعيد إلا ما تغيّر بعد الختم، فالعمود المضاف حديثاً لا يصل في
/// السجلات القديمة أبداً: جهاز سحب الطلاب قبل `parent_portal_code` يبقى بلا كلمة
/// مرور ولي الأمر وهي في السحابة — ثم يعرض «توليد»، وأي تعديل على الطالب يرفع
/// الحقل فارغاً فيمحوها. البصمة تُحفظ مع الختم، فيعود أول سحب بعد التحديث كاملاً.
final String pullColumnsSignature = () {
  // FNV-1a بـ 32 بت: ثابتة بين التشغيلات والإصدارات، بخلاف `hashCode`
  var hash = 0x811c9dc5;
  for (final entry in tableAllowedColumns.entries) {
    for (final unit in '${entry.key}:${entry.value.join(',')};'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
  }
  return hash.toRadixString(16);
}();

/// هل يحمل الجدول عمود `updated_at`؟
///
/// السحب التزايدي يرشّح بـ `updated_at=gt.<الختم>`، وسؤال جدول لا يملك العمود
/// يردّه PostgREST بخطأ 400 فيسقط الجدول كله من السحب. `class_announcements`
/// مثلاً لا يحمل إلا `created_at`، فيُسحب كاملاً في كل مرة.
bool tableHasUpdatedAt(String table) =>
    tableAllowedColumns[table]?.contains('updated_at') ?? true;

/// عمود التصالح عند الرفع لكل جدول يختلف مفتاحه الطبيعي عن `id`.
///
/// `attendance` عليه `UNIQUE (tenant_id, session_id, student_id)`: صفٌّ بمعرّف
/// جديد لنفس الطالب في نفس الجلسة كان يُرفض بـ «معرّف مكرّر» ويعلق في الطابور.
/// التصالح على المفتاح الطبيعي يدمجه في الصف القائم بدل أن يفشل.
const tableConflictTarget = <String, String>{
  'attendance': 'tenant_id,session_id,student_id',
};

const maxSyncRetries = 5;
const pushChunk = 50;
const pullPageSize = 500;
const stampToleranceMs = 1000;

String get supabaseUrl => SupabaseConfig.url;
String get supabaseKey => SupabaseConfig.key;

String localDateStr([DateTime? d]) {
  final x = d ?? DateTime.now();
  return isoDate(x);
}

int toTimestamp(dynamic value) {
  if (value == null) return 0;
  final s = value.toString().trim();
  if (s.isEmpty) return 0;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return 0;
  return parsed.millisecondsSinceEpoch;
}

Map<String, dynamic> sanitizePayload(String tableName, Map<String, dynamic>? payload, String tenantId) {
  if (payload == null) return {'tenant_id': tenantId};
  final allowed = tableAllowedColumns[tableName];
  final clean = <String, dynamic>{};

  if (allowed != null) {
    for (final key in allowed) {
      if (payload.containsKey(key)) {
        clean[key] = payload[key];
      }
    }
  } else {
    for (final e in payload.entries) {
      if (e.key == 'sync_status' || e.key == 'synced_at') continue;
      clean[e.key] = e.value;
    }
  }

  if (tableName == 'enrollments') {
    if (clean['enrollment_date'] == null || '${clean['enrollment_date']}'.isEmpty) {
      if (payload['enrolled_at'] != null) {
        clean['enrollment_date'] = payload['enrolled_at'].toString().split('T').first;
      } else {
        clean['enrollment_date'] = localDateStr();
      }
    }
  }

  final nonText = nonTextColumns[tableName];
  if (nonText != null) {
    for (final key in nonText) {
      final v = clean[key];
      if (v == '' || v == null) {
        if (key == 'created_at' || key == 'updated_at') {
          clean.remove(key);
        } else {
          clean[key] = null;
        }
      }
    }
  }

  clean['tenant_id'] = tenantId;
  return clean;
}

int _pendingSeq = 1;

/// مطابق لـ queuePendingSync في sync.ts
void queuePendingSync(
  List<PendingSync> queue, {
  required String tableName,
  required String recordId,
  required String action,
  Map<String, dynamic>? payload,
  String tenantId = '',
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  // الدمج لا يتخطى حدود المنشأة: عملية منشأة أخرى على المعرّف نفسه تبقى لها
  final existingIdx = queue.indexWhere(
    (e) =>
        e.tableName == tableName &&
        e.recordId == recordId &&
        (tenantId.isEmpty || e.tenantId.isEmpty || e.tenantId == tenantId),
  );

  if (existingIdx >= 0) {
    final existing = queue[existingIdx];
    if (action == 'DELETE') {
      if (existing.action == 'INSERT') {
        queue.removeAt(existingIdx);
        return;
      }
      existing.action = 'DELETE';
      existing.payload = null;
      existing.createdAt = now;
      existing.retryCount = 0;
      existing.lastError = null;
      return;
    }

    existing.payload = {
      ...?existing.payload,
      ...?payload,
      'id': recordId,
    };
    existing.createdAt = now;
    existing.retryCount = 0;
    existing.lastError = null;
    return;
  }

  queue.add(
    PendingSync(
      id: _pendingSeq++,
      tenantId: tenantId,
      tableName: tableName,
      recordId: recordId,
      action: action,
      payload: payload,
      createdAt: now,
    ),
  );
}

void cleanupBogusDemoUserSyncs(List<PendingSync> queue) {
  queue.removeWhere((a) => a.tableName == 'users' && a.action == 'DELETE' && (a.payload == null || a.payload!['name'] == null));
}

String describeRecord(String table, Map<String, dynamic>? payload, Map<String, dynamic>? fallback) {
  final r = payload ?? fallback ?? const <String, dynamic>{};
  switch (table) {
    case 'students':
      final full = '${r['full_name'] ?? ''}'.trim();
      if (full.isNotEmpty) return full;
      final name = '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
      return name.isEmpty ? 'طالب' : name;
    case 'payments':
      return r['receipt_number'] != null ? 'سند ${r['receipt_number']}' : 'سند قبض';
    case 'teachers':
    case 'users':
    case 'subjects':
    case 'rooms':
    case 'groups':
      return '${r['name'] ?? '—'}';
    case 'installments':
      return '${r['title'] ?? 'قسط'}';
    case 'expenses':
      return '${r['description'] ?? r['category'] ?? 'مصروف'}';
    case 'grade_fees':
      return '${r['grade_name'] ?? 'رسوم صف'}';
    case 'sessions':
      return r['session_date'] != null ? 'حصة ${r['session_date']}' : 'حصة';
    case 'attendance':
      return 'سجل حضور';
    case 'enrollments':
      return 'تسجيل في مجموعة';
    case 'teacher_payouts':
      return 'مستحق معلم';
    case 'student_attachments':
      return 'مرفقات طالب';
    case 'student_evaluations':
      return '${r['title'] ?? ''}'.trim().isEmpty ? 'تقييم طالب' : 'تقييم ${r['title']}';
    case 'class_announcements':
      return '${r['title'] ?? 'إعلان صفّي'}';
    case 'institution_settings':
      return 'الشعار والألوان';
    default:
      return '—';
  }
}

/// أخطاء النقل: انقطاع شبكة أو تعذّر وصول، لا عيب في البيانات.
final _transientError = RegExp(
  r'Failed to fetch|NetworkError|fetch failed|SocketException|ClientException|'
  r'Connection (closed|refused|reset|timed out)|HandshakeException|TimeoutException|'
  r'HTTP 5\d\d|HTTP 429|Broken pipe|Software caused connection abort',
  caseSensitive: false,
);

/// هل هذا الخطأ عابر (شبكة/خادم) بحيث لا يُحتسب على رصيد المحاولات؟
///
/// احتسابه كان يحرق المحاولات الخمس على جهاز بشبكة ضعيفة، فتُركن سجلات
/// سليمة تماماً في «المتعثرة» ولا يُعاد رفعها تلقائياً أبداً.
bool isTransientSyncError(Object error) => _transientError.hasMatch(error.toString());

/// تعارض رقم سند صدر مرتين من جهازين كانا يعملان بلا اتصال —
/// قيد `uq_payments_tenant_receipt` في السحابة.
bool isDuplicateReceiptError(Object error) {
  final raw = error.toString().toLowerCase();
  final duplicate = raw.contains('duplicate key') || raw.contains('23505');
  return duplicate && raw.contains('receipt');
}

String describeSupabaseError(Object error, String tableName) {
  final raw = error.toString();
  final table = tableLabelsAr[tableName] ?? tableName;

  if (RegExp(r'invalid input syntax for type (date|timestamp)', caseSensitive: false).hasMatch(raw)) {
    return '$table: قيمة تاريخ غير صالحة في أحد الحقول.';
  }
  if (RegExp(r'invalid input syntax for type (numeric|integer|bigint)', caseSensitive: false).hasMatch(raw)) {
    return '$table: قيمة رقمية غير صالحة في أحد الحقول.';
  }
  if (RegExp(r'invalid input syntax for type uuid', caseSensitive: false).hasMatch(raw)) {
    return '$table: معرّف غير صالح.';
  }
  if (RegExp(r'duplicate key value|already exists', caseSensitive: false).hasMatch(raw)) {
    return '$table: هذا السجل مسجَّل مسبقاً برقم أو معرّف مكرّر.';
  }
  if (RegExp(r'violates not-null constraint', caseSensitive: false).hasMatch(raw)) {
    final col = RegExp(r'column "([^"]+)"').firstMatch(raw)?.group(1);
    return '$table: حقل إلزامي فارغ${col != null ? ' ($col)' : ''}.';
  }
  if (RegExp(r'violates foreign key constraint', caseSensitive: false).hasMatch(raw)) {
    return '$table: السجل مرتبط بسجل آخر غير موجود في السحابة. ارفع السجل الأصل أولاً.';
  }
  if (RegExp(r'PGRST303|jwt expired|invalid claim', caseSensitive: false).hasMatch(raw)) {
    return '$table: انتهت جلسة الدخول. سجّل الخروج ثم الدخول من جديد ليُعاد الرفع.';
  }
  if (RegExp(r'PGRST204|could not find|schema cache', caseSensitive: false).hasMatch(raw)) {
    final col = RegExp(r"'([^']+)' column").firstMatch(raw)?.group(1);
    return '$table: العمود ${col ?? 'المطلوب'} غير موجود في قاعدة البيانات. نفّذ ملف الهجرة على Supabase.';
  }
  if (RegExp(r'Failed to fetch|NetworkError|fetch failed|SocketException|ClientException', caseSensitive: false).hasMatch(raw)) {
    return 'تعذّر الوصول إلى السحابة. تحقق من الاتصال بالإنترنت.';
  }
  return '$table: $raw';
}

/// تراجعٌ عن المؤشر قبل الجلب: ساعة السيرفر قد تسبق كتابة صفٍّ بلحظة، فسجل
/// كُتب أثناء السحب السابق كان يُفوَّت إلى الأبد.
const cursorOverlapMs = 60 * 1000;

/// معرّفات الطلب الواحد عند الجلب بالمعرّفات، وما زاد عن الحد يُجلب صفحاتٍ.
const idFetchChunk = 100;
const maxIdFetch = 1000;

/// مؤشر سجل المحذوفات — يُحفظ كما تُحفظ مؤشرات الجداول.
const deletesCursor = '__deleted_records';

/// ما يستحق الجلب: السجل الذي يختلف ختم السيرفر عليه عمّا عندنا.
///
/// يُقارن ختم السيرفر لا `updated_at`: الأخير يكتبه الجهاز بساعته لحظة التعديل،
/// فتعديلٌ رُفع متأخراً يحمل وقتاً أقدم من آخر سحب للأجهزة الأخرى فلا تراه أبداً.
List<String> pickChangedIds(List<Map<String, dynamic>> remote, Map<String, String> localStamps) => [
      for (final r in remote)
        if (toTimestamp(localStamps['${r['id']}']) != toTimestamp(r['server_updated_at'])) '${r['id']}',
    ];

/// حذف قادم من السحابة يُطبَّق ما لم يكن للسجل تعديل معلّق، أو نسخة أُنشئت بعده.
bool shouldApplyRemoteDelete({
  required bool existsLocally,
  required String? localStamp,
  required String deletedAt,
  required bool isPending,
}) {
  if (!existsLocally || isPending) return false;
  return toTimestamp(localStamp) <= toTimestamp(deletedAt);
}

/// الأحدث بين ختمين.
String? laterStamp(String? current, String? candidate) {
  if (candidate == null || candidate.isEmpty) return current;
  if (current == null || current.isEmpty) return candidate;
  return toTimestamp(candidate) > toTimestamp(current) ? candidate : current;
}

/// السجلات التي حُذفت من السحابة فيجب أن تُحذف من الجهاز.
///
/// القاعدة — مطابقة لتوفيق الحذف في `pullFromCloud` بالنسخة المكتبية:
///  - `synced` وحدها تُحذف: ما لم يُرفع بعد شغلٌ للمستخدم لا نسخةٌ من السحابة.
///  - ما له عملية في الطابور يُترك لها.
///  - وبعد أول سحب: ما عُدّل بعد آخر ختم يُترك لجولة قادمة، فقد يكون سبق الحذف.
List<String> rowsDeletedInCloud({
  required Iterable<Map<String, dynamic>> local,
  required Set<String> cloudIds,
  required Set<String> pendingIds,
  required String? lastPullAt,
}) {
  return [
    for (final r in local)
      if (r['sync_status'] == 'synced' &&
          !cloudIds.contains('${r['id']}') &&
          !pendingIds.contains('${r['id']}') &&
          (lastPullAt == null ||
              r['updated_at'] == null ||
              toTimestamp(r['updated_at']) < toTimestamp(lastPullAt)))
        '${r['id']}',
  ];
}

/// مخزن محلي يوفّر لخدمة المزامنة ما يوفّره Dexie في التطبيق المكتبي.
abstract class SyncLocalStore {
  String? get tenantId;

  /// المنشأة التي تخصّها البيانات المحفوظة على هذا الجهاز، أو `null` لجهاز جديد.
  String? get dbTenantId;
  bool get isMaster;
  List<PendingSync> get pendingSyncs;
  Map<String, dynamic>? recordOf(String table, String id);
  List<Map<String, dynamic>> allOf(String table);
  void putRows(String table, List<Map<String, dynamic>> rows);

  /// ختم السيرفر المحفوظ لسجل، أو `null` إن لم يصل من السحابة بعد.
  String? serverStamp(String table, String id);

  /// أختام جدول كامل — لمقارنة ما تغيّر في السحابة بما عندنا.
  Map<String, String> serverStampsOf(String table);

  void rememberServerStamps(String table, Map<String, String> stamps);

  void forgetServerStamps(String table, Iterable<String> ids);
  void removeIds(String table, List<String> ids);
  void markSynced(String table, String id);
  void notifySync();

  /// ما يجري بعد اكتمال سحب: قراءة الإعدادات التي وصلت مع الصفوف.
  Future<void> onPulled();

  /// إعادة حساب أرصدة الطلاب من سجلاتهم بعد السحب. تعيد عدد ما صُحِّح.
  int recalculateAllBalances();

  /// منح سند رقماً جديداً متاحاً بعد تعارض رقمه مع سند آخر. يعيد الرقم الجديد،
  /// أو `null` إن لم يعد السند موجوداً.
  String? reissueReceiptNumber(String paymentId);
}

class SyncService {
  SyncService(this.local);

  final SyncLocalStore local;
  bool _syncing = false;
  final remotePendingIds = <String>{};

  /// جداول غير منشورة في قاعدة هذه المنشأة — هجرتها لم تُطبَّق بعد. تُتخطّى في
  /// السحب والفحص بدل أن تُعدّ عطلاً: وإلا بقي كل سحب «ناقصاً» فلا يتقدّم ختمه،
  /// ويُعاد جلب التعديلات نفسها في كل مرة، ولا يُعلَن «متزامن» أبداً.
  final missingTables = <String>{};

  int get remotePendingCount => remotePendingIds.length;
  bool get isSyncing => _syncing;

  /// آخر مرة سُئلت فيها السحابة عن تغييرات.
  DateTime? lastRemoteCheck;

  /// هل نعرف حالة السحابة الآن؟ يقادم العهد يجعل «متزامن» ادّعاءً لا خبراً.
  bool get remoteStateKnown {
    final at = lastRemoteCheck;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(minutes: 3);
  }

  int getPendingCount() {
    cleanupBogusDemoUserSyncs(local.pendingSyncs);
    return local.pendingSyncs.length;
  }

  PendingSummary getPendingSummary() {
    cleanupBogusDemoUserSyncs(local.pendingSyncs);
    final actions = [...local.pendingSyncs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final bucket = <String, int>{};
    final items = <PendingSummaryItem>[];

    for (final a in actions) {
      final key = '${a.tableName}|${a.action}';
      bucket[key] = (bucket[key] ?? 0) + 1;
      if (items.length < 40) {
        items.add(
          PendingSummaryItem(
            table: a.tableName,
            action: a.action,
            label: describeRecord(a.tableName, a.payload, local.recordOf(a.tableName, a.recordId)),
            at: a.createdAt,
          ),
        );
      }
    }

    final rows = bucket.entries
        .map((e) {
          final parts = e.key.split('|');
          return SyncRow(parts[0], e.value, parts.length > 1 ? parts[1] : '');
        })
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return PendingSummary(total: actions.length, rows: rows, items: items);
  }

  String lastPullKey(String tenantId) => 'last_pull_at_$tenantId';

  /// نوع الجلسة وبصمة الأعمدة اللذان سحب بهما الجهاز آخر مرة — يُحفظان بجوار الختم.
  String lastPullAuthKey(String tenantId) => 'last_pull_auth_$tenantId';

  /// علامة السحب: `session` أو `anon`، ومعها [pullColumnsSignature].
  String pullMarkFor({required bool signedIn}) => '${signedIn ? 'session' : 'anon'}:$pullColumnsSignature';

  String get _pullAuthMark => pullMarkFor(signedIn: SupabaseAuth.signedIn);

  /// ختم آخر سحب ناجح، أو `null` لسحب كامل.
  ///
  /// الختم الذي سُجّل بجلسة غير الجلسة الحالية لا يُعتمد: سحبٌ بلا دخول يُعاد له
  /// من القاعدة المحمية صفرُ سجل بلا خطأ، فيُسجَّل ختماً «ناجحاً» — ثم يطلب كل سحب
  /// تزايدي بعده ما تغيّر بعد ذلك الختم وحده، فلا تصل السجلات القديمة أبداً.
  /// أول سحب بعد الدخول يعود كاملاً فيُصلح الجهاز من تلقاء نفسه.
  ///
  /// ولا يُعتمد كذلك ختمٌ سُجّل بأعمدة غير الأعمدة الحالية — انظر [pullColumnsSignature].
  Future<String?> getLastPullAt() async {
    final tenantId = local.tenantId;
    if (tenantId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(lastPullAuthKey(tenantId)) != _pullAuthMark) return null;
    return prefs.getString(lastPullKey(tenantId));
  }

  Future<void> _setLastPullAt(String tenantId, String iso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastPullKey(tenantId), iso);
    await prefs.setString(lastPullAuthKey(tenantId), _pullAuthMark);
  }

  Future<RemoteChangeSummary> checkRemoteChanges() async {
    final tenantId = local.tenantId;
    if (tenantId == null) {
      return RemoteChangeSummary(total: 0, rows: [], items: [], since: null);
    }

    final rows = <SyncRow>[];
    final items = <PendingSummaryItem>[];
    final allNewKeys = <String>[];
    var total = 0;
    var failed = false;

    // الجداول تُسأل معاً، والنتائج تُجمع بترتيبها
    final checks = await mapPooled(syncedTables, pullConcurrency, (cloud) async {
      String? cursor;
      final newIds = <String>[];
      final samples = <PendingSummaryItem>[];
      var tableFailed = false;
      try {
        cursor = await _cursor(tenantId, cloud);
        final localStamps = local.serverStampsOf(cloud);
        var from = 0;
        while (true) {
          // ختم السيرفر هو الفيصل: `updated_at` يكتبه الجهاز بساعته، فتعديلٌ
          // رُفع متأخراً كان يبدو «قديماً» فلا يُحسب تغييراً قادماً
          final page = await _select(
            cloud,
            tenantId,
            columns: 'id,server_updated_at',
            since: cursor,
            from: from,
            to: from + pullPageSize - 1,
            order: 'server_updated_at.desc',
          );
          if (page == null) {
            if (!missingTables.contains(cloud)) tableFailed = true;
            break;
          }
          newIds.addAll(pickChangedIds(page, localStamps));
          if (page.length < pullPageSize) break;
          from += page.length;
        }

        if (newIds.isNotEmpty) {
          final full = await _selectIn(cloud, tenantId, newIds.take(10).toList());
          for (final row in full) {
            samples.add(
              PendingSummaryItem(
                table: cloud,
                action: local.recordOf(cloud, '${row['id']}') != null ? 'UPDATE' : 'INSERT',
                label: describeRecord(cloud, row, null),
                at: '${row['updated_at'] ?? ''}',
              ),
            );
          }
        }
      } catch (_) {
        tableFailed = true;
      }
      return (cloud: cloud, cursor: cursor, newIds: newIds, samples: samples, failed: tableFailed);
    });

    // أقدم مؤشر جدول: يُعرض للمستخدم «منذ متى» لم يصله شيء
    String? since;
    for (final check in checks) {
      if (check.failed) failed = true;
      final cursor = check.cursor;
      since = since == null ? cursor : (toTimestamp(cursor) < toTimestamp(since) ? cursor : since);
      if (check.newIds.isEmpty) continue;
      rows.add(SyncRow(check.cloud, check.newIds.length));
      total += check.newIds.length;
      for (final id in check.newIds) {
        allNewKeys.add('${check.cloud}:$id');
      }
      items.addAll(check.samples);
    }

    // الحذف القادم تغييرٌ كبقيته: عدّه يمنع «متزامن» وفي السحابة حذفٌ لم يصل
    try {
      final deletes = await _pendingRemoteDeletes(tenantId);
      if (deletes.isNotEmpty) {
        rows.add(SyncRow('deleted_records', deletes.length));
        total += deletes.length;
        allNewKeys.addAll(deletes);
      }
    } catch (_) {
      failed = true;
    }

    items.sort((a, b) => b.at.compareTo(a.at));
    if (items.length > 40) items.removeRange(40, items.length);
    if (failed) {
      // فحص ناقص لا يُثبت خلوّ السحابة: يُضاف ما وُجد ولا يُمسح ما عُرف، ولا
      // يُسجَّل وقت فحص كان سيُظهر «متزامن» على غير حقيقة.
      remotePendingIds.addAll(allNewKeys);
    } else {
      lastRemoteCheck = DateTime.now();
      remotePendingIds
        ..clear()
        ..addAll(allNewKeys);
    }

    return RemoteChangeSummary(total: total, rows: rows..sort((a, b) => b.count.compareTo(a.count)), items: items, since: since);
  }

  /// مفاتيح ما حُذف في السحابة ولم يُطبَّق على الجهاز بعد.
  Future<List<String>> _pendingRemoteDeletes(String tenantId) async {
    final since = await _cursor(tenantId, deletesCursor);
    final keys = <String>[];

    for (var from = 0;; from += pullPageSize) {
      final page = await _select(
        'deleted_records',
        tenantId,
        columns: 'table_name,record_id,deleted_at',
        since: since,
        sinceColumn: 'deleted_at',
        from: from,
        to: from + pullPageSize - 1,
        order: 'deleted_at.asc',
      );
      if (page == null) return keys;

      for (final row in page) {
        final table = '${row['table_name'] ?? ''}';
        final id = '${row['record_id'] ?? ''}';
        if (table.isEmpty || id.isEmpty) continue;
        final pending = local.pendingSyncs.any((p) => p.tableName == table && p.recordId == id);
        final applies = shouldApplyRemoteDelete(
          existsLocally: local.recordOf(table, id) != null,
          localStamp: local.serverStamp(table, id),
          deletedAt: '${row['deleted_at'] ?? ''}',
          isPending: pending,
        );
        if (applies) keys.add('$table:$id');
      }

      if (page.length < pullPageSize) return keys;
    }
  }

  List<PendingSync> getFailedActions() {
    return local.pendingSyncs.where((a) => a.retryCount >= maxSyncRetries).toList();
  }

  /// كل عملية معلّقة سجّلت خطأً، سواء استنفدت محاولاتها أم لا.
  List<PendingSync> getStuckActions() {
    return local.pendingSyncs.where((a) => a.lastError != null).toList();
  }

  /// أسباب التعثّر مجمّعة: السبب → عدد السجلات المتأثرة به.
  Map<String, int> failureReasons() {
    final out = <String, int>{};
    for (final a in getStuckActions()) {
      final key = a.lastError ?? '';
      if (key.isEmpty) continue;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  /// [refreshRemote] يفحص بعد الرفع ما تغيّر في السحابة لعدّاد الواجهة — جولة
  /// على كل الجداول. الرفع التلقائي يستغني عنها: السحب يليه عند أي إشارة.
  Future<SyncResult> push({bool refreshRemote = true}) async {
    if (_syncing) return SyncResult(success: false, message: 'عملية مزامنة أخرى جارية');
    if (local.isMaster) {
      return SyncResult(success: false, message: 'وضع المطور لا يقوم بمزامنة بيانات المدارس');
    }
    final tenantId = local.tenantId;
    if (tenantId == null) return SyncResult(success: false, message: 'لا توجد منشأة محددة');
    // القاعدة المحلية لمنشأة أخرى: لا يُرفع إليها ولا يُسحب فوقها قبل تبديلها
    final dbTenant = local.dbTenantId;
    if (dbTenant != null && dbTenant != tenantId) {
      return SyncResult(success: false, message: 'البيانات المحلية تخص منشأة أخرى. أعد تسجيل الدخول.');
    }

    _syncing = true;
    try {
      final result = await pushPendingChanges(tenantId);
      if (result.pushed > 0 && refreshRemote) {
        try {
          await checkRemoteChanges();
        } catch (_) {}
      }
      local.notifySync();
      String message;
      if (result.failed > 0) {
        // السبب يُذكر هنا مباشرةً: تبويب الإعدادات قد يكون محجوباً عن صلاحية
        // المستخدم، فإحالته إليه تتركه بلا تفسير لما جرى.
        final stuck = local.pendingSyncs.where((a) => a.lastError != null).toList();
        final reason = stuck.firstOrNull?.lastError;
        message = 'تم رفع ${result.pushed} تعديلاً، وتعذّر رفع ${result.failed}.'
            '${reason != null ? '\nالسبب: $reason' : ''}';
      } else {
        message = 'تم رفع ${result.pushed} تعديلاً بنجاح';
      }
      return SyncResult(success: result.failed == 0, message: message, pushed: result.pushed, failed: result.failed);
    } catch (err) {
      return SyncResult(success: false, message: err.toString());
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> pull() async {
    if (_syncing) return SyncResult(success: false, message: 'عملية مزامنة أخرى جارية');
    if (local.isMaster) {
      return SyncResult(success: false, message: 'وضع المطور لا يقوم بمزامنة بيانات المدارس');
    }
    final tenantId = local.tenantId;
    if (tenantId == null) return SyncResult(success: false, message: 'لا توجد منشأة محددة');
    // القاعدة المحلية لمنشأة أخرى: لا يُرفع إليها ولا يُسحب فوقها قبل تبديلها
    final dbTenant = local.dbTenantId;
    if (dbTenant != null && dbTenant != tenantId) {
      return SyncResult(success: false, message: 'البيانات المحلية تخص منشأة أخرى. أعد تسجيل الدخول.');
    }

    _syncing = true;
    try {
      final result = await pullFromCloud(tenantId);
      // هوية المنشأة تصل ضمن السحب: تُقرأ فوراً ليظهر الشعار واللون المعتمد
      await local.onPulled();
      final removedNote = result.removed > 0 ? ' وحُذف ${result.removed} سجلاً محذوفاً من السحابة' : '';
      local.notifySync();

      if (!result.isComplete) {
        final names = result.failedTables.keys.map((t) => tableLabelsAr[t] ?? t).join('، ');
        return SyncResult(
          success: false,
          message: 'سحب ناقص: تم سحب ${result.pulled} سجلاً$removedNote، '
              'وتعذّر جلب ($names). ${result.failedTables.values.first}',
          pulled: result.pulled,
          removed: result.removed,
        );
      }

      return SyncResult(
        success: true,
        message: 'تم سحب ${result.pulled} سجلاً$removedNote',
        pulled: result.pulled,
        removed: result.removed,
      );
    } catch (err) {
      return SyncResult(success: false, message: err.toString());
    } finally {
      _syncing = false;
    }
  }

  /// مزامنة كاملة: رفع ثم سحب — المقابل لـ `syncAll` في النسخة المكتبية.
  ///
  /// الرفع يسبق السحب دائماً: السحب أولاً كان يجلب النسخة السحابية الأقدم
  /// فوق تعديل محلي لم يُرفع بعد، فيبدو للمستخدم أن تعديله «رجع».
  Future<SyncResult> syncAll() async {
    final pushResult = await push();
    if (!pushResult.success && pushResult.pushed == 0 && getPendingCount() > 0) {
      return pushResult;
    }
    final pullResult = await pull();
    return SyncResult(
      success: pushResult.success && pullResult.success,
      message: '${pushResult.message} · ${pullResult.message}',
      pushed: pushResult.pushed,
      pulled: pullResult.pulled,
      failed: pushResult.failed,
      removed: pullResult.removed,
    );
  }

  Future<({int pushed, int failed})> pushPendingChanges(String tenantId) async {
    // عمليات منشأة أخرى لا تُرفع إلى سحابة هذه: بقايا جهاز انتقل بين منشأتين
    final all = [...local.pendingSyncs.where((a) => a.tenantId.isEmpty || a.tenantId == tenantId)];
    final actions = all.where((a) => a.retryCount < maxSyncRetries).toList();
    if (actions.isEmpty) return (pushed: 0, failed: all.length);

    var pushed = 0;
    var failed = 0;

    final deletesByTable = <String, List<PendingSync>>{};
    final writesByTable = <String, List<PendingSync>>{};
    for (final a in actions) {
      final bucket = a.action == 'DELETE' ? deletesByTable : writesByTable;
      bucket.putIfAbsent(a.tableName, () => []).add(a);
    }

    // ترتيب الجداول حسب تبعية المفاتيح الأجنبية.
    //
    // `syncedTables` مرتّبة من الأصل إلى الفرع (المعلمون ثم المجموعات ثم
    // الطلاب ثم الدفعات). ترك الترتيب على ترتيب الطابور كان يرفع الدفعة قبل
    // صاحبها فيرفضها القيد الأجنبي، ويُحتسب ذلك فشلاً على سجل سليم.
    // الحذف يسير عكس ذلك: الفروع أولاً حتى لا نحذف أصلاً ما زال مرتبطاً.
    List<String> ordered(Iterable<String> names, {required bool reverse}) {
      final list = names.toList()
        ..sort((a, b) {
          final ia = syncedTables.indexOf(a);
          final ib = syncedTables.indexOf(b);
          return (ia < 0 ? syncedTables.length : ia).compareTo(ib < 0 ? syncedTables.length : ib);
        });
      return reverse ? list.reversed.toList() : list;
    }

    for (final tableName in ordered(deletesByTable.keys, reverse: true)) {
      final list = deletesByTable[tableName]!;
      for (var i = 0; i < list.length; i += pushChunk) {
        final chunk = list.sublist(i, (i + pushChunk).clamp(0, list.length));
        final ids = chunk.map((a) => a.recordId).where((id) => id.isNotEmpty).toList();
        if (ids.isEmpty) continue;
        try {
          await _deleteIds(tableName, tenantId, ids);
          pushed += chunk.length;
          local.pendingSyncs.removeWhere((p) => chunk.any((c) => c.id == p.id));
        } catch (err) {
          failed += chunk.length;
          _markFailed(chunk, describeSupabaseError(err, tableName), transient: isTransientSyncError(err));
        }
      }
    }

    for (final tableName in ordered(writesByTable.keys, reverse: false)) {
      final list = writesByTable[tableName]!;
      for (var i = 0; i < list.length; i += pushChunk) {
        final chunk = list.sublist(i, (i + pushChunk).clamp(0, list.length));
        final rows = <Map<String, dynamic>>[];
        final kept = <PendingSync>[];
        for (final action in chunk) {
          final recordId = action.recordId.isNotEmpty ? action.recordId : '${action.payload?['id'] ?? ''}';
          if (recordId.isEmpty) continue;
          var fullRecord = {...?action.payload};
          final localRec = local.recordOf(tableName, recordId);
          if (localRec != null) {
            fullRecord = {...localRec, ...?action.payload, 'id': recordId};
          } else {
            fullRecord = {...fullRecord, 'id': recordId};
          }
          // جلسة بلا مجموعة تنتهك قيود السحابة ولن تُقبل مهما أُعيدت
          if (tableName == 'sessions' && '${fullRecord['group_id'] ?? ''}'.isEmpty) {
            local.pendingSyncs.removeWhere((p) => p.id == action.id);
            continue;
          }

          rows.add(sanitizePayload(tableName, fullRecord, tenantId));
          kept.add(action);
        }
        if (rows.isEmpty) continue;

        try {
          await _upsert(tableName, rows);
          pushed += kept.length;
          local.pendingSyncs.removeWhere((p) => kept.any((c) => c.id == p.id));
          for (final a in kept) {
            local.markSynced(tableName, a.recordId);
          }
        } catch (err) {
          // الشبكة مقطوعة: إعادة المحاولة صفاً صفاً تعني 50 نداءً فاشلاً بلا
          // فائدة. نُسجّل السبب بلا استهلاك محاولات ونتوقف — الطابور سليم
          // وسيُرفع كما هو عند عودة الاتصال.
          if (isTransientSyncError(err)) {
            _markFailed(kept, describeSupabaseError(err, tableName), transient: true);
            failed += kept.length;
            return (pushed: pushed, failed: failed + (all.length - actions.length));
          }

          // صف واحد معطوب يُسقط الدفعة كلها، فتُعاد صفاً صفاً لعزله وحده
          var rowFailed = 0;
          for (var k = 0; k < rows.length; k++) {
            try {
              await _upsert(tableName, [rows[k]]);
              pushed++;
              local.pendingSyncs.removeWhere((p) => p.id == kept[k].id);
              local.markSynced(tableName, kept[k].recordId);
            } catch (rowErr) {
              // سندان برقم واحد صدرا من جهازين بلا اتصال: يُمنح هذا السند رقماً
              // متاحاً ويُحفظ رقمه الورقي في بيانه، بدل انتظار تدخل يدوي من المدير
              if (tableName == 'payments' && isDuplicateReceiptError(rowErr)) {
                final reissued = await _retryWithFreshReceipt(kept[k], tenantId);
                if (reissued) {
                  pushed++;
                  continue;
                }
              }
              rowFailed++;
              _markFailed(
                [kept[k]],
                describeSupabaseError(rowErr, tableName),
                transient: isTransientSyncError(rowErr),
              );
            }
          }
          failed += rowFailed;
        }
      }
    }

    return (pushed: pushed, failed: failed + (all.length - actions.length));
  }

  /// إعادة رفع سند برقم جديد بعد تعارض رقمه. يعيد `true` إن نجح الرفع.
  Future<bool> _retryWithFreshReceipt(PendingSync action, String tenantId) async {
    if (local.reissueReceiptNumber(action.recordId) == null) return false;
    final updated = local.recordOf('payments', action.recordId);
    if (updated == null) return false;
    try {
      await _upsert('payments', [sanitizePayload('payments', updated, tenantId)]);
      local.pendingSyncs.removeWhere((p) => p.id == action.id);
      local.markSynced('payments', action.recordId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// تسجيل فشل محاولة رفع.
  ///
  /// [transient] يعني خطأ نقل (شبكة أو خادم): تُحفظ الرسالة ولا يُستهلك رصيد
  /// المحاولات، لأن السجل سليم ولا ذنب له في انقطاع الاتصال.
  void _markFailed(List<PendingSync> actions, String message, {bool transient = false}) {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final a in actions) {
      if (!transient) a.retryCount = a.retryCount + 1;
      a.lastError = message;
      a.lastAttemptAt = now;
    }
  }

  /// إعادة السجلات المتعثرة إلى الطابور النشط — المقابل لزر إعادة المحاولة
  /// في `FailedSyncPanel`. يعيد عدد ما أُعيد تفعيله.
  int retryFailedActions() {
    final failed = getFailedActions();
    for (final a in failed) {
      a.retryCount = 0;
      a.lastError = null;
    }
    if (failed.isNotEmpty) local.notifySync();
    return failed.length;
  }

  /// إسقاط سجل متعثر نهائياً بعد أن يقرر المستخدم التخلي عنه.
  void discardAction(PendingSync action) {
    local.pendingSyncs.removeWhere((a) => a.id == action.id);
    local.notifySync();
  }
  /// جلب ما تغيّر في السحابة ودمجه محلياً — مطابق لـ `pullFromCloud`.
  ///
  /// لكل جدول مؤشر بختم السيرفر: أول سحب يجلب الجدول كاملاً، وما بعده يجلب
  /// المعرّفات والأختام منذ المؤشر ثم السجلات المختلفة عمّا عندنا وحدها. والحذف
  /// يصل من سجل المحذوفات الذي تملؤه القاعدة، فلا تُجلب معرّفات الجداول كلها.
  ///
  /// ختم السيرفر هو الفيصل لا `updated_at`: الأخير يكتبه الجهاز بساعته، فتعديلٌ
  /// رُفع متأخراً كان يحمل وقتاً أقدم من آخر سحب لجهاز آخر فلا يصله أبداً.
  ///
  /// ولا يُكتب فوق سجل له تعديل معلّق محلياً، ولا فوق نسخة معلّقة أحدث.
  Future<PullOutcome> pullFromCloud(String tenantId) async {
    var totalPulled = 0;
    var totalRemoved = 0;
    final failedTables = <String, String>{};

    // عمودٌ جديد في التطبيق لا يغيّر ختم السيرفر لسجل قديم، فلا يصل أبداً:
    // تغيّر بصمة الأعمدة يُصفّر المؤشرات فيعود السحب التالي كاملاً مرة واحدة
    await _resetCursorsIfColumnsChanged(tenantId);

    // الجلب شبكيٌّ فيُطلب للجداول معاً، والتطبيق محليٌّ فيسير بترتيب الجداول بعده
    // مرفقات الطلاب لا تُسحب دورياً: صور Base64 تُجلب عند فتح ملف الطالب وحده
    final tables = syncedTables.where((t) => t != 'student_attachments').toList();
    final fetched = await mapPooled(tables, pullConcurrency, (cloud) => _fetchTableChanges(cloud, tenantId));

    for (final f in fetched) {
      final cloud = f.cloud;
      if (f.error != null) {
        failedTables[cloud] = f.error!;
        continue;
      }
      final rows = f.rows;
      if (rows == null) continue;

      try {
        final pendingIds = local.pendingSyncs.where((p) => p.tableName == cloud).map((p) => p.recordId).toSet();
        final toWrite = <Map<String, dynamic>>[];
        final stamps = <String, String>{};

        for (final record in rows) {
          final id = '${record['id']}';
          if (pendingIds.contains(id)) continue;

          final loc = local.recordOf(cloud, id);
          if (loc != null &&
              loc['sync_status'] == 'pending' &&
              toTimestamp(loc['updated_at']) > toTimestamp(record['updated_at']) + stampToleranceMs) {
            continue;
          }

          final rest = Map<String, dynamic>.from(record)..remove('tenant_id');
          final stamp = '${rest.remove('server_updated_at') ?? ''}';
          if (stamp.isNotEmpty) stamps[id] = stamp;
          if (cloud == 'enrollments' && (rest['enrolled_at'] == null || '${rest['enrolled_at']}'.isEmpty) && rest['enrollment_date'] != null) {
            rest['enrolled_at'] = rest['enrollment_date'];
          }
          rest['sync_status'] = 'synced';
          toWrite.add(rest);
        }

        if (toWrite.isNotEmpty) {
          local.putRows(cloud, toWrite);
          local.rememberServerStamps(cloud, stamps);
          totalPulled += toWrite.length;
        }

        // الجلب الكامل يعرف السحابة كلها: سجلٌ مُزامَن غائب عنها حُذف هناك. وما
        // كُتب محلياً قُبيل بدء الجلب قد يكون رُفع للتوّ فلا يُحكم عليه.
        if (f.since == null) {
          final cloudIds = rows.map((r) => '${r['id']}').toSet();
          final toRemove = [
            for (final r in local.allOf(cloud))
              if (r['sync_status'] == 'synced' &&
                  !cloudIds.contains('${r['id']}') &&
                  !pendingIds.contains('${r['id']}') &&
                  toTimestamp(r['updated_at']) < f.startedAt - cursorOverlapMs)
                '${r['id']}',
          ];
          if (toRemove.isNotEmpty) {
            local.removeIds(cloud, toRemove);
            totalRemoved += toRemove.length;
          }
        }

        await _setCursor(tenantId, cloud, f.maxStamp);
      } catch (err) {
        failedTables[cloud] = describeSupabaseError(err, cloud);
      }
    }

    totalRemoved += await _applyRemoteDeletes(tenantId);

    // أرصدة الطلاب تُعاد من السجلات بعد كل سحب: أجهزة مختلفة قد تكون كتبت
    // أرقاماً مختلفة للرصيد نفسه، والحساب من السجلات يوحّدها بلا كتابة جديدة.
    if (totalPulled > 0 || totalRemoved > 0) local.recalculateAllBalances();

    remotePendingIds.clear();
    lastRemoteCheck = DateTime.now();
    if (failedTables.isEmpty) {
      await _setLastPullAt(tenantId, DateTime.now().toUtc().toIso8601String());
    }
    return PullOutcome(pulled: totalPulled, removed: totalRemoved, failedTables: failedTables);
  }

  /// الشقّ الشبكي من سحب جدول: ما تغيّر منذ مؤشره، بلا لمس للبيانات المحلية.
  ///
  /// [rows] `null` مع [error] فارغ يعني جدولاً غير موجود في قاعدة المنشأة بعد.
  Future<({String cloud, String? since, int startedAt, String? maxStamp, List<Map<String, dynamic>>? rows, String? error})>
      _fetchTableChanges(String cloud, String tenantId) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    String? since;
    try {
      since = await _cursor(tenantId, cloud);
      var maxStamp = since;
      List<Map<String, dynamic>>? rows;

      if (since == null) {
        rows = await _fetchPages(cloud, tenantId, null);
        for (final r in rows ?? const <Map<String, dynamic>>[]) {
          maxStamp = laterStamp(maxStamp, '${r['server_updated_at'] ?? ''}');
        }
      } else {
        final changed = await _findChanged(cloud, tenantId, since);
        if (changed == null) {
          final error = missingTables.contains(cloud) ? null : 'تعذّر جلب بيانات ${tableLabelsAr[cloud] ?? cloud} من السحابة.';
          return (cloud: cloud, since: since, startedAt: startedAt, maxStamp: maxStamp, rows: null, error: error);
        }
        maxStamp = changed.maxStamp;
        rows = changed.ids.isEmpty
            ? <Map<String, dynamic>>[]
            : changed.ids.length > maxIdFetch
                ? await _fetchPages(cloud, tenantId, since)
                : await _fetchByIds(cloud, tenantId, changed.ids);
      }

      final error = rows == null && !missingTables.contains(cloud)
          ? 'تعذّر جلب بيانات ${tableLabelsAr[cloud] ?? cloud} من السحابة.'
          : null;
      return (cloud: cloud, since: since, startedAt: startedAt, maxStamp: maxStamp, rows: rows, error: error);
    } catch (err) {
      return (cloud: cloud, since: since, startedAt: startedAt, maxStamp: since, rows: null, error: describeSupabaseError(err, cloud));
    }
  }

  /// ما حُذف في السحابة منذ آخر سحب، من سجل المحذوفات الذي تملؤه القاعدة.
  ///
  /// إعادة تطبيق حذف قديم لا تضرّ: سجلٌ أُعيد إنشاؤه بعده يحمل ختماً أحدث فيبقى.
  Future<int> _applyRemoteDeletes(String tenantId) async {
    var since = await _cursor(tenantId, deletesCursor);
    var maxStamp = since;
    var removed = 0;

    for (var from = 0;; from += pullPageSize) {
      final page = await _select(
        'deleted_records',
        tenantId,
        columns: 'table_name,record_id,deleted_at',
        since: since,
        sinceColumn: 'deleted_at',
        from: from,
        to: from + pullPageSize - 1,
        order: 'deleted_at.asc',
      );
      // الجدول غير منشور بعد (هجرة لم تُنفَّذ): الحذف يُكتشف بالسحب الكامل
      if (page == null) return removed;

      for (final row in page) {
        final table = '${row['table_name'] ?? ''}';
        final id = '${row['record_id'] ?? ''}';
        final deletedAt = '${row['deleted_at'] ?? ''}';
        maxStamp = laterStamp(maxStamp, deletedAt);
        if (table.isEmpty || id.isEmpty || !syncedTables.contains(table)) continue;

        final pending = local.pendingSyncs.any((p) => p.tableName == table && p.recordId == id);
        final applies = shouldApplyRemoteDelete(
          existsLocally: local.recordOf(table, id) != null,
          localStamp: local.serverStamp(table, id),
          deletedAt: deletedAt,
          isPending: pending,
        );
        if (!applies) continue;
        local.removeIds(table, [id]);
        removed++;
      }

      if (page.length < pullPageSize) break;
    }

    await _setCursor(tenantId, deletesCursor, maxStamp);
    return removed;
  }

  /// ما تغيّر في جدول منذ المؤشر ولا نملك نسخته، بجلب المعرّفات والأختام وحدها.
  /// ما رفعناه نحن يعود بالختم المحفوظ عندنا نفسه فلا يُجلب ثانيةً.
  Future<({List<String> ids, String? maxStamp})?> _findChanged(
    String cloud,
    String tenantId,
    String since,
  ) async {
    final localStamps = local.serverStampsOf(cloud);
    final ids = <String>[];
    String? maxStamp = since;

    for (var from = 0;; from += pullPageSize) {
      final page = await _select(
        cloud,
        tenantId,
        columns: 'id,server_updated_at',
        since: since,
        sinceColumn: 'server_updated_at',
        from: from,
        to: from + pullPageSize - 1,
        order: 'server_updated_at.asc',
      );
      if (page == null) return null;

      ids.addAll(pickChangedIds(page, localStamps));
      for (final row in page) {
        maxStamp = laterStamp(maxStamp, '${row['server_updated_at'] ?? ''}');
      }
      if (page.length < pullPageSize) return (ids: ids, maxStamp: maxStamp);
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchPages(String cloud, String tenantId, String? since) async {
    final all = <Map<String, dynamic>>[];
    for (var from = 0;; from += pullPageSize) {
      final page = await _select(
        cloud,
        tenantId,
        since: since,
        sinceColumn: 'server_updated_at',
        from: from,
        to: from + pullPageSize - 1,
        order: 'id.asc',
      );
      if (page == null) return null;
      all.addAll(page);
      if (page.length < pullPageSize) return all;
    }
  }

  Future<List<Map<String, dynamic>>?> _fetchByIds(String cloud, String tenantId, List<String> ids) async {
    final all = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += idFetchChunk) {
      final chunk = ids.sublist(i, i + idFetchChunk > ids.length ? ids.length : i + idFetchChunk);
      final page = await _selectIn(cloud, tenantId, chunk);
      all.addAll(page);
    }
    return all;
  }

  /// مؤشر الجدول: ختم السيرفر لآخر ما وصلنا منه.
  String cursorKey(String tenantId, String table) => 'sync_cursor_${tenantId}_$table';

  String columnsSignatureKey(String tenantId) => 'sync_columns_$tenantId';

  /// تصفير المؤشرات حين تتغيّر أعمدة التطبيق — انظر [pullColumnsSignature].
  Future<void> _resetCursorsIfColumnsChanged(String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = columnsSignatureKey(tenantId);
    if (prefs.getString(key) == pullColumnsSignature) return;

    for (final table in [...syncedTables, deletesCursor]) {
      await prefs.remove(cursorKey(tenantId, table));
    }
    await prefs.setString(key, pullColumnsSignature);
  }

  Future<String?> _cursor(String tenantId, String table) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(cursorKey(tenantId, table));
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _setCursor(String tenantId, String table, String? stamp) async {
    if (stamp == null || stamp.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cursorKey(tenantId, table), stamp);
  }

  /// تراجعٌ عن المؤشر قبل الجلب — انظر [cursorOverlapMs].
  static String overlapped(String since) =>
      DateTime.fromMillisecondsSinceEpoch(toTimestamp(since) - cursorOverlapMs, isUtc: true).toIso8601String();

  /// ترويسات الجلسة لا المفتاح المنشور: القاعدة محمية بـ RLS، والزائر المجهول
  /// يُعاد له جدول فارغ بلا خطأ — فكان السحب «ينجح» بصفر سجل والرفع يُرفض.
  Map<String, String> get _headers => {
        ...SupabaseConfig.headers,
        'Prefer': 'return=representation',
      };

  Future<List<Map<String, dynamic>>?> _select(
    String table,
    String tenantId, {
    String columns = '*',
    String? since,

    /// العمود الذي يُرشَّح به [since] — ختم السيرفر، أو وقت الحذف في سجل المحذوفات.
    String sinceColumn = 'server_updated_at',
    required int from,
    required int to,
    required String order,
  }) async {
    await SupabaseAuth.ensureFresh();
    final params = <String, String>{
      'select': columns,
      'tenant_id': 'eq.$tenantId',
      'order': order,
    };
    if (since != null && since.isNotEmpty) {
      // تراجعٌ عن المؤشر بلحظة: صفٌّ كُتب أثناء السحب السابق كان يُفوَّت للأبد
      params[sinceColumn] = 'gt.${overlapped(since)}';
    }
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(queryParameters: params);
    try {
      final res = await SupabaseAuth.withRetryOnExpiry(
        () => http.get(uri, headers: {..._headers, 'Range': '$from-$to'}),
        expired: (r) => SupabaseAuth.isExpiredResponse(r.statusCode, r.body),
      );
      if (res.statusCode >= 400) {
        if (isMissingTableError(res.statusCode, res.body)) missingTables.add(table);
        return null;
      }
      final data = jsonDecode(res.body);
      if (data is! List) return [];
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _selectIn(String table, String tenantId, List<String> ids) async {
    if (ids.isEmpty) return [];
    await SupabaseAuth.ensureFresh();
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(
      queryParameters: {
        'select': '*',
        'tenant_id': 'eq.$tenantId',
        'id': 'in.(${ids.join(',')})',
      },
    );
    try {
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode >= 400) return [];
      final data = jsonDecode(res.body);
      if (data is! List) return [];
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// رفع دفعة، وحفظ ختم السيرفر الذي تعيده القاعدة لكل صف.
  ///
  /// بلا حفظه يظن الجهاز أن ما رفعه للتوّ تغييرٌ قادم من السحابة: ختم الصف تغيّر
  /// هناك وما عنده ختمٌ يطابقه — فيقول «سحب 1» لتعديل هو صاحبه.
  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    await SupabaseAuth.ensureFresh();
    final conflict = tableConflictTarget[table] ?? 'id';
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(
      queryParameters: {'on_conflict': conflict, 'select': 'id,server_updated_at'},
    );
    final res = await SupabaseAuth.withRetryOnExpiry(
      () => http.post(
        uri,
        headers: {
          ..._headers,
          'Prefer': 'resolution=merge-duplicates,return=representation',
        },
        body: jsonEncode(rows),
      ),
      expired: (r) => SupabaseAuth.isExpiredResponse(r.statusCode, r.body),
    );
    if (res.statusCode >= 400) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
    _rememberStampsFrom(table, res.body);
  }

  /// أختام السيرفر من ردّ الرفع — تُتجاهَل بصمت إن لم يعدها الردّ.
  void _rememberStampsFrom(String table, String body) {
    if (body.isEmpty) return;
    try {
      final data = jsonDecode(body);
      if (data is! List) return;
      final stamps = <String, String>{};
      for (final row in data) {
        if (row is! Map) continue;
        final id = '${row['id'] ?? ''}';
        final stamp = '${row['server_updated_at'] ?? ''}';
        if (id.isNotEmpty && stamp.isNotEmpty) stamps[id] = stamp;
      }
      local.rememberServerStamps(table, stamps);
    } catch (_) {
      // ردٌّ بلا تمثيل: السحب التالي سيجلب الختم
    }
  }

  Future<void> _deleteIds(String table, String tenantId, List<String> ids) async {
    await SupabaseAuth.ensureFresh();
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(
      queryParameters: {
        'id': 'in.(${ids.join(',')})',
        'tenant_id': 'eq.$tenantId',
      },
    );
    final res = await SupabaseAuth.withRetryOnExpiry(
      () => http.delete(uri, headers: _headers),
      expired: (r) => SupabaseAuth.isExpiredResponse(r.statusCode, r.body),
    );
    if (res.statusCode >= 400) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
  }
}
