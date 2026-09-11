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
    'id', 'name', 'subject_id', 'teacher_id', 'room_id', 'grade_level',
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
    'has_flexible_exception', 'exception_reason', 'custom_monthly_fee',
    'portal_code',
    'notes', 'tenant_id', 'created_at', 'updated_at',
  ],
  'student_attachments': [
    'id', 'student_id_photo', 'birth_certificate',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'institution_settings': [
    'id', 'institution_type', 'institution_name', 'logo', 'colors',
    'tenant_id', 'created_at', 'updated_at',
  ],
  'enrollments': [
    'id', 'student_id', 'group_id', 'enrollment_date', 'enrolled_at',
    'custom_price', 'applied_price', 'discount_reason',
    'status', 'tenant_id', 'created_at', 'updated_at',
  ],
  'installments': [
    'id', 'student_id', 'title', 'amount', 'due_date', 'paid_amount',
    'status', 'has_flexible_exception', 'exception_notes', 'tenant_id',
    'created_at', 'updated_at',
  ],
  'payments': [
    'id', 'receipt_number', 'student_id', 'enrollment_id', 'group_id',
    'installment_id', 'amount', 'payment_method', 'payment_date',
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
    'created_at', 'days', 'end_time', 'max_students', 'price_per_month', 'start_time',
    'tenant_id', 'updated_at',
  ],
  'installments': [
    'amount', 'created_at', 'due_date', 'has_flexible_exception', 'paid_amount',
    'tenant_id', 'updated_at',
  ],
  'institution_settings': ['colors', 'created_at', 'tenant_id', 'updated_at'],
  'payments': [
    'amount', 'created_at', 'is_cancelled', 'payment_date', 'remaining_balance_after',
    'tenant_id', 'total_due_at_payment', 'transfer_date', 'updated_at',
  ],
  'rooms': ['capacity', 'created_at', 'tenant_id', 'updated_at'],
  'sessions': ['created_at', 'end_time', 'session_date', 'start_time', 'tenant_id', 'updated_at'],
  'student_attachments': ['created_at', 'tenant_id', 'updated_at'],
  'students': [
    'academic_discount_applied', 'academic_discount_rate', 'balance', 'birth_date',
    'created_at', 'custom_monthly_fee', 'enrollment_date', 'guardian_declaration',
    'has_flexible_exception', 'initial_rating', 'seat_reservation_discounted',
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
  'class_announcements',
  'student_evaluations',
];

/// هل ردّ الخادم أن الجدول غير موجود في القاعدة؟ (PostgREST: `PGRST205`)
///
/// يحدث حين تُضاف ميزة في الكود ولم تُطبَّق هجرتها على قاعدة المنشأة بعد —
/// كجدول `class_announcements`. يُميَّز عن بقية الأعطال لأنه لا يُصلَح بإعادة المحاولة.
bool isMissingTableError(int status, String body) => status == 404 && body.contains('PGRST205');

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
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final existingIdx = queue.indexWhere((e) => e.tableName == tableName && e.recordId == recordId);

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
  if (RegExp(r'PGRST204|could not find|schema cache', caseSensitive: false).hasMatch(raw)) {
    final col = RegExp(r"'([^']+)' column").firstMatch(raw)?.group(1);
    return '$table: العمود ${col ?? 'المطلوب'} غير موجود في قاعدة البيانات. نفّذ ملف الهجرة على Supabase.';
  }
  if (RegExp(r'Failed to fetch|NetworkError|fetch failed|SocketException|ClientException', caseSensitive: false).hasMatch(raw)) {
    return 'تعذّر الوصول إلى السحابة. تحقق من الاتصال بالإنترنت.';
  }
  return '$table: $raw';
}

/// مخزن محلي يوفّر لخدمة المزامنة ما يوفّره Dexie في التطبيق المكتبي.
abstract class SyncLocalStore {
  String? get tenantId;
  bool get isMaster;
  List<PendingSync> get pendingSyncs;
  Map<String, dynamic>? recordOf(String table, String id);
  List<Map<String, dynamic>> allOf(String table);
  void putRows(String table, List<Map<String, dynamic>> rows);
  void removeIds(String table, List<String> ids);
  void markSynced(String table, String id);
  void notifySync();

  /// ما يجري بعد اكتمال سحب: قراءة الإعدادات التي وصلت مع الصفوف.
  Future<void> onPulled();
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

  Future<String?> getLastPullAt() async {
    final tenantId = local.tenantId;
    if (tenantId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(lastPullKey(tenantId));
  }

  Future<void> _setLastPullAt(String tenantId, String iso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastPullKey(tenantId), iso);
  }

  Future<RemoteChangeSummary> checkRemoteChanges() async {
    final tenantId = local.tenantId;
    if (tenantId == null) {
      return RemoteChangeSummary(total: 0, rows: [], items: [], since: null);
    }

    final since = await getLastPullAt();
    final rows = <SyncRow>[];
    final items = <PendingSummaryItem>[];
    final allNewKeys = <String>[];
    var total = 0;
    var failed = false;

    for (final cloud in syncedTables) {
      try {
        final localStamps = <String, int>{};
        for (final rec in local.allOf(cloud)) {
          localStamps['${rec['id']}'] = toTimestamp(rec['updated_at']);
        }

        final newIds = <String>[];
        var from = 0;
        var keepFetching = true;

        while (keepFetching) {
          final page = await _select(
            cloud,
            tenantId,
            columns: 'id,updated_at',
            since: since,
            from: from,
            to: from + pullPageSize - 1,
            order: 'updated_at.desc',
          );
          if (page == null) {
            if (!missingTables.contains(cloud)) failed = true;
            break;
          }
          for (final row in page) {
            final localAt = localStamps[row['id']?.toString()];
            final remoteAt = toTimestamp(row['updated_at']);
            if (localAt == null || remoteAt > localAt + stampToleranceMs) {
              newIds.add('${row['id']}');
            }
          }
          if (page.length < pullPageSize) {
            keepFetching = false;
          } else {
            from += page.length;
          }
        }

        if (newIds.isEmpty) continue;
        rows.add(SyncRow(cloud, newIds.length));
        total += newIds.length;
        for (final id in newIds) {
          allNewKeys.add('$cloud:$id');
        }

        if (items.length < 40) {
          final sampleIds = newIds.take((10).clamp(0, 40 - items.length)).toList();
          final full = await _selectIn(cloud, tenantId, sampleIds);
          for (final row in full) {
            items.add(
              PendingSummaryItem(
                table: cloud,
                action: localStamps.containsKey('${row['id']}') ? 'UPDATE' : 'INSERT',
                label: describeRecord(cloud, row, null),
                at: '${row['updated_at'] ?? ''}',
              ),
            );
          }
        }
      } catch (_) {
        failed = true;
      }
    }

    items.sort((a, b) => b.at.compareTo(a.at));
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

  Future<SyncResult> push() async {
    if (_syncing) return SyncResult(success: false, message: 'عملية مزامنة أخرى جارية');
    if (local.isMaster) {
      return SyncResult(success: false, message: 'وضع المطور لا يقوم بمزامنة بيانات المدارس');
    }
    final tenantId = local.tenantId;
    if (tenantId == null) return SyncResult(success: false, message: 'لا توجد منشأة محددة');

    _syncing = true;
    try {
      final result = await pushPendingChanges(tenantId);
      if (result.pushed > 0) {
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
    final all = [...local.pendingSyncs];
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

  /// جلب البيانات من السحابة ودمجها محلياً.
  ///
  /// وضعان — مطابق لـ `pullFromCloud` في lib/sync.ts:
  ///  - **أول سحب** (`lastPullAt = null`): سحب كامل لكل الجداول لتأسيس النسخة.
  ///  - **السحبات اللاحقة**: تزايدي — فقط ما تغيّر (`updated_at > lastPullAt`).
  ///    ولكشف الحذف تُجلب المعرّفات وحدها (`select=id`) بدل السجلات الكاملة.
  Future<PullOutcome> pullFromCloud(String tenantId) async {
    var totalPulled = 0;
    var totalRemoved = 0;
    final lastPullAt = await getLastPullAt();
    final safeToReconcileDeletes = lastPullAt != null;
    final incrementalPull = lastPullAt != null;
    // الجداول التي تعذّر جلبها. ابتلاع الخطأ بصمت كان يُظهر «تم سحب 0 سجلاً»
    // على أنه نجاح، فلا يعرف المستخدم أن جدولاً كاملاً لم يصل.
    final failedTables = <String, String>{};

    for (final cloud in syncedTables) {
      // الجدول بلا `updated_at` لا يقبل الترشيح التزايدي فيُسحب كاملاً
      final isIncremental = incrementalPull && tableHasUpdatedAt(cloud);
      try {
        final allData = <Map<String, dynamic>>[];
        var from = 0;
        var keepFetching = true;
        var fetchComplete = true;

        while (keepFetching) {
          final page = await _select(
            cloud,
            tenantId,
            since: isIncremental ? lastPullAt : null,
            from: from,
            to: from + pullPageSize - 1,
            order: 'id.asc',
          );
          if (page == null) {
            fetchComplete = false;
            break;
          }
          if (page.isNotEmpty) {
            allData.addAll(page);
            from += page.length;
            if (page.length < pullPageSize) keepFetching = false;
          } else {
            keepFetching = false;
          }
        }

        if (!fetchComplete) {
          // جدول لم تُنشر هجرته: لا بيانات فيه ولا يُحسب عطلاً
          if (missingTables.contains(cloud)) continue;
          failedTables[cloud] = 'تعذّر جلب بيانات ${tableLabelsAr[cloud] ?? cloud} من السحابة.';
          continue;
        }

        final pendingIds = local.pendingSyncs.where((p) => p.tableName == cloud).map((p) => p.recordId).toSet();
        final localRecords = local.allOf(cloud);
        final localById = <String, Map<String, dynamic>>{
          for (final r in localRecords) '${r['id']}': r,
        };

        final toWrite = <Map<String, dynamic>>[];
        for (final record in allData) {
          final id = '${record['id']}';
          if (pendingIds.contains(id)) continue;
          final loc = localById[id];
          if (loc != null && loc['sync_status'] == 'pending') {
            if (toTimestamp(loc['updated_at']) > toTimestamp(record['updated_at']) + stampToleranceMs) {
              continue;
            }
          }
          final rest = Map<String, dynamic>.from(record)..remove('tenant_id');
          if (cloud == 'enrollments' && (rest['enrolled_at'] == null || '${rest['enrolled_at']}'.isEmpty) && rest['enrollment_date'] != null) {
            rest['enrolled_at'] = rest['enrollment_date'];
          }
          rest['sync_status'] = 'synced';
          toWrite.add(rest);
        }

        if (toWrite.isNotEmpty) {
          local.putRows(cloud, toWrite);
          totalPulled += toWrite.length;
        }

        // ── توفيق الحذف ──────────────────────────────────────────────────
        // في السحب التزايدي `allData` لا تحوي إلا المتغيّر، فلا تصلح لكشف
        // الحذف. تُجلب المعرّفات وحدها: صفحة `select=id` أخفّ من السجل كاملاً.
        if (safeToReconcileDeletes) {
          Set<String> cloudIds;
          if (isIncremental) {
            final allIds = <String>[];
            var idFrom = 0;
            var idKeep = true;
            var idComplete = true;

            while (idKeep) {
              final page = await _select(
                cloud,
                tenantId,
                columns: 'id',
                from: idFrom,
                to: idFrom + pullPageSize - 1,
                order: 'id.asc',
              );
              if (page == null) {
                idComplete = false;
                break;
              }
              if (page.isNotEmpty) {
                for (final row in page) {
                  allIds.add('${row['id']}');
                }
                idFrom += page.length;
                if (page.length < pullPageSize) idKeep = false;
              } else {
                idKeep = false;
              }
            }

            if (!idComplete) {
              failedTables[cloud] = 'تعذّر التحقق من المحذوف في ${tableLabelsAr[cloud] ?? cloud}.';
              continue;
            }
            cloudIds = allIds.toSet();
          } else {
            // أول سحب: المعرّفات متاحة من البيانات المجلوبة أصلاً
            cloudIds = allData.map((r) => '${r['id']}').toSet();
          }

          final toRemove = localRecords
              .where(
                (r) =>
                    r['sync_status'] == 'synced' &&
                    !cloudIds.contains('${r['id']}') &&
                    !pendingIds.contains('${r['id']}') &&
                    (r['updated_at'] == null || toTimestamp(r['updated_at']) < toTimestamp(lastPullAt)),
              )
              .map((r) => '${r['id']}')
              .toList();

          if (toRemove.isNotEmpty) {
            local.removeIds(cloud, toRemove);
            totalRemoved += toRemove.length;
          }
        }

        if (!safeToReconcileDeletes) {
          final cloudIds = allData.map((r) => '${r['id']}').toSet();
          final orphans = localRecords.where(
            (r) => r['sync_status'] == 'synced' && !cloudIds.contains('${r['id']}') && !pendingIds.contains('${r['id']}'),
          );
          for (final orphan in orphans) {
            queuePendingSync(
              local.pendingSyncs,
              tableName: cloud,
              recordId: '${orphan['id']}',
              action: 'INSERT',
              payload: orphan,
            );
          }
        }
      } catch (err) {
        failedTables[cloud] = describeSupabaseError(err, cloud);
      }
    }

    remotePendingIds.clear();
    lastRemoteCheck = DateTime.now();
    // ختم آخر سحب لا يتقدّم إلا بعد سحب كامل ناجح: تقديمه بعد سحب ناقص كان
    // يجعل تغييرات الجدول الفاشل تقع قبل الختم فلا تُحسب في «السحب» أبداً.
    if (failedTables.isEmpty) {
      await _setLastPullAt(tenantId, DateTime.now().toUtc().toIso8601String());
    }
    return PullOutcome(pulled: totalPulled, removed: totalRemoved, failedTables: failedTables);
  }

  Map<String, String> get _headers => {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<List<Map<String, dynamic>>?> _select(
    String table,
    String tenantId, {
    String columns = '*',
    String? since,
    required int from,
    required int to,
    required String order,
  }) async {
    final params = <String, String>{
      'select': columns,
      'tenant_id': 'eq.$tenantId',
      'order': order,
    };
    if (since != null && since.isNotEmpty) {
      params['updated_at'] = 'gt.$since';
    }
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(queryParameters: params);
    try {
      final res = await http.get(uri, headers: {..._headers, 'Range': '$from-$to'});
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

  Future<void> _upsert(String table, List<Map<String, dynamic>> rows) async {
    final conflict = tableConflictTarget[table] ?? 'id';
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(queryParameters: {'on_conflict': conflict});
    final res = await http.post(
      uri,
      headers: {
        ..._headers,
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
      body: jsonEncode(rows),
    );
    if (res.statusCode >= 400) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
  }

  Future<void> _deleteIds(String table, String tenantId, List<String> ids) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/$table').replace(
      queryParameters: {
        'id': 'in.(${ids.join(',')})',
        'tenant_id': 'eq.$tenantId',
      },
    );
    final res = await http.delete(uri, headers: _headers);
    if (res.statusCode >= 400) {
      throw Exception(res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body);
    }
  }
}
