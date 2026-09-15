import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import 'academic_matching.dart';
import 'balance.dart';
import 'grading.dart';
import 'institution.dart';
import 'local_db.dart';
import 'payment_methods.dart';
import 'permissions.dart';
import 'system_features.dart';
import 'phone.dart';
import 'realtime.dart';
import 'supabase.dart';
import 'sync.dart';
import 'tenant_service.dart';

class AppStore extends ChangeNotifier implements SyncLocalStore {
  AppStore._() {
    sync = SyncService(this);
  }

  static final AppStore instance = AppStore._();

  /// مخزن مستقل للاختبارات — لا يشارك الحالة مع [instance] ولا يلمس الشبكة.
  @visibleForTesting
  factory AppStore.forTesting() => AppStore._()
    ..tenantApi = const OfflineTenantService()
    ..networkEnabled = false;

  /// يُوقف كل ما يحتاج شبكة أو إضافات النظام — للاختبارات.
  bool networkEnabled = true;

  /// خدمة المنشآت. تُستبدل بـ [OfflineTenantService] في الاختبارات.
  TenantService tenantApi = const TenantService();

  late final SyncService sync;

  /// التخزين المحلي الدائم. يبقى [NoPersistence] في الاختبارات.
  Persistence db = NoPersistence();

  /// اكتمل تحميل التخزين المحلي واستعادة الجلسة.
  /// قبله تُعرض شاشة الإقلاع بدل واجهة فارغة أو شاشة دخول خاطئة.
  bool ready = false;

  bool loggedIn = false;
  bool isMasterAdmin = false;
  String institutionName = '';
  String roleName = 'مدير';
  Tenant? currentTenant;

  @override
  final pendingSyncs = <PendingSync>[];
  /// جداول تُزامَن كما هي دون نموذج مخصّص بعد.
  final extraCloud = <String, List<Map<String, dynamic>>>{
    'teacher_payouts': [],
    'expenses': [],
    'institution_settings': [],
    'student_evaluations': [],
    'class_announcements': [],
    'finance_attachments': [],
  };
  final attachmentsByStudent = <String, StudentAttachments>{};

  final teachers = <Teacher>[];
  final subjects = <SubjectItem>[];
  final rooms = <Classroom>[];
  final students = <Student>[];
  final payments = <Payment>[];
  final installments = <Installment>[];
  final attendance = <AttendanceMark>[];
  final gradeFees = <GradeFee>[];
  final users = <AppUser>[];
  final tenants = <Tenant>[];
  final groups = <Group>[];
  final enrollments = <StudentEnrollment>[];
  final sessions = <ClassSession>[];

  String _tenantUser = '';
  String _tenantPass = '';
  int _receipt = 1000;
  final _uuid = const Uuid();

  // ── التخزين المحلي: تتبّع الجداول المتغيّرة وكتابتها بعد التعديل ────────────
  final _dirty = <String>{};
  final _dirtyRecords = <String, Set<String>>{};
  final _deletedRecords = <String, Set<String>>{};
  Timer? _flushTimer;
  bool _loading = false;

  /// كل الجداول التي يملكها المخزن، بنفس أسماء السحابة.
  static const ownedTables = [
    'students',
    'student_attachments',
    'teachers',
    'subjects',
    'rooms',
    'grade_fees',
    'users',
    'payments',
    'installments',
    'attendance',
    'tenants',
    'groups',
    'enrollments',
    'sessions',
  ];

  // ── الفهارس ────────────────────────────────────────────────────────────────
  //
  // البحث الخطي في القوائم كان يجعل كل إعادة رسم لكشف الحضور تمرّ على كل
  // سجلات الحضور والجلسات مرتين لكل طالب. تُبنى الفهارس عند أول استعمال بعد
  // أي تعديل، فتصبح القراءة في زمن ثابت.
  int _rev = 0;
  int _indexRev = -1;
  final _studentIndex = <String, Student>{};
  final _sessionIndex = <String, ClassSession>{};
  final _sessionOwners = <String, Set<String>>{};

  /// الرصد المملوك لصف محدد: 'صف|طالب|يوم'.
  final _markOwned = <String, AttendanceMark>{};

  /// الرصد بلا جلسة معروفة: 'طالب|يوم'. يتبنّاه أول صف يُرصد منه.
  final _markLoose = <String, AttendanceMark>{};

  /// أي رصد للطالب في اليوم مهما كان صفه — للقراءة المحايدة تجاه الصف.
  final _markAny = <String, AttendanceMark>{};

  int _dueRev = -1;
  List<DueItem> _dueCache = const [];

  static String looseKey(String studentId, String date) => '$studentId|$date';
  static String ownedKey(String ownerId, String studentId, String date) => '$ownerId|$studentId|$date';
  static String sessionKey(String ownerId, String date) => '$ownerId|$date';

  void _touch() => _rev++;

  /// أي إخطار للشاشات يعني أن شيئاً تغيّر، فتسقط الفهارس والنتائج المحفوظة.
  /// ربطها بالإخطار وحده يمنع نسيان إبطالها في أي مسار تعديل جديد.
  @override
  void notifyListeners() {
    _rev++;
    super.notifyListeners();
  }

  void _rebuildIndexes() {
    if (_indexRev == _rev) return;
    _indexRev = _rev;

    _studentIndex
      ..clear()
      ..addEntries(students.map((s) => MapEntry(s.id, s)));

    // الجلسات أولاً: منها يُعرف مالك كل رصد
    _sessionIndex.clear();
    _sessionOwners.clear();
    for (final sess in sessions) {
      final owners = <String>{};
      if (sess.groupId.isNotEmpty) {
        owners.add(sess.groupId);
        _sessionIndex[sessionKey(sess.groupId, sess.sessionDate)] = sess;
      }
      if (sess.roomId.isNotEmpty) {
        owners.add(sess.roomId);
        _sessionIndex[sessionKey(sess.roomId, sess.sessionDate)] = sess;
      }
      _sessionOwners[sess.id] = owners;
    }

    _markOwned.clear();
    _markLoose.clear();
    _markAny.clear();
    for (final a in attendance) {
      _markAny[looseKey(a.studentId, a.date)] = a;
      final owners = a.sessionId.isEmpty ? null : _sessionOwners[a.sessionId];
      if (owners == null || owners.isEmpty) {
        _markLoose[looseKey(a.studentId, a.date)] = a;
        continue;
      }
      for (final owner in owners) {
        _markOwned[ownedKey(owner, a.studentId, a.date)] = a;
      }
    }
  }

  void markDirty(String table) {
    _touch();
    if (_loading) return;
    _dirty.add(table);
    _scheduleFlush();
    // كل عملية تدخل طابور الرفع تُرفع تلقائياً، من أي مسار جاءت. مسارات كثيرة
    // (الدفعة، رصد الكل حاضراً، رموز البوابة، الترحيلات) تكتب في الطابور مباشرةً
    // فكانت تنتظر تعديلاً لاحقاً يمرّ على `_queue` كي تُرفع
    if (table == _pendingTable) _onQueueChanged();
  }

  /// تعليم سجل واحد للكتابة بدل الجدول كله.
  void markRecord(String table, String id, {bool deleted = false}) {
    _touch();
    if (_loading) return;
    if (_dirty.contains(table)) return; // الجدول كله سيُكتب على أي حال
    if (deleted) {
      _dirtyRecords.putIfAbsent(table, () => {}).remove(id);
      _deletedRecords.putIfAbsent(table, () => {}).add(id);
    } else {
      _deletedRecords[table]?.remove(id);
      _dirtyRecords.putIfAbsent(table, () => {}).add(id);
    }
    _scheduleFlush();
  }

  void markAllDirty() {
    _touch();
    if (_loading) return;
    _dirty
      ..addAll(ownedTables)
      ..addAll(extraCloud.keys)
      ..add(_pendingTable);
    _dirtyRecords.clear();
    _deletedRecords.clear();
    _scheduleFlush();
  }

  static const _pendingTable = '__pending_syncs';

  /// جدول أختام السيرفر على القرص — `جدول|معرّف` ← ختم.
  static const _stampsTable = '__server_stamps';

  /// ختم السيرفر لكل سجل: `جدول` ← (`معرّف` ← ختم).
  ///
  /// النماذج لا تحمل العمود، وحفظه هنا يجنّب تعديلها كلها. به يعرف السحب أي
  /// سجل تغيّر في السحابة فعلاً بدل جلب الجداول كاملةً في كل مرة.
  final serverStamps = <String, Map<String, String>>{};

  @override
  String? serverStamp(String table, String id) => serverStamps[table]?[id];

  @override
  Map<String, String> serverStampsOf(String table) => serverStamps[table] ?? const {};

  @override
  void rememberServerStamps(String table, Map<String, String> stamps) {
    if (stamps.isEmpty) return;
    serverStamps.putIfAbsent(table, () => {}).addAll(stamps);
    markDirty(_stampsTable);
  }

  @override
  void forgetServerStamps(String table, Iterable<String> ids) {
    final bucket = serverStamps[table];
    if (bucket == null) return;
    var changed = false;
    for (final id in ids) {
      if (bucket.remove(id) != null) changed = true;
    }
    if (changed) markDirty(_stampsTable);
  }

  /// بصمة آخر حالة عُرف أنها مطابقة للسحابة: 'جدول|معرّف' ← بصمة.
  ///
  /// بها نعرف أن تعديلاً عاد إلى ما في السحابة، فنُسقط عمليته من الطابور بدل
  /// أن يظل العدّاد يقول «تعديل بانتظار الرفع» ولا شيء في الحقيقة تغيّر.
  final _syncedPrint = <String, String>{};

  /// الحقول المتغيّرة دائماً لا تدخل البصمة، وإلا لاختلفت من غير سبب.
  static const _volatile = {'updated_at', 'created_at', 'sync_status', 'synced_at', 'tenant_id'};

  String _fingerprint(Map<String, dynamic> row) {
    final keys = row.keys.where((k) => !_volatile.contains(k)).toList()..sort();
    return jsonEncode({for (final k in keys) k: row[k]});
  }

  void _rememberSynced(String table, String id, Map<String, dynamic>? row) {
    if (row == null) {
      _syncedPrint.remove('$table|$id');
      return;
    }
    _syncedPrint['$table|$id'] = _fingerprint(row);
  }

  /// هل عاد السجل إلى آخر حالة مرفوعة، فلا شيء يستحق الرفع؟
  bool _isBackToSynced(String table, String id, Map<String, dynamic>? payload) {
    final known = _syncedPrint['$table|$id'];
    if (known == null) return false;
    final current = payload ?? recordOf(table, id);
    if (current == null) return false;
    return _fingerprint(current) == known;
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(flush());
    });
  }

  /// كتابة كل الجداول المتغيّرة إلى القرص فوراً.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dirty.isEmpty && _dirtyRecords.isEmpty && _deletedRecords.isEmpty) return;

    final tables = _dirty.toList();
    final records = Map<String, Set<String>>.from(_dirtyRecords);
    final deletes = Map<String, Set<String>>.from(_deletedRecords);
    _dirty.clear();
    _dirtyRecords.clear();
    _deletedRecords.clear();

    for (final t in tables) {
      await db.saveTable(t, _rowsForPersist(t));
      records.remove(t);
      deletes.remove(t);
    }
    for (final entry in deletes.entries) {
      await db.deleteRecords(entry.key, entry.value.toList());
    }
    for (final entry in records.entries) {
      await db.saveRecords(entry.key, _rowsForPersist(entry.key, only: entry.value));
    }
  }

  /// صفوف جدول للكتابة على القرص. [only] يقصرها على معرّفات بعينها، فلا
  /// يُسلسَل الجدول كله — ثمانية آلاف سجل حضور — لأجل رصدٍ واحد.
  List<Map<String, dynamic>> _rowsForPersist(String table, {Set<String>? only}) {
    if (table == _stampsTable) {
      return [
        for (final entry in serverStamps.entries)
          for (final e in entry.value.entries) {'id': '${entry.key}|${e.key}', 'stamp': e.value},
      ];
    }
    if (table == _pendingTable) {
      final tid = tenantId ?? '';
      return [
        for (var i = 0; i < pendingSyncs.length; i++)
          {
            'id': '$i',
            // ختم المنشأة يُوضع هنا: كل تغيير على الطابور يمر بالحفظ، فلا تبقى
            // عملية بلا ختم تُرفع لاحقاً إلى سحابة منشأة أخرى
            ...(pendingSyncs[i]..tenantId = pendingSyncs[i].tenantId.isEmpty ? tid : pendingSyncs[i].tenantId)
                .toJson(),
          },
      ];
    }
    if (only != null && only.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (final id in only) {
        final row = recordOf(table, id);
        if (row != null) out.add(row);
      }
      return out;
    }
    if (table == 'tenants') return tenants.map((e) => e.toCloud()).toList();
    return allOf(table);
  }

  /// تصفير كل البيانات المحلية مع الإبقاء على الإعدادات والجلسة.
  /// المقابل لـ `clearAllLocalData` + زر «مسح وتصفير قاعدة البيانات».
  Future<void> wipeAllData() async {
    students.clear();
    payments.clear();
    installments.clear();
    attendance.clear();
    teachers.clear();
    subjects.clear();
    rooms.clear();
    gradeFees.clear();
    users.clear();
    groups.clear();
    enrollments.clear();
    sessions.clear();
    attachmentsByStudent.clear();
    pendingSyncs.clear();
    serverStamps.clear();
    for (final k in extraCloud.keys) {
      extraCloud[k]!.clear();
    }
    await db.wipeData();
    _dirty.clear();
    notifyListeners();
  }

  /// إدراج صفوف قادمة من نسخة احتياطية (تشمل `tenants` التي لا يمرّرها [putRows]).
  void putRowsFromBackup(String table, List<Map<String, dynamic>> rows) {
    if (table == 'tenants') {
      for (final r in rows) {
        final t = Tenant.fromCloud(r);
        final i = tenants.indexWhere((e) => e.id == t.id);
        if (i >= 0) {
          tenants[i] = t;
        } else {
          tenants.add(t);
        }
      }
      markDirty('tenants');
      return;
    }
    putRows(table, rows);
  }

  /// تحميل كل ما على القرص إلى الذاكرة، ثم استعادة الجلسة.
  Future<void> bootstrap(Persistence persistence) async {
    db = persistence;
    await db.open();
    _loading = true;
    try {
      final data = await db.loadAll();
      for (final entry in data.entries) {
        if (entry.key == _stampsTable) {
          for (final row in entry.value) {
            final parts = '${row['id'] ?? ''}'.split('|');
            if (parts.length != 2) continue;
            serverStamps.putIfAbsent(parts[0], () => {})[parts[1]] = '${row['stamp'] ?? ''}';
          }
        } else if (entry.key == _pendingTable) {
          pendingSyncs
            ..clear()
            ..addAll(entry.value.map(PendingSync.fromJson));
        } else if (entry.key == 'tenants') {
          tenants
            ..clear()
            ..addAll(entry.value.map(Tenant.fromCloud));
        } else {
          putRows(entry.key, entry.value);
        }
      }
      _restoreSession();
      // كل تجديد للتوكن يُحفظ فوراً: السحابة تُدوّر توكن التجديد، والقديم يُرفض
      SupabaseAuth.onSessionChanged = _saveSession;
      SupabaseAuth.onSessionInvalid = _onSessionExpired;
      applyBrandColors();
      // الأرصدة من السجلات عند كل إقلاع: الرقم المحفوظ قد يكون كتبه إصدار أقدم
      // بقاعدة حساب أخرى، فيبقى معروضاً حتى أول سحب أو حركة مالية
      recalculateAllBalances();
    } finally {
      _loading = false;
    }
    await _resolveSetupGate();
    ready = true;
    notifyListeners();
  }

  // ── الجلسة والإعدادات (المقابل لـ session.ts + currentUser.ts + institution.ts) ──
  static const _kLoggedIn = 'session_logged_in';
  static const _kMasterAdmin = 'is_master_admin';
  static const _kTenantId = 'last_active_tenant_id';
  static const _kDeviceUser = 'device_user_id';
  static const _kReceiptLabel = 'device_receipt_label';
  static const _kLastUsername = 'last_entered_username';
  static const _kReceiptCounter = 'receipt_counter';
  static const _kCustomUser = 'custom_app_username';
  static const _kCustomPass = 'custom_app_password';

  // جلسة Supabase Auth: تُحفظ ليبقى الجهاز داخلاً بعد إغلاق التطبيق
  static const _kAuthAccess = 'auth_access_token';
  static const _kAuthRefresh = 'auth_refresh_token';
  static const _kAuthExpiry = 'auth_expires_at';
  static const _kAuthClaims = 'auth_claims';

  /// تهيئة بدأت ولم تكتمل — تُكتب على القرص قبل الجلسة نفسها.
  static const _kSetupPending = 'device_setup_pending';

  /// منشأة البيانات المحفوظة على هذا الجهاز.
  static const _kDbTenant = 'db_tenant_id';

  String get lastUsername => db.settings[_kLastUsername] ?? '';

  void _restoreSession() {
    final s = db.settings;
    // توكن الجلسة أولاً: كل قراءة من السحابة بعده تمرّ به لا بالمفتاح المنشور
    SupabaseAuth.restore(
      access: s[_kAuthAccess],
      refresh: s[_kAuthRefresh],
      expiry: DateTime.tryParse(s[_kAuthExpiry] ?? ''),
      savedClaims: _decodeClaims(s[_kAuthClaims]),
    );
    _tenantUser = s[_kCustomUser] ?? '';
    _tenantPass = s[_kCustomPass] ?? '';
    _receipt = int.tryParse(s[_kReceiptCounter] ?? '') ?? 1000;
    deviceUserId = s[_kDeviceUser];
    receiptReceiverLabel = s[_kReceiptLabel] ?? '';
    institutionName = s[institutionNameKey] ?? '';

    if (s[_kLoggedIn] != 'true') return;
    if (s[_kMasterAdmin] == 'true') {
      loggedIn = true;
      isMasterAdmin = true;
      roleName = 'المطور العام';
      return;
    }
    final tid = s[_kTenantId];
    final tenant = tenants.where((t) => t.id == tid).firstOrNull;
    if (tenant == null) return;
    final check = subscriptionProblem(tenant);
    if (check != null) return;
    loggedIn = true;
    isMasterAdmin = false;
    currentTenant = tenant;
    if (institutionName.isEmpty) institutionName = tenant.name;
    final me = deviceUserId == null ? null : users.where((u) => u.id == deviceUserId).firstOrNull;
    roleName = me == null ? 'مدير' : roleLabel(me.role);
  }

  /// مطالبات التوكن المحفوظة. صفٌّ تالف لا يمنع الإقلاع.
  static Map<String, dynamic> _decodeClaims(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// انتهت جلسة السحابة ولم يعد التجديد ممكناً: تُمحى فيعود الجهاز لشاشة الدخول
  /// بدل أن يبقى «داخلاً» ويفشل كل رفع وسحب بصمت.
  Future<void> _onSessionExpired() async {
    if (!loggedIn && !SupabaseAuth.signedIn) return;
    SupabaseAuth.clear();
    loggedIn = false;
    sessionExpiredNotice = 'انتهت جلسة الدخول. سجّل الدخول من جديد ليُستأنف الرفع والسحب.';
    await _saveSession();
    notifyListeners();
  }

  /// رسالة تُعرض في شاشة الدخول بعد انتهاء الجلسة، وتُمحى بأول دخول ناجح.
  String? sessionExpiredNotice;

  Future<void> _saveSession() async {
    await db.setSetting(_kLoggedIn, loggedIn ? 'true' : null);
    await db.setSetting(_kMasterAdmin, isMasterAdmin ? 'true' : null);
    await db.setSetting(_kTenantId, currentTenant?.id);
    await db.setSetting(_kAuthAccess, SupabaseAuth.accessToken);
    await db.setSetting(_kAuthRefresh, SupabaseAuth.refreshToken);
    await db.setSetting(_kAuthExpiry, SupabaseAuth.expiresAt?.toIso8601String());
    await db.setSetting(_kAuthClaims, SupabaseAuth.claims.isEmpty ? null : jsonEncode(SupabaseAuth.claims));
  }

  // ── إعدادات المنشأة (المقابل لـ institution.ts) ─────────────────────────────

  /// المراحل التي تُعرض في النماذج والتصفية.
  ///
  /// مراحل المنشأة كما أضافتها في «المراحل والرسوم» وحدها: مدرسةٌ جديدة لم
  /// تُضف مراحل لا تُعرض عليها «عاشر» و«حادي عشر» كأنها مراحلها.
  List<String> get gradeOptions {
    final fees = [...gradeFees]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final names = <String>[];
    for (final f in fees) {
      final name = f.gradeName.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  String get institutionLogo => db.settings[institutionLogoKey] ?? '';

  /// طبع ألوان المنشأة على الواجهة. تُستدعى بعد كل ما قد يغيّرها.
  void applyBrandColors() => AppColors.apply(institutionColors);

  InstitutionColors get institutionColors {
    final raw = db.settings[institutionColorsKey];
    if (raw == null || raw.isEmpty) return InstitutionColors.defaults;
    try {
      return InstitutionColors.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return InstitutionColors.defaults;
    }
  }

  // ── التقييمات والدرجات (المقابل لـ evaluations.service.ts) ────────────────

  /// كل التقييمات، الأحدث تاريخاً أولاً.
  List<Evaluation> get evaluations {
    final rows = extraCloud['student_evaluations'] ?? const [];
    final out = rows.map(Evaluation.fromCloud).toList();
    out.sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
    return out;
  }

  List<Evaluation> evaluationsOfStudent(String studentId) =>
      evaluations.where((e) => e.studentId == studentId).toList();

  List<Evaluation> evaluationsOfGroup(String groupId) =>
      evaluations.where((e) => e.groupId == groupId).toList();

  /// رصد درجات شعبة دفعةً واحدة — مطابق لـ `saveBatchEvaluations`.
  ///
  /// `scores` تحمل معرّف الطالب مقابل درجته؛ من لم تُرصد له درجة يُتخطّى بلا
  /// سجل، فالحقل الفارغ في الشاشة يعني «لم يُرصد» لا «صفر».
  int saveEvaluationBatch({
    required String groupId,
    required String title,
    required String type,
    required double maxScore,
    required String evaluationDate,
    required Map<String, double> scores,
    Map<String, String> notes = const {},
    String term = '',
    String componentId = '',
  }) {
    requireSection('evaluations');
    final cleanTitle = title.trim();
    if (groupId.isEmpty) throw StoreException('يرجى اختيار الشعبة');
    if (cleanTitle.isEmpty) throw StoreException('يرجى تحديد عنوان التقييم');
    if (scores.isEmpty) throw StoreException('يرجى رصد درجة واحدة على الأقل');

    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) throw StoreException('الشعبة المختارة غير موجودة');

    final now = _nowIso();
    final bucket = extraCloud.putIfAbsent('student_evaluations', () => []);
    for (final entry in scores.entries) {
      final e = Evaluation(
        id: newId(),
        studentId: entry.key,
        groupId: groupId,
        subjectId: group.subjectId,
        teacherId: group.teacherId,
        title: cleanTitle,
        score: entry.value,
        maxScore: maxScore <= 0 ? 100 : maxScore,
        evaluationDate: evaluationDate,
        type: type,
        notes: (notes[entry.key] ?? '').trim(),
        // ربطٌ بمخطط العلامات إن عرّفته المدرسة: به يُحسب معدل الفصل بالأوزان
        term: term,
        componentId: componentId,
        syncStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      final row = e.toCloud();
      bucket.add(row);
      _queue('student_evaluations', e.id, 'INSERT', row);
    }

    markDirty('student_evaluations');
    notifyListeners();
    return scores.length;
  }

  void deleteEvaluation(String id) {
    requireSection('evaluations');
    final bucket = extraCloud['student_evaluations'];
    if (bucket == null) return;
    final before = bucket.length;
    bucket.removeWhere((e) => '${e['id']}' == id);
    if (bucket.length == before) return;
    _queue('student_evaluations', id, 'DELETE', null);
    markDirty('student_evaluations');
    notifyListeners();
  }

  // ── المصروفات وأجور المعلمين (المقابل لـ finance.service.ts) ───────────────

  /// سندات الصرف التشغيلية، الأحدث أولاً.
  ///
  /// الجدولان يعيشان في `extraCloud` لا في قائمة مستقلة: مخزّنان ومزامَنان
  /// أصلاً بذلك المسار، وتكرارهما في قائمة ثانية كان يفتح باب تعارض بين نسختين.
  List<Expense> get expenses {
    final rows = extraCloud['expenses'] ?? const [];
    final out = rows.map(Expense.fromCloud).toList();
    out.sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    return out;
  }

  /// دفعات أجور المعلمين، الأحدث أولاً.
  List<TeacherPayout> get teacherPayouts {
    final rows = extraCloud['teacher_payouts'] ?? const [];
    final out = rows.map(TeacherPayout.fromCloud).toList();
    out.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return out;
  }

  double get totalExpenses => expenses.fold<double>(0, (a, e) => a + e.amount);
  double get totalPayouts => teacherPayouts.fold<double>(0, (a, p) => a + p.amount);

  /// تسجيل سند صرف — مطابق لـ `FinanceService.createExpense`.
  Expense addExpense({
    required String category,
    required String description,
    required double amount,
    required String expenseDate,
    String method = 'cash',
    String notes = '',
  }) {
    requireSection('finance.expenses');
    final desc = description.trim();
    if (desc.isEmpty) throw StoreException('البيان مطلوب لتسجيل سند الصرف');
    if (amount <= 0) throw StoreException('مبلغ سند الصرف يجب أن يكون أكبر من صفر');

    final now = _nowIso();
    final e = Expense(
      id: newId(),
      category: category,
      description: desc,
      amount: amount,
      expenseDate: expenseDate,
      recordedByUserId: currentUserId,
      recordedByName: receiptReceiver,
      method: method,
      notes: notes.trim(),
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    final row = e.toCloud();
    extraCloud.putIfAbsent('expenses', () => []).add(row);
    _queue('expenses', e.id, 'INSERT', row);
    markDirty('expenses');
    notifyListeners();
    return e;
  }

  /// صرف أجر معلم — مطابق لـ `FinanceService.createTeacherPayout`.
  ///
  /// اسم المعلم واسم من صرف يُجمَّدان وقت الصرف: السند لا يتغيّر نصّه إذا عُدّل
  /// الاسم أو حُذف المعلم بعد الصرف.
  TeacherPayout addTeacherPayout({
    required String teacherId,
    required double amount,
    required String paymentDate,
    String groupId = '',
    String periodStart = '',
    String periodEnd = '',
    String method = 'cash',
    String notes = '',
  }) {
    requireSection('finance.expenses');
    if (teacherId.trim().isEmpty) throw StoreException('اختر المعلم المستفيد');
    if (amount <= 0) throw StoreException('مبلغ الأجر يجب أن يكون أكبر من صفر');

    final now = _nowIso();
    final p = TeacherPayout(
      id: newId(),
      teacherId: teacherId,
      teacherName: teacherById(teacherId)?.name ?? '',
      groupId: groupId,
      amount: amount,
      // فترة الاستحقاق تساوي يوم الصرف ما لم تُحدَّد، كما في النسخة المكتبية
      periodStart: periodStart.isEmpty ? paymentDate : periodStart,
      periodEnd: periodEnd.isEmpty ? paymentDate : periodEnd,
      paymentDate: paymentDate,
      paidByUserId: currentUserId,
      paidByName: receiptReceiver,
      method: method,
      notes: notes.trim(),
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    final row = p.toCloud();
    extraCloud.putIfAbsent('teacher_payouts', () => []).add(row);
    _queue('teacher_payouts', p.id, 'INSERT', row);
    markDirty('teacher_payouts');
    notifyListeners();
    return p;
  }

  void deleteExpense(String id) {
    requireSection('finance.expenses');
    final bucket = extraCloud['expenses'];
    if (bucket == null) return;
    final before = bucket.length;
    bucket.removeWhere((e) => '${e['id']}' == id);
    if (bucket.length == before) return;
    _queue('expenses', id, 'DELETE', null);
    markDirty('expenses');
    notifyListeners();
  }

  // ── أعلام الميزات (المقابل لـ systemFeatures.ts) ──────────────────────────

  SystemFeatures get features => SystemFeatures.decode(db.settings[systemFeaturesKey]);

  /// تعديل علم واحد أو أكثر. ما لا يُمرَّر يبقى كما هو — مطابق لـ
  /// `saveSystemFeatures(Partial<SystemFeaturesConfig>)`.
  Future<void> saveFeatures({
    bool? enableExpenses,
    bool? enableEvaluations,
    bool? enableStudentPortal,
    bool? enableStudentAttachments,
  }) async {
    final next = features.copyWith(
      enableExpenses: enableExpenses,
      enableEvaluations: enableEvaluations,
      enableStudentPortal: enableStudentPortal,
      enableStudentAttachments: enableStudentAttachments,
    );
    await db.setSetting(systemFeaturesKey, next.encode());
    // ومعها نسخة في كائن المنشأة كي تصل بقية الأجهزة، كما في `saveSystemFeatures`
    await _syncInstitutionSetting('__system_features', next.toMap());
    notifyListeners();
  }

  /// رسم حجز المقعد. قيمته الافتراضية 0 حتى تعتمد الإدارة رقماً صراحةً —
  /// تثبيته بـ 50 في الكود قاعدة عمل مخترعة.
  double get seatReservationFee {
    final local = db.settings[seatReservationFeeKey];
    // إعداد المنشأة المتزامن هو الطريق الذي يصل به ضبط سطح المكتب إلى الجوال
    final raw = local == null || local.isEmpty ? '${_storedColorsMap[seatFeeColorKey] ?? ''}' : local;
    final n = double.tryParse(raw);
    return n == null || n < 0 ? 0 : n;
  }

  Future<void> setSeatReservationFee(double value) async {
    final fee = value < 0 ? 0.0 : value;
    await db.setSetting(seatReservationFeeKey, '$fee');
    // ومعه نسخة في كائن المنشأة كي تصل بقية الأجهزة، كما يفعل `setSeatReservationFee`
    await _syncInstitutionSetting(seatFeeColorKey, fee);
    notifyListeners();
  }

  /// مفاتيح إعدادات المنشأة داخل كائن الألوان المتزامن — مطابقة للنسخة المكتبية.
  static const seatFeeColorKey = '__seat_reservation_fee';
  static const studyMonthsColorKey = '__study_months';

  /// كتابة إعداد منشأة داخل الكائن المتزامن — المقابل لـ `syncInstitutionSetting`.
  Future<void> _syncInstitutionSetting(String key, Object? value) async {
    await db.setSetting(institutionColorsKey, jsonEncode({..._storedColorsMap, key: value}));
    _persistInstitutionRow();
  }

  /// الأشهر (1-12) التي يُستحق فيها الرسم الشهري، أو `null` فلا يُستحق شيء.
  ///
  /// مدرسةٌ لم تحدّد أشهرها لا تُولَّد لطلابها مستحقات: توليدها على مدار السنة
  /// يطالب الطالب بشهور العطلة — مطابق لـ `getStudyMonths`.
  List<int>? get studyMonths {
    final raw = db.settings[_kStudyMonths];
    final decoded = raw == null || raw.isEmpty ? _storedColorsMap[studyMonthsColorKey] : _tryDecodeList(raw);
    if (decoded is! List) return null;
    final months = <int>{
      for (final m in decoded)
        if (m is num && m >= 1 && m <= 12) m.toInt(),
    }.toList()
      ..sort();
    return months.isEmpty ? null : months;
  }

  static List<dynamic>? _tryDecodeList(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is List ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStudyMonths(List<int> months) async {
    requireSection('settings');
    final clean = <int>{
      for (final m in months)
        if (m >= 1 && m <= 12) m,
    }.toList()
      ..sort();
    await db.setSetting(_kStudyMonths, clean.isEmpty ? null : jsonEncode(clean));
    await _syncInstitutionSetting(studyMonthsColorKey, clean);
    notifyListeners();
  }

  static const _kStudyMonths = 'study_months';

  /// بادئة معرّف المستحق الشهري — معرّف حتمي فلا يتكرر بين الأجهزة.
  static const dueIdPrefix = 'due_';

  /// عنوان قسط رسم الحجز — معرّف في `balance.dart` مع ترتيب السداد الذي يقدّمه.
  static const seatInstallmentTitle = seatTitle;

  String monthlyDueId(String studentId, String monthKey) => '$dueIdPrefix${studentId}_$monthKey';

  /// رسم المرحلة لكل اسم مرحلة — المقابل لـ `loadFeeByGrade`.
  Map<String, double> feeByGrade() {
    final map = <String, double>{};
    for (final f in gradeFees) {
      final key = f.gradeName.trim().toLowerCase();
      map.putIfAbsent(key, () => f.monthlyFee);
    }
    return map;
  }

  /// رسم الطالب الخاص إن حُدِّد (والصفر إعفاء)، وإلا رسم صفه؛ `null` حين لا رسم له.
  double? resolveMonthlyFee(Student student, [Map<String, double>? fees]) {
    final custom = student.customMonthlyFee;
    if (custom != null) return custom;
    return (fees ?? feeByGrade())[student.gradeLevel.trim().toLowerCase()];
  }

  /// عدد الطلاب النشطين بلا رسم معرّف — تحذير في شاشة المراحل.
  int get studentsMissingFee {
    final fees = feeByGrade();
    return students.where((s) => s.status == 'active' && resolveMonthlyFee(s, fees) == null).length;
  }

  /// توليد مستحق الشهر الحالي لطلاب المدرسة — المقابل لـ `generateMonthlyDues`.
  ///
  /// لا يمسّ مستحقاً قائماً: كل شهر يثبت بالرسم النافذ لحظة استحقاقه، وتغيير
  /// الرسم لاحقاً يسري على ما بعده. ومن له خطة أقساط يدوية لا يُولَّد له شيء
  /// حتى لا يُطالَب مرتين.
  ({int created, int missingFee}) generateMonthlyDues({DateTime? now}) {
    final months = studyMonths;
    if (months == null) return (created: 0, missingFee: 0);

    final today = now ?? DateTime.now();
    if (!months.contains(today.month)) return (created: 0, missingFee: 0);
    final monthKey = '${today.year}-${today.month.toString().padLeft(2, '0')}';

    final fees = feeByGrade();
    var created = 0;
    var missingFee = 0;

    for (final student in students.where((s) => s.status == 'active').toList()) {
      final dueId = monthlyDueId(student.id, monthKey);
      final existing = installments.where((i) => i.studentId == student.id).toList();
      if (existing.any((i) => i.id == dueId)) continue;

      // خطة أقساط يدوية تغطي رسومه أصلاً. الرسم الإضافي ليس خطةً: يُقيَّد فوق
      // الرسم الشهري، فوجوده لا يوقف توليد المستحق
      final manual = existing.any((i) =>
          !i.id.startsWith(dueIdPrefix) && !i.id.startsWith(feeIdPrefix) && i.title != seatInstallmentTitle);
      if (manual) continue;

      final fee = resolveMonthlyFee(student, fees);
      if (fee == null) {
        missingFee++;
        continue;
      }
      if (fee <= 0) continue;

      // رسم الحجز يُخصم من أول مستحق مرة واحدة
      final seat = existing.where((i) => i.title == seatInstallmentTitle).firstOrNull;
      final hadDues = existing.any((i) => i.id.startsWith(dueIdPrefix));
      final deduction = seat != null && !hadDues ? seat.amount : 0.0;
      final amount = fee - deduction;

      final inst = Installment(
        id: dueId,
        studentId: student.id,
        title: 'رسوم ${today.month.toString().padLeft(2, '0')}/${today.year}',
        amount: amount < 0 ? 0 : amount,
        dueDate: DateTime(today.year, today.month, 1),
        syncStatus: 'pending',
        createdAt: _nowIso(),
        updatedAt: _nowIso(),
      );
      installments.add(inst);
      _queue('installments', inst.id, 'INSERT', inst.toCloud());

      // خُصم من مستحق الشهر أقل من رسم الحجز: لا يُطالَب الطالب بفرقٍ لم يُخصم له
      if (seat != null && deduction > fee) {
        seat.amount = fee;
        seat.updatedAt = _nowIso();
        seat.syncStatus = 'pending';
        _queue('installments', seat.id, 'UPDATE', seat.toCloud());
      }

      markDirty('installments');
      _persistStudentLedger(student);
      created++;
    }

    if (created > 0) notifyListeners();
    return (created: created, missingFee: missingFee);
  }

  /// أشهر الدراسة الباقية بعد [month] — `remainingStudyMonths`.
  int remainingStudyMonths(int month) {
    final months = studyMonths;
    if (months == null) return 0;
    // السنة الدراسية تبدأ في أيلول: كانون الثاني بعد كانون الأول لا قبله
    int offset(int m) => (m - 9 + 12) % 12;
    return months.where((m) => offset(m) > offset(month)).length;
  }

  /// المتوقع على الطلاب النشطين لباقي السنة — `projectRemainingYear`.
  ///
  /// الأشهر القادمة والأقساط التي لم يحن موعدها، ناقصاً ما دفعه كل طالب مقدماً.
  /// رقمٌ للإدارة وحدها: لا يُطالَب به قبل موعده، ولذلك لا يدخل في «المستحق».
  double projectRemainingYear({DateTime? today}) {
    final day = today ?? DateTime.now();
    final upcoming = remainingStudyMonths(day.month);
    final fees = feeByGrade();
    var total = 0.0;

    for (final student in students.where((s) => s.status == 'active')) {
      final own = installments.where((i) => i.studentId == student.id).toList();
      // خطة أقساط يدوية تحلّ محل الرسم الشهري، فلا يُحتسب الشهري فوقها
      final hasPlan = own.any((i) =>
          !i.id.startsWith(dueIdPrefix) && !i.id.startsWith(feeIdPrefix) && i.title != seatInstallmentTitle);
      final monthly = hasPlan ? 0.0 : math.max(0.0, resolveMonthlyFee(student, fees) ?? 0);
      var scheduled = 0.0;
      for (final i in own) {
        if (!isInstallmentDue(i, day)) scheduled += math.max(0.0, i.remaining);
      }
      final credit = student.balance > 0 ? student.balance : 0.0;
      final projected = monthly * upcoming + scheduled - credit;
      if (projected > 0) total += projected;
    }
    return total;
  }

  /// نقل طلاب إلى شعبة — المقابل لـ `StudentsService.assignSection`.
  ///
  /// الطالب في شعبة واحدة، فمن كان في غيرها يُنقل منها. يعيد عدد من نُقل.
  int assignSection(Iterable<String> studentIds, String section) {
    requireSection('students');
    final target = section.trim();
    final now = _nowIso();
    var moved = 0;

    for (final id in studentIds) {
      final student = studentById(id);
      if (student == null || student.section.trim() == target) continue;
      student.section = target;
      student.updatedAt = now;
      student.syncStatus = 'pending';
      _queue('students', student.id, 'UPDATE', student.toCloud());
      moved++;
    }

    if (moved > 0) {
      // النقل يسجّله في مواد شعبته الجديدة وينهي تسجيله في مواد سابقتها
      syncStudentRoomEnrollments(studentIds);
      markDirty('students');
      notifyListeners();
    }
    return moved;
  }

  /// طلاب المرحلة خارج هذه الشعبة — مرشّحو الإضافة إليها.
  ///
  /// المعلّق بعد الترقية يحتاج شعبة، ومن في شعبة أخرى يُنقل منها؛ ومن بلا شعبة
  /// يتصدّر لأنه بلا مكان أصلاً.
  List<Student> sectionCandidates(Classroom room) {
    final list = students.where((s) {
      if (s.status != 'active' && s.status != 'pending') return false;
      if (isSameSectionName(s.section, room.name)) return false;
      // مطابقة تامة كـ `isSameGrade`: شعبةٌ بلا مرحلة كانت تعرض طلاب كل المراحل
      return isSameGrade(s.gradeLevel, room.gradeLevel);
    }).toList();

    list.sort((a, b) {
      final byPlace = (a.section.trim().isEmpty ? 0 : 1).compareTo(b.section.trim().isEmpty ? 0 : 1);
      return byPlace != 0 ? byPlace : a.fullName.compareTo(b.fullName);
    });
    return list;
  }

  /// ترقية طلاب المدرسة النشطين — المقابل لـ `promoteStudents`.
  ///
  /// كل صف يُنقل إلى الصف المحدد له، ومن لا صف بعده يُؤرشف طلابه. تُمسح الشعبة
  /// ويصير الطالب «بانتظار التأكيد» فلا تُستحق عليه رسوم قبل تأكيده، وديونه تبقى.
  ({int promoted, int archived}) promoteStudents(Map<String, String?> nextGradeOf) {
    requireSection('students');
    final targets = {
      for (final e in nextGradeOf.entries) e.key.trim().toLowerCase(): e.value,
    };
    var promoted = 0;
    var archived = 0;

    for (final student in students.where((s) => s.status == 'active').toList()) {
      final key = student.gradeLevel.trim().toLowerCase();
      if (!targets.containsKey(key)) continue;
      final to = targets[key];

      student.section = '';
      if (to != null && to.trim().isNotEmpty) {
        student.gradeLevel = to.trim();
        student.status = 'pending';
        promoted++;
      } else {
        student.status = 'archived';
        archived++;
      }
      student.updatedAt = _nowIso();
      student.syncStatus = 'pending';
      _queue('students', student.id, 'UPDATE', student.toCloud());
    }

    if (promoted + archived > 0) {
      markDirty('students');
      notifyListeners();
    }
    return (promoted: promoted, archived: archived);
  }

  /// كائن الألوان كما حُفظ بكل مفاتيحه، ومنها ما لا تعرفه هذه النسخة —
  /// `__custom_payment_methods` مثلاً. الكتابة فوقه بالألوان الخمسة وحدها
  /// كانت تمسح من السحابة إعدادات حفظتها نسخة أخرى في العمود نفسه.
  Map<String, dynamic> get _storedColorsMap {
    final raw = db.settings[institutionColorsKey];
    if (raw == null || raw.isEmpty) return {};
    try {
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  // ── وسائل الدفع وقواعد الخصم (المقابل لـ finance/paymentMethods.ts) ───────

  /// وسائل الدفع كما ضبطتها المنشأة، أو الأساسية إن لم تُضبط.
  ///
  /// تُقرأ من إعداد الجهاز أولاً، فإن لم يوجد فمن كائن ألوان المنشأة المتزامن —
  /// وهو الطريق الذي تصل به ضبطات سطح المكتب إلى الجوال.
  List<PaymentMethodItem> get paymentMethods {
    final local = db.settings[customPaymentMethodsKey];
    if (local != null && local.trim().isNotEmpty) return decodePaymentMethods(local);
    return decodePaymentMethods(_storedColorsMap[customPaymentMethodsColorKey]);
  }

  /// الوسائل المعروضة عند القبض — المعطّلة تبقى للسندات القديمة ولا تُعرض.
  List<PaymentMethodItem> get activePaymentMethods => paymentMethods.where((m) => m.enabled).toList();

  /// مسمّى وسيلة الدفع كما ضبطته المنشأة — مطابق لـ `getPaymentMethodLabel`.
  String paymentMethodLabel(String? key) {
    final id = (key ?? '').trim();
    if (id.isEmpty) return '-';
    final found = paymentMethods.where((m) => m.id == id).firstOrNull;
    // سند قديم بوسيلة حُذفت: يبقى اسمها المعروف بدل معرّف خام في الوصل
    return found?.name ?? paymentMethodNames[id] ?? id;
  }

  Future<void> savePaymentMethods(List<PaymentMethodItem> methods) async {
    requireSection('settings');
    final encoded = encodePaymentMethods(methods);
    await db.setSetting(customPaymentMethodsKey, encoded);
    // ومعها نسخة في ألوان المنشأة كي تصل بقية الأجهزة، كما تفعل النسخة المكتبية
    await db.setSetting(
      institutionColorsKey,
      jsonEncode({..._storedColorsMap, customPaymentMethodsColorKey: jsonDecode(encoded)}),
    );
    _persistInstitutionRow();
    notifyListeners();
  }

  /// مخطط علامات المدرسة — مكوّنات كل فصل وأوزانها.
  ///
  /// يُقرأ من إعداد الجهاز، فإن لم يوجد فمن كائن المنشأة المتزامن: هو طريق وصول
  /// ما ضبطه سطح المكتب إلى الجوال وإلى بوابتي الطالب وولي الأمر.
  static const gradingSchemeKey = 'grading_scheme';
  static const gradingSchemeColorKey = '__grading_scheme';

  GradingScheme get gradingScheme {
    final local = db.settings[gradingSchemeKey];
    if (local != null && local.trim().isNotEmpty) return GradingScheme.decode(local);
    final synced = _storedColorsMap[gradingSchemeColorKey];
    return synced is Map ? GradingScheme.fromMap(Map<String, dynamic>.from(synced)) : GradingScheme.empty;
  }

  Future<void> saveGradingScheme(GradingScheme scheme) async {
    requireSection('settings');
    await db.setSetting(gradingSchemeKey, scheme.isEmpty ? null : scheme.encode());
    await _syncInstitutionSetting(gradingSchemeColorKey, scheme.toMap());
    notifyListeners();
  }

  /// معدل الطالب في فصل وفق المخطط — يشمل تقييماته كلها في كل المواد.
  TermGrade termGradeOf(String studentId, String term) =>
      computeTermGrade(evaluationsOfStudent(studentId), gradingScheme, term);

  /// بادئة معرّف قسط الرسم الإضافي — `FEE_ID_PREFIX`.
  static const feeIdPrefix = 'fee_';

  /// معرّف حتمي: الرسم لا يُقيَّد على الطالب مرتين مهما تكرر التطبيق.
  static String feeInstallmentId(String itemId, String studentId) => '$feeIdPrefix${itemId}_$studentId';

  /// الرسوم الإضافية المعتمدة — `getFeeItems`.
  List<FeeItem> get feeItems {
    final raw = db.settings[feeItemsKey];
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map) FeeItem.fromMap(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveFeeItems(List<FeeItem> items) async {
    requireSection('settings');
    final encoded = [for (final i in items) i.toMap()];
    await db.setSetting(feeItemsKey, jsonEncode(encoded));
    // ومعها نسخة في كائن المنشأة كي تصل بقية الأجهزة
    await _syncInstitutionSetting('__fee_items', encoded);
    notifyListeners();
  }

  /// تقييد الرسم على الطلاب المستهدفين ممن لم يُقيَّد عليهم — `applyFeeItem`.
  /// يعيد عدد من قُيّد عليهم.
  int applyFeeItem(FeeItem item) {
    requireSection('settings');
    final now = _nowIso();
    final due = parseIsoDate(item.dueDate) ?? DateTime.now();
    var created = 0;

    for (final student in students.where((s) => s.status == 'active')) {
      if (item.gradeLevel.isNotEmpty && !isSameGrade(student.gradeLevel, item.gradeLevel)) continue;
      final id = feeInstallmentId(item.id, student.id);
      if (installments.any((i) => i.id == id)) continue;

      final inst = Installment(
        id: id,
        studentId: student.id,
        title: item.name,
        amount: item.amount,
        dueDate: due,
        syncStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      installments.add(inst);
      _queue('installments', inst.id, 'INSERT', inst.toCloud());
      _persistStudentLedger(student);
      created++;
    }

    if (created > 0) {
      markDirty('installments');
      notifyListeners();
    }
    return created;
  }

  /// إزالة الرسم عن الطلاب، إلا من عليه سند مربوط به — `removeFeeItem`.
  /// يعيد عدد من بقي الرسم عليهم.
  int removeFeeItem(String itemId) {
    requireSection('settings');
    final prefix = '$feeIdPrefix${itemId}_';
    final rows = installments.where((i) => i.id.startsWith(prefix)).toList();
    var kept = 0;

    for (final row in rows) {
      // سندٌ مربوط بالقسط: حذفه يترك سنداً يشير إلى لا شيء
      final linked = payments.any((p) => !p.cancelled && p.installmentId == row.id);
      if (linked) {
        kept++;
        continue;
      }
      installments.remove(row);
      _queue('installments', row.id, 'DELETE', null);
      final student = studentById(row.studentId);
      if (student != null) _persistStudentLedger(student);
    }

    if (rows.length > kept) {
      markDirty('installments');
      notifyListeners();
    }
    return kept;
  }

  SchoolDiscountRules get discountRules => SchoolDiscountRules.decode(db.settings[discountRulesKey]);

  Future<void> saveDiscountRules(SchoolDiscountRules rules) async {
    requireSection('settings');
    await db.setSetting(discountRulesKey, rules.encode());
    // ومعها نسخة في كائن المنشأة كي تصل بقية الأجهزة
    await _syncInstitutionSetting('__discount_rules', rules.toMap());
    notifyListeners();
  }

  Future<void> saveInstitution({
    String? name,
    String? logo,
    InstitutionColors? colors,
  }) async {
    if (name != null) {
      institutionName = name.trim();
      await db.setSetting(institutionNameKey, institutionName.isEmpty ? null : institutionName);
    }
    if (logo != null) await db.setSetting(institutionLogoKey, logo.isEmpty ? null : logo);
    if (colors != null) {
      await db.setSetting(institutionColorsKey, jsonEncode({..._storedColorsMap, ...colors.toMap()}));
    }
    applyBrandColors();
    _persistInstitutionRow();
    notifyListeners();
  }

  /// حفظ هوية المنشأة في جدول `institution_settings` لتصل كل الأجهزة.
  /// حفظها محلياً وحده كان يعني أن الشعار لا يظهر على جهاز الاستقبال أبداً.
  void _persistInstitutionRow() {
    final tid = tenantId;
    if (tid == null) return;
    final row = {
      'id': tid,
      // النظام مدرسي وحده: يُكتب ثابتاً ولا يُقرأ، لأن أجهزة لم تُحدَّث ما زالت تقرؤه
      'institution_type': 'school',
      'institution_name': institutionName,
      'logo': institutionLogo.isEmpty ? null : institutionLogo,
      'colors': {..._storedColorsMap, ...institutionColors.toMap()},
      'updated_at': _nowIso(),
    };
    final bucket = extraCloud.putIfAbsent('institution_settings', () => []);
    final i = bucket.indexWhere((e) => '${e['id']}' == tid);
    if (i >= 0) {
      bucket[i] = row;
      _queue('institution_settings', tid, 'UPDATE', row);
    } else {
      bucket.add(row);
      _queue('institution_settings', tid, 'INSERT', row);
    }
    markDirty('institution_settings');
  }

  /// قراءة هوية المنشأة القادمة من السحابة إلى الإعدادات المحلية.
  Future<void> hydrateInstitution() async {
    final tid = tenantId;
    if (tid == null) return;
    final row = extraCloud['institution_settings']?.where((e) => '${e['id']}' == tid).firstOrNull;
    if (row == null) return;
    final name = '${row['institution_name'] ?? ''}'.trim();
    final logo = row['logo'];
    final colors = row['colors'];
    if (name.isNotEmpty) {
      institutionName = name;
      await db.setSetting(institutionNameKey, name);
    }
    if (logo is String && logo.isNotEmpty) await db.setSetting(institutionLogoKey, logo);
    if (colors is Map) {
      final synced = Map<String, dynamic>.from(colors);
      await db.setSetting(institutionColorsKey, jsonEncode(synced));

      // إعدادات المنشأة الأخرى تُحمَل داخل `colors` في الجدول المتزامن — مطابق
      // لـ `hydrateInstitutionSettings`. بلا استعادتها هنا تبقى محليةً على الجهاز
      // الذي ضبطها: رسم الحجز يظهر 50 على سطح المكتب و«بلا رسم» على الجوال.
      final features = synced['__system_features'];
      if (features is Map) await db.setSetting(systemFeaturesKey, jsonEncode(features));

      final rules = synced['__discount_rules'];
      if (rules is Map) await db.setSetting(discountRulesKey, jsonEncode(rules));

      final fees = synced['__fee_items'];
      if (fees is List) await db.setSetting(feeItemsKey, jsonEncode(fees));

      final seatFee = synced[seatFeeColorKey];
      if (seatFee is num) await db.setSetting(seatReservationFeeKey, '${seatFee < 0 ? 0 : seatFee}');

      if (synced.containsKey(studyMonthsColorKey)) {
        final months = synced[studyMonthsColorKey];
        final clean = months is List
            ? (<int>{
                for (final m in months)
                  if (m is num && m >= 1 && m <= 12) m.toInt(),
              }.toList()
              ..sort())
            : const <int>[];
        await db.setSetting(_kStudyMonths, clean.isEmpty ? null : jsonEncode(clean));
      }

      final scheme = synced[gradingSchemeColorKey];
      if (scheme is Map) {
        await db.setSetting(gradingSchemeKey, jsonEncode(Map<String, dynamic>.from(scheme)));
      }

      final methods = synced[customPaymentMethodsColorKey];
      if (methods is List && methods.isNotEmpty) {
        await db.setSetting(customPaymentMethodsKey, jsonEncode(methods));
      }
    }
    applyBrandColors();
    notifyListeners();
  }

  List<StudentEnrollment> enrollmentsOf(String studentId) =>
      enrollments.where((e) => e.studentId == studentId).toList();

  /// سبب عدم سريان الاشتراك، أو `null` إن كان سارياً.
  /// مطابق لـ `tenantService.isSubscriptionValid` في النسخة المكتبية.
  String? subscriptionProblem(Tenant t) {
    if (!t.active) return 'تم إيقاف هذه المنشأة من قبل إدارة المنصة.';
    if (t.planType == 'lifetime') return null;
    if (t.expiresAt.isBefore(DateTime.now())) {
      return 'انتهت فترة اشتراك هذه المنشأة. يرجى التواصل مع المطور لتجديد الاشتراك.';
    }
    return null;
  }

  @override
  String? get tenantId => currentTenant?.id;

  @override
  String? get dbTenantId => db.settings[_kDbTenant];

  @override
  bool get isMaster => isMasterAdmin;

  int get pendingPush {
    cleanupBogusDemoUserSyncs(pendingSyncs);
    return pendingSyncs.length;
  }

  int get pendingPull => sync.remotePendingCount;

  List<SyncRow> get pendingRows => sync.getPendingSummary().rows;

  String newId() => _uuid.v4();

  /// رمز دخول البوابة — ست خانات، مطابق لـ `generateRandomCode` في Center:
  /// `Math.floor(100000 + Math.random() * 900000)`.
  String newPortalCode() => (100000 + _rand.nextInt(900000)).toString();

  final _rand = math.Random();

  /// رمز لا يساوي [other] — كلمة الطالب وكلمة ولي أمره لا تتساويان أبداً،
  /// لأن السيرفر يرفض الدخول حين تتساويان (مطابق لـ `generateDistinctCode`).
  String newDistinctPortalCode(String other) {
    var code = newPortalCode();
    while (code == other.trim()) {
      code = newPortalCode();
    }
    return code;
  }

  /// ضمان وجود كلمتَي الطالب وولي أمره لكل طالب في القائمة. يعيد عدد الطلاب
  /// الذين وُلِّد لهم شيء.
  int ensureStudentPortalCodes(List<Student> list) {
    requireSection('students');
    var made = 0;
    for (final s in list) {
      final needsStudent = s.portalCode.trim().isEmpty;
      final needsParent = s.parentPortalCode.trim().isEmpty;
      if (!needsStudent && !needsParent) continue;
      if (needsStudent) s.portalCode = newDistinctPortalCode(s.parentPortalCode);
      if (needsParent) s.parentPortalCode = newDistinctPortalCode(s.portalCode);
      s.updatedAt = _nowIso();
      s.syncStatus = 'pending';
      queuePendingSync(pendingSyncs,
          tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
      markRecord('students', s.id);
      made++;
    }
    if (made > 0) {
      markDirty(_pendingTable);
      notifyListeners();
    }
    return made;
  }

  /// ضمان وجود رمز بوابة لمعلم.
  String ensureTeacherPortalCode(Teacher t) {
    if (t.portalCode.trim().isNotEmpty) return t.portalCode;
    t.portalCode = newPortalCode();
    upsertTeacher(t);
    return t.portalCode;
  }

  /// تسجيل الدخول — مطابق لـ `LandingPage.handleLogin` بعد الانتقال إلى
  /// Supabase Auth: السحابة تتحقق من كلمة المرور وتُصدر توكناً يحمل دور صاحبه
  /// ومنشأته، والجهاز لا يرى كلمة مرور ولا يقارنها.
  ///
  /// دون شبكة يبقى المسار المحلي القديم — للأجهزة المعزولة وللاختبارات.
  Future<String?> login(String username, String password) async {
    final u = username.trim().toLowerCase();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) {
      return 'أدخل اسم المستخدم وكلمة المرور';
    }

    // محاولة دخول جديدة: إشعار انتهاء الجلسة السابق لم يعد يعني شيئاً
    sessionExpiredNotice = null;
    await db.setSetting(_kLastUsername, username.trim());

    if (networkEnabled) return _cloudLogin(u, p);
    return _localLogin(u, p);
  }

  /// الدخول عبر Supabase Auth — المقابل لـ `signInWithUsername`.
  Future<String?> _cloudLogin(String username, String password) async {
    final result = await supabaseSignIn(username, password);
    if (result.claims == null) return result.error ?? 'تعذّر تسجيل الدخول';

    if (SupabaseAuth.isDeveloper) {
      loggedIn = true;
      isMasterAdmin = true;
      currentTenant = null;
      roleName = 'المطور العام';
      await _saveSession();
      await refreshTenantsFromCloud();
      notifyListeners();
      return null;
    }

    if (SupabaseAuth.role != 'tenant_admin') {
      await supabaseSignOut();
      return 'هذا الحساب لا يملك صلاحية الدخول إلى التطبيق';
    }

    final tenant = await tenantApi.findById(SupabaseAuth.tenantId);
    if (tenant == null) {
      await supabaseSignOut();
      return 'هذا الحساب غير مرتبط بمنشأة';
    }

    final problem = subscriptionProblem(tenant);
    if (problem != null) {
      await supabaseSignOut();
      return problem;
    }

    await _enterTenant(tenant);
    return null;
  }

  /// المسار المحلي: جهاز بلا شبكة أو بيئة اختبار.
  Future<String?> _localLogin(String u, String p) async {
    if (TenantService.hasMasterAccount &&
        u == TenantService.masterUsername.trim().toLowerCase() &&
        p == TenantService.masterPassword.trim()) {
      loggedIn = true;
      isMasterAdmin = true;
      currentTenant = null;
      roleName = 'المطور العام';
      await _saveSession();
      notifyListeners();
      return null;
    }

    final match = tenants
        .where((t) => t.username.trim().toLowerCase() == u && t.password.trim() == p)
        .firstOrNull;

    if (match != null) {
      final problem = subscriptionProblem(match);
      if (problem != null) return problem;
      await _enterTenant(match);
      return null;
    }

    // منشأة محفوظة محلياً (جهاز يعمل بلا اتصال)
    if (_tenantUser.isNotEmpty && u == _tenantUser.toLowerCase() && p == _tenantPass) {
      final saved = tenants.where((t) => t.username.trim().toLowerCase() == u).firstOrNull;
      if (saved != null) {
        final problem = subscriptionProblem(saved);
        if (problem != null) return problem;
        await _enterTenant(saved);
        return null;
      }
    }

    return 'اسم المستخدم أو كلمة المرور غير صحيحة';
  }

  /// ما يجري مرة واحدة بعد دخول منشأة — مطابق لـ `useEffect` في App.tsx:
  /// توحيد أرقام السندات، وتنظيف طابور المزامنة، واستشارة السحابة عن آخر رقم،
  /// وفتح قناة التحديث اللحظي.
  Future<void> afterEnter() async {
    if (!loggedIn || isMasterAdmin) return;
    cleanupBogusDemoUserSyncs(pendingSyncs);
    await migrateReceiptNumbers();
    await migrateAttendanceIds();
    await migratePaymentSnapshots();
    await migrateSectionNames();
    await migrateEnrollmentRooms();
    await migrateWithdrawnStatus();
    dedupeAttendance();
    if (!networkEnabled) return;
    // الاستماع أولاً: لا يتوقف على نجاح خطوات الشبكة التي تليه
    await startRealtime();
    await primeReceiptCounter();
    // مرفقٌ تعثّر رفعه على جهاز بلا اتصال يُعاد الآن، وإلا بقي على الجهاز وحده
    unawaited(retryPendingAttachments());
    unawaited(flushPendingNotices());
    // الدخول يرفع ما تراكم دون اتصال ويسحب ما فات، بلا فحصٍ كامل يسبقهما
    startAutoSync();
    notifyListeners();
  }

  // ── التحديث اللحظي ─────────────────────────────────────────────────────────
  RealtimeListener? _realtime;

  bool get realtimeConnected => _realtime?.isConnected ?? false;

  /// فتح قناة الاستماع لتغييرات السحابة لهذه المنشأة.
  Future<void> startRealtime() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled) return;
    _realtime ??= RealtimeListener(
      tables: syncedTables,
      onChange: handleRemoteEvent,
      onJoined: handleRealtimeJoined,
      onBroadcast: handlePeerChanged,
    );
    await _realtime!.connect(tid);
  }

  Future<void> stopRealtime() async {
    _joinCheck?.cancel();
    _joinCheck = null;
    await _realtime?.disconnect();
    _realtime = null;
  }

  Timer? _joinCheck;

  /// (إعادة) الاشتراك: ما تغيّر أثناء الانقطاع لم يصل حدثاً، فيُفحص مرة واحدة
  /// بعد أن تستقر ردود الاشتراك لكل الجداول.
  void handleRealtimeJoined() {
    if (autoSync) {
      // الاشتراك يعني أن الاتصال عاد: ما تعثّر رفعه لا ينتظر بقية مهلته، والسحب
      // فوري كما عند `SUBSCRIBED` في النسخة المكتبية
      _pushFailures = 0;
      if (pendingSyncs.any((a) => a.retryCount < maxSyncRetries)) scheduleAutoPush(Duration.zero);
      scheduleAutoPull(Duration.zero);
      unawaited(retryPendingAttachments());
      unawaited(flushPendingNotices());
      return;
    }
    _joinCheck?.cancel();
    _joinCheck = Timer(const Duration(milliseconds: 1500), () async {
      await sync.checkRemoteChanges();
      notifyListeners();
    });
  }

  // ── المزامنة التلقائية ─────────────────────────────────────────────────────
  // مطابقة لـ `startAutoSync` في sync.ts: رفعٌ بعد كل تعديل، وسحبٌ عند إشارة جهاز
  // آخر وعند الدخول والعودة إلى التطبيق. كانت المزامنة بزرٍّ يدوي يسبقه فحصٌ كامل
  // لكل الجداول، فبدا الرفع والسحب بطيئين ولم تصل تعديلات الأجهزة الأخرى وحدها.
  static const autoPushDelay = Duration(seconds: 3);
  static const autoPullDelay = Duration(milliseconds: 1500);
  static const _resumePullGap = Duration(seconds: 60);

  bool autoSync = false;
  Timer? _autoPushTimer;
  Timer? _autoPullTimer;
  DateTime? _lastResumePull;

  /// محاولات الرفع المتتالية التي تعثّرت بانقطاع — تحدد مهلة المحاولة التالية.
  int _pushFailures = 0;

  /// مهل إعادة الرفع بعد انقطاع: تتباعد ولا تتجاوز الدقيقة، وعودة الاتصال تختصرها.
  static const pushRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static Duration pushRetryDelay(int failures) =>
      pushRetryDelays[(failures - 1).clamp(0, pushRetryDelays.length - 1)];

  @visibleForTesting
  bool get autoPushScheduled => _autoPushTimer?.isActive ?? false;

  @visibleForTesting
  Duration? lastAutoPushDelay;

  /// ما بعد رفع تلقائي — دالة صرفة قابلة للاختبار.
  ///
  /// [attempted] معرّفات ما كان قابلاً للرفع قبل الرفع مع رصيد محاولاته. عملية
  /// بقيت برصيدها وعليها خطأ تعثّرت بانقطاع لا بعيب فيها، فتُعاد بمهلة متباعدة.
  /// وعملية أُضيفت أثناء الرفع لم تُحاوَل بعد، فتُرفع بالمهلة المعتادة. الفشل
  /// الدائم لا يُعاد وحده، كما في النسخة المكتبية: ينتظر تعديلاً تالياً أو زرّ
  /// إعادة المحاولة.
  static ({Duration? delay, bool stalled}) autoPushFollowUp(
    Map<int, int> attempted,
    Iterable<PendingSync> queue,
    int failures,
  ) {
    final remaining = queue.where((a) => a.retryCount < maxSyncRetries).toList();
    if (remaining.isEmpty) return (delay: null, stalled: false);
    final stalled = remaining.any((a) => attempted[a.id] == a.retryCount && a.lastError != null);
    if (stalled) return (delay: pushRetryDelay(failures + 1), stalled: true);
    if (remaining.any((a) => !attempted.containsKey(a.id))) return (delay: autoPushDelay, stalled: false);
    return (delay: null, stalled: false);
  }

  void startAutoSync() {
    if (autoSync || !networkEnabled || !loggedIn || isMasterAdmin) return;
    autoSync = true;
    scheduleAutoPush(Duration.zero);
    scheduleAutoPull(Duration.zero);
  }

  void stopAutoSync() {
    autoSync = false;
    _pushFailures = 0;
    _autoPushTimer?.cancel();
    _autoPullTimer?.cancel();
    _autoPushTimer = null;
    _autoPullTimer = null;
  }

  /// التعديلات المتتالية تُجمع في رفعٍ واحد بعد أن يهدأ المستخدم.
  void scheduleAutoPush([Duration delay = autoPushDelay]) {
    if (!autoSync) return;
    lastAutoPushDelay = delay;
    _autoPushTimer?.cancel();
    _autoPushTimer = Timer(delay, () => _runAuto(push: true));
  }

  void _onQueueChanged() {
    // الرفع نفسه يعدّل الطابور: الجدولة منه تُدخل المحاولة الفاشلة في حلقة.
    // ما يُضاف أثناءه يُلتقط بعد انتهائه في `autoPushFollowUp`
    if (!autoSync || sync.isSyncing) return;
    scheduleAutoPush();
  }

  /// جهاز آخر رفع تعديلاته — إشارة `changed` على قناة المنشأة.
  void handlePeerChanged() => scheduleAutoPull();

  @visibleForTesting
  bool get autoPullScheduled => _autoPullTimer?.isActive ?? false;

  @visibleForTesting
  Duration? lastAutoPullDelay;

  /// عدد إشارات `changed` التي أرسلها هذا الجهاز بعد رفع ناجح.
  @visibleForTesting
  int peerNotifications = 0;

  void _notifyPeers() {
    peerNotifications++;
    _realtime?.broadcastChanged();
  }

  /// إشارات متتالية من أجهزة أخرى تُجمع في سحبٍ واحد.
  void scheduleAutoPull([Duration delay = autoPullDelay]) {
    if (!autoSync) return;
    lastAutoPullDelay = delay;
    _autoPullTimer?.cancel();
    _autoPullTimer = Timer(delay, () => _runAuto(push: false));
  }

  /// العودة إلى التطبيق ترفع وتسحب، لكن لا أكثر من مرة في الدقيقة.
  void pullOnResume([DateTime? now]) {
    final at = now ?? DateTime.now();
    final last = _lastResumePull;
    if (last != null && at.difference(last) < _resumePullGap) return;
    _lastResumePull = at;
    scheduleAutoPush(Duration.zero);
    scheduleAutoPull(Duration.zero);
  }

  Future<void> _runAuto({required bool push}) async {
    // جهازٌ في التهيئة ينزّل بياناته بنفسه: سحبٌ موازٍ يتزاحم معه
    if (!autoSync || needsInitialSetup) return;
    // عملية جارية: تُعاد المحاولة بعدها بدل التزاحم على الطابور نفسه
    if (sync.isSyncing) {
      if (push) {
        scheduleAutoPush();
      } else {
        scheduleAutoPull();
      }
      return;
    }
    try {
      if (push) {
        final attempted = {
          for (final a in pendingSyncs)
            if (a.retryCount < maxSyncRetries) a.id: a.retryCount,
        };
        if (attempted.isEmpty) return;
        final result = await sync.push(refreshRemote: false);
        // الأجهزة الأخرى تسحب فور الإشارة بدل أن تنتظر عودة مستخدمها
        if (result.pushed > 0) _notifyPeers();
        final next = autoPushFollowUp(attempted, pendingSyncs, _pushFailures);
        _pushFailures = next.stalled ? _pushFailures + 1 : 0;
        if (next.delay != null) scheduleAutoPush(next.delay!);
      } else {
        await sync.pull();
      }
    } catch (_) {
      // الانقطاع لا يُظهر خطأ: الرفع يُعاد بمهلة متباعدة، والسحب عند إشارة أو عودة
      if (push) {
        _pushFailures++;
        scheduleAutoPush(pushRetryDelay(_pushFailures));
      }
    }
  }

  /// تغيير وصل لحظياً من السحابة — مطابق لـ `handleRealtimeChange` في sync.ts.
  ///
  /// يُنبّه بوجود تعديل ولا يطبّقه، ويُحسب لكل سجل من الحدث نفسه بلا استعلام.
  /// التجميع السابق كان يُسقط كل حدث يلي آخر بأقل من ثانية.
  void handleRemoteEvent(RealtimeEvent e) {
    if (!syncedTables.contains(e.table)) return;
    final record = e.record;

    // الحذف يحمل المفتاح وحده: يُسقط لاختلاف المنشأة لا لغياب tenant_id
    final remoteTenant = record['tenant_id']?.toString() ?? '';
    if (remoteTenant.isNotEmpty && remoteTenant != tenantId) return;

    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) return;

    // تعديل ما زال في طابور الرفع عندنا — ليس قادماً من الخارج
    if (pendingSyncs.any((p) => p.tableName == e.table && p.recordId == id)) return;
    scheduleAutoPull();

    final local = recordOf(e.table, id);
    if (e.type == 'DELETE') {
      // الحذف يهمّنا فقط إن كان السجل ما زال عندنا
      if (local == null) return;
    } else if (local != null &&
        toTimestamp(record['updated_at']) <= toTimestamp(local['updated_at']) + stampToleranceMs) {
      // صدى تعديلاتنا نحن بعد رفعها: نسختنا نفسها أو أحدث منها
      return;
    }

    if (sync.remotePendingIds.add('${e.table}:$id')) notifyListeners();
  }

  /// إعدادات تخص منشأة بعينها — تُمسح حين ينتقل الجهاز إلى غيرها.
  ///
  /// الاسم والشعار والألوان والميزات وطرق الدفع وقواعد الخصم ورسم حجز المقعد
  /// وهوية الجهاز وأعلام الترحيل: تركها كان يجعل المنشأة الجديدة تقرأ مخلفات
  /// سابقتها — تفتح باسمها وشعارها، وتُصدر سنداتها باسم موظف مدرسة أخرى.
  static const _tenantScopedSettings = [
    institutionNameKey,
    institutionLogoKey,
    institutionColorsKey,
    seatReservationFeeKey,
    feeItemsKey,
    systemFeaturesKey,
    customPaymentMethodsKey,
    discountRulesKey,
    gradingSchemeKey,
    receiptMigrationKey,
    attendanceIdMigrationKey,
    paymentSnapshotKey,
    sectionNameMigrationKey,
    enrollmentRoomMigrationKey,
    withdrawnStatusMigrationKey,
    _kDeviceUser,
    _kReceiptLabel,
    _kReceiptCounter,
    _kSetupPending,
    _kCustomUser,
    _kCustomPass,
  ];

  Future<void> _clearTenantScopedSettings() async {
    for (final key in _tenantScopedSettings) {
      await db.setSetting(key, null);
    }
    institutionName = '';
    deviceUserId = null;
    roleName = 'مدير';
  }

  Future<void> _enterTenant(Tenant tenant) async {
    // جهاز انتقل من منشأة إلى أخرى: بيانات الأولى وإعداداتها لا تبقى تحت
    // الثانية. السحب يُعيد بناء المحلي من سحابة المنشأة الجديدة.
    final previous = dbTenantId;
    if (previous != null && previous != tenant.id) {
      await wipeAllData();
      await _clearTenantScopedSettings();
    }
    await db.setSetting(_kDbTenant, tenant.id);

    // المنشأة تُحفظ على القرص: الجلسة تُستعاد منها عند الإقلاع التالي، فلا يُطالَب
    // المستخدم بتسجيل دخول جديد كلما أغلق التطبيق — والتطبيق يعمل بلا إنترنت
    final at = tenants.indexWhere((t) => t.id == tenant.id);
    if (at >= 0) {
      tenants[at] = tenant;
    } else {
      tenants.add(tenant);
    }
    markDirty('tenants');

    // الحالة كاملةً قبل أي إخطار: تحديد الدخول ثم فتح بوابة التهيئة في نفس
    // اللحظة. ترك حسم البوابة إلى ما بعد `hydrateInstitution` — وهي تُخطر
    // الشاشات — كان يعرض شاشة العمل فارغة للحظة ثم يقفز إلى شاشة التهيئة.
    isMasterAdmin = false;
    currentTenant = tenant;
    _setupPending = true;
    loggedIn = true;

    _tenantUser = tenant.username;
    _tenantPass = tenant.password;
    final me = deviceUserId == null ? null : users.where((x) => x.id == deviceUserId).firstOrNull;
    roleName = me == null ? 'مدير' : roleLabel(me.role);
    notifyListeners();

    // علامة التهيئة المعلّقة قبل حفظ الجلسة: لو أُغلق التطبيق أو انقطع الاتصال
    // أثناء السحب الأولي، يُقلع على شاشة التهيئة لا على شاشة العمل
    await db.setSetting(_kSetupPending, tenant.id);
    await db.setSetting(_kCustomUser, tenant.username);
    await db.setSetting(_kCustomPass, tenant.password);
    // اسم العرض يُكتب مرة واحدة: لو خصّصه المدير فلا يُدهس عند كل دخول
    if (institutionName.trim().isEmpty) {
      institutionName = tenant.name;
      await db.setSetting(institutionNameKey, tenant.name);
    }
    await _saveSession();
    await hydrateInstitution();

    // الترحيلات وفتح قناة السحابة لا تحبس زر الدخول: شاشة التهيئة تسحب بنفسها
    unawaited(afterEnter());
    notifyListeners();
  }

  /// دخول المطور إلى منشأة — مطابق لـ `handleEnterTenant` ثم `startTenantSession`.
  ///
  /// كان يمرّ على `login` بكلمة مرور المنشأة، وكلمات المرور صارت في Supabase Auth
  /// ولا تصل الجهاز، فيفشل الدخول. توكن المطور نفسه يبقى: سياسات RLS تفتح له
  /// جداول كل منشأة (`is_developer()`)، والمنشأة النشطة تُحفظ فتُستعاد عند الإقلاع.
  Future<String?> enterTenantAsDeveloper(Tenant tenant) async {
    if (!isMasterAdmin) return 'الدخول للمنشآت من بوابة المطور';
    final problem = subscriptionProblem(tenant);
    if (problem != null) return problem;
    await _enterTenant(tenant);
    return null;
  }

  /// جلب المنشآت من السحابة مع الإبقاء على المحلية عند انقطاع الاتصال.
  Future<bool> refreshTenantsFromCloud() async {
    if (!networkEnabled) return false;
    final fetched = await tenantApi.fetchAll();
    if (fetched == null) return false;
    tenants
      ..clear()
      ..addAll(fetched);
    markDirty('tenants');
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await flush();
    stopAutoSync();
    await stopRealtime();
    await supabaseSignOut();
    loggedIn = false;
    isMasterAdmin = false;
    currentTenant = null;
    _setupPending = false;
    await _saveSession();
    notifyListeners();
  }

  Student? studentById(String id) {
    _rebuildIndexes();
    return _studentIndex[id];
  }

  Teacher? teacherById(String id) {
    for (final t in teachers) {
      if (t.id == id) return t;
    }
    return null;
  }

  GradeFee? feeFor(String grade) {
    for (final g in gradeFees) {
      if (g.gradeName == grade) return g;
    }
    return null;
  }

  StudentAttachments? attachmentsOf(String studentId) => attachmentsByStudent[studentId];

  /// حاوية مرفقات الطلاب — خاصة، ولا يقرؤها إلا حساب المنشأة.
  static const studentDocsBucket = 'student-docs';

  static const studentDocKinds = ['student_id_photo', 'birth_certificate'];

  /// مسار الملف: مجلد لكل منشأة ثم لكل طالب — سياسة الحاوية تقرأ المنشأة منه.
  static String studentDocPath(String tenantId, String studentId, String kind, String mime) =>
      '$tenantId/$studentId/$kind.${storageExtensionForMime(mime)}';

  /// جلب مرفقات الطالب عند الطلب — المقابل لـ `getAttachments`.
  ///
  /// الملفان في المخزن والصف يحمل مساريهما، فيُنزَّلان عند فتح ملف الطالب وحده
  /// ويبقيان على الجهاز بعدها.
  Future<StudentAttachments?> loadAttachments(String studentId) async {
    final local = attachmentsByStudent[studentId];
    if (local != null && local.hasData) return local;
    if (!networkEnabled || tenantId == null) return local;

    try {
      final rows = await supabaseSelect(
        'student_attachments',
        filters: {'id': 'eq.$studentId'},
        limit: 1,
      );
      if (rows == null || rows.isEmpty) return local;
      final fetched = StudentAttachments.fromCloud(rows.first);

      for (final kind in studentDocKinds) {
        final path = fetched.pathOf(kind);
        if (path.isEmpty) continue;
        final file = await storageDownload(studentDocsBucket, path);
        if (file == null) continue;
        final data = 'data:${file.mime};base64,${base64Encode(file.bytes)}';
        if (kind == 'student_id_photo') {
          fetched.studentIdPhoto = data;
        } else {
          fetched.birthCertificate = data;
        }
      }
      if (fetched.isEmpty) return local;

      attachmentsByStudent[studentId] = fetched;
      markDirty('student_attachments');
      notifyListeners();
      return fetched;
    } catch (_) {
      return local;
    }
  }

  /// رفع المرفقات: الملفات إلى الحاوية ثم الصف بمساريهما.
  ///
  /// خارج طابور المزامنة: صورة واحدة تزن أضعاف الطابور كله. ما تعذّر رفعه يبقى
  /// على الجهاز موسوماً `pending`، ويُعاد عند الإقلاع وعند عودة الاتصال.
  Future<void> _pushAttachments(String studentId, StudentAttachments a, {StudentAttachments? previous}) async {
    final tid = tenantId;
    if (!networkEnabled || tid == null) return;
    try {
      for (final kind in studentDocKinds) {
        final data = a.dataOf(kind);
        if (data.isEmpty) {
          a.setPath(kind, '');
          continue;
        }
        // صورة لم تتغيّر: مسارها المرفوع يكفي بلا رفعٍ ثانٍ لنفس البايتات
        final samePath = previous?.pathOf(kind) ?? '';
        if (previous != null && previous.dataOf(kind) == data && samePath.isNotEmpty) {
          a.setPath(kind, samePath);
          continue;
        }
        final file = decodeDataUrl(data);
        if (file == null) continue;
        final path = studentDocPath(tid, studentId, kind, file.mime);
        await storageUpload(studentDocsBucket, path, file.bytes, file.mime, upsert: true);
        a.setPath(kind, path);
      }

      await supabaseUpsert('student_attachments', [
        {...a.toCloud(), 'id': studentId, 'tenant_id': tid},
      ]);
      a.syncStatus = 'synced';
    } catch (_) {
      // تعذّر الرفع الآن: النسخة المحلية باقية، وتُعاد المحاولة لاحقاً
      a.syncStatus = 'pending';
    }
    markDirty('student_attachments');
  }

  /// إعادة رفع المرفقات المتعثرة — عند الإقلاع وعند عودة الاتصال.
  Future<int> retryPendingAttachments() async {
    if (!networkEnabled || tenantId == null) return 0;
    final stuck = attachmentsByStudent.entries.where((e) => e.value.syncStatus == 'pending').toList();
    var done = 0;
    for (final entry in stuck) {
      await _pushAttachments(entry.key, entry.value);
      if (entry.value.syncStatus == 'synced') done++;
    }
    if (stuck.isNotEmpty) notifyListeners();
    return done;
  }

  /// [paths] تُمرَّر لأن الصف المحلي يُحذف قبل هذا النداء.
  Future<void> _removeCloudAttachments(String studentId, List<String> paths) async {
    if (!networkEnabled || tenantId == null) return;
    try {
      // الملفات أولاً: صف محذوف بلا ملفاته يترك صور هويات في المخزن بلا صاحب
      if (paths.isNotEmpty) await storageRemove(studentDocsBucket, paths);
      await supabaseDelete('student_attachments', {'id': 'eq.$studentId'});
    } catch (_) {
      // الحذف المحلي تم، والسحابي يُعاد عند الحذف التالي
    }
  }

  // ── إشعارات التحويل (مرفقات السندات) ───────────────────────────────────────

  /// حاوية صور الإشعارات — خاصة، وروابطها تُوقَّع عند الطلب.
  static const noticeBucket = 'finance-notices';

  List<Map<String, dynamic>> get _notices => extraCloud.putIfAbsent('finance_attachments', () => []);

  Map<String, dynamic>? financeAttachment(String recordId) =>
      _notices.where((r) => '${r['id']}' == recordId).firstOrNull;

  /// مسار الملف: مجلد لكل منشأة، فلا تقرأ مدرسة إشعارات غيرها.
  static String noticePath(String tenantId, String recordId, String mime) =>
      '$tenantId/$recordId.${storageExtensionForMime(mime)}';

  /// حفظ إشعار تحويل لسند — مطابق لـ `saveFinanceAttachment`.
  ///
  /// الصورة في حاوية خاصة والصف لا يحمل إلا مسارها: عددها ينمو بعدد الدفعات،
  /// وتخزينها في القاعدة يزاحم بيانات المدرسة على مساحتها. الحفظ لا ينتظر الرفع:
  /// السند يُسجَّل بلا إنترنت، والصورة تلحق بأول اتصال.
  Future<void> saveFinanceAttachment(String recordId, String recordType, String? image) async {
    if (recordId.isEmpty) return;
    final now = _nowIso();
    final existing = financeAttachment(recordId);

    if (image == null || image.isEmpty) {
      if (existing == null) return;
      final path = '${existing['storage_path'] ?? ''}';
      _notices.removeWhere((r) => '${r['id']}' == recordId);
      // الملف قبل الصف: صفٌّ حُذف وملفه باقٍ يترك صورة إشعار بلا صاحب
      if (path.isNotEmpty) await storageRemove(noticeBucket, [path]);
      _queue('finance_attachments', recordId, 'DELETE', null);
      markDirty('finance_attachments');
      notifyListeners();
      return;
    }

    final row = {
      'id': recordId,
      'record_type': recordType,
      'storage_path': existing?['storage_path'],
      'image': image,
      'created_at': existing?['created_at'] ?? now,
      'updated_at': now,
      'sync_status': 'pending',
    };
    _notices
      ..removeWhere((r) => '${r['id']}' == recordId)
      ..add(row);
    markDirty('finance_attachments');
    notifyListeners();

    await _uploadNotice(row);
  }

  /// رفع صورة إشعار ثم تسجيل مسارها في الصف المتزامن. يفشل بصمت بلا اتصال:
  /// النسخة المحلية تبقى ويعيد `flushPendingNotices` المحاولة.
  Future<bool> _uploadNotice(Map<String, dynamic> row) async {
    final tid = tenantId;
    final image = '${row['image'] ?? ''}';
    if (!networkEnabled || tid == null || image.isEmpty) return false;
    final file = decodeDataUrl(image);
    if (file == null) return false;

    try {
      final path = '${row['storage_path'] ?? ''}'.isNotEmpty
          ? '${row['storage_path']}'
          : noticePath(tid, '${row['id']}', file.mime);
      await storageUpload(noticeBucket, path, file.bytes, file.mime, upsert: true);

      final isNew = '${row['storage_path'] ?? ''}'.isEmpty;
      row['storage_path'] = path;
      row['updated_at'] = _nowIso();
      row['sync_status'] = 'synced';
      _queue('finance_attachments', '${row['id']}', isNew ? 'INSERT' : 'UPDATE', {
        'id': row['id'],
        'record_type': row['record_type'],
        'storage_path': path,
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      });
      markDirty('finance_attachments');
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// إعادة رفع الإشعارات التي سُجّلت بلا اتصال — عند الإقلاع وعودة الاتصال.
  Future<int> flushPendingNotices() async {
    if (!networkEnabled || tenantId == null) return 0;
    final stuck = _notices.where((r) => '${r['storage_path'] ?? ''}'.isEmpty && '${r['image'] ?? ''}'.isNotEmpty).toList();
    var done = 0;
    for (final row in stuck) {
      if (await _uploadNotice(row)) done++;
    }
    return done;
  }

  /// صورة الإشعار: من الجهاز إن كانت، وإلا تُنزَّل من مسارها عند فتح السند.
  Future<String?> loadNoticeImage(String recordId) async {
    final local = financeAttachment(recordId);
    final image = '${local?['image'] ?? ''}';
    if (image.isNotEmpty) return image;
    if (!networkEnabled || tenantId == null) return null;

    try {
      var path = '${local?['storage_path'] ?? ''}';
      if (path.isEmpty) {
        final rows = await supabaseSelect('finance_attachments', filters: {'id': 'eq.$recordId'}, limit: 1);
        if (rows == null || rows.isEmpty) return null;
        path = '${rows.first['storage_path'] ?? ''}';
        if (path.isEmpty) return null;
        _notices
          ..removeWhere((r) => '${r['id']}' == recordId)
          ..add({...rows.first, 'sync_status': 'synced'});
      }

      final file = await storageDownload(noticeBucket, path);
      if (file == null) return null;
      final data = 'data:${file.mime};base64,${base64Encode(file.bytes)}';
      financeAttachment(recordId)?['image'] = data;
      markDirty('finance_attachments');
      return data;
    } catch (_) {
      return null;
    }
  }

  /// دفعات الطالب مرتّبة بالأحدث — مطابق لـ `FinanceService.getPaymentsByStudent`.
  List<Payment> paymentsOf(String studentId) {
    final list = payments.where((p) => p.studentId == studentId).toList();
    sortPayments(list);
    return list;
  }

  /// أقساط الطالب مرتّبة بتاريخ الاستحقاق — مطابق لـ `StudentsService.getInstallments`.
  List<Installment> installmentsOf(String studentId) {
    return installments.where((i) => i.studentId == studentId).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  /// طلاب الشعبة — مطابق لـ `SchoolClasses.tsx`.
  ///
  /// المطابقة تامة كما في حفظ توزيع المواد (`studentBelongsToRoom`): كانت هنا
  /// باحتواء النص، فتعرض الشاشة طلاب «علمي 1» ضمن «علمي 10» ولا يسجّلهم الحفظ.
  /// الطالب بلا شعبة يُحسب على الشعبة فقط إن كانت الوحيدة لمرحلته، والمؤرشف
  /// خريجٌ لم يعد من طلاب أي شعبة.
  List<Student> studentsOf(Classroom room) {
    return students.where((s) {
      if (s.status == 'archived') return false;
      if (s.section.trim().isNotEmpty) return studentBelongsToRoom(s, room);
      if (room.gradeLevel.trim().isEmpty || s.gradeLevel.trim().isEmpty) return false;
      final ofGrade = rooms.where((r) => isSameGrade(r.gradeLevel, s.gradeLevel)).toList();
      return ofGrade.length == 1 && ofGrade.first.id == room.id;
    }).toList();
  }

  /// طلاب الشعبة في الحضور — مطابق لـ `Attendance.tsx`.
  ///
  /// من له شعبة يُرصد في شعبته وحدها، ومن لا شعبة له يبقى ضمن شعب مرحلته حتى
  /// تُسنَد شعبته، فلا يغيب عن الرصد يوم تسجيله.
  List<Student> attendanceRosterOf(Classroom room) {
    return students.where((s) {
      if (s.status == 'archived') return false;
      return s.section.trim().isNotEmpty
          ? studentBelongsToRoom(s, room)
          : isSameGrade(s.gradeLevel, room.gradeLevel);
    }).toList();
  }

  String? attendanceOf(String studentId, String date) => attendanceRecord(studentId, date)?.status;

  /// أي رصد للطالب في هذا اليوم، بصرف النظر عن الصف — للتقارير وكشف الطالب.
  AttendanceMark? attendanceRecord(String studentId, String date) {
    _rebuildIndexes();
    return _markAny[looseKey(studentId, date)];
  }

  /// السجل الذي يخصّ هذا الصف وهذا الطالب في هذا اليوم — **المرجع الوحيد**
  /// للقراءة والكتابة معاً.
  ///
  /// اختلافهما كان أصل العطل: القارئ يأخذ آخر سجل بمفتاح (طالب، يوم)
  /// والكاتب يأخذ أوله. فحين يحمل الطالب سجلين لليوم نفسه — واحد وصل من
  /// السحابة لصف آخر — كان كلٌّ منهما يعمل على سجل مختلف، فتبدو النقرة
  /// كأنها لم تحدث.
  AttendanceMark? markFor(String? ownerId, String studentId, String date) {
    _rebuildIndexes();
    if (ownerId != null && ownerId.isNotEmpty) {
      final owned = _markOwned[ownedKey(ownerId, studentId, date)];
      if (owned != null) return owned;
    }
    // سجل بلا جلسة معروفة: يتبنّاه الصف الذي يُرصد منه
    return _markLoose[looseKey(studentId, date)];
  }

  /// حالة الحضور لطالب في تاريخ ضمن صف/مجموعة محددة.
  /// يمر عبر الجلسة كما في النسخة المكتبية بدل مطابقة التاريخ وحده.
  String? attendanceInSession(String ownerId, String studentId, String date) =>
      markFor(ownerId, studentId, date)?.status;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  void _queue(String table, String recordId, String action, Map<String, dynamic>? payload) {
    // تعديل ثم تراجع عنه: السجل صار كما في السحابة، فتُسقط العملية المعلّقة
    // بدل رفعٍ لا يغيّر شيئاً وعدّادٍ يشير إلى تغيير غير موجود.
    if (action == 'UPDATE' && _isBackToSynced(table, recordId, payload)) {
      final had = pendingSyncs.any((p) => p.tableName == table && p.recordId == recordId);
      pendingSyncs.removeWhere((p) => p.tableName == table && p.recordId == recordId);
      markRecord(table, recordId);
      if (had) markDirty(_pendingTable);
      notifyListeners();
      return;
    }

    queuePendingSync(
      pendingSyncs,
      tableName: table,
      recordId: recordId,
      action: action,
      payload: payload,
      tenantId: tenantId ?? '',
    );
    markRecord(table, recordId, deleted: action == 'DELETE');
    markDirty(_pendingTable);
    notifyListeners();
  }

  /// رصد حالة محددة لطالب في يوم. `null` يمسح الرصد.
  /// [ownerId] هو معرّف الصف (نظام مدرسة) أو المجموعة (نظام مركز).
  void setAttendance(String studentId, String date, String? status, {String? ownerId}) {
    requireSection('attendance');
    final existing = markFor(ownerId, studentId, date);

    if (status == null) {
      if (existing == null) return;
      attendance.remove(existing);
      _queue('attendance', existing.id, 'DELETE', null);
      return;
    }

    // الجلسة تُنشأ عند الحاجة فقط، بعد التأكد من وجود ما يُرصد
    final sessionId = ownerId == null || ownerId.isEmpty
        ? ''
        : sessionFor(ownerId, date).id;

    if (existing != null) {
      if (existing.status == status && (sessionId.isEmpty || existing.sessionId == sessionId)) {
        return; // لا تغيير: لا داعي لإخطار الشاشات ولا لكتابة القرص
      }
      existing.status = status;
      existing.markedByUserId = currentUserId;
      if (sessionId.isNotEmpty) existing.sessionId = sessionId;
      existing.updatedAt = _nowIso();
      existing.syncStatus = 'pending';
      _queue('attendance', existing.id, 'UPDATE', existing.toCloud());
      return;
    }

    final mark = AttendanceMark(
      id: newId(),
      studentId: studentId,
      date: date,
      status: status,
      sessionId: sessionId,
      markedByUserId: currentUserId,
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    attendance.add(mark);
    _queue('attendance', mark.id, 'INSERT', mark.toCloud());
  }

  /// دورة النقر: غير مرصود ← غائب ← حاضر ← غير مرصود.
  /// مطابقة لـ `toggleAttendanceCell` — النقرة الأولى للرصد السريع للغياب.
  void cycleAttendance(String studentId, String date, {String? ownerId}) {
    final current = markFor(ownerId, studentId, date)?.status;
    // مطابق لـ `toggleAttendanceCell`: حاضر ثم غائب ثم مأذون ثم إلغاء الرصد
    final next = switch (current) {
      null => 'present',
      'present' => 'absent',
      'absent' => 'excused',
      _ => null,
    };
    setAttendance(studentId, date, next, ownerId: ownerId);
  }

  /// رصد كل طلاب الصف حاضرين ليوم واحد.
  ///
  /// يمرّ على نفس مفتاح [markFor] لكل طالب، فلا يتخلّف أحد لأن سجله مرتبط
  /// بجلسة أخرى — وهو ما كان يجعل الزر يُغيّر البعض دون البعض.
  int markAllPresent(String date, List<Student> list, {String? ownerId}) {
    requireSection('attendance');
    if (list.isEmpty) return 0;
    final sessionId = ownerId == null || ownerId.isEmpty
        ? ''
        : sessionFor(ownerId, date).id;

    final now = _nowIso();
    var changed = 0;

    for (final s in list) {
      final existing = markFor(ownerId, s.id, date);
      if (existing != null) {
        if (existing.status == 'present' && (sessionId.isEmpty || existing.sessionId == sessionId)) {
          continue;
        }
        existing.status = 'present';
        existing.markedByUserId = currentUserId;
        if (sessionId.isNotEmpty) existing.sessionId = sessionId;
        existing.updatedAt = now;
        existing.syncStatus = 'pending';
        queuePendingSync(pendingSyncs,
            tableName: 'attendance', recordId: existing.id, action: 'UPDATE', payload: existing.toCloud());
        markRecord('attendance', existing.id);
        changed++;
        continue;
      }

      final mark = AttendanceMark(
        id: newId(),
        studentId: s.id,
        date: date,
        status: 'present',
        sessionId: sessionId,
        markedByUserId: currentUserId,
        syncStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      attendance.add(mark);
      queuePendingSync(pendingSyncs,
          tableName: 'attendance', recordId: mark.id, action: 'INSERT', payload: mark.toCloud());
      markRecord('attendance', mark.id);
      changed++;
      // الفهرس يسقط مع كل markRecord، فيُعاد بناؤه لطالب التالي
    }

    if (changed > 0) {
      markDirty(_pendingTable);
      notifyListeners();
    }
    return changed;
  }

  /// إزالة أي رصد مكرّر لنفس (الجلسة، الطالب) — القيد الفريد في السحابة.
  /// يُبقي الأحدث ويُسقط الباقي، فلا تصطدم الدفعة بنفسها عند الرفع.
  int dedupeAttendance() {
    final seen = <String, AttendanceMark>{};
    final drop = <AttendanceMark>[];

    for (final a in attendance) {
      final key = a.sessionId.isEmpty ? looseKey(a.studentId, a.date) : '${a.sessionId}|${a.studentId}';
      final kept = seen[key];
      if (kept == null) {
        seen[key] = a;
        continue;
      }
      final keptAt = kept.updatedAt ?? '';
      final thisAt = a.updatedAt ?? '';
      if (thisAt.compareTo(keptAt) >= 0) {
        seen[key] = a;
        drop.add(kept);
      } else {
        drop.add(a);
      }
    }

    if (drop.isEmpty) return 0;
    for (final a in drop) {
      attendance.remove(a);
      pendingSyncs.removeWhere((p) => p.tableName == 'attendance' && p.recordId == a.id);
    }
    markDirty('attendance');
    markDirty(_pendingTable);
    notifyListeners();
    return drop.length;
  }

  /// أيام الأسبوع المدرسي (السبت → الخميس) بإزاحة أسابيع.
  /// مطابق لـ `getSchoolWeekDates`.
  static List<SchoolDay> schoolWeek([int offsetWeeks = 0]) {
    final now = DateTime.now();
    final distFromSaturday = (now.weekday + 1) % 7;
    final saturday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: distFromSaturday))
        .add(Duration(days: offsetWeeks * 7));
    const names = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    final today = isoDate(now);
    return [
      for (var i = 0; i < 6; i++)
        () {
          final d = saturday.add(Duration(days: i));
          return SchoolDay(
            date: d,
            dateStr: isoDate(d),
            dayName: names[i],
            shortDate: '${d.day}/${d.month}',
            isToday: isoDate(d) == today,
          );
        }(),
    ];
  }

  Student? findByNationalId(String id, {String? exclude}) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    for (final s in students) {
      if (exclude != null && s.id == exclude) continue;
      if (s.nationalId.trim() == clean) return s;
    }
    return null;
  }

  Student? findByPhone(String phone, {String? exclude}) {
    final digits = digitsOnly(combinePhoneAndPrefix(phone));
    if (digits.length < 7) return null;
    for (final s in students) {
      if (exclude != null && s.id == exclude) continue;
      final other = digitsOnly(combinePhoneAndPrefix(s.phone, s.phonePrefix));
      if (other == digits) return s;
    }
    return null;
  }

  void upsertStudent(Student incoming, {bool isNew = false, StudentAttachments? attachments}) {
    requireSection('students');
    if (!isValidNationalId(incoming.nationalId)) {
      throw StoreException('رقم الهوية غير صالح! يجب أن يتكون من 9 أرقام.');
    }
    final dupId = findByNationalId(incoming.nationalId, exclude: incoming.id);
    if (dupId != null) {
      throw StoreException('رقم الهوية (${incoming.nationalId}) مسجل مسبقاً للطالب "${dupId.fullName}" ولا يمكن تكراره.');
    }
    if (!isValidStudentPhone(incoming.phone, incoming.phonePrefix)) {
      throw StoreException(
        'رقم جوال الطالب غير مكتمل! يجب إدخال ${phoneTargetLength(incoming.phonePrefix)} أرقام بعد المقدمة (${incoming.phonePrefix}).',
      );
    }
    final dupPhone = findByPhone(incoming.phone, exclude: incoming.id);
    if (dupPhone != null) {
      throw StoreException('رقم جوال الطالب (${incoming.phone}) مسجل مسبقاً للطالب "${dupPhone.fullName}" ولا يمكن تكراره.');
    }
    if (incoming.fullName.trim().isEmpty) {
      throw StoreException('يرجى إدخال الاسم الرباعي للطالب.');
    }

    incoming.splitNameIfNeeded();
    incoming.updatedAt = _nowIso();
    incoming.syncStatus = 'pending';

    final i = students.indexWhere((e) => e.id == incoming.id);
    if (i >= 0) {
      final before = students[i];
      final placementChanged = before.section != incoming.section ||
          before.gradeLevel != incoming.gradeLevel ||
          before.status != incoming.status;
      incoming.balance = before.balance;
      incoming.createdAt = before.createdAt ?? incoming.createdAt;
      students[i] = incoming;
      _queue('students', incoming.id, 'UPDATE', incoming.toCloud());
      // تغيّر الشعبة أو المرحلة أو الحالة يعيد تشكيل عضويته في مواد شعبته
      if (placementChanged) syncStudentRoomEnrollments([incoming.id]);
    } else {
      incoming.createdAt ??= _nowIso();
      // رسم حجز المقعد يُقرأ من الإعدادات ولا يُقيَّد إن لم تعتمد الإدارة قيمة له.
      // لا تُولَّد أقساط تلقائياً: النسخة المكتبية تُنشئ الأقساط فقط إن مُرِّرت
      // صراحةً، والطالب الجديد يبدأ برصيد صفر.
      if (incoming.seatReservationPaid) {
        incoming.balance = incoming.balance + seatReservationFee;
      }
      // رمز بوابة الطالب يُولَّد عند التسجيل، كما في StudentForm
      if (incoming.portalCode.trim().isEmpty) {
        incoming.portalCode = newPortalCode();
      }
      students.insert(0, incoming);
      _queue('students', incoming.id, 'INSERT', incoming.toCloud());
    }

    if (attachments != null) {
      final existed = attachmentsByStudent.containsKey(incoming.id);
      final hasAny = !attachments.isEmpty;
      if (!hasAny) {
        if (existed) {
          final gone = attachmentsByStudent.remove(incoming.id);
          markDirty('student_attachments');
          unawaited(_removeCloudAttachments(incoming.id, gone?.paths ?? const []));
        }
      } else {
        final previous = attachmentsByStudent[incoming.id];
        attachments.updatedAt = _nowIso();
        attachments.syncStatus = 'pending';
        attachmentsByStudent[incoming.id] = attachments;
        markDirty('student_attachments');
        unawaited(_pushAttachments(incoming.id, attachments, previous: previous));
      }
    }
    markDirty('students');
  }

  /// ما استُحق على الطالب ولم يُسدَّد حتى اليوم.
  ///
  /// القسط الذي لم يحن موعده ليس ديناً عليه: يصير مطلوباً يوم استحقاقه.
  double outstandingDue(String studentId) =>
      overdueByStudent(installments.where((i) => i.studentId == studentId))[studentId] ?? 0;

  /// هل سدّد الطالب كل ما استُحق عليه حتى اليوم؟
  bool isSettledToDate(String studentId) => outstandingDue(studentId) <= cent && !(studentById(studentId)?.isDebtor ?? false);

  /// حذف طالب مع كل ما يتبعه.
  ///
  /// يُحذف من سدّد ما استُحق عليه حتى اليوم؛ أما من عليه متأخرات فلا، كي لا
  /// يختفي الدَّين بحذف صاحبه. الأقساط القادمة لا تمنع: لم تُستحق بعد.
  void deleteStudent(String id) {
    requireSection('students');
    final due = outstandingDue(id);
    if (due > cent) {
      throw StoreException(
        'لا يمكن حذف هذا الطالب لأن عليه ${money(due)} مستحقة حتى اليوم. '
        'حصّلها أو غيّر حالته إلى «منسحب» للاحتفاظ بسجله.',
      );
    }

    for (final inst in installments.where((i) => i.studentId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'DELETE', payload: null);
    }
    for (final a in attendance.where((a) => a.studentId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: a.id, action: 'DELETE', payload: null);
    }
    for (final p in payments.where((p) => p.studentId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'payments', recordId: p.id, action: 'DELETE', payload: null);
    }
    for (final e in enrollmentsOf(id)) {
      queuePendingSync(pendingSyncs, tableName: 'enrollments', recordId: e.id, action: 'DELETE', payload: null);
    }

    students.removeWhere((s) => s.id == id);
    payments.removeWhere((p) => p.studentId == id);
    installments.removeWhere((i) => i.studentId == id);
    attendance.removeWhere((a) => a.studentId == id);
    enrollments.removeWhere((e) => e.studentId == id);
    final removedDocs = attachmentsByStudent.remove(id);
    if (removedDocs != null) {
      unawaited(_removeCloudAttachments(id, removedDocs.paths));
    }
    _queue('students', id, 'DELETE', null);
    markDirty('students');
    markDirty('payments');
    markDirty('installments');
    markDirty('attendance');
    markDirty('student_attachments');
    markDirty('enrollments');
  }

  /// أعلى رقم تسلسلي مستخدم لسنة معينة ضمن قائمة أرقام سندات.
  /// مطابق لـ `FinanceService.maxSerialFor`.
  static int maxSerialFor(int year, Iterable<String> receiptNumbers) {
    var max = 1000;
    for (final raw in receiptNumbers) {
      final parts = raw.split('/');
      if (parts.length == 2 && parts[0] == '$year') {
        final serial = int.tryParse(parts[1]);
        if (serial != null && serial > max) max = serial;
      }
    }
    return max;
  }

  /// آخر تسلسل رآه هذا الجهاز من السحابة، يُحدَّث قبل كل دفعة عند توفّر الاتصال.
  int _cloudSerialHint = 0;

  /// استشارة السحابة عن أعلى رقم سند لهذه السنة.
  ///
  /// الاعتماد على القاعدة المحلية وحدها كان يجعل جهازين يُصدران الرقم نفسه
  /// لسندين مختلفين. القيد `UNIQUE(tenant_id, receipt_number)` هو خط الدفاع
  /// الأخير، ويعالجه [addPayment] بإعادة التوليد عند التعارض.
  Future<void> primeReceiptCounter() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled) return;
    final year = DateTime.now().year;
    final rows = await supabaseSelect(
      'payments',
      columns: 'receipt_number',
      filters: {'tenant_id': 'eq.$tid', 'receipt_number': 'like.$year/%'},
      order: 'receipt_number.desc',
      limit: 200,
    );
    if (rows == null) return;
    final cloudMax = maxSerialFor(year, rows.map((r) => '${r['receipt_number'] ?? ''}'));
    if (cloudMax > _cloudSerialHint) _cloudSerialHint = cloudMax;
  }

  /// منح سند رقماً جديداً بعد تعارض رقمه مع سند آخر صدر بلا اتصال.
  ///
  /// الرقم الورقي الأول يبقى في بيان السند: الوصل المطبوع بيد ولي الأمر يحمله،
  /// فلا يضيع أثره حين يتغيّر الرقم في النظام.
  @override
  String? reissueReceiptNumber(String paymentId) {
    final p = payments.where((x) => x.id == paymentId).firstOrNull;
    if (p == null) return null;

    final old = p.receiptNumber;
    final fresh = _nextReceipt();
    p.receiptNumber = fresh;
    final mark = 'رقم ورقي: $old';
    p.notes = p.notes.trim().isEmpty ? '($mark)' : '${p.notes.trim()} ($mark)';
    p.updatedAt = _nowIso();
    markDirty('payments');
    return fresh;
  }

  String _nextReceipt() {
    final year = DateTime.now().year;
    var max = maxSerialFor(year, payments.map((p) => p.receiptNumber));
    if (_receipt > max) max = _receipt;
    if (_cloudSerialHint > max) max = _cloudSerialHint;
    _receipt = max + 1 < 1001 ? 1001 : max + 1;
    unawaited(db.setSetting(_kReceiptCounter, '$_receipt'));
    return '$year/$_receipt';
  }

  /// توحيد صيغة أرقام السندات القديمة إلى `YYYY/NNNN`.
  ///
  /// تعمل مرة واحدة فقط لكل جهاز خلف علامة في الإعدادات. تشغيلها عند كل عرض
  /// للشاشة المالية كان يُنتج تأرجحاً دائماً: الجهاز يغيّر الرقم، والسحب يعيده.
  /// دمج حالة «غير نشط» في «منسحب» — مطابق لترقية v9 في db.ts.
  ///
  /// كانتا بمعنى واحد ولا يفرّق بينهما منطق، فبقاء القديمة يُظهر حالتين لشيء واحد.
  Future<int> migrateWithdrawnStatus() async {
    if (db.settings[withdrawnStatusMigrationKey] == 'true') return 0;

    var changed = 0;
    for (final student in students.where((s) => s.status == 'inactive')) {
      student.status = 'withdrawn';
      student.updatedAt = _nowIso();
      student.syncStatus = 'pending';
      _queue('students', student.id, 'UPDATE', student.toCloud());
      changed++;
    }
    if (changed > 0) {
      markDirty('students');
      notifyListeners();
    }
    await db.setSetting(withdrawnStatusMigrationKey, 'true');
    return changed;
  }

  /// استبدال معرّفات الحضور النصية القديمة بمعرّفات UUID.
  ///
  /// كانت تُولَّد بصيغة `att-<studentId>-<date>`، وعمود `id` في السحابة من نوع
  /// uuid فيرفضها بـ «invalid input syntax for type uuid». السجلات المكتوبة
  /// بها تظل عالقة في طابور الرفع مهما أُعيدت المحاولة، فتُعاد كتابتها هنا
  /// بمعرّف صالح مرة واحدة لكل جهاز.
  Future<int> migrateAttendanceIds() async {
    if (db.settings[attendanceIdMigrationKey] == 'true') return 0;

    final stale = attendance.where((a) => a.id.startsWith('att-')).toList();
    for (final old in stale) {
      // إسقاط أي عملية معلّقة تشير إلى المعرّف القديم: لن يقبله الخادم أبداً
      pendingSyncs.removeWhere((p) => p.tableName == 'attendance' && p.recordId == old.id);

      final fresh = AttendanceMark(
        id: newId(),
        studentId: old.studentId,
        date: old.date,
        status: old.status,
        sessionId: old.sessionId,
        markedByUserId: old.markedByUserId,
        notes: old.notes,
        syncStatus: 'pending',
        createdAt: old.createdAt ?? _nowIso(),
        updatedAt: _nowIso(),
      );
      final i = attendance.indexOf(old);
      attendance[i] = fresh;
      queuePendingSync(
        pendingSyncs,
        tableName: 'attendance',
        recordId: fresh.id,
        action: 'INSERT',
        payload: fresh.toCloud(),
      );
    }

    await db.setSetting(attendanceIdMigrationKey, 'true');
    if (stale.isNotEmpty) {
      markDirty('attendance');
      markDirty(_pendingTable);
      notifyListeners();
    }
    return stale.length;
  }

  /// مطابق لـ `migrateReceiptNumbers`.
  Future<int> migrateReceiptNumbers({bool force = false}) async {
    if (!force && db.settings[receiptMigrationKey] == 'true') return 0;

    final currentYear = DateTime.now().year;
    final recPattern = RegExp(r'^REC-(\d{4})-(\d+)$', caseSensitive: false);
    final plainPattern = RegExp(r'^(\d+)$');
    final canonical = RegExp(r'^\d{4}/\d+$');
    var changed = 0;

    for (final p in payments) {
      final raw = p.receiptNumber;
      if (canonical.hasMatch(raw)) continue;

      var next = raw;
      final rec = recPattern.firstMatch(raw);
      if (rec != null) {
        final year = rec.group(1)!;
        var serial = int.parse(rec.group(2)!);
        if (serial >= 100 && serial < 200) {
          serial = 1000 + (serial - 100);
        } else if (serial < 1000) {
          serial = 1000 + serial;
        }
        next = '$year/$serial';
      } else {
        final plain = plainPattern.firstMatch(raw);
        if (plain != null) {
          var serial = int.parse(plain.group(1)!);
          if (serial < 1000) serial = 1000 + serial;
          next = '$currentYear/$serial';
        }
      }

      if (next != raw) {
        p.receiptNumber = next;
        p.updatedAt = _nowIso();
        p.syncStatus = 'pending';
        // التغيير يجب أن يصل السحابة، وإلا عاد الرقم القديم مع أول سحب
        _queue('payments', p.id, 'UPDATE', p.toCloud());
        changed++;
      }
    }

    await db.setSetting(receiptMigrationKey, 'true');
    if (changed > 0) notifyListeners();
    return changed;
  }

  Payment addPayment({
    required String studentId,
    required double amount,
    required String method,
    required DateTime date,
    String purpose = 'monthly_fee',
    String notes = '',
    String reference = '',
    String senderName = '',
    String channel = '',
    String transferDate = '',
    String customMethodNotes = '',
    String? installmentId,
    String? groupId,
    String? enrollmentId,
  }) {
    requireSection('finance');
    if (amount <= 0) throw StoreException('يرجى إدخال مبلغ صحيح');
    final stu = studentById(studentId);
    if (stu == null) throw StoreException('يرجى اختيار الطالب أولاً');

    final totalDue = stu.balance < 0 ? stu.balance.abs() : 0.0;

    final p = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
      // لقطة وقت الإصدار: اسم الطالب والمستلم لا يتغيّران بأثر رجعي
      studentName: stu.fullName,
      receivedByName: receiptReceiver,
      studentId: studentId,
      amount: amount,
      method: method,
      date: date,
      purpose: purpose,
      notes: notes,
      reference: reference,
      senderName: senderName,
      channel: channel,
      transferDate: transferDate,
      customMethodNotes: customMethodNotes,
      installmentId: installmentId,
      groupId: groupId,
      enrollmentId: enrollmentId,
      receivedByUserId: currentUserId,
      remainingAfter: 0,
      totalDueAtPayment: totalDue,
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    payments.insert(0, p);
    // الرصيد وسداد الأقساط من السجلات بعد إضافة السند — لا جمع تراكمي يتضارب
    // بين الأجهزة، والسند الذي يغطي أكثر من قسط يُسدِّدها بالترتيب
    final after = _persistStudentLedger(stu);
    p.remainingAfter = after < 0 ? after.abs() : 0;
    queuePendingSync(pendingSyncs, tableName: 'payments', recordId: p.id, action: 'INSERT', payload: p.toCloud());
    markDirty('payments');
    markDirty(_pendingTable);
    notifyListeners();
    return p;
  }

  void cancelPayment(Payment p, [String reason = 'ملغاة من قبل الإدارة']) {
    requireSection('finance');
    if (p.cancelled) return;
    p.cancelled = true;
    p.cancelReason = reason;
    p.updatedAt = _nowIso();
    p.syncStatus = 'pending';
    final stu = studentById(p.studentId);
    // السداد يُعاد اشتقاقه من السندات الباقية: القسط الذي غطّاه السند الملغى
    // يعود غير مسدَّد، وما فاض منه على غيره يعود كذلك
    if (stu != null) _persistStudentLedger(stu);
    _queue('payments', p.id, 'UPDATE', p.toCloud());
  }

  /// رصيد الطالب محسوباً من سجلاته الفعلية — المقابل لـ `computeStudentBalance`.
  ///
  ///   الرصيد = (السندات غير الملغاة + خصوماتها) − (رسوم التسجيلات النشطة + الأقساط)
  ///
  /// الأقساط تدخل كاملةً في المدرسة كما في النسخة المكتبية: مديونية الطالب كلها
  /// في أقساطه، والقسط المجدول دَينٌ قائم وإن لم يحن موعده — «المستحق الآن» شيء
  /// آخر يحسبه [overdueByStudent].
  ///
  /// حسابه من السجلات لا تراكمياً: جمعه وطرحه مع كل حركة كان يتضارب بين جهازين
  /// بلا اتصال، فيفوز آخر رقم يصل السحابة وتضيع حركة الجهاز الآخر.
  double computeStudentBalance(String studentId) => balanceFrom(
        enrollments: enrollments.where((e) => e.studentId == studentId),
        installments: installments.where((i) => i.studentId == studentId),
        payments: payments.where((p) => p.studentId == studentId),      );

  /// إعادة حساب أرصدة كل الطلاب من سجلاتهم — تُستدعى بعد كل سحب.
  ///
  /// تصحيح محلي لا يُرفع: كل جهاز يصل إلى النتيجة نفسها من السجلات نفسها، فلا
  /// داعي لجولة كتابة جديدة تُشعل تضارباً آخر. تعيد عدد الأرصدة المصحَّحة.
  @override
  int recalculateAllBalances() {
    final paymentsByStudent = <String, List<Payment>>{};
    for (final p in payments) {
      if (p.studentId.isEmpty) continue;
      (paymentsByStudent[p.studentId] ??= []).add(p);
    }
    final installmentsByStudent = <String, List<Installment>>{};
    for (final i in installments) {
      if (i.studentId.isEmpty) continue;
      (installmentsByStudent[i.studentId] ??= []).add(i);
    }
    final enrollmentsByStudent = <String, List<StudentEnrollment>>{};
    for (final e in enrollments) {
      if (e.studentId.isEmpty) continue;
      (enrollmentsByStudent[e.studentId] ??= []).add(e);
    }

    const none = <Never>[];
    var corrected = 0;
    var installmentsFixed = false;

    for (final student in students) {
      final pays = paymentsByStudent[student.id] ?? none;
      final insts = installmentsByStudent[student.id] ?? none;
      final enrs = enrollmentsByStudent[student.id] ?? none;

      // المسدَّد من كل قسط مشتقٌّ من السندات: دفعةٌ تغطي أكثر من شهر وإلغاءُ سندٍ
      // يعطيان النتيجة نفسها على كل جهاز، بلا رفع — كلٌّ يصل إليها من السجلات
      final allocated = allocatePaymentsToInstallments(insts, pays);
      for (final inst in insts) {
        final paid = allocated[inst.id] ?? 0;
        final status = installmentStatusFor(inst.amount, paid);
        if ((inst.paidAmount - paid).abs() <= cent && inst.status == status) continue;
        inst.paidAmount = paid;
        inst.status = status;
        installmentsFixed = true;
      }

      final computed = balanceFrom(
        enrollments: enrs,
        installments: insts,
        payments: pays,      );
      // فرق أقل من قرش لا يستحق كتابة
      if ((student.balance - computed).abs() <= 0.01) continue;
      student.balance = computed;
      student.updatedAt = _nowIso();
      corrected++;
    }

    if (installmentsFixed) markDirty('installments');
    if (corrected > 0) markDirty('students');
    if (corrected > 0 || installmentsFixed) notifyListeners();
    return corrected;
  }

  /// كتابة الرصيد وسداد الأقساط كما تقتضيها السجلات — المقابل لـ
  /// `persistStudentLedger`. تعيد الرصيد المحسوب.
  ///
  /// المسدَّد مشتقّ من السندات لا مجموعاً تراكمياً: سندٌ يغطي شهرين يُسدِّد قسطيه،
  /// وإلغاؤه يعيد الحال كما كان — والنتيجة واحدة على كل جهاز مهما اختلف الترتيب.
  double _persistStudentLedger(Student student) {
    final pays = payments.where((p) => p.studentId == student.id).toList();
    final insts = installments.where((i) => i.studentId == student.id).toList();
    final now = _nowIso();

    final allocated = allocatePaymentsToInstallments(insts, pays);
    var queued = false;
    for (final inst in insts) {
      final paid = allocated[inst.id] ?? 0;
      final status = installmentStatusFor(inst.amount, paid);
      if ((inst.paidAmount - paid).abs() <= cent && inst.status == status) continue;
      inst.paidAmount = paid;
      inst.status = status;
      inst.updatedAt = now;
      inst.syncStatus = 'pending';
      queuePendingSync(
        pendingSyncs,
        tableName: 'installments',
        recordId: inst.id,
        action: 'UPDATE',
        payload: inst.toCloud(),
        tenantId: tenantId ?? '',
      );
      markDirty('installments');
      queued = true;
    }

    final computed = balanceFrom(
      enrollments: enrollments.where((e) => e.studentId == student.id),
      installments: insts,
      payments: pays,    );
    if ((student.balance - computed).abs() > 0.01) {
      student.balance = computed;
      student.updatedAt = now;
      student.syncStatus = 'pending';
      queuePendingSync(
        pendingSyncs,
        tableName: 'students',
        recordId: student.id,
        action: 'UPDATE',
        payload: student.toCloud(),
        tenantId: tenantId ?? '',
      );
      markDirty('students');
      queued = true;
    }
    if (queued) markDirty(_pendingTable);
    return computed;
  }

  /// تحديث رصيد الطالب المخبّأ من سجلاته ورفعه إن تغيّر.
  void _refreshBalance(Student student) => _persistStudentLedger(student);

  List<DueItem> dueItems() {
    // تُستدعى من شريط التنقّل في كل إعادة رسم، وحسابها يمرّ على كل الأقساط
    // والطلاب. النتيجة تُحفظ حتى التعديل التالي.
    if (_dueRev == _rev) return _dueCache;
    _dueRev = _rev;
    _dueCache = _computeDueItems();
    return _dueCache;
  }

  List<DueItem> _computeDueItems() {
    final today = dateOnly(DateTime.now());
    final list = <DueItem>[];
    final withInst = <String>{};

    for (final inst in installments) {
      if (inst.isPaid) continue;
      final student = studentById(inst.studentId);
      if (student == null) continue;
      withInst.add(student.id);
      final due = dateOnly(inst.dueDate);
      list.add(
        DueItem(
          id: inst.id,
          student: student,
          title: inst.title,
          amount: inst.remaining,
          dueDate: inst.dueDate,
          late: due.isBefore(today),
          scheduled: due.isAfter(today),
          installmentId: inst.id,
        ),
      );
    }

    for (final s in students) {
      if (s.balance >= 0 || withInst.contains(s.id)) continue;
      list.add(
        DueItem(
          id: 'debt-${s.id}',
          student: s,
          title: 'رسوم شهرية مستحقة',
          amount: s.balance.abs(),
          dueDate: today,
          late: DateTime.now().day > 10,
        ),
      );
    }

    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  // ── المجموعات والتسجيلات (المقابل لـ schedule.service.ts) ───────────────────

  Group? groupById(String id) => groups.where((g) => g.id == id).firstOrNull;

  SubjectItem? subjectById(String id) => subjects.where((s) => s.id == id).firstOrNull;

  Classroom? roomById(String id) => rooms.where((r) => r.id == id).firstOrNull;

  String subjectName(String id) => subjectById(id)?.name ?? 'غير محدد';

  String teacherName(String id) => teacherById(id)?.name ?? 'غير محدد';

  String roomName(String? id) => (id == null || id.isEmpty) ? 'غير محدد' : (roomById(id)?.name ?? 'غير محدد');

  /// التسجيلات النشطة في مجموعة.
  List<StudentEnrollment> enrollmentsInGroup(String groupId) =>
      enrollments.where((e) => e.groupId == groupId && e.isActive).toList();

  int enrollmentCount(String groupId) => enrollmentsInGroup(groupId).length;

  List<Student> studentsInGroup(String groupId) {
    final ids = enrollmentsInGroup(groupId).map((e) => e.studentId).toSet();
    return students.where((s) => ids.contains(s.id)).toList();
  }
  void upsertGroup(Group g) {
    requireSection('classes');
    if (g.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المجموعة');
    if (g.subjectId.isEmpty) throw StoreException('يرجى اختيار المادة الدراسية');
    if (g.teacherId.isEmpty) throw StoreException('يرجى اختيار المدرّس');
    if (g.days.isEmpty) throw StoreException('يرجى اختيار أيام الدوام');
    if (g.pricePerMonth < 0) throw StoreException('يرجى إدخال سعر شهري صحيح');

    final clash = findConflict(g);
    if (clash != null) throw StoreException(clash);

    g.updatedAt = _nowIso();
    g.syncStatus = 'pending';
    final i = groups.indexWhere((e) => e.id == g.id);
    if (i >= 0) {
      g.createdAt = groups[i].createdAt;
      groups[i] = g;
      _queue('groups', g.id, 'UPDATE', g.toCloud());
    } else {
      g.createdAt = _nowIso();
      groups.add(g);
      _queue('groups', g.id, 'INSERT', g.toCloud());
    }
  }

  /// فحص تعارض المدرّس أو القاعة في نفس اليوم والوقت.
  /// مطابق لـ `ScheduleService.checkConflicts`.
  String? findConflict(Group candidate) {
    bool overlaps(String aStart, String aEnd, String bStart, String bEnd) {
      return aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;
    }

    for (final other in groups) {
      if (other.id == candidate.id || !other.isActive) continue;
      final sharedDays = other.days.where(candidate.days.contains).toList();
      if (sharedDays.isEmpty) continue;
      if (!overlaps(candidate.startTime, candidate.endTime, other.startTime, other.endTime)) {
        continue;
      }
      final dayLabel = daysNames(sharedDays);
      if (other.teacherId == candidate.teacherId && candidate.teacherId.isNotEmpty) {
        return 'المدرّس «${teacherName(candidate.teacherId)}» مرتبط بمجموعة «${other.name}» '
            'في $dayLabel من ${other.startTime} إلى ${other.endTime}.';
      }
      if (other.roomId == candidate.roomId && candidate.roomId.isNotEmpty) {
        return 'القاعة «${roomName(candidate.roomId)}» محجوزة لمجموعة «${other.name}» '
            'في $dayLabel من ${other.startTime} إلى ${other.endTime}.';
      }
    }
    return null;
  }

  /// حذف مجموعة، أو أرشفتها إن كان لها تاريخ.
  ///
  /// المجموعة التي لها تسجيلات أو حصص سابقة تُؤرشف بدل حذفها حتى لا تُمحى قيود
  /// مالية وسجلات حضور مرتبطة بها — مطابق لـ `ScheduleService.deleteGroup` بعد
  /// «منع تعديل البيانات بأثر رجعي». تعيد `true` إن حُذفت فعلاً، و`false` إن أُرشفت.
  bool deleteGroup(String id) {
    requireSection('classes');
    final hasHistory = enrollments.any((e) => e.groupId == id) || sessions.any((s) => s.groupId == id);

    if (hasHistory) {
      final group = groupById(id);
      if (group == null) return false;
      group.status = 'archived';
      group.updatedAt = _nowIso();
      group.syncStatus = 'pending';
      _queue('groups', id, 'UPDATE', group.toCloud());
      markDirty('groups');
      return false;
    }

    groups.removeWhere((g) => g.id == id);
    _queue('groups', id, 'DELETE', null);
    return true;
  }

  // ─── مواد الشعبة ومعلموها ──────────────────────────────────────────────
  //
  // في المدرسة لكل شعبة موادها، ولكل مادة معلمها. تُمثَّل — كما في النسخة
  // المكتبية — بمجموعة لكل (مادة، شعبة) بلا أيام ولا رسوم: وعاء يربط المعلم
  // بطلاب الشعبة كي يظهروا له في البوابة والتقييمات والرصد، دون أن يقيَّد على
  // الطالب قرش واحد.

  /// مجموعات مواد الشعبة النشطة — مطابق لـ `SettingsService.getSectionSubjectGroups`.
  List<Group> sectionSubjectGroups(String roomId) =>
      groups.where((g) => g.isActive && g.includesRoom(roomId)).toList();

  /// المواد التي تنطبق على مرحلة — مطابق لـ `getGradeApplicableSubjects`.
  /// المادة العامة تنطبق على الجميع، والمرحلة تُطابَق تماماً: كان «حادي عشر»
  /// يطابق «حادي عشر علمي» فتُعرض مواد الفرع الآخر.
  List<SubjectItem> gradeApplicableSubjects(String? gradeLevel) =>
      subjects.where((s) => subjectAppliesToGrade(s.gradeLevel, gradeLevel)).toList();

  /// معلمو الشعبة: مربّيها ومعلمو موادها بلا تكرار.
  Set<String> sectionTeacherIds(Classroom room) {
    final ids = <String>{};
    if (room.teacherId.trim().isNotEmpty && teacherById(room.teacherId) != null) {
      ids.add(room.teacherId.trim());
    }
    for (final g in sectionSubjectGroups(room.id)) {
      if (g.teacherId.trim().isNotEmpty) ids.add(g.teacherId.trim());
    }
    return ids;
  }

  /// حفظ مواد الشعبة ومعلميها — مطابق لـ `saveSectionSubjectAssignments`.
  ///
  /// [assignments] معرّف المادة ← معرّف معلمها، والفارغ مادة تنتظر معلماً وتبقى
  /// محفوظة. الموديل مشترك: مادة ومعلم ومرحلة بسجل واحد تنضم إليه الشعب، ففصل
  /// شعبة ينهي تسجيلات طلابها وحدهم ويؤرشف الموديل حين لا تبقى له شعبة.
  /// التسجيل يُنهى ولا يُحذف: الدرجات المرصودة معلّقة به. تُعيد عدد المواد.
  int saveSectionSubjectAssignments({
    required String roomId,
    required String gradeLevel,
    required String roomName,
    required Map<String, String> assignments,
  }) {
    requireSection('classes');
    final room = roomById(roomId);
    if (room == null) throw StoreException('لم يتم العثور على الصف');

    final now = _nowIso();
    final grade = gradeLevel.trim().isNotEmpty ? gradeLevel.trim() : room.gradeLevel;
    final sectionName = roomName.trim().isNotEmpty ? roomName.trim() : room.name;

    // مادة واحدة لكل إسناد، والمادة المحذوفة لا تُحفظ
    final desired = <String, String>{
      for (final e in assignments.entries)
        if (subjects.any((s) => s.id == e.key)) e.key: e.value.trim(),
    };
    final archived = <String>{};
    final thisRoom = groups.where((g) => g.isActive && g.includesRoom(roomId)).toList();

    // طلاب الشعبة بمطابقة تامة للاسم والمرحلة: الطالب بلا مرحلة كان يُسجَّل في كل
    // شعبة يُحفظ توزيعها، لأن غياب القيمة كان يُعدّ مطابقة
    final sectionStudents = sectionName.isEmpty
        ? const <Student>[]
        : students
            .where((s) =>
                s.status == 'active' &&
                belongsToSection(section: s.section, grade: s.gradeLevel, roomName: sectionName, roomGrade: grade))
            .toList();
    final sectionIds = {for (final s in sectionStudents) s.id};

    void enrollSectionStudents(Group group) {
      for (final st in sectionStudents) {
        final current = enrollments.where((e) => e.groupId == group.id && e.studentId == st.id).firstOrNull;
        if (current == null) {
          final enrollment = StudentEnrollment(
            id: newId(),
            studentId: st.id,
            groupId: group.id,
            roomId: roomId,
            customPrice: 0,
            appliedPrice: 0,
            syncStatus: 'pending',
            createdAt: now,
            updatedAt: now,
          );
          enrollments.add(enrollment);
          _queue('enrollments', enrollment.id, 'INSERT', enrollment.toCloud());
          continue;
        }
        // تسجيل مختوم بشعبة أخرى تشارك الموديل: ليس من شأن هذه الشعبة
        if (current.roomId.isNotEmpty && current.roomId != roomId) continue;
        if (current.isActive && current.roomId == roomId) continue;
        current.status = 'active';
        current.roomId = roomId;
        current.updatedAt = now;
        current.syncStatus = 'pending';
        _queue('enrollments', current.id, 'UPDATE', current.toCloud());
      }
    }

    void detach(Group group) {
      final remaining = group.allRoomIds.where((id) => id != roomId).toList();
      final otherRooms = remaining.map(roomById).whereType<Classroom>().toList();
      for (final e in enrollments.where((e) => e.groupId == group.id && e.isActive)) {
        final student = studentById(e.studentId);
        // تسجيل قديم بلا ربط: لا يُمسّ إلا إن كان صاحبه من هذه الشعبة وحدها
        final mine = e.roomId.isNotEmpty
            ? e.roomId == roomId
            : student != null &&
                sectionIds.contains(e.studentId) &&
                !otherRooms.any((r) => studentBelongsToRoom(student, r));
        if (!mine) continue;
        e.status = 'withdrawn';
        e.updatedAt = now;
        e.syncStatus = 'pending';
        _queue('enrollments', e.id, 'UPDATE', e.toCloud());
      }
      if (remaining.isEmpty) {
        group.status = 'archived';
        group.roomIds = [];
        archived.add(group.id);
      } else {
        group.roomId = remaining.first;
        group.roomIds = remaining;
      }
      group.updatedAt = now;
      group.syncStatus = 'pending';
      _queue('groups', group.id, 'UPDATE', group.toCloud());
    }

    // ١. فصل الشعبة عن مواد أُزيلت من قائمتها
    for (final g in thisRoom) {
      if (!desired.containsKey(g.subjectId)) detach(g);
    }

    // ٢. لكل مادة: الموديل المشترك (مادة + معلم + مرحلة) أو إنشاؤه
    for (final entry in desired.entries) {
      final subjectId = entry.key;
      final teacherId = entry.value;
      final subject = subjectName(subjectId);
      final teacher = teacherId.isEmpty ? 'غير مسند' : (teacherById(teacherId)?.name ?? 'معلم');
      final name = '${subject.isEmpty ? 'مادة' : subject} - $teacher';

      final current = thisRoom.where((g) => g.subjectId == subjectId && !archived.contains(g.id)).firstOrNull;
      if (current != null && current.teacherId == teacherId) {
        // لم يتغيّر المعلم: يبقى تسجيل من انضم إلى الشعبة بعد آخر حفظ
        enrollSectionStudents(current);
        continue;
      }
      // الشعبة كانت على معلم آخر للمادة: تُفصل عن موديله أولاً
      if (current != null) detach(current);

      var target = groups
          .where((g) =>
              g.isActive &&
              g.id != current?.id &&
              g.subjectId == subjectId &&
              g.teacherId == teacherId &&
              isSameGrade(g.gradeLevel, grade) &&
              !g.includesRoom(roomId))
          .firstOrNull;

      if (target != null) {
        target.roomIds = [...target.allRoomIds, roomId];
        if (target.roomId.isEmpty) target.roomId = roomId;
        target.name = name;
        target.updatedAt = now;
        target.syncStatus = 'pending';
        _queue('groups', target.id, 'UPDATE', target.toCloud());
      } else {
        // لا تمرّ على `upsertGroup`: تلك تشترط أياماً ومواعيد لا وجود لها هنا
        target = Group(
          id: newId(),
          name: name,
          subjectId: subjectId,
          teacherId: teacherId,
          roomId: roomId,
          roomIds: [roomId],
          gradeLevel: grade,
          startTime: '',
          endTime: '',
          syncStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        groups.add(target);
        thisRoom.add(target);
        _queue('groups', target.id, 'INSERT', target.toCloud());
      }
      enrollSectionStudents(target);
    }

    markDirty('groups');
    markDirty('enrollments');
    return desired.length;
  }

  /// مواءمة تسجيلات الطلاب مع شعبهم الحالية — `syncStudentRoomEnrollments`.
  ///
  /// تغيير شعبة الطالب كان يعدّل `section` وحده، فيبقى مسجّلاً في مواد شعبته
  /// القديمة ولا يظهر في الجديدة حتى يُعاد حفظ توزيعها. تقتصر على مجموعات المواد
  /// المدرسية؛ التسجيل المجدول المدفوع لا يُمسّ.
  void syncStudentRoomEnrollments(Iterable<String> studentIds) {
    final now = _nowIso();
    final activeGroups = groups.where((g) => g.isActive).toList();
    var changed = false;

    for (final id in studentIds.toSet()) {
      final student = studentById(id);
      if (student == null) continue;

      final room = student.status == 'active' ? rooms.where((r) => studentBelongsToRoom(student, r)).firstOrNull : null;
      final target = room == null
          ? const <Group>[]
          : activeGroups.where((g) => g.isSchoolGroup && g.includesRoom(room.id)).toList();
      final targetIds = {for (final g in target) g.id};
      final current = enrollments.where((e) => e.studentId == id).toList();

      // إنهاء تسجيلات شعبة سابقة — المختومة بشعبة وحدها
      for (final e in current) {
        if (!e.isActive || targetIds.contains(e.groupId)) continue;
        if (e.roomId.isEmpty || (room != null && e.roomId == room.id)) continue;
        final group = activeGroups.where((g) => g.id == e.groupId).firstOrNull;
        if (group != null && !group.isSchoolGroup) continue;
        e.status = 'withdrawn';
        e.updatedAt = now;
        e.syncStatus = 'pending';
        _queue('enrollments', e.id, 'UPDATE', e.toCloud());
        changed = true;
      }

      if (room == null) continue;
      // تسجيله في مواد شعبته الحالية
      for (final group in target) {
        final existing = current.where((e) => e.groupId == group.id).firstOrNull;
        if (existing == null) {
          final enrollment = StudentEnrollment(
            id: newId(),
            studentId: id,
            groupId: group.id,
            roomId: room.id,
            customPrice: 0,
            appliedPrice: 0,
            syncStatus: 'pending',
            createdAt: now,
            updatedAt: now,
          );
          enrollments.add(enrollment);
          _queue('enrollments', enrollment.id, 'INSERT', enrollment.toCloud());
          changed = true;
        } else if (!existing.isActive || existing.roomId != room.id) {
          existing.status = 'active';
          existing.roomId = room.id;
          existing.updatedAt = now;
          existing.syncStatus = 'pending';
          _queue('enrollments', existing.id, 'UPDATE', existing.toCloud());
          changed = true;
        }
      }
    }

    if (changed) markDirty('enrollments');
  }

  /// تسجيل طالب في مجموعة.
  ///
  /// السعر المطبَّق يُثبَّت لحظة التسجيل حتى لا يتغيّر عكس القيد المالي إذا
  /// عُدّل سعر المجموعة لاحقاً — مطابق لـ `ScheduleService.enrollStudent`.
  StudentEnrollment enrollStudent({
    required String studentId,
    required String groupId,
    double? customPrice,
    String discountReason = '',
  }) {
    requireSection('classes');
    final student = studentById(studentId);
    if (student == null) throw StoreException('يرجى اختيار الطالب أولاً');
    final group = groupById(groupId);
    if (group == null) throw StoreException('يرجى اختيار المجموعة أولاً');

    final existing = enrollments
        .where((e) => e.studentId == studentId && e.groupId == groupId && e.isActive)
        .firstOrNull;
    if (existing != null) {
      throw StoreException('الطالب «${student.fullName}» مسجَّل بالفعل في مجموعة «${group.name}».');
    }

    final max = group.maxStudents;
    if (max != null && max > 0 && enrollmentCount(groupId) >= max) {
      throw StoreException('مجموعة «${group.name}» اكتمل عددها ($max طالباً).');
    }

    final applied = customPrice ?? group.pricePerMonth;
    final enrollment = StudentEnrollment(
      id: newId(),
      studentId: studentId,
      groupId: groupId,
      customPrice: customPrice,
      appliedPrice: applied,
      discountReason: discountReason.trim(),
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    enrollments.add(enrollment);
    _queue('enrollments', enrollment.id, 'INSERT', enrollment.toCloud());
    // رسوم المجموعة مديونية على الطالب — كانت لا تُقيَّد على الرصيد إطلاقاً
    _refreshBalance(student);
    return enrollment;
  }

  void updateEnrollmentStatus(String enrollmentId, String status) {
    requireSection('classes');
    final e = enrollments.where((x) => x.id == enrollmentId).firstOrNull;
    if (e == null) return;
    e.status = status;
    e.updatedAt = _nowIso();
    e.syncStatus = 'pending';
    _queue('enrollments', e.id, 'UPDATE', e.toCloud());
    // الملغى لا تُحتسب رسومه، والنشط تُحتسب
    final owner = studentById(e.studentId);
    if (owner != null) _refreshBalance(owner);
  }

  void deleteEnrollment(String enrollmentId) {
    requireSection('classes');
    final linked = payments.where((p) => p.enrollmentId == enrollmentId && !p.cancelled).length;
    if (linked > 0) {
      throw StoreException(
        'لا يمكن إلغاء هذا التسجيل لأن عليه $linked سند قبض مسجَّل. ألغِ السندات أولاً.',
      );
    }
    final removed = enrollments.where((e) => e.id == enrollmentId).firstOrNull;
    enrollments.removeWhere((e) => e.id == enrollmentId);
    _queue('enrollments', enrollmentId, 'DELETE', null);
    final owner = removed == null ? null : studentById(removed.studentId);
    if (owner != null) _refreshBalance(owner);
  }

  // ── الجلسات (المقابل لـ attendance.service.ts) ──────────────────────────────

  /// إيجاد جلسة لتاريخ ومجموعة/قاعة، أو إنشاؤها.
  ClassSession sessionFor(String roomId, String dateStr) {
    final found = sessions
        .where((s) => s.sessionDate == dateStr && (s.groupId == roomId || s.roomId == roomId))
        .firstOrNull;
    if (found != null) return found;

    final created = ClassSession(
      id: newId(),
      groupId: roomId,
      sessionDate: dateStr,
      startTime: '08:00',
      endTime: '10:00',
      teacherId: '',
      roomId: roomId,
      status: 'scheduled',
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    sessions.add(created);
    _queue('sessions', created.id, 'INSERT', created.toCloud());
    return created;
  }

  void upsertTeacher(Teacher t) {
    requireSection('settings');
    if (t.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المعلم');
    t.updatedAt = _nowIso();
    t.syncStatus = 'pending';
    final i = teachers.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      t.createdAt = teachers[i].createdAt;
      teachers[i] = t;
      _queue('teachers', t.id, 'UPDATE', t.toCloud());
    } else {
      t.createdAt = _nowIso();
      teachers.add(t);
      _queue('teachers', t.id, 'INSERT', t.toCloud());
    }
  }

  /// حذف معلم بعد فكّ ارتباطه — مطابق لـ `SettingsService.deleteTeacher`.
  ///
  /// المجموعات والشعب تشير إليه بمفتاح أجنبي: حذفه قبل فكّها ترفضه السحابة
  /// (`violates foreign key constraint`)، فتبقى العملية عالقة في الطابور
  /// والمعلم محذوفاً على الجهاز وحده.
  void deleteTeacher(String id) {
    requireSection('settings');
    final now = _nowIso();

    for (final g in groups.where((g) => g.teacherId == id)) {
      g.teacherId = '';
      g.updatedAt = now;
      g.syncStatus = 'pending';
      _queue('groups', g.id, 'UPDATE', g.toCloud());
    }
    for (final r in rooms.where((r) => r.teacherId == id)) {
      r.teacherId = '';
      r.updatedAt = now;
      r.syncStatus = 'pending';
      _queue('rooms', r.id, 'UPDATE', r.toCloud());
    }

    teachers.removeWhere((t) => t.id == id);
    _queue('teachers', id, 'DELETE', null);
    markDirty('groups');
    markDirty('rooms');
    markDirty('teachers');
    notifyListeners();
  }

  void upsertSubject(SubjectItem s) {
    requireSection('settings');
    if (s.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المادة');
    s.updatedAt = _nowIso();
    s.syncStatus = 'pending';
    final i = subjects.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      s.createdAt = subjects[i].createdAt;
      subjects[i] = s;
      _queue('subjects', s.id, 'UPDATE', s.toCloud());
    } else {
      s.createdAt = _nowIso();
      subjects.add(s);
      _queue('subjects', s.id, 'INSERT', s.toCloud());
    }
  }

  /// حذف مادة بعد فكّ مجموعاتها منها — مطابق لـ `SettingsService.deleteSubject`.
  void deleteSubject(String id) {
    requireSection('settings');
    final now = _nowIso();

    // مجموعة المادة المحذوفة تُؤرشف، فلا تبقى صفاً بلا عنوان في مواد الشعبة
    for (final g in groups.where((g) => g.subjectId == id)) {
      g.subjectId = '';
      g.status = 'archived';
      g.updatedAt = now;
      g.syncStatus = 'pending';
      _queue('groups', g.id, 'UPDATE', g.toCloud());
    }

    subjects.removeWhere((s) => s.id == id);
    _queue('subjects', id, 'DELETE', null);
    markDirty('groups');
    markDirty('subjects');
    notifyListeners();
  }

  void upsertRoom(Classroom r) {
    requireSection('classes', ['settings']);
    if (r.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم الصف / الشعبة');
    // المرحلة في حقلها: تكرارها داخل اسم الشعبة يُنتج «ثاني عشر علمي (ثاني عشر علمي أ)»
    r.name = r.gradeLevel.trim().isEmpty ? r.name.trim() : sanitizeSectionName(r.name, r.gradeLevel);
    r.updatedAt = _nowIso();
    r.syncStatus = 'pending';
    final i = rooms.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      final oldName = rooms[i].name.trim();
      r.createdAt = rooms[i].createdAt;
      rooms[i] = r;
      _queue('rooms', r.id, 'UPDATE', r.toCloud());
      // شعبة الطلاب تتبع اسم الصف: إبقاؤها على الاسم القديم كان يُفرغ الصف من طلابه
      if (oldName.isNotEmpty && oldName != r.name) _renameStudentSection(oldName, r.name);
    } else {
      r.createdAt = _nowIso();
      rooms.add(r);
      _queue('rooms', r.id, 'INSERT', r.toCloud());
    }
  }

  /// نقل طلاب شعبة إلى اسمها الجديد بعد تغييره.
  void _renameStudentSection(String oldName, String newName) {
    for (final s in students) {
      if (s.section.trim() != oldName) continue;
      s.section = newName;
      s.updatedAt = _nowIso();
      s.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
    }
    markDirty('students');
    markDirty(_pendingTable);
  }

  /// ربط التسجيلات القائمة بشعبها — مرة واحدة، مطابق لترقية v10 في db.ts.
  ///
  /// يُستنتج من البيانات ويُرفع حتى لا يمحوه أول سحب على جهاز آخر: مجموعة بشعبة
  /// واحدة شعبتها معروفة، ومجموعة بشعب عدة تُحسم بشعبة الطالب إن طابقت واحدة
  /// منها. ما يتعذّر حسمه يقيناً يُترك فارغاً.
  Future<int> migrateEnrollmentRooms() async {
    if (db.settings[enrollmentRoomMigrationKey] == 'true') return 0;

    var changed = 0;
    for (final e in enrollments) {
      if (e.roomId.isNotEmpty) continue;
      final group = groupById(e.groupId);
      if (group == null) continue;
      final groupRooms = group.allRoomIds.map(roomById).whereType<Classroom>().toList();
      if (groupRooms.isEmpty) continue;

      Classroom? resolved;
      if (groupRooms.length == 1) {
        resolved = groupRooms.first;
      } else {
        final student = studentById(e.studentId);
        final candidates =
            student == null ? const <Classroom>[] : groupRooms.where((r) => studentBelongsToRoom(student, r)).toList();
        if (candidates.length == 1) resolved = candidates.first;
      }
      if (resolved == null) continue;

      e.roomId = resolved.id;
      e.updatedAt = _nowIso();
      e.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'enrollments', recordId: e.id, action: 'UPDATE', payload: e.toCloud());
      changed++;
    }

    if (changed > 0) {
      markDirty('enrollments');
      markDirty(_pendingTable);
    }
    await db.setSetting(enrollmentRoomMigrationKey, 'true');
    return changed;
  }

  /// تنقية أسماء الشعب والمجموعات المحفوظة سابقاً — مرة واحدة لكل جهاز.
  Future<int> migrateSectionNames() async {
    if (db.settings[sectionNameMigrationKey] == 'true') return 0;

    var changed = 0;
    for (final r in rooms) {
      if (r.gradeLevel.trim().isEmpty) continue;
      final clean = sanitizeSectionName(r.name, r.gradeLevel);
      if (clean.isEmpty || clean == r.name) continue;
      final oldName = r.name.trim();
      r.name = clean;
      r.updatedAt = _nowIso();
      r.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'rooms', recordId: r.id, action: 'UPDATE', payload: r.toCloud());
      _renameStudentSection(oldName, clean);
      changed++;
    }

    for (final g in groups) {
      final clean = sanitizeGroupName(g.name, subject: subjectName(g.subjectId), gradeLevel: g.gradeLevel);
      if (clean.isEmpty || clean == g.name) continue;
      g.name = clean;
      g.updatedAt = _nowIso();
      g.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'groups', recordId: g.id, action: 'UPDATE', payload: g.toCloud());
      changed++;
    }

    if (changed > 0) {
      markDirty('rooms');
      markDirty('groups');
      markDirty(_pendingTable);
    }
    await db.setSetting(sectionNameMigrationKey, 'true');
    return changed;
  }

  /// حذف شعبة بعد فكّ ما يتبعها — مطابق لـ `SettingsService.deleteRoom`.
  ///
  /// طلابها تبقى شعبتهم اسماً لصفٍّ لا وجود له، ومجموعاتها تشير إليها بمفتاح
  /// أجنبي ترفض السحابة حذفه قبل فكّه.
  void deleteRoom(String id) {
    requireSection('classes', ['settings']);
    final room = rooms.where((r) => r.id == id).firstOrNull;
    final now = _nowIso();

    if (room != null && room.name.trim().isNotEmpty) {
      for (final s in students.where((s) => s.section.trim() == room.name.trim())) {
        s.section = '';
        s.updatedAt = now;
        s.syncStatus = 'pending';
        _queue('students', s.id, 'UPDATE', s.toCloud());
      }
    }
    // فك ارتباط المجموعات بالشعبة في room_id وroom_ids معاً
    for (final g in groups.where((g) => g.includesRoom(id))) {
      final remaining = g.allRoomIds.where((r) => r != id).toList();
      g.roomId = remaining.isEmpty ? '' : remaining.first;
      g.roomIds = remaining;
      g.updatedAt = now;
      g.syncStatus = 'pending';
      _queue('groups', g.id, 'UPDATE', g.toCloud());
    }

    rooms.removeWhere((r) => r.id == id);
    _queue('rooms', id, 'DELETE', null);
    markDirty('students');
    markDirty('groups');
    markDirty('rooms');
    notifyListeners();
  }

  void updateGradeFee(GradeFee f) {
    requireSection('settings');
    if (f.gradeName.trim().isEmpty) throw StoreException('يرجى إدخال اسم المرحلة الدراسية');
    if (f.monthlyFee < 0) throw StoreException('يرجى إدخال رسم شهري صحيح');
    f.updatedAt = _nowIso();
    f.syncStatus = 'pending';
    final i = gradeFees.indexWhere((e) => e.id == f.id);
    if (i >= 0) {
      f.createdAt = gradeFees[i].createdAt;
      gradeFees[i] = f;
    }
    _queue('grade_fees', f.id, 'UPDATE', f.toCloud());
  }

  void addGradeFee(GradeFee f, {String initialSection = ''}) {
    requireSection('settings');
    if (f.gradeName.trim().isEmpty) throw StoreException('يرجى إدخال اسم المرحلة أو الصف');
    if (f.monthlyFee < 0) throw StoreException('يرجى إدخال رسم شهري صحيح');
    f.createdAt = _nowIso();
    f.updatedAt = _nowIso();
    f.syncStatus = 'pending';
    gradeFees.add(f);
    _queue('grade_fees', f.id, 'INSERT', f.toCloud());
    if (initialSection.trim().isNotEmpty) {
      upsertRoom(
        Classroom(
          id: newId(),
          name: initialSection.trim(),
          gradeLevel: f.gradeName,
          teacherId: '',
          capacity: 25,
          tier: f.tier,
        ),
      );
    }
  }

  void deleteGradeFee(GradeFee f) {
    requireSection('settings');
    final count = students.where((s) => isSameGrade(s.gradeLevel, f.gradeName)).length;
    if (count > 0) {
      throw StoreException(
        'لا يمكن حذف مرحلة "${f.gradeName}" لوجود ($count) طالب مسجلين بها حالياً.\nيرجى نقل أو تعديل مراحل هؤلاء الطلاب أولاً قبل حذف المرحلة الدراسية.',
      );
    }
    gradeFees.removeWhere((e) => e.id == f.id);
    _queue('grade_fees', f.id, 'DELETE', null);
  }

  void updateUser(AppUser u) {
    requireSection('settings.users');
    final i = users.indexWhere((e) => e.id == u.id);
    if (i < 0) return;
    u.updatedAt = _nowIso();
    u.syncStatus = 'pending';
    u.createdAt = users[i].createdAt;
    users[i] = u;
    _queue('users', u.id, 'UPDATE', u.toCloud());
  }

  void deleteUser(String id) {
    requireSection('settings.users');
    if (users.length <= 1) throw StoreException('لا يمكن حذف المستخدم الوحيد في النظام');
    users.removeWhere((u) => u.id == id);
    _queue('users', id, 'DELETE', null);
  }

  String? deviceUserId;
  String receiptReceiverLabel = '';

  // ── تهيئة الجهاز الجديد (المقابل لـ NewDeviceSetupModal) ───────────────────

  /// هل يحتاج هذا الجهاز إلى تهيئة أولية قبل السماح بالعمل؟
  ///
  /// **مثبَّتة**: تُحسم مرة واحدة عند الدخول ولا تُعاد قراءتها مع كل رسم. لو
  /// اعتمدت على `students.isEmpty` لحظياً لانقلبت إلى `false` بمجرد نجاح
  /// السحب الأولي، فتُغلق الشاشة قبل أن يختار المستخدم هوية الجهاز وصلاحيته.
  bool _setupPending = false;

  bool get needsInitialSetup => _setupPending && loggedIn && !isMasterAdmin;

  /// حسم الحاجة إلى التهيئة.
  ///
  /// [freshLogin] يعني أن المستخدم أدخل بياناته للتو، لا أن الجلسة استُعيدت
  /// بعد إقلاع. كل دخول جديد يمرّ على شاشة تحديد المستخدم والصلاحية، لأن من
  /// يسجّل الخروج غالباً يسلّم الجهاز لغيره — ولا يصحّ أن يرث صلاحية سابقه.
  /// أما إعادة تشغيل التطبيق بجلسة قائمة فتدخل مباشرةً.
  Future<void> _resolveSetupGate({bool freshLogin = false}) async {
    final tid = tenantId;
    if (!loggedIn || isMasterAdmin || tid == null) {
      _setupPending = false;
      return;
    }
    if (freshLogin) {
      _setupPending = true;
      return;
    }
    // تهيئة بدأت ولم تكتمل: السحب الأولي يملأ الطلاب قبل اختيار الهوية، فلو
    // حُسمت البوابة بوجود البيانات لدخل من أغلق التطبيق أثناءه بلا كلمة مرور
    if (db.settings[_kSetupPending] != null) {
      _setupPending = true;
      return;
    }
    // بلا هوية مثبَّتة لا دخول: الجهاز بلا هوية يعمل بصلاحية المدير الكاملة
    if (deviceUser == null) {
      _setupPending = true;
      return;
    }
    if (db.settings[initialSetupKey(tid)] == 'true') {
      _setupPending = false;
      return;
    }
    // جهاز يحمل بيانات وهوية من قبل هذه الميزة يُعتبر مهيَّأً
    if (students.isNotEmpty) {
      await db.setSetting(initialSetupKey(tid), 'true');
      _setupPending = false;
      return;
    }
    _setupPending = true;
  }

  /// حساب مدير المنشأة الأول.
  ///
  /// المعرّف حتمي (`owner_<tenantId>`) فلا ينتج عن تهيئة جهازين حسابان
  /// متكرران — يتفقان على نفس السجل ويدمجه upsert.
  AppUser ensureOwnerAdmin() {
    final tid = tenantId;
    final id = 'owner_${tid ?? 'local'}';
    final existing = users.where((u) => u.id == id).firstOrNull;
    if (existing != null) return existing;

    final name = (currentTenant?.ownerName.trim().isNotEmpty ?? false)
        ? currentTenant!.ownerName.trim()
        : (currentTenant?.name.trim() ?? '');
    final owner = AppUser(
      id: id,
      name: name.isEmpty ? 'مدير المنشأة' : name,
      role: 'admin',
      capabilities: [...allSections],
    )
      ..createdAt = _nowIso()
      ..updatedAt = _nowIso()
      ..syncStatus = 'pending';
    users.add(owner);
    _queue('users', id, 'INSERT', owner.toCloud());
    return owner;
  }

  /// إزالة حسابات العرض التجريبية المتسربة محلياً بلا رفع حذف للسحابة.
  void cleanLocalDemoUsers() {
    const demoEmails = {'principal@alamal.edu', 'reception@alamal.edu'};
    final ids = users.where((u) => demoEmails.contains(u.email.trim())).map((u) => u.id).toSet();
    if (ids.isEmpty) return;
    users.removeWhere((u) => ids.contains(u.id));
    pendingSyncs.removeWhere((a) => a.tableName == 'users' && ids.contains(a.recordId));
    markDirty('users');
    markDirty(_pendingTable);
  }

  /// السحب الأولي الكامل عند تهيئة جهاز جديد. يعيد عدد السجلات المنزَّلة.
  /// بيانات هذه المنشأة محفوظة على الجهاز من جلسة سابقة.
  ///
  /// تبديل المستخدم داخل المدرسة نفسها لا يستدعي تنزيلاً جديداً: القاعدة المحلية
  /// هي هي، ويكفي تحديثُ ما تغيّر في الخلفية.
  bool get hasLocalTenantData => dbTenantId == tenantId && (students.isNotEmpty || users.isNotEmpty);

  Future<int> initialPull() async {
    final tid = tenantId;
    if (tid == null) throw StoreException('لا توجد منشأة نشطة على هذا الجهاز.');
    if (!networkEnabled) {
      throw StoreException('لا يمكن تهيئة الجهاز دون اتصال بالإنترنت.');
    }
    final res = await sync.pullFromCloud(tid);
    cleanLocalDemoUsers();
    await hydrateInstitution();
    notifyListeners();
    return res.pulled;
  }

  /// تجميد لقطات السندات القديمة — المقابل لـ `freezeHistoricalPaymentSnapshots`.
  ///
  /// السند المحاسبي يحفظ اسم الطالب واسم المستلم كما كانا وقت القبض. قراءتهما من
  /// السجل الحالي عند كل عرض كانت تُغيّر سندات قديمة بأثر رجعي إذا تغيّر اسم
  /// الطالب أو هوية الجهاز. تُكتب محلياً فقط ولا تُرفع (لا عمود لها في السحابة).
  Future<int> migratePaymentSnapshots() async {
    if (db.settings[paymentSnapshotKey] == 'true') return 0;

    var changed = 0;
    for (final p in payments) {
      if (p.studentName.trim().isEmpty) {
        final student = studentById(p.studentId);
        if (student != null) {
          p.studentName = student.fullName;
          changed++;
        }
      }
      if (p.receivedByName.trim().isEmpty) {
        final issuer = users.where((u) => u.id == p.receivedByUserId).firstOrNull;
        p.receivedByName = issuer?.name ?? 'الإدارة';
        changed++;
      }
    }

    if (changed > 0) markDirty('payments');
    await db.setSetting(paymentSnapshotKey, 'true');
    return changed;
  }

  /// المستخدمون النشطون المتاحون لاختيار هوية الجهاز.
  List<AppUser> get setupCandidates {
    final active = users.where((u) => u.isActive).toList();
    if (active.isEmpty) return [ensureOwnerAdmin()];
    return active;
  }

  /// كلمات المرور المقبولة لتثبيت صلاحية مدير على هذا الجهاز: كلمة المنشأة
  /// نفسها، أو كلمة المطور إن بُنيت النسخة بحساب مطور.
  ///
  /// كان يقبل مفتاحاً عاماً مكتوباً في الكود يفتح تهيئة أي جهاز في أي مدرسة —
  /// سرٌّ واحد مكشوف لكل من يفكّ التطبيق.
  /// التحقق السحابي — `verify_admin_password`. القاعدة تحمل البصمة وحدها،
  /// فلا تُقارن كلمة مرور المدير على الجهاز ولا تُخزَّن فيه.
  Future<bool> verifyAdminSetupPassword(String entered) async {
    final e = entered.trim();
    if (e.isEmpty) return false;
    final tid = currentTenant?.id;
    if (networkEnabled && SupabaseAuth.signedIn && tid != null) {
      final answer = await supabaseRpc('verify_admin_password', {'p_tenant_id': tid, 'p_password': e});
      if (answer is bool) return answer;
      // تعذّر السؤال (انقطاع أو دالة غير منشورة): يُحتكم إلى الفحص المحلي
    }
    return isAdminSetupPasswordValid(e);
  }

  bool isAdminSetupPasswordValid(String entered) {
    final e = entered.trim();
    if (e.isEmpty) return false;
    if (TenantService.hasMasterAccount && e == TenantService.masterPassword.trim()) return true;
    final tenantPass = (currentTenant?.password.trim().isNotEmpty ?? false)
        ? currentTenant!.password.trim()
        : _tenantPass.trim();
    return tenantPass.isNotEmpty && e == tenantPass;
  }

  /// تثبيت هوية الجهاز وإنهاء التهيئة.
  Future<void> completeInitialSetup(AppUser user) async {
    await setDeviceIdentity(user, user.name);
    final tid = tenantId;
    if (tid != null) await db.setSetting(initialSetupKey(tid), 'true');
    await db.setSetting(_kSetupPending, null);
    _setupPending = false;
    await flush();
    notifyListeners();
  }

  /// إعادة فتح التهيئة (لتغيير هوية الجهاز لاحقاً من الإعدادات).
  Future<void> resetInitialSetup() async {
    final tid = tenantId;
    if (tid != null) {
      await db.setSetting(initialSetupKey(tid), null);
      await db.setSetting(_kSetupPending, tid);
    }
    _setupPending = loggedIn && !isMasterAdmin && tid != null;
    notifyListeners();
  }

  Future<void> setDeviceIdentity(AppUser user, String receiptLabel) async {
    deviceUserId = user.id;
    receiptReceiverLabel = receiptLabel.trim().isEmpty ? user.name : receiptLabel.trim();
    roleName = roleLabel(user.role);
    await db.setSetting(_kDeviceUser, user.id);
    await db.setSetting(_kReceiptLabel, receiptReceiverLabel);
    notifyListeners();
  }

  /// المستخدم المثبَّت على هذا الجهاز — المقابل لـ `getCurrentUser()`.
  AppUser? get deviceUser {
    final id = deviceUserId;
    if (id == null) return null;
    return users.where((u) => u.id == id).firstOrNull;
  }

  /// معرّف من يسجّل العمليات. مطابق لـ `getCurrentUserId()`.
  String get currentUserId => deviceUserId ?? '';

  // ── الصلاحيات (المقابل لـ usePermissions + userCan) ─────────────────────────

  /// حارس التبويب في أول كل عملية كتابة يطلبها المستخدم.
  ///
  /// إخفاء الأزرار وحده لا يكفي: كل زر جديد فرصة لنسيان فحصه. هنا يُرفض الفعل
  /// نفسه مهما كان المسار إليه، بالتبويب الذي يملك العملية. الجهاز الذي لم
  /// تُثبَّت عليه هوية بعد يرى كل التبويبات، كما في النسخة المكتبية.
  /// [alternatives] لعملية تخدم تبويبين، كالصفوف من شاشتها ومن الإعدادات.
  void requireSection(String section, [List<String> alternatives = const []]) {
    if (can(section) || alternatives.any(can)) return;
    throw StoreException('لا صلاحية لك على «${sectionLabel(section)}»');
  }

  /// التبويبات الفعلية لمستخدم هذا الجهاز. الحساب الموقوف لا يرى شيئاً.
  List<String> get mySections {
    final me = deviceUser;
    if (me == null) return [...allSections];
    if (!me.isActive) return const [];
    return effectiveSections(me.capabilities, me.role);
  }

  /// هل يرى مستخدم هذا الجهاز هذا التبويب؟ — `userCanAccess`.
  bool can(String section) => mySections.contains(resolveSection(section) ?? section);

  /// هل يستطيع فتح هذا القسم؟ القسم غير المعروف لا يُحرس.
  bool canOpenSection(String section) {
    final needed = resolveSection(section);
    return needed == null || can(needed);
  }

  /// اسم المستلم على سند القبض — مطابق لـ `getReceiptReceiverLabel()`.
  String get receiptReceiver {
    if (receiptReceiverLabel.trim().isNotEmpty) return receiptReceiverLabel.trim();
    return deviceUser?.name ?? 'موظف الاستقبال';
  }

  void addUser(AppUser u) {
    requireSection('settings.users');
    if (u.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المستخدم');
    u.createdAt = _nowIso();
    u.updatedAt = _nowIso();
    u.syncStatus = 'pending';
    users.add(u);
    _queue('users', u.id, 'INSERT', u.toCloud());
  }

  void upsertTenant(Tenant t) {
    if (t.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المنشأة');
    final i = tenants.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      tenants[i] = t;
    } else {
      tenants.add(t);
    }
    markDirty('tenants');
    notifyListeners();
  }

  void deleteTenant(String id) {
    tenants.removeWhere((t) => t.id == id);
    markDirty('tenants');
    notifyListeners();
  }

  /// صفٌّ للمزامنة والقرص: شكل السحابة ومعه حالة السجل المحلية.
  ///
  /// `toCloud` تكتب أعمدة السحابة وحدها بلا `sync_status`، وغيابه كان يُعطّل
  /// توفيق الحذف كله: الشرط `sync_status == 'synced'` لا ينطبق على أي صف، فتبقى
  /// السجلات المحذوفة من السحابة ظاهرة على الجهاز إلى الأبد.
  static Map<String, dynamic> _row(Map<String, dynamic> cloud, String status) => {...cloud, 'sync_status': status};

  static List<Map<String, dynamic>> _rows<T>(
    Iterable<T> items,
    Map<String, dynamic> Function(T) cloud,
    String Function(T) status,
  ) =>
      [for (final e in items) _row(cloud(e), status(e))];

  @override
  Map<String, dynamic>? recordOf(String table, String id) {
    switch (table) {
      case 'students':
        final e = studentById(id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'student_attachments':
        final e = attachmentsByStudent[id];
        return e == null ? null : _row(e.toLocal(), e.syncStatus);
      case 'teachers':
        final e = teacherById(id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'subjects':
        final e = subjects.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'rooms':
        final e = rooms.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'grade_fees':
        final e = gradeFees.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'users':
        final e = users.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'payments':
        final e = payments.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'installments':
        final e = installments.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'attendance':
        final e = attendance.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'tenants':
        return tenants.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'groups':
        final e = groups.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'enrollments':
        final e = enrollments.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'sessions':
        final e = sessions.where((e) => e.id == id).firstOrNull;
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      default:
        return extraCloud[table]?.where((e) => '${e['id']}' == id).firstOrNull;
    }
  }

  @override
  List<Map<String, dynamic>> allOf(String table) {
    switch (table) {
      case 'students':
        return _rows(students, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'student_attachments':
        return _rows(attachmentsByStudent.values, (e) => e.toLocal(), (e) => e.syncStatus);
      case 'teachers':
        return _rows(teachers, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'subjects':
        return _rows(subjects, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'rooms':
        return _rows(rooms, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'grade_fees':
        return _rows(gradeFees, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'users':
        return _rows(users, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'payments':
        return _rows(payments, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'installments':
        return _rows(installments, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'attendance':
        return _rows(attendance, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'groups':
        return _rows(groups, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'enrollments':
        return _rows(enrollments, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'sessions':
        return _rows(sessions, (e) => e.toCloud(), (e) => e.syncStatus);
      default:
        return extraCloud[table] ?? [];
    }
  }

  @override
  void putRows(String table, List<Map<String, dynamic>> rows) {
    markDirty(table);
    // الصف الذي حالته `synced` يمثّل ما في السحابة، سواء وصل منها أو من القرص
    for (final r in rows) {
      final id = '${r['id'] ?? ''}';
      if (id.isEmpty) continue;
      final status = '${r['sync_status'] ?? 'synced'}';
      if (status == 'synced') _rememberSynced(table, id, r);
    }
    // جدول الحضور السحابي لا يحمل عمود تاريخ؛ اليوم المرصود في الجلسة المرتبطة
    if (table == 'attendance') rows = _withSessionDates(rows);
    void upsertList<T>(List<T> list, T Function(Map<String, dynamic>) parse, String Function(T) idOf, void Function(int, T) setAt, void Function(T) add) {
      for (final r in rows) {
        final item = parse(r);
        final i = list.indexWhere((e) => idOf(e) == idOf(item));
        if (i >= 0) {
          setAt(i, item);
        } else {
          add(item);
        }
      }
    }

    switch (table) {
      case 'students':
        upsertList(students, Student.fromCloud, (e) => e.id, (i, e) => students[i] = e, students.add);
      case 'student_attachments':
        for (final r in rows) {
          final a = StudentAttachments.fromCloud(r);
          attachmentsByStudent[a.id] = a;
        }
      case 'teachers':
        upsertList(teachers, Teacher.fromCloud, (e) => e.id, (i, e) => teachers[i] = e, teachers.add);
      case 'subjects':
        upsertList(subjects, SubjectItem.fromCloud, (e) => e.id, (i, e) => subjects[i] = e, subjects.add);
      case 'rooms':
        upsertList(rooms, Classroom.fromCloud, (e) => e.id, (i, e) => rooms[i] = e, rooms.add);
      case 'grade_fees':
        upsertList(gradeFees, GradeFee.fromCloud, (e) => e.id, (i, e) => gradeFees[i] = e, gradeFees.add);
      case 'users':
        upsertList(users, AppUser.fromCloud, (e) => e.id, (i, e) => users[i] = e, users.add);
      case 'payments':
        upsertList(payments, Payment.fromCloud, (e) => e.id, (i, e) => payments[i] = e, payments.add);
      case 'installments':
        upsertList(installments, Installment.fromCloud, (e) => e.id, (i, e) => installments[i] = e, installments.add);
      case 'attendance':
        upsertList(attendance, AttendanceMark.fromCloud, (e) => e.id, (i, e) => attendance[i] = e, attendance.add);
      case 'groups':
        upsertList(groups, Group.fromCloud, (e) => e.id, (i, e) => groups[i] = e, groups.add);
      case 'enrollments':
        upsertList(enrollments, StudentEnrollment.fromCloud, (e) => e.id, (i, e) => enrollments[i] = e, enrollments.add);
      case 'sessions':
        upsertList(sessions, ClassSession.fromCloud, (e) => e.id, (i, e) => sessions[i] = e, sessions.add);
      default:
        final bucket = extraCloud.putIfAbsent(table, () => []);
        for (final r in rows) {
          final i = bucket.indexWhere((e) => '${e['id']}' == '${r['id']}');
          if (i >= 0) {
            bucket[i] = r;
          } else {
            bucket.add(r);
          }
        }
    }
  }

  /// إلحاق تاريخ الجلسة بكل سجل حضور قادم من السحابة.
  List<Map<String, dynamic>> _withSessionDates(List<Map<String, dynamic>> rows) {
    final byId = {for (final s in sessions) s.id: s.sessionDate};
    return [
      for (final r in rows)
        if ('${r['session_date'] ?? ''}'.isNotEmpty) r
        else if (byId['${r['session_id'] ?? ''}'] case final d?) {...r, 'session_date': d}
        else r,
    ];
  }

  @override
  void removeIds(String table, List<String> ids) {
    markDirty(table);
    forgetServerStamps(table, ids);
    final set = ids.toSet();
    switch (table) {
      case 'students':
        students.removeWhere((e) => set.contains(e.id));
      case 'student_attachments':
        attachmentsByStudent.removeWhere((k, _) => set.contains(k));
      case 'teachers':
        teachers.removeWhere((e) => set.contains(e.id));
      case 'subjects':
        subjects.removeWhere((e) => set.contains(e.id));
      case 'rooms':
        rooms.removeWhere((e) => set.contains(e.id));
      case 'grade_fees':
        gradeFees.removeWhere((e) => set.contains(e.id));
      case 'users':
        users.removeWhere((e) => set.contains(e.id));
      case 'payments':
        payments.removeWhere((e) => set.contains(e.id));
      case 'installments':
        installments.removeWhere((e) => set.contains(e.id));
      case 'attendance':
        attendance.removeWhere((e) => set.contains(e.id));
      case 'groups':
        groups.removeWhere((e) => set.contains(e.id));
      case 'enrollments':
        enrollments.removeWhere((e) => set.contains(e.id));
      case 'sessions':
        sessions.removeWhere((e) => set.contains(e.id));
      default:
        extraCloud[table]?.removeWhere((e) => set.contains('${e['id']}'));
    }
  }

  @override
  void markSynced(String table, String id) {
    markDirty(table);
    markDirty(_pendingTable);
    _rememberSynced(table, id, recordOf(table, id));
    void stamp(dynamic rec) {
      try {
        rec.syncStatus = 'synced';
      } catch (_) {}
    }

    switch (table) {
      case 'students':
        stamp(studentById(id));
      case 'student_attachments':
        stamp(attachmentsByStudent[id]);
      case 'teachers':
        stamp(teacherById(id));
      case 'subjects':
        stamp(subjects.where((e) => e.id == id).firstOrNull);
      case 'rooms':
        stamp(rooms.where((e) => e.id == id).firstOrNull);
      case 'grade_fees':
        stamp(gradeFees.where((e) => e.id == id).firstOrNull);
      case 'users':
        stamp(users.where((e) => e.id == id).firstOrNull);
      case 'payments':
        stamp(payments.where((e) => e.id == id).firstOrNull);
      case 'installments':
        stamp(installments.where((e) => e.id == id).firstOrNull);
      case 'attendance':
        stamp(attendance.where((e) => e.id == id).firstOrNull);
      case 'groups':
        stamp(groups.where((e) => e.id == id).firstOrNull);
      case 'enrollments':
        stamp(enrollments.where((e) => e.id == id).firstOrNull);
      case 'sessions':
        stamp(sessions.where((e) => e.id == id).firstOrNull);
    }
  }

  @override
  void notifySync() => notifyListeners();

  @override
  Future<void> onPulled() => hydrateInstitution();
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope missing');
    return scope!.notifier!;
  }
}
