import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';
import 'academic_matching.dart';
import 'app_settings.dart';
import 'balance.dart';
import 'fee_plan.dart';
import 'grade_plan_sync.dart';
import 'grading.dart';
import 'institution.dart';
import 'local_db.dart';
import 'monthly_averages.dart';
import 'payment_methods.dart';
import 'permissions.dart';
import 'portal.dart';
import 'system_features.dart';
import 'phone.dart';
import 'realtime.dart';
import 'supabase.dart';
import 'sync.dart';
import 'tenant_service.dart';
import 'year_structure_clone.dart';

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

  /// جداول محمّلة في الذاكرة — الباقي يُجلب عند فتح الشاشة عبر [ensureTables].
  final loadedTables = <String>{};

  /// نواة الإقلاع: ما يكفي لتسجيل الدخول والهيكل (طلاب/صفوف) بلا حضور ومالية.
  static const bootstrapCoreTables = <String>[
    _stampsTable,
    _pendingTable,
    'tenants',
    'users',
    'academic_years',
    'institution_settings',
    'subjects',
    'rooms',
    'teachers',
    'grade_fees',
    'groups',
    'students',
    'student_years',
    'enrollments',
  ];

  /// جداول ثقيلة تُؤجَّل حتى تطلبها الشاشة أو يطبّقها السحب وهي محمّلة.
  static const deferredTables = <String>{
    'attendance',
    'sessions',
    'payments',
    'installments',
    'student_attachments',
    'finance_attachments',
    'teacher_payouts',
    'expenses',
    'audit_log',
    'finance_requests',
    'student_evaluations',
    'class_announcements',
  };

  bool tablesReady(Iterable<String> tables) => tables.every(loadedTables.contains);

  final _ensureInFlight = <String, Future<void>>{};

  /// تسلسل تحميل القرص: استعلامات متزامنة على SQLite كانت تفشل أحياناً عند فتح عدة بوابات.
  Future<void> _diskLoadTail = Future<void>.value();

  /// تحميل جداول من القرص إلى الذاكرة عند أول حاجة — مع لودنغ الشاشة.
  Future<void> ensureTables(Iterable<String> tables) async {
    final missing = [
      for (final t in tables)
        if (t.isNotEmpty && !loadedTables.contains(t)) t,
    ];
    if (missing.isEmpty) return;

    final waiters = <Future<void>>[];
    final toFetch = <String>[];
    for (final t in missing) {
      final inflight = _ensureInFlight[t];
      if (inflight != null) {
        waiters.add(inflight);
      } else {
        toFetch.add(t);
      }
    }

    if (toFetch.isNotEmpty) {
      final job = _enqueueDiskLoad(toFetch);
      for (final t in toFetch) {
        _ensureInFlight[t] = job;
      }
      waiters.add(job);
      try {
        await job;
      } finally {
        for (final t in toFetch) {
          _ensureInFlight.remove(t);
        }
      }
    }

    if (waiters.isNotEmpty) await Future.wait(waiters);
  }

  Future<void> _enqueueDiskLoad(List<String> tables) {
    final run = _diskLoadTail.then((_) => _loadTablesFromDisk(tables));
    // لا تُسقط السلسلة إن فشل تحميل — التالي ينتظر اكتماله فقط
    _diskLoadTail = run.catchError((_) {});
    return run;
  }

  Future<void> _loadTablesFromDisk(List<String> tables) async {
    final data = await db.loadTables(tables);
    _loading = true;
    try {
      for (final table in tables) {
        try {
          final rows = data[table] ?? const <Map<String, dynamic>>[];
          if (table == _stampsTable) {
            for (final row in rows) {
              final parts = '${row['id'] ?? ''}'.split('|');
              if (parts.length != 2) continue;
              serverStamps.putIfAbsent(parts[0], () => {})[parts[1]] = '${row['stamp'] ?? ''}';
            }
          } else if (table == _pendingTable) {
            pendingSyncs
              ..clear()
              ..addAll(rows.map(PendingSync.fromJson));
          } else if (table == 'tenants') {
            tenants
              ..clear()
              ..addAll(rows.map(Tenant.fromCloud));
          } else if (rows.isEmpty) {
            // لا شيء
          } else {
            // دفعات صغيرة + إفساح: جدول حضور كبير كان يوقف دوران أزرار التحميل ثوانٍ
            await prepareApply(table);
            const chunk = 100;
            for (var i = 0; i < rows.length; i += chunk) {
              final end = i + chunk > rows.length ? rows.length : i + chunk;
              putRows(table, rows.sublist(i, end));
              await Future<void>.delayed(Duration.zero);
            }
          }
          loadedTables.add(table);
        } catch (e, st) {
          // جدول فاسد لا يمنع فتح الشاشة — نُعلّمه محمّلاً بما تيسّر
          debugPrint('ensureTables($table): $e\n$st');
          loadedTables.add(table);
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _loading = false;
    }
    if (tables.any((t) => t == 'payments' || t == 'installments') &&
        tablesReady(const ['payments', 'installments'])) {
      await recalculateAllBalancesYielding();
    }
    notifyListeners();
  }

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
  final academicYears = <AcademicYear>[];
  final studentYears = <StudentYear>[];
  final financeRequests = <FinanceRequest>[];
  final financeAudit = <FinanceAuditEntry>[];

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

  /// أثناء تطبيق سحب السحابة: لا تُجدول كتابة قرص لكل دفعة، ولا تُعاد رسم الواجهة لكل صف.
  bool _applyingPull = false;
  final _pullTouched = <String>{};

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
    'academic_years',
    'student_years',
    'finance_requests',
    'audit_log',
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

  /// ختم لكل جدول على حدة.
  ///
  /// كان ختمٌ واحد يخدم كل الذاكرات المحفوظة، فوصولُ دفعة حضور من المزامنة
  /// يُبطل حساب المستحقات ولا علاقة له به. أثناء المزامنة تصل عشرات الدفعات،
  /// فتُعاد كل حسبة في كل إطار وتتجمّد الشاشة تحت الإصبع.
  final _tableRev = <String, int>{};

  int tableRev(String table) => _tableRev[table] ?? 0;

  /// ختم ذاكرة محفوظة لجدول: عدّاد تعديلاته، وهوية القائمة وطولها.
  ///
  /// العدّاد وحده لا يكفي: التحميل من القرص يستبدل القائمة كلها، ومساراتٌ
  /// تضيف صفاً مباشرةً بلا `markDirty`. الهوية والطول يلتقطان الحالتين.
  int _listStamp(String table, List<Object?> list) =>
      Object.hash(tableRev(table), identityHashCode(list), list.length);

  /// ختم فهارس الحضور: جدولا الحضور والجلسات وحدهما.
  ///
  /// كان الختم العام يُسقطها مع أي تعديل — تعديل اسم وليّ أمر، أو دفعة — فيُعاد
  /// بناء فهرس خمسين ألف رصد في الإطار التالي لعملية لا علاقة لها بالحضور.
  int get _studentsStamp =>
      Object.hash(_listStamp('students', students), _listStamp('student_years', studentYears));

  int get _markStamp =>
      Object.hash(_listStamp('attendance', attendance), _listStamp('sessions', sessions));

  void _touchTable(String table) {
    _rev++;
    _tableRev[table] = (_tableRev[table] ?? 0) + 1;
  }

  /// أي إخطار للشاشات يعني أن شيئاً تغيّر، فتسقط الفهارس والنتائج المحفوظة.
  /// ربطها بالإخطار وحده يمنع نسيان إبطالها في أي مسار تعديل جديد.
  @override
  void notifyListeners() {
    _rev++;
    super.notifyListeners();
  }

  ({Map<String, double> due, Map<String, double> scheduled})? _bucketsCache;
  int _bucketsRev = -1;

  /// أقساط كل طالب مفصولةً: ما حلّ وما بقي مجدولاً — محسوبة مرة لكل تغيّر.
  ///
  /// كانت تُحسب داخل `build` فتمرّ على كل أقساط المدرسة مع كل إعادة بناء. ضغطة
  /// «عرض المزيد» لا تغيّر بيانات، ومع ذلك كانت تُعيد المرور على آلاف السجلات
  /// وتبني خريطتين من جديد، فتتجمّد الشاشة تحت الإصبع.
  ({Map<String, double> due, Map<String, double> scheduled}) get installmentBuckets {
    // الأقساط وحدها تُبطلها: دفعة حضور من المزامنة لا شأن لها بها
    final stamp = _listStamp('installments', installments);
    if (_bucketsCache == null || _bucketsRev != stamp) {
      _bucketsCache = installmentBucketsByStudent(installments);
      _bucketsRev = stamp;
    }
    return _bucketsCache!;
  }

  /// ترقيع الفهارس بعد تعديل سجلٍّ واحد بدل بنائها من جديد.
  ///
  /// كان كل إخطار يُبطل الفهارس، فلمسةُ حضورٍ واحدة تُعيد المرور على عشرات
  /// آلاف الأرصدة والجلسات. الفهارس هنا تُرقَّع مكانها، فتبقى صالحة بلا مسح.
  /// تُستعمل مع التعديلات المفردة وحدها؛ أي تغيير جملة يترك الإبطال يعمل.
  /// [wasValid] تُلتقط **قبل** التعديل: الإخطار يبطل الفهارس، فلو سُئلنا بعده
  /// لوجدناها باطلة دائماً ولما رُقّعت أبداً.
  void _keepIndexes(bool wasValid, void Function() patch) {
    if (!wasValid) return; // لم تكن مبنية أصلاً: تُبنى عند أول قراءة
    patch();
    _indexRev = _markStamp;
  }

  /// إدخال رصدٍ في فهارسه بمفاتيحه الثلاثة.
  void _indexMark(AttendanceMark a) {
    _markAny[looseKey(a.studentId, a.date)] = a;
    final owners = a.sessionId.isEmpty ? null : _sessionOwners[a.sessionId];
    if (owners == null || owners.isEmpty) {
      _markLoose[looseKey(a.studentId, a.date)] = a;
      return;
    }
    _markLoose.remove(looseKey(a.studentId, a.date));
    for (final owner in owners) {
      _markOwned[ownedKey(owner, a.studentId, a.date)] = a;
    }
  }

  /// إخراج رصدٍ من فهارسه — يُستدعى عند حذفه.
  void _unindexMark(AttendanceMark a) {
    _markAny.remove(looseKey(a.studentId, a.date));
    _markLoose.remove(looseKey(a.studentId, a.date));
    final owners = a.sessionId.isEmpty ? null : _sessionOwners[a.sessionId];
    for (final owner in owners ?? const <String>{}) {
      _markOwned.remove(ownedKey(owner, a.studentId, a.date));
    }
  }

  /// إدخال جلسة في فهرسها — لازمٌ قبل فهرسة أرصدتها.
  void _indexSession(ClassSession sess) {
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

  int _studentIndexRev = -1;

  /// فهرس الطلاب وحده — يتبع جدول الطلاب لا كل تغيّر في المخزن.
  ///
  /// كان بناؤه ملتصقاً ببناء فهارس الحضور، فوصولُ دفعة طلاب من المزامنة يُعيد
  /// المرور على خمسين ألف رصدٍ لا علاقة لها بها.
  void _rebuildStudentIndex() {
    final stamp = _listStamp('students', students);
    if (_studentIndexRev == stamp) return;
    _studentIndexRev = stamp;
    _studentIndex
      ..clear()
      ..addEntries(students.map((s) => MapEntry(s.id, s)));
  }

  void _rebuildIndexes() {
    _rebuildStudentIndex();
    if (_indexRev == _markStamp) return;
    _indexRev = _markStamp;

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
    _touchTable(table);
    if (_loading) return;
    if (_applyingPull) {
      _pullTouched.add(table);
      return;
    }
    _dirty.add(table);
    _scheduleFlush();
    // كل عملية تدخل طابور الرفع تُرفع تلقائياً، من أي مسار جاءت. مسارات كثيرة
    // (الدفعة، رصد الكل حاضراً، رموز البوابة، الترحيلات) تكتب في الطابور مباشرةً
    // فكانت تنتظر تعديلاً لاحقاً يمرّ على `_queue` كي تُرفع
    if (table == _pendingTable) _onQueueChanged();
  }

  /// تعليم سجل واحد للكتابة بدل الجدول كله.
  void markRecord(String table, String id, {bool deleted = false}) {
    _touchTable(table);
    if (_loading) return;
    if (_applyingPull) {
      _pullTouched.add(table);
      return;
    }
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
  ///
  /// البصمة عددٌ لا نصّ: كانت `jsonEncode` للصف كله مع ترتيب مفاتيحه، تُحسب لكل
  /// صفّ يصل من السحابة — عشرات آلاف الترميزات على خيط الواجهة في السحب الأول،
  /// وعشرات الميغابايتات من النصوص محفوظةً في الذاكرة.
  final _syncedPrint = <String, int>{};

  /// الحقول المتغيّرة دائماً لا تدخل البصمة، وإلا لاختلفت من غير سبب.
  static const _volatile = {'updated_at', 'created_at', 'sync_status', 'synced_at', 'tenant_id'};

  /// بصمة FNV-1a بـ 32 بتّاً على المفاتيح مرتبةً وقيمها، بلا بناء نصّ JSON.
  ///
  /// 32 بت كافٍ للمقارنة المحلية (نفس السجل قبل/بعد)، ويعمل على الويب حيث
  /// JavaScript لا يمثّل ثوابت 64 بت بدقّة. كل قيمة تُسبق بوسم نوعها.
  int _fingerprint(Map<String, dynamic> row) {
    final keys = row.keys.where((k) => !_volatile.contains(k)).toList()..sort();
    var h = 0x811c9dc5;
    void mix(String text) {
      for (var i = 0; i < text.length; i++) {
        h ^= text.codeUnitAt(i);
        h = (h * 0x01000193) & 0xffffffff;
      }
      h ^= 0x1f; // فاصل بين الأجزاء
      h = (h * 0x01000193) & 0xffffffff;
    }

    for (final k in keys) {
      final v = row[k];
      mix(k);
      mix(switch (v) {
        null => 'n',
        String() => 's$v',
        int() => 'i$v',
        double() => 'd$v',
        bool() => 'b$v',
        _ => 'o${jsonEncode(v)}',
      });
    }
    return h;
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
    // مهلة أطول قليلاً: تفريغ القرص أثناء دوران زر التحميل كان يوقف المؤشر
    _flushTimer = Timer(const Duration(milliseconds: 700), () {
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
      // بناء الصفوف قد يطول على جداول كبيرة — إفساح قبل وبعد الكتابة
      final rows = await _rowsForPersistYielding(t);
      await db.saveTable(t, rows);
      records.remove(t);
      deletes.remove(t);
      await Future<void>.delayed(Duration.zero);
    }
    for (final entry in deletes.entries) {
      await db.deleteRecords(entry.key, entry.value.toList());
      await Future<void>.delayed(Duration.zero);
    }
    for (final entry in records.entries) {
      final rows = await _rowsForPersistYielding(entry.key, only: entry.value);
      await db.saveRecords(entry.key, rows);
      await Future<void>.delayed(Duration.zero);
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
            ...(pendingSyncs[i]..tenantId = pendingSyncs[i].tenantId.isEmpty ? tid : pendingSyncs[i].tenantId).toJson(),
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

  /// كـ [_rowsForPersist] مع إفساح كل بضع مئات صفوف كي لا يتوقف مؤشر الزر.
  Future<List<Map<String, dynamic>>> _rowsForPersistYielding(String table, {Set<String>? only}) async {
    if (only != null && only.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      var n = 0;
      for (final id in only) {
        final row = recordOf(table, id);
        if (row != null) out.add(row);
        if (++n % 200 == 0) await Future<void>.delayed(Duration.zero);
      }
      return out;
    }
    if (table == _stampsTable || table == _pendingTable || table == 'tenants') {
      return _rowsForPersist(table);
    }
    final entry = _listFor(table);
    if (entry == null) {
      // جداول في extraCloud أو غير مفهرسة
      final all = allOf(table);
      if (all.length < 250) return all;
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < all.length; i++) {
        out.add(all[i]);
        if ((i + 1) % 200 == 0) await Future<void>.delayed(Duration.zero);
      }
      return out;
    }
    final (list, idOf) = entry;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      final row = recordOf(table, idOf(list[i]));
      if (row != null) out.add(row);
      if ((i + 1) % 200 == 0) await Future<void>.delayed(Duration.zero);
    }
    return out;
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
    academicYears.clear();
    studentYears.clear();
    attachmentsByStudent.clear();
    pendingSyncs.clear();
    serverStamps.clear();
    for (final k in extraCloud.keys) {
      extraCloud[k]!.clear();
    }
    await db.wipeData();
    _dirty.clear();
    loadedTables.clear();
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
      loadedTables.add('tenants');
      markDirty('tenants');
      return;
    }
    putRows(table, rows);
  }

  /// تسجيل صف مسترجَع من نسخة للرفع — بلا [putRowsFromBackup] يبقى محلياً ويمحوه السحب.
  void queueBackupSync(String table, String recordId, Map<String, dynamic> payload) {
    _queue(table, recordId, 'UPDATE', payload);
  }

  @override
  void notifySync() => _notifyOrDefer();

  @override
  void beginPullApply() {
    _applyingPull = true;
    _batchNotify = true;
    _pullTouched.clear();
  }

  @override
  Future<void> endPullApply() async {
    _applyingPull = false;
    _batchNotify = false;
    if (_pullTouched.isNotEmpty) {
      _dirty.addAll(_pullTouched);
      _pullTouched.clear();
      _scheduleFlush();
    }
    if (_queuedNotify) {
      _queuedNotify = false;
      notifyListeners();
    }
  }

  @override
  bool hydrateOnPull(String table) =>
      !deferredTables.contains(table) || loadedTables.contains(table);

  @override
  Future<void> persistPullOnly(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await db.saveRecords(table, rows);
  }

  /// تحميل كل ما على القرص إلى الذاكرة، ثم استعادة الجلسة.
  Future<void> bootstrap(Persistence persistence) async {
    db = persistence;
    await db.open();
    _loading = true;
    try {
      // النواة فقط — الحضور والمالية تُحمَّل عند فتح شاشاتها
      final data = await db.loadTables(bootstrapCoreTables);
      for (final table in bootstrapCoreTables) {
        final rows = data[table] ?? const <Map<String, dynamic>>[];
        if (table == _stampsTable) {
          for (final row in rows) {
            final parts = '${row['id'] ?? ''}'.split('|');
            if (parts.length != 2) continue;
            serverStamps.putIfAbsent(parts[0], () => {})[parts[1]] = '${row['stamp'] ?? ''}';
          }
        } else if (table == _pendingTable) {
          pendingSyncs
            ..clear()
            ..addAll(rows.map(PendingSync.fromJson));
        } else if (table == 'tenants') {
          tenants
            ..clear()
            ..addAll(rows.map(Tenant.fromCloud));
        } else if (rows.isNotEmpty || table != 'institution_settings') {
          putRows(table, rows);
        }
        loadedTables.add(table);
        await Future<void>.delayed(Duration.zero);
      }
      // institution_settings قد تكون فارغة — تبقى مُعلَّمة محمّلة
      if (!loadedTables.contains('institution_settings')) {
        loadedTables.add('institution_settings');
      }
      _restoreSession();
      // كل تجديد للتوكن يُحفظ فوراً: السحابة تُدوّر توكن التجديد، والقديم يُرفض
      SupabaseAuth.onSessionChanged = _saveSession;
      SupabaseAuth.onSessionInvalid = _onSessionExpired;
      applyBrandColors();
      // مواءمة افتراضي قديم مع الويب قبل أول سحب للهوية
      if (_isLegacyMobileDefault(institutionColors)) {
        await db.setSetting(institutionColorsKey, null);
        applyBrandColors();
      }
    } finally {
      _loading = false;
    }
    await settleAcademicYears();
    await _resolveSetupGate();
    ready = true;
    notifyListeners();
    // الأرصدة بعد تحميل الأقساط والمدفوعات فقط — لا عند الإقلاع
  }

  // ── الجلسة والإعدادات (المقابل لـ session.ts + currentUser.ts + institution.ts) ──
  static const _kLoggedIn = 'session_logged_in';
  static const _kMasterAdmin = 'is_master_admin';
  static const _kTenantId = 'last_active_tenant_id';
  static const _kDeviceUser = 'device_user_id';
  static const _kReceiptLabel = 'device_receipt_label';
  static const _kLastUsername = 'last_entered_username';
  static const _kLastPortalId = 'last_entered_portal_id';

  /// جلسة البوابة المحفوظة: رقم الهوية ورمز الدخول ومعرّف الحساب المختار —
  /// إغلاق التطبيق لا يُخرج الطالب أو المعلم، كما لا يُخرج الإدارة.
  static const _kPortalSession = 'portal_session';
  static const _kReceiptCounter = 'receipt_counter';
  static const _kDeviceUid = 'device_uid';
  static const _kDeviceCode = 'receipt_device_code';
  static const _kDeviceCodeRegistered = 'receipt_device_code_registered';
  static const _kCustomUser = 'custom_app_username';
  static const _kCustomPass = 'custom_app_password';
  static const _kViewedAcademicYear = 'nun_active_academic_year_id';

  /// حروف لا تلتبس ببعضها ولا بالأرقام (لا I ولا O) — مطابق لـ `CODE_LETTERS`.
  static const _receiptCodeLetters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

  String get _academicYearTenantId => tenantId ?? db.settings[_kDbTenant] ?? db.settings[_kTenantId] ?? 'local';

  String get _viewedAcademicYearKey => _academicYearTenantId == 'local' ? _kViewedAcademicYear : '${_kViewedAcademicYear}_$_academicYearTenantId';

  /// العام المعروض في الواجهة؛ قد يكون أرشيفياً وغير عام التشغيل الحالي.
  String get viewedAcademicYearId {
    final stored = db.settings[_viewedAcademicYearKey];
    if (stored != null && academicYears.any((y) => y.id == stored)) return stored;
    return operationalAcademicYear?.id ?? academicYears.firstOrNull?.id ?? '';
  }

  set viewedAcademicYearId(String id) {
    if (!academicYears.any((y) => y.id == id)) return;
    unawaited(db.setSetting(_viewedAcademicYearKey, id));
    notifyListeners();
  }

  AcademicYear? get viewedAcademicYear => academicYears.where((y) => y.id == viewedAcademicYearId).firstOrNull;

  AcademicYear? get operationalAcademicYear => academicYears.where((y) => y.isCurrent).firstOrNull;

  /// معرّف حتمي: المنشأة وسنة بداية العام.
  String yearIdFor(String label) {
    final match = RegExp(r'(\d{4})\s*/\s*(\d{4})').firstMatch(label);
    final startYear = match == null ? DateTime.now().year : int.parse(match.group(1)!);
    return 'ay_${_academicYearTenantId}_$startYear';
  }

  ({String label, String startsOn, String endsOn}) _defaultYearBounds([String? label]) {
    final raw = (label ?? academicYear()).trim();
    final match = RegExp(r'(\d{4})\s*/\s*(\d{4})').firstMatch(raw);
    final y1 = match == null ? DateTime.now().year : int.parse(match.group(1)!);
    final y2 = match == null ? y1 + 1 : int.parse(match.group(2)!);
    return (label: '$y1 / $y2', startsOn: '$y1-08-01', endsOn: '$y2-07-31');
  }

  AcademicYear _newAcademicYear(({String label, String startsOn, String endsOn}) bounds) {
    final now = _nowIso();
    return AcademicYear(
      id: yearIdFor(bounds.label),
      label: bounds.label,
      startsOn: bounds.startsOn,
      endsOn: bounds.endsOn,
      term1Start: '${bounds.startsOn.substring(0, 4)}-09-01',
      term1End: '${bounds.startsOn.substring(0, 4)}-12-31',
      term2Start: '${bounds.endsOn.substring(0, 4)}-01-01',
      term2End: '${bounds.endsOn.substring(0, 4)}-06-30',
      status: 'open',
      isCurrent: true,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// يضمن وجود عام حالي واحد، ويُبقي الأحدث عند وصول أكثر من عام حالي.
  Future<AcademicYear> ensureCurrentAcademicYear() async {
    final currents = academicYears.where((y) => y.isCurrent).toList()..sort((a, b) => b.startsOn.compareTo(a.startsOn));
    if (currents.isNotEmpty) {
      final keep = currents.first;
      if (currents.length > 1) await setCurrentAcademicYear(keep.id);
      if (!academicYears.any((y) => y.id == db.settings[_viewedAcademicYearKey])) {
        viewedAcademicYearId = keep.id;
      }
      return keep;
    }
    if (academicYears.isNotEmpty) {
      final open = academicYears.where((y) => y.status == 'open').toList()..sort((a, b) => b.startsOn.compareTo(a.startsOn));
      final keep = open.firstOrNull ?? academicYears.first;
      await setCurrentAcademicYear(keep.id);
      return keep;
    }
    final created = _newAcademicYear(_defaultYearBounds());
    academicYears.add(created);
    _queue('academic_years', created.id, 'INSERT', created.toCloud());
    markDirty('academic_years');
    viewedAcademicYearId = created.id;
    return created;
  }

  Future<void> setCurrentAcademicYear(String id) async {
    if (!academicYears.any((y) => y.id == id)) throw StoreException('العام الدراسي غير موجود');
    final now = _nowIso();
    for (final year in academicYears) {
      final current = year.id == id;
      if (year.isCurrent == current && (!current || year.status == 'open')) continue;
      year.isCurrent = current;
      if (current) year.status = 'open';
      year.updatedAt = now;
      year.syncStatus = 'pending';
      _queue('academic_years', year.id, 'UPDATE', year.toCloud());
    }
    viewedAcademicYearId = id;
    markDirty('academic_years');
    notifyListeners();
  }

  /// يثبّت أعوام المنشأة بعد الدخول وبعد كل سحب.
  ///
  /// قبل الدخول لا منشأة، فلا يُنشأ عام: الإقلاع الأول على جهاز فارغ كان يُنشئ
  /// عاماً مؤقتاً `ay_local_…` حالياً، فيبقى هو المعروض بعد السحب الأولي
  /// وتُفلتر به كل الشاشات فتظهر فارغة رغم وصول البيانات. العام المؤقت يُحذف
  /// هنا، وما خُتم به ينتقل إلى العام الحالي للمنشأة.
  Future<void> settleAcademicYears() async {
    if (tenantId == null || isMasterAdmin) return;
    final placeholders = academicYears.where((y) => y.id.startsWith('ay_local_')).map((y) => y.id).toSet();
    if (placeholders.isNotEmpty) {
      academicYears.removeWhere((y) => placeholders.contains(y.id));
      for (final id in placeholders) {
        _queue('academic_years', id, 'DELETE', null);
      }
      markDirty('academic_years');
    }
    final current = await ensureCurrentAcademicYear();
    if (placeholders.isNotEmpty) {
      _moveRowsToYear((id) => placeholders.contains(id), current.id);
      notifyListeners();
    }
  }

  void _backfillUnscopedToYear(String yearId) => _moveRowsToYear((id) => id.isEmpty, yearId);

  void _moveRowsToYear(bool Function(String yearId) matches, String yearId) {
    final now = _nowIso();
    void stamp(String table, Iterable<dynamic> rows, Map<String, dynamic> Function(dynamic) cloud) {
      for (final row in rows.where((e) => matches(e.academicYearId as String))) {
        row.academicYearId = yearId;
        row.updatedAt = now;
        row.syncStatus = 'pending';
        _queue(table, row.id, 'UPDATE', cloud(row));
      }
      markDirty(table);
    }

    stamp('students', students, (e) => e.toCloud());
    stamp('subjects', subjects, (e) => e.toCloud());
    stamp('teachers', teachers, (e) => e.toCloud());
    stamp('rooms', rooms, (e) => e.toCloud());
    stamp('grade_fees', gradeFees, (e) => e.toCloud());
    stamp('groups', groups, (e) => e.toCloud());
    stamp('installments', installments, (e) => e.toCloud());
    stamp('payments', payments, (e) => e.toCloud());
  }

  /// يغلق عام التشغيل ويفتح التالي، ثم ينسخ هيكله من دون الطلاب وسجلاتهم.
  Future<({AcademicYear closed, AcademicYear opened})> closeCurrentAndOpenNext() async {
    final current = await ensureCurrentAcademicYear();
    final match = RegExp(r'(\d{4})\s*/\s*(\d{4})').firstMatch(current.label);
    final start = (match == null ? DateTime.now().year : int.parse(match.group(1)!)) + 1;
    final bounds = _defaultYearBounds('$start / ${start + 1}');
    _backfillUnscopedToYear(current.id);
    current
      ..status = 'closed'
      ..isCurrent = false
      ..syncStatus = 'pending'
      ..updatedAt = _nowIso();
    _queue('academic_years', current.id, 'UPDATE', current.toCloud());
    var opened = academicYears.where((y) => y.label == bounds.label).firstOrNull;
    if (opened == null) {
      opened = _newAcademicYear(bounds);
      academicYears.add(opened);
      _queue('academic_years', opened.id, 'INSERT', opened.toCloud());
    }
    await setCurrentAcademicYear(opened.id);
    final hasStructure = rooms.any((r) => r.academicYearId == opened!.id);
    if (!hasStructure) {
      await cloneYearStructure(this, current.id, opened.id);
    }
    return (closed: current, opened: opened);
  }

  /// تحديث تواريخ العام وفصوله — `AcademicYearsService.update`.
  Future<void> updateAcademicYear(
    String id, {
    String? startsOn,
    String? endsOn,
    String? term1Start,
    String? term1End,
    String? term2Start,
    String? term2End,
  }) async {
    requireSection('settings');
    final year = academicYears.where((y) => y.id == id).firstOrNull;
    if (year == null) throw StoreException('العام الدراسي غير موجود');
    if (startsOn != null && startsOn.isNotEmpty) year.startsOn = startsOn;
    if (endsOn != null && endsOn.isNotEmpty) year.endsOn = endsOn;
    if (term1Start != null) year.term1Start = term1Start;
    if (term1End != null) year.term1End = term1End;
    if (term2Start != null) year.term2Start = term2Start;
    if (term2End != null) year.term2End = term2End;
    year
      ..updatedAt = _nowIso()
      ..syncStatus = 'pending';
    _queue('academic_years', year.id, 'UPDATE', year.toCloud());
    markDirty('academic_years');
    notifyListeners();
  }

  List<T> filterByYear<T>(Iterable<T> rows, {String? yearId, bool includeUnscoped = true}) {
    final wanted = yearId ?? viewedAcademicYearId;
    return rows.where((row) {
      final id = (row as dynamic).academicYearId as String;
      return id == wanted || (includeUnscoped && id.isEmpty);
    }).toList();
  }

  /// طلاب العام المعروض بلقطاتهم — مطابق لـ `StudentsService.forDisplayYear`.
  ///
  /// من سنته الحالية هي العام المعروض يظهر بسجله. ومن أنهى هذا العام وانتقل
  /// يظهر بلقطته (صف/شعبة/حالة) فلا يختفي المُرقّى من السنة المغلقة.
  List<Student>? _studentsYearCache;
  String? _studentsYearCacheId;
  int _studentsYearRev = -1;

  List<Student> get studentsInViewedYear {
    final yearId = viewedAcademicYearId;
    if (_studentsYearCache != null &&
        _studentsYearRev == _studentsStamp &&
        _studentsYearCacheId == yearId) {
      return _studentsYearCache!;
    }
    final snapshotOf = {
      for (final y in studentYears.where((y) => y.academicYearId == yearId)) y.studentId: y,
    };
    final result = <Student>[];
    for (final s in students) {
      if (s.academicYearId.isEmpty || s.academicYearId == yearId) {
        result.add(s);
        continue;
      }
      final snap = snapshotOf[s.id];
      if (snap == null) continue;
      result.add(Student.fromCloud({
        ...s.toCloud(),
        'grade_level': snap.gradeLevel,
        'section': snap.section,
        'status': snap.status,
      }));
    }
    _studentsYearCache = result;
    _studentsYearRev = _studentsStamp;
    _studentsYearCacheId = yearId;
    return result;
  }

  List<Installment>? _instYearCache;
  int _instYearRev = -1;
  String _instYearCacheId = '';

  /// أقساط العام المعروض — محفوظة حتى يتغيّر جدول الأقساط أو العام.
  ///
  /// `filterByYear` يقرأ الحقل بـ`as dynamic`، وهو نداء بطيء في دارت. شاشة
  /// المالية كانت تستدعيه مرتين في كل إعادة حساب، فيمرّ على عشرة آلاف قسط
  /// مرتين — ومع كل دفعة مزامنة يتكرر ذلك في كل إطار.
  List<Installment> get installmentsInViewedYear {
    final stamp = _listStamp('installments', installments);
    final yearId = viewedAcademicYearId;
    if (_instYearCache != null && _instYearRev == stamp && _instYearCacheId == yearId) {
      return _instYearCache!;
    }
    final result = <Installment>[];
    for (final i in installments) {
      if (i.academicYearId.isEmpty || i.academicYearId == yearId) result.add(i);
    }
    _instYearCache = result;
    _instYearRev = stamp;
    _instYearCacheId = yearId;
    return result;
  }
  List<Payment> get paymentsInViewedYear => filterByYear(payments);
  List<Classroom>? _roomsYearCache;
  int _roomsYearRev = -1;
  String _roomsYearCacheId = '';

  /// شعب العام المعروض — محفوظة حتى يتغيّر جدول الشعب أو العام.
  List<Classroom> get roomsInViewedYear {
    final stamp = _listStamp('rooms', rooms);
    final yearId = viewedAcademicYearId;
    if (_roomsYearCache != null && _roomsYearRev == stamp && _roomsYearCacheId == yearId) {
      return _roomsYearCache!;
    }
    final result = <Classroom>[];
    for (final r in rooms) {
      if (r.academicYearId.isEmpty || r.academicYearId == yearId) result.add(r);
    }
    _roomsYearCache = result;
    _roomsYearRev = stamp;
    _roomsYearCacheId = yearId;
    return result;
  }
  List<Teacher> get teachersInViewedYear => filterByYear(teachers);
  List<SubjectItem> get subjectsInViewedYear => filterByYear(subjects);
  List<GradeFee> get gradeFeesInViewedYear => filterByYear(gradeFees);
  List<Group> get groupsInViewedYear => filterByYear(groups);

  /// سجلات المعلم نفسه عبر الأعوام — `linkedTeacherIds` في Finance.tsx.
  ///
  /// بعد إغلاق عام يصير للمعلم نسختان؛ سندات الرواتب موزّعة عليها. الربط
  /// بالهوية، وإلا بالاسم والهاتف معاً.
  Set<String> linkedTeacherIds(String teacherId) {
    final t = teacherById(teacherId);
    if (t == null) return {teacherId};
    final nid = t.nationalId.trim();
    return {
      for (final x in teachers)
        if (x.id == t.id ||
            (nid.isNotEmpty ? x.nationalId.trim() == nid : x.name == t.name && x.phone == t.phone))
          x.id,
    };
  }

  /// إيرادات غير مرتبطة بطالب في العام المعروض — سندات `other_income`.
  List<GeneralIncome> get generalIncomes {
    final out = payments
        .where((p) =>
            p.studentId.isEmpty &&
            isGeneralIncomePurpose(p.purpose) &&
            (p.academicYearId == viewedAcademicYearId || p.academicYearId.isEmpty))
        .map(GeneralIncome.fromPayment)
        .toList();
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  List<FinanceRequest> get pendingFinanceRequests =>
      financeRequests.where((r) => r.status == 'pending').toList()..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

  bool get isFinanceAdmin {
    final me = deviceUser;
    return me == null || (me.isActive && normalizeRole(me.role) == 'admin');
  }

  void _recordFinanceAudit({
    required String action,
    required String summary,
    String studentId = '',
    String studentName = '',
    String entityId = '',
    double? amount,
    String reason = '',
  }) {
    final student = studentId.isEmpty ? null : studentById(studentId);
    final now = _nowIso();
    final row = FinanceAuditEntry(
      id: newId(),
      action: action,
      summary: summary,
      userId: currentUserId,
      userName: deviceUser?.name ?? receiptReceiver,
      studentId: studentId,
      studentName: studentName.trim().isNotEmpty ? studentName.trim() : (student?.fullName ?? ''),
      entityId: entityId,
      amount: amount == null ? null : (amount * 100).round() / 100,
      reason: reason.trim(),
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );
    financeAudit.add(row);
    _queue('audit_log', row.id, 'INSERT', row.toCloud());
  }

  FinanceRequest submitFinanceRequest({
    required String kind,
    required String summary,
    required Map<String, dynamic> payload,
    required String reason,
    String studentId = '',
    String targetId = '',
    double? amount,
  }) {
    if (reason.trim().isEmpty) {
      throw StoreException('اكتب سبب الطلب ليعرفه المدير');
    }
    final duplicate = financeRequests.any((r) => r.status == 'pending' && r.kind == kind && r.targetId == targetId && r.studentId == studentId);
    if (duplicate) {
      throw StoreException('يوجد طلب مماثل بانتظار موافقة المدير');
    }
    final now = _nowIso();
    final row = FinanceRequest(
      id: newId(),
      kind: kind,
      status: 'pending',
      summary: summary,
      studentId: studentId,
      studentName: studentById(studentId)?.fullName ?? '',
      targetId: targetId,
      payload: Map<String, dynamic>.from(payload),
      amount: amount,
      reason: reason.trim(),
      requestedById: currentUserId,
      requestedByName: deviceUser?.name ?? receiptReceiver,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );
    financeRequests.add(row);
    _queue('finance_requests', row.id, 'INSERT', row.toCloud());
    _recordFinanceAudit(action: 'request_submitted', summary: 'طلب مالي: $summary', studentId: studentId, entityId: row.id, amount: amount, reason: reason);
    return row;
  }

  void approveFinanceRequest(String id, {String note = ''}) {
    if (!isFinanceAdmin) {
      throw StoreException('الموافقة على الطلبات للمدير وحده');
    }
    final request = financeRequests.where((r) => r.id == id).firstOrNull;
    if (request == null) throw StoreException('الطلب غير موجود');
    if (request.status != 'pending') {
      throw StoreException('الطلب مُعالج مسبقاً');
    }

    // التنفيذ أولاً: إن فشل يبقى الطلب معلّقاً كما في الويب.
    _executeFinanceRequest(request);

    final now = _nowIso();
    request
      ..status = 'approved'
      ..decidedById = currentUserId
      ..decidedByName = deviceUser?.name ?? receiptReceiver
      ..decidedAt = now
      ..decisionNote = note.trim()
      ..updatedAt = now
      ..syncStatus = 'pending';
    _queue('finance_requests', request.id, 'UPDATE', request.toCloud());
    _recordFinanceAudit(
      action: 'request_approved',
      summary: 'موافقة على طلب ${request.requestedByName}: ${request.summary}',
      studentId: request.studentId,
      entityId: request.id,
      amount: request.amount,
      reason: note,
    );
  }

  void rejectFinanceRequest(String id, String note) {
    if (!isFinanceAdmin) throw StoreException('رفض الطلبات للمدير وحده');
    if (note.trim().isEmpty) throw StoreException('اكتب سبب الرفض');
    final request = financeRequests.where((r) => r.id == id).firstOrNull;
    if (request == null) throw StoreException('الطلب غير موجود');
    if (request.status != 'pending') {
      throw StoreException('الطلب مُعالج مسبقاً');
    }
    final now = _nowIso();
    request
      ..status = 'rejected'
      ..decidedById = currentUserId
      ..decidedByName = deviceUser?.name ?? receiptReceiver
      ..decidedAt = now
      ..decisionNote = note.trim()
      ..updatedAt = now
      ..syncStatus = 'pending';
    _queue('finance_requests', request.id, 'UPDATE', request.toCloud());
    _recordFinanceAudit(
      action: 'request_rejected',
      summary: 'رفض طلب ${request.requestedByName}: ${request.summary}',
      studentId: request.studentId,
      entityId: request.id,
      amount: request.amount,
      reason: note,
    );
  }

  void _executeFinanceRequest(FinanceRequest request) {
    final p = request.payload;
    switch (request.kind) {
      case 'payment_cancel':
        final payment = payments.where((item) => item.id == request.targetId).firstOrNull;
        if (payment == null) throw StoreException('السند غير موجود');
        voidPayment(payment, request.reason);
        return;
      case 'refund':
        refundStudentCredit(
          request.studentId,
          amount: (p['amount'] as num?)?.toDouble() ?? 0,
          method: '${p['payment_method'] ?? 'cash'}',
          reason: request.reason,
        );
        return;
      case 'installment_discount':
        final installment = installments.where((item) => item.id == request.targetId).firstOrNull;
        if (installment == null) throw StoreException('القسط غير موجود');
        final input = p['input'] is Map ? Map<String, dynamic>.from(p['input'] as Map) : p;
        setInstallmentDiscount(
          installment,
          kind: '${input['kind'] ?? 'amount'}',
          amount: (input['amount'] as num?)?.toDouble() ?? 0,
          reason: '${input['reason'] ?? request.reason}',
        );
        return;
      case 'installment_remove':
        final installment = installments.where((item) => item.id == request.targetId).firstOrNull;
        if (installment == null) throw StoreException('القسط غير موجود');
        removeInstallmentAdjustment(installment);
        return;
      case 'student_discount':
        final raw = p['discount'];
        setStudentPlanDiscount(request.studentId, raw is Map ? Map<String, dynamic>.from(raw) : null, reason: request.reason);
        return;
      default:
        throw StoreException('نوع طلب مالي غير معروف');
    }
  }

  // جلسة Supabase Auth: تُحفظ ليبقى الجهاز داخلاً بعد إغلاق التطبيق
  static const _kAuthAccess = 'auth_access_token';
  static const _kAuthRefresh = 'auth_refresh_token';
  static const _kAuthExpiry = 'auth_expires_at';
  static const _kAuthClaims = 'auth_claims';

  /// تهيئة بدأت ولم تكتمل — تُكتب على القرص قبل الجلسة نفسها.
  static const _kSetupPending = 'device_setup_pending';

  /// منشأة البيانات المحفوظة على هذا الجهاز.
  static const _kDbTenant = 'db_tenant_id';

  /// المنشأة التي تخصها الإعدادات المحفوظة — تُكتب مع كل دخول.
  static const _kSettingsTenant = 'settings_tenant_id';

  String? get _settingsTenant => db.settings[_kSettingsTenant];

  String get lastUsername => db.settings[_kLastUsername] ?? '';

  /// آخر رقم هوية أُدخل في دخول البوابة على هذا الجهاز (بلا رمز الدخول).
  String get lastPortalNationalId => db.settings[_kLastPortalId] ?? '';

  Future<void> rememberPortalNationalId(String nationalId) async {
    final id = nationalId.trim();
    if (id.isEmpty) return;
    await db.setSetting(_kLastPortalId, id);
  }

  /// جلسة البوابة المحفوظة على الجهاز، أو `null` إن لم تُحفظ.
  ///
  /// [user] هو الحساب كما وصل آخر مرة. وجوده يسمح بفتح البوابة بلا شبكة: التحقق
  /// يمرّ على دالة السيرفر، فبدونه يبقى المعلم على شاشة الدخول ولو كانت كل
  /// بيانات صفوفه محفوظة على جهازه.
  ({String nationalId, String code, String userId, PortalUser? user})? get portalSession {
    final raw = db.settings[_kPortalSession];
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final id = '${map['national_id'] ?? ''}'.trim();
      final code = '${map['code'] ?? ''}'.trim();
      if (id.isEmpty || code.isEmpty) return null;
      final userRaw = map['user'];
      return (
        nationalId: id,
        code: code,
        userId: '${map['user_id'] ?? ''}',
        user: userRaw is Map ? PortalUser.fromJson(Map<String, dynamic>.from(userRaw)) : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePortalSession({
    required String nationalId,
    required String code,
    required String userId,
    PortalUser? user,
  }) async {
    await db.setSetting(
      _kPortalSession,
      jsonEncode({
        'national_id': nationalId.trim(),
        'code': code.trim(),
        'user_id': userId,
        if (user != null) 'user': user.toJson(),
      }),
    );
  }

  /// الخروج من البوابة: لا تُفتح من جديد حتى يُدخل الرمز.
  Future<void> clearPortalSession() => db.setSetting(_kPortalSession, '');

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
    final fees = [...gradeFeesInViewedYear]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final names = <String>[];
    for (final f in fees) {
      final name = f.gradeName.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  String get institutionLogo => db.settings[institutionLogoKey] ?? '';

  /// الختم الرسمي: يُحفظ في سجل الهوية المتزامن فيصل كل أجهزة المدرسة، لا على
  /// جهاز من رفعه وحده.
  String get institutionStamp => db.settings[institutionStampKey] ?? '';

  Future<void> saveInstitutionStamp(String stamp) async {
    requireSection('settings');
    await db.setSetting(institutionStampKey, stamp.isEmpty ? null : stamp);
    await _syncInstitutionSetting('__official_stamp', stamp.isEmpty ? null : stamp);
    notifyListeners();
  }

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

  /// افتراضي الجوال القديم (كحلي/برتقالي) قبل مواءمته مع الويب — إن وُجد وحده
  /// بلا ضبط صريح من السحابة يبقى الجهاز برتقالياً والويب أزرق.
  static bool _isLegacyMobileDefault(InstitutionColors c) =>
      c.sidebarBg.toUpperCase() == '#0B2545' &&
      c.activeItem.toUpperCase() == '#E88C15' &&
      c.primaryButton.toUpperCase() == '#0B2545' &&
      c.actionButton.toUpperCase() == '#E88C15';

  // ── التقييمات والدرجات (المقابل لـ evaluations.service.ts) ────────────────

  /// كل التقييمات، الأحدث تاريخاً أولاً.
  List<Evaluation> get evaluations {
    final rows = extraCloud['student_evaluations'] ?? const [];
    final out = rows.map(Evaluation.fromCloud).toList();
    out.sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
    return out;
  }

  List<Evaluation> evaluationsOfStudent(String studentId) => evaluations.where((e) => e.studentId == studentId).toList();

  List<Evaluation> evaluationsOfGroup(String groupId) => evaluations.where((e) => e.groupId == groupId).toList();

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
    // تعديل/حذف علامة مرصودة — `userCanEditGrades` على الويب
    if (!canEditGrades) {
      throw StoreException('لا صلاحية لك على «${sectionLabel('evaluations.edit')}»');
    }
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
    String payoutType = 'salary',
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
      payoutType: payoutType,
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
  Future<void> saveFeatures({bool? enableExpenses, bool? enableEvaluations, bool? enableStudentPortal, bool? enableStudentAttachments}) async {
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

  // ── إعدادات المنشأة المشتركة (المقابل لـ lib/appSettings.ts) ──────────────

  /// إعدادات المدرسة كما وصلت في عمود `settings`.
  ///
  /// المفاتيح القديمة داخل `colors` تبقى مقروءةً: أجهزةٌ لم تُحدَّث بعد ما زالت
  /// تكتب فيها، وسجلٌّ حُفظ قبل العمود الجديد لا يفقد رسمه ولا رسومه الإضافية.
  AppSettings get settings {
    final stored = AppSettings.fromMap(_storedSettingsMap);
    if (_storedSettingsMap.isNotEmpty) return stored;
    return stored.copyWith(seatFee: _legacySeatFee, feeItems: _legacyFeeItems);
  }

  Map<String, dynamic> get _storedSettingsMap => _decodeMap(db.settings[institutionSettingsKey]);

  /// إعدادات السحابة الآن؛ `null` بلا اتصال أو عند التعذّر (مهلة قصيرة).
  ///
  /// تعديل محلي لم يُرفع بعد أحدث من السحابة — لا تُجلب فوقه.
  Future<Map<String, dynamic>?> _latestCloudSettingsMap() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled || !SupabaseAuth.signedIn) return null;
    if (pendingSyncs.any((p) => p.tableName == 'institution_settings' && p.recordId == tid)) {
      return null;
    }
    try {
      final rows = await supabaseSelect(
        'institution_settings',
        filters: {'id': 'eq.$tid'},
        columns: 'settings',
        limit: 1,
      ).timeout(const Duration(seconds: 3), onTimeout: () => null);
      final settings = rows?.firstOrNull?['settings'];
      return settings is Map ? Map<String, dynamic>.from(settings) : null;
    } catch (_) {
      return null;
    }
  }

  /// كتابة ما تغيّر محلياً فوراً ثم دمج السحابة في الخلفية — استجابة الإدارة
  /// لا تنتظر الشبكة. جهاز يعدّل رسم الحجز وآخر العلامات: الدمج الخلفي يبقي
  /// مفاتيح الآخر، والمفتاح المحلّي يبقى هو الأحدث عند التعارض.
  Future<void> _writeSettings(AppSettings Function(AppSettings prev) update) async {
    final localMap = _storedSettingsMap;
    final prev = AppSettings.fromMap(localMap);
    final next = update(prev);
    final nextMap = next.toMap();
    final prevByYear = prev.gradingByYear;
    final nextByYear = next.gradingByYear;
    final byYear = <String, dynamic>{
      for (final e in prevByYear.entries) e.key: e.value.toMap(),
      for (final e in nextByYear.entries) e.key: e.value.toMap(),
    };
    final mergedMap = <String, dynamic>{
      ...prev.toMap(),
      ...nextMap,
      if (byYear.isNotEmpty) 'grading_by_year': byYear,
    };
    final merged = AppSettings.fromMap(mergedMap);
    await db.setSetting(institutionSettingsKey, jsonEncode(merged.toMap()));
    _persistInstitutionRow();
    notifyListeners();
    unawaited(_mergeCloudSettingsInBackground());
  }

  /// دمج مفاتيح سحابية لم تُمسّ محلياً — بلا حجب الواجهة.
  Future<void> _mergeCloudSettingsInBackground() async {
    final cloud = await _latestCloudSettingsMap();
    if (cloud == null || cloud.isEmpty) return;
    final local = _storedSettingsMap;
    final merged = <String, dynamic>{...cloud, ...local};
    if (jsonEncode(merged) == jsonEncode(local)) return;
    await db.setSetting(institutionSettingsKey, jsonEncode(AppSettings.fromMap(merged).toMap()));
    _persistInstitutionRow();
    notifyListeners();
  }

  /// رسم حجز المقعد. قيمته الافتراضية 0 حتى تعتمد الإدارة رقماً صراحةً —
  /// تثبيته بـ 50 في الكود قاعدة عمل مخترعة.
  double get seatReservationFee => settings.seatFee;

  /// هل يُقتطع رسم الحجز من أول الأقساط، أم يبقى مطالبةً مستقلة فوقها؟
  bool get deductsSeatFee => settings.deductsSeatFee;

  double get _legacySeatFee {
    final local = db.settings[seatReservationFeeKey];
    final raw = local == null || local.isEmpty ? '${_storedColorsMap[seatFeeColorKey] ?? ''}' : local;
    final n = double.tryParse(raw);
    return n == null || n < 0 ? 0 : n;
  }

  Future<void> setSeatReservationFee(double value, {bool? deduct}) async {
    final fee = value < 0 ? 0.0 : value;
    await _writeSettings(
      (prev) => prev.copyWith(
        seatFee: fee,
        seatFeeMode: deduct == null ? null : (deduct ? seatFeeModeDeduct : seatFeeModeSeparate),
      ),
    );
  }

  /// مفاتيح إعدادات المنشأة داخل كائن الألوان المتزامن — مطابقة للنسخة المكتبية.
  static const seatFeeColorKey = '__seat_reservation_fee';

  /// كتابة إعداد منشأة داخل الكائن المتزامن — المقابل لـ `syncInstitutionSetting`.
  Future<void> _syncInstitutionSetting(String key, Object? value) async {
    await db.setSetting(institutionColorsKey, jsonEncode({..._storedColorsMap, key: value}));
    _persistInstitutionRow();
  }

  /// عنوان قسط رسم الحجز — معرّف في `balance.dart` مع ترتيب السداد الذي يقدّمه.
  static const seatInstallmentTitle = seatTitle;

  // ── خطط أقساط المراحل (المقابل لـ students.service.ts) ────────────────────

  /// خطة كل مرحلة مفهرسة باسمها — `loadGradePlans`.
  Map<String, GradeFee> gradePlans() {
    final map = <String, GradeFee>{};
    final yearId = operationalAcademicYear?.id ?? viewedAcademicYearId;
    final scoped = gradeFees.where((f) => f.academicYearId == yearId);
    final source = scoped.isNotEmpty ? scoped : gradeFees.where((f) => f.academicYearId.isEmpty);
    for (final f in source) {
      map.putIfAbsent(f.gradeName.trim().toLowerCase(), () => f);
    }
    return map;
  }

  /// خطة مرحلة الطالب، أو `null` حين لا مرحلة له ولا خطة لها.
  GradeFee? planForStudent(Student student, [Map<String, GradeFee>? plans]) => (plans ?? gradePlans())[student.gradeLevel.trim().toLowerCase()];

  /// بنود خطة المرحلة؛ فارغة حين لم تُضبط بعد.
  List<PlanItem> planItemsOf(GradeFee? grade) => grade?.planItems ?? const [];

  /// عدد الطلاب النشطين بلا خطة لمرحلتهم — تحذير في شاشة المراحل.
  int get studentsMissingPlan {
    final plans = gradePlans();
    return students.where((s) => s.status == 'active' && planItemsOf(planForStudent(s, plans)).isEmpty).length;
  }

  /// أقساط الطالب من خطة مرحلته، مع خصمه ورسم الحجز — `buildStudentPlan`.
  List<Installment> _studentPlanInstallments(
    Student student, {
    required List<PlanItem> items,
    PlanDiscount? discount,
    EnrollmentPlanMode enrollmentMode = EnrollmentPlanMode.full,
    bool customIds = false,
  }) {
    final rows = buildStudentPlan(
      items,
      student.id,
      seatFee: seatReservationFee,
      deductSeat: deductsSeatFee,
      discount: discount,
      enrollmentDate: isoDate(student.enrollmentDate),
      enrollmentMode: enrollmentMode,
      customIds: customIds,
    );
    final yearId = operationalAcademicYear?.id ?? viewedAcademicYearId;
    return toInstallments(rows, student.id, _nowIso(), academicYearId: yearId);
  }

  /// تطبيق خطة المرحلة على طلابها النشطين ممن لا أقساط لهم بعد — `applyGradePlan`.
  ///
  /// يمر عبر المزامنة الموحّدة (`syncGradePlan`) ويُرجع عدد من بُنيت لهم الخطة.
  ({int applied, int skipped}) applyGradePlan(String gradeName) {
    final result = syncGradePlan(gradeName, apply: true);
    return (applied: result.build.students, skipped: result.considered - result.build.students + result.skipped.customPlan + result.skipped.manualInstallments);
  }

  /// تحديث أقساط طلاب المرحلة على أسعار خطتها الجديدة — `repriceGradePlan`.
  ///
  /// يمر عبر المزامنة الموحّدة بوضع التسعير فقط (لا بناء ولا تكميل ولا حذف).
  ({int students, int installments, double difference}) repriceGradePlan(String gradeName, {bool apply = false}) {
    final result = syncGradePlan(gradeName, apply: apply, repriceOnly: true);
    return (students: result.reprice.students, installments: result.reprice.installments, difference: result.reprice.difference);
  }

  /// مزامنة خطة المرحلة الموحّدة — `GradePlanSync.run`.
  GradePlanSyncResult syncGradePlan(
    String gradeName, {
    bool apply = false,
    Set<String>? studentIds,
    bool includePaid = false,
    bool removePaid = false,
    bool resetUnexplained = false,
    bool repriceOnly = false,
    bool discountChange = false,
  }) => GradePlanSync.run(
    this,
    gradeName,
    opts: GradePlanSyncOptions(
      apply: apply,
      studentIds: studentIds,
      includePaid: includePaid,
      removePaid: removePaid,
      resetUnexplained: resetUnexplained,
      repriceOnly: repriceOnly,
      discountChange: discountChange,
    ),
  );

  /// المتوقع على الطلاب النشطين لباقي السنة — `projectRemainingYear`.
  ///
  /// أقساطهم التي لم يحن موعدها، ناقصاً ما دفعوه مقدماً. رقمٌ للإدارة وحدها:
  /// لا يُطالَب به قبل موعده، ولذلك لا يدخل في «المستحق».
  String? _projectRemainingStamp;
  double? _projectRemainingCached;

  double projectRemainingYear({DateTime? today}) {
    final day = today ?? DateTime.now();
    final stamp =
        '$viewedAcademicYearId|${day.year}-${day.month}-${day.day}|${installments.length}|${students.length}';
    if (_projectRemainingStamp == stamp && _projectRemainingCached != null) {
      return _projectRemainingCached!;
    }

    var total = 0.0;
    for (final student in students.where((s) => s.status == 'active')) {
      var scheduled = 0.0;
      for (final i in installments.where((i) => i.studentId == student.id)) {
        if (!isInstallmentDue(i, day)) scheduled += math.max(0.0, i.remaining);
      }
      final credit = student.balance > 0 ? student.balance : 0.0;
      final projected = scheduled - credit;
      if (projected > 0) total += projected;
    }
    _projectRemainingStamp = stamp;
    _projectRemainingCached = total;
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
    final list = studentsInViewedYear.where((s) {
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
    final targets = {for (final e in nextGradeOf.entries) e.key.trim().toLowerCase(): e.value};
    var promoted = 0;
    var archived = 0;
    final targetYearId = operationalAcademicYear?.id ?? viewedAcademicYearId;
    final latestClosed = academicYears.where((y) => y.status == 'closed').toList()..sort((a, b) => b.startsOn.compareTo(a.startsOn));
    final viewed = viewedAcademicYearId;
    final sourceYearId = viewed != targetYearId ? viewed : (latestClosed.firstOrNull?.id ?? viewed);
    final movingYear = sourceYearId.isNotEmpty && sourceYearId != targetYearId;
    final now = _nowIso();

    for (final student
        in students.where((s) => s.status == 'active' && (s.academicYearId == sourceYearId || (!movingYear && s.academicYearId.isEmpty))).toList()) {
      final key = student.gradeLevel.trim().toLowerCase();
      if (!targets.containsKey(key)) continue;
      final to = targets[key];

      if (movingYear) {
        final snapshot = StudentYear(
          id: studentYearRecordId(student.id, sourceYearId),
          studentId: student.id,
          academicYearId: sourceYearId,
          gradeLevel: student.gradeLevel,
          section: student.section,
          status: 'completed',
          planDiscountType: student.planDiscountType,
          planDiscountValue: student.planDiscountValue,
          planDiscountReason: student.planDiscountReason,
          syncStatus: 'pending',
          createdAt: now,
          updatedAt: now,
        );
        studentYears.removeWhere((e) => e.id == snapshot.id);
        studentYears.add(snapshot);
        _queue('student_years', snapshot.id, 'INSERT', snapshot.toCloud());
      }

      student.section = '';
      if (to != null && to.trim().isNotEmpty) {
        student.gradeLevel = to.trim();
        student.status = 'pending';
        if (movingYear) {
          student.academicYearId = targetYearId;
          student.usesCustomPlan = false;
          student.planDiscountType = null;
          student.planDiscountValue = 0;
          student.planDiscountReason = '';
          student.planDiscountFrom = '';
          student.academicDiscountApplied = false;
          student.academicDiscountRate = 0;
        }
        promoted++;
      } else {
        student.status = 'archived';
        if (movingYear) student.academicYearId = targetYearId;
        archived++;
      }
      student.updatedAt = now;
      student.syncStatus = 'pending';
      _queue('students', student.id, 'UPDATE', student.toCloud());

      for (final enrollment in enrollments.where((e) => e.studentId == student.id && e.status == 'active')) {
        enrollment.status = 'completed';
        enrollment.updatedAt = now;
        enrollment.syncStatus = 'pending';
        _queue('enrollments', enrollment.id, 'UPDATE', enrollment.toCloud());
      }
    }

    if (promoted + archived > 0) {
      markDirty('students');
      markDirty('student_years');
      markDirty('enrollments');
      notifyListeners();
    }
    return (promoted: promoted, archived: archived);
  }

  /// تأكيد طالب معلّق وبناء خطة عامه إن كانت مرحلته تحمل خطة.
  ({int confirmed, int planBuilt, int withoutPlan, int customPlan}) confirmPendingStudents(Iterable<String> ids) {
    requireSection('students');
    final wanted = ids.toSet();
    final pending = students.where((s) => wanted.contains(s.id) && s.status == 'pending').toList();
    final now = _nowIso();
    for (final student in pending) {
      student.status = 'active';
      student.updatedAt = now;
      student.syncStatus = 'pending';
      _queue('students', student.id, 'UPDATE', student.toCloud());
    }
    if (pending.isNotEmpty) syncStudentRoomEnrollments(pending.map((s) => s.id));

    var built = 0;
    var custom = 0;
    final byGrade = <String, Set<String>>{};
    for (final student in pending) {
      if (student.usesCustomPlan) {
        custom++;
        continue;
      }
      byGrade.putIfAbsent(student.gradeLevel, () => {}).add(student.id);
    }
    for (final entry in byGrade.entries) {
      built += GradePlanSync.run(this, entry.key, opts: GradePlanSyncOptions(apply: true, studentIds: entry.value, checkPermission: false)).build.students;
    }
    if (pending.isNotEmpty) {
      markDirty('students');
      notifyListeners();
    }
    return (confirmed: pending.length, planBuilt: built, withoutPlan: pending.length - built - custom, customPlan: custom);
  }

  ({bool planBuilt}) confirmPendingStudent(String id) {
    if (studentById(id) == null) throw StoreException('الطالب غير موجود');
    final result = confirmPendingStudents([id]);
    return (planBuilt: result.planBuilt > 0);
  }

  /// كائن الألوان كما حُفظ بكل مفاتيحه، ومنها ما لا تعرفه هذه النسخة —
  /// `__custom_payment_methods` مثلاً. الكتابة فوقه بالألوان الخمسة وحدها
  /// كانت تمسح من السحابة إعدادات حفظتها نسخة أخرى في العمود نفسه.
  Map<String, dynamic> get _storedColorsMap => _decodeMap(db.settings[institutionColorsKey]);

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  static List<dynamic>? _decodeList(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is List ? data : null;
    } catch (_) {
      return null;
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
    await db.setSetting(institutionColorsKey, jsonEncode({..._storedColorsMap, customPaymentMethodsColorKey: jsonDecode(encoded)}));
    _persistInstitutionRow();
    notifyListeners();
  }

  /// نظام الرصد من `settings.grading` مع ترحيل المخطط القديم.
  GradingSettings get gradingSettings {
    final fromSettings = settings.grading;
    if (!fromSettings.scheme.isEmpty || fromSettings.mode == 'monthly') return fromSettings;
    final legacy = _legacyGradingScheme;
    if (legacy.isEmpty) return fromSettings;
    return fromSettings.copyWith(scheme: legacy);
  }

  /// نظام العام المعروض: لقطة العام المغلق إن وُجدت، وإلا النظام الحالي.
  ///
  /// مطابق لـ `grading_by_year[year]` في StudentDetail على الويب (EV-03).
  GradingSettings get gradingForViewedYear {
    final year = viewedAcademicYear;
    if (year != null && year.status == 'closed') {
      final snap = settings.gradingByYear[year.id];
      if (snap != null) return snap;
    }
    return gradingSettings;
  }

  /// مرادف لـ [gradingForViewedYear] — أسماء قديمة في الحساب والحفظ.
  GradingSettings get effectiveGradingSettings => gradingForViewedYear;

  /// مخطط علامات المدرسة — مكوّنات كل فصل وأوزانها.
  ///
  /// المصدر: `settings.grading.scheme`، ثم إعداد الجهاز، ثم `__grading_scheme` القديم.
  static const gradingSchemeKey = 'grading_scheme';
  static const gradingSchemeColorKey = '__grading_scheme';

  GradingScheme get _legacyGradingScheme {
    final local = db.settings[gradingSchemeKey];
    if (local != null && local.trim().isNotEmpty) return GradingScheme.decode(local);
    final synced = _storedColorsMap[gradingSchemeColorKey];
    return synced is Map ? GradingScheme.fromMap(Map<String, dynamic>.from(synced)) : GradingScheme.empty;
  }

  GradingScheme get gradingScheme {
    final fromGrading = effectiveGradingSettings.scheme;
    if (!fromGrading.isEmpty) return fromGrading;
    return _legacyGradingScheme;
  }

  Future<void> saveGradingScheme(GradingScheme scheme) async {
    requireSection('settings');
    await db.setSetting(gradingSchemeKey, scheme.isEmpty ? null : scheme.encode());
    await _writeSettings((prev) {
      final base = prev.grading.scheme.isEmpty ? gradingSettings : prev.grading;
      return prev.copyWith(grading: base.copyWith(scheme: scheme));
    });
    // توافق أجهزة قديمة ما زالت تقرأ من colors
    await _syncInstitutionSetting(gradingSchemeColorKey, scheme.toMap());
  }

  Future<void> saveGradingSettings(GradingSettings grading) async {
    requireSection('settings');
    await _writeSettings((prev) => prev.copyWith(grading: grading));
    await db.setSetting(gradingSchemeKey, grading.scheme.isEmpty ? null : grading.scheme.encode());
    await _syncInstitutionSetting(gradingSchemeColorKey, grading.scheme.toMap());
  }

  /// معدل الطالب في فصل لمادة واحدة — لا يخلط مواداً مختلفة.
  TermGrade termGradeOf(String studentId, String term, {String? subjectId, String? gradeLevel}) {
    final evals = evaluationsOfStudent(studentId).where((e) {
      if (subjectId == null) return true;
      return e.subjectId == subjectId;
    });
    final student = studentById(studentId);
    final grade = gradeLevel ?? student?.gradeLevel ?? '';
    final sid = subjectId ?? '';
    final g = effectiveGradingSettings;
    final scheme = sid.isEmpty ? gradingScheme : g.schemeForSubject(grade, sid);
    final fullMark = sid.isEmpty ? defaultFullMark : g.fullMarkForSubject(grade, sid);
    return computeTermGrade(evals, scheme, term, fullMark: fullMark);
  }

  /// علامة النجاح التي ضبطتها المدرسة — 50% ما لم تُغيَّر.
  double get gradingPassPercent => effectiveGradingSettings.passPercent;

  /// هل نجح الطالب في هذا التقييم بعلامة نجاح المدرسة؟ `Evaluation.passed`
  /// يفترض 50% لأنه لا يرى الإعدادات.
  bool evaluationPassed(Evaluation e) => e.percent >= gradingPassPercent;

  /// ملخص علامات لكل مادة — مطابق لـ StudentDetail / StudentPortal على الويب.
  List<SubjectGradeSummary> subjectGradesOf(String studentId) {
    final student = studentById(studentId);
    final grade = student?.gradeLevel ?? '';
    final g = effectiveGradingSettings;
    return subjectGradeSummaries(
      evaluationsOfStudent(studentId),
      g.scheme.isEmpty ? gradingScheme : g.scheme,
      subjectName,
      grading: g,
      gradeLevel: grade,
    );
  }

  /// يحفظ معدلات الشهر: يعدّل الموجود ويضيف الناقص، والخانة الفارغة تحذف معدلها.
  int saveMonthlyAverages(String month, List<({String studentId, double? score})> entries) {
    requireSection('evaluations');
    final now = _nowIso();
    final allRows = monthlyRowsByStudent(evaluations, month);
    final existing = loadMonthlyAverages(evaluations, month);
    final bucket = extraCloud.putIfAbsent('student_evaluations', () => <Map<String, dynamic>>[]);
    var changed = 0;

    for (final entry in entries) {
      final current = existing[entry.studentId];
      final duplicates = (allRows[entry.studentId] ?? []).where((r) => r.id != current?.id);
      for (final dup in duplicates) {
        bucket.removeWhere((e) => '${e['id']}' == dup.id);
        _queue('student_evaluations', dup.id, 'DELETE', null);
      }

      if (entry.score == null) {
        if (current == null) continue;
        bucket.removeWhere((e) => '${e['id']}' == current.id);
        _queue('student_evaluations', current.id, 'DELETE', null);
        changed++;
        continue;
      }

      final score = entry.score!.clamp(0, 100).toDouble();
      if (current != null && current.score == score) continue;

      final record = Evaluation(
        id: current?.id ?? monthlyAverageId(entry.studentId, month),
        studentId: entry.studentId,
        title: 'معدل ${month.length >= 7 ? '${month.substring(5, 7)}/${month.substring(0, 4)}' : month}',
        score: score,
        maxScore: 100,
        evaluationDate: monthDate(month),
        type: 'monthly',
        createdAt: current?.createdAt ?? now,
        updatedAt: now,
        syncStatus: 'pending',
      );
      final row = record.toCloud();
      final idx = bucket.indexWhere((e) => '${e['id']}' == record.id);
      if (idx >= 0) {
        bucket[idx] = row;
        _queue('student_evaluations', record.id, 'UPDATE', row);
      } else {
        bucket.add(row);
        _queue('student_evaluations', record.id, current != null ? 'UPDATE' : 'INSERT', row);
      }
      changed++;
    }

    if (changed > 0) {
      markDirty('student_evaluations');
      notifyListeners();
    }
    return changed;
  }

  /// يقيّد خصم الشهر لمستحقيه على قسطهم القادم — سند خصم بمبلغ صفر.
  ({int applied, int already, int noInstallment}) applyMonthlyRewards(
    String month, {
    List<String>? studentIds,
  }) {
    requireFinanceAction('finance.discount');
    final rules = effectiveGradingSettings.monthlyDiscountRules;
    var applied = 0;
    var already = 0;
    var noInstallment = 0;
    final averages = loadMonthlyAverages(evaluations, month);
    final label = month.length >= 7 ? '${month.substring(5, 7)}/${month.substring(0, 4)}' : month;

    for (final entry in averages.entries) {
      final studentId = entry.key;
      if (studentIds != null && !studentIds.contains(studentId)) continue;
      final percent = rewardPercent(entry.value.score, rules);
      if (percent <= 0) continue;

      final student = studentById(studentId);
      if (student == null || student.status != 'active') continue;
      if (hasReward(payments, studentId, month)) {
        already++;
        continue;
      }

      final open = installments
          .where((i) => i.studentId == studentId && chargeableAmount(i) - i.paidAmount > cent)
          .toList()
        ..sort(compareInstallments);
      final target = open.where((i) => !isInstallmentDue(i)).firstOrNull ?? open.firstOrNull;
      if (target == null) {
        noInstallment++;
        continue;
      }

      final remaining = chargeableAmount(target) - target.paidAmount;
      final discount =
          ((math.min(remaining, (chargeableAmount(target) * percent) / 100) * 100).round() / 100);
      if (discount <= 0) continue;

      addPayment(
        studentId: studentId,
        amount: 0,
        method: 'other',
        date: DateTime.now(),
        purpose: rewardPurpose,
        reference: rewardReference(month),
        installmentId: target.id,
        discountAmount: discount,
        discountReason: 'تفوق $label (${trimNum(entry.value.score)}%)',
        originalAmount: discount,
      );
      applied++;
    }

    return (applied: applied, already: already, noInstallment: noInstallment);
  }

  /// بادئة معرّف قسط الرسم الإضافي — `FEE_ID_PREFIX`.
  static const feeIdPrefix = 'fee_';

  /// معرّف حتمي: الرسم لا يُقيَّد على الطالب مرتين مهما تكرر التطبيق.
  static String feeInstallmentId(String itemId, String studentId) => '$feeIdPrefix${itemId}_$studentId';

  /// الرسوم الإضافية المعتمدة — `getFeeItems`.
  List<FeeItem> get feeItems => settings.feeItems;

  List<FeeItem> get _legacyFeeItems {
    final raw = db.settings[feeItemsKey];
    final list = raw == null || raw.isEmpty ? _storedColorsMap['__fee_items'] : _decodeList(raw);
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) FeeItem.fromMap(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> saveFeeItems(List<FeeItem> items) async {
    requireSection('settings');
    await _writeSettings((prev) => prev.copyWith(feeItems: items));
  }

  /// يجعل الرسم مقيّداً على المستهدفين به بالضبط — `applyFeeItem`.
  ///
  /// الرحلة لا يشترك فيها كل الصف، والكتاب لا يشتريه الجميع: الاستهداف إما طلاب
  /// بأسمائهم ([FeeItem.studentIds]) أو مرحلة كاملة أو الجميع. يُضاف لمن نقصه
  /// ويُرفع عمّن خرج من القائمة — إلا قسطاً دُفع منه شيء أو عليه سند، فالسجل
  /// المالي لا يُمحى.
  ({int added, int removed}) applyFeeItem(FeeItem item) {
    requireSection('settings');
    final now = _nowIso();
    final due = parseIsoDate(item.dueDate) ?? DateTime.now();
    final chosen = item.studentIds;
    var added = 0;
    var removed = 0;

    final targets = students.where((s) {
      if (s.status != 'active') return false;
      if (chosen != null) return chosen.contains(s.id);
      return item.gradeLevel.isEmpty || isSameGrade(s.gradeLevel, item.gradeLevel);
    }).toList();

    for (final student in targets) {
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
      added++;
    }

    // من رُفع عن القائمة: يُحذف قسطه ما لم يكن قد دفع منه شيئاً
    final targetIds = targets.map((s) => s.id).toSet();
    final prefix = '$feeIdPrefix${item.id}_';
    for (final row in installments.where((i) => i.id.startsWith(prefix)).toList()) {
      if (targetIds.contains(row.studentId) || row.paidAmount > 0) continue;
      if (_dropFeeInstallment(row)) removed++;
    }

    if (added + removed > 0) {
      markDirty('installments');
      notifyListeners();
    }
    return (added: added, removed: removed);
  }

  /// يحذف قسط رسم إن لم يكن عليه سند قبض فعّال؛ يعيد هل حُذف.
  bool _dropFeeInstallment(Installment row) {
    // سندٌ مربوط بالقسط: حذفه يترك سنداً يشير إلى لا شيء
    if (payments.any((p) => !p.cancelled && p.installmentId == row.id)) return false;
    installments.remove(row);
    _queue('installments', row.id, 'DELETE', null);
    final student = studentById(row.studentId);
    if (student != null) _persistStudentLedger(student);
    return true;
  }

  /// إزالة الرسم عن الطلاب، إلا من عليه سند مربوط به — `removeFeeItem`.
  /// يعيد عدد من بقي الرسم عليهم.
  int removeFeeItem(String itemId) {
    requireSection('settings');
    final prefix = '$feeIdPrefix${itemId}_';
    final rows = installments.where((i) => i.id.startsWith(prefix)).toList();
    var kept = 0;

    for (final row in rows) {
      if (!_dropFeeInstallment(row)) kept++;
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

  Future<void> saveInstitution({String? name, String? logo, InstitutionColors? colors}) async {
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
    final stored = _storedColorsMap;
    final bucket = extraCloud.putIfAbsent('institution_settings', () => []);
    final i = bucket.indexWhere((e) => '${e['id']}' == tid);
    final existing = i >= 0 ? bucket[i] : null;
    final existingColors = existing?['colors'];
    final existingMap = existingColors is Map ? Map<String, dynamic>.from(existingColors) : <String, dynamic>{};

    final hasLocalPalette = stored.containsKey('sidebarBg') ||
        stored.containsKey('activeItem') ||
        stored.containsKey('actionButton') ||
        stored.containsKey('primaryButton') ||
        stored.containsKey('appBg');
    final hasExistingPalette = existingMap.containsKey('sidebarBg') ||
        existingMap.containsKey('activeItem') ||
        existingMap.containsKey('actionButton') ||
        existingMap.containsKey('primaryButton') ||
        existingMap.containsKey('appBg');

    // ابدأ بألوان الصف القائم (سحابة/قرص) ثم أضِف مفاتيح `__` المحلية.
    // بلا لوحة محلّية حقيقية لا تُحقَن ألوان النظام الافتراضية فوق السحابة —
    // ذلك كان يمحو ثيم المنشأة عند أول دخول للجوال.
    final colorsPayload = <String, dynamic>{
      ...existingMap,
      for (final e in stored.entries)
        if (e.key.startsWith('__')) e.key: e.value,
    };
    if (hasLocalPalette) {
      final local = institutionColors;
      final wouldOverwriteCloud =
          hasExistingPalette && _isSystemDefaultPalette(local) && !_isSystemDefaultPalette(InstitutionColors.fromMap(existingMap));
      if (!wouldOverwriteCloud) {
        colorsPayload.addAll(local.toMap());
        for (final e in stored.entries) {
          if (!e.key.startsWith('__')) colorsPayload[e.key] = e.value;
        }
      }
    }

    final row = {
      'id': tid,
      // النظام مدرسي وحده: يُكتب ثابتاً ولا يُقرأ، لأن أجهزة لم تُحدَّث ما زالت تقرؤه
      'institution_type': 'school',
      'institution_name': institutionName,
      'logo': institutionLogo.isEmpty ? null : institutionLogo,
      'colors': colorsPayload,
      'settings': settings.toMap(),
      'updated_at': _nowIso(),
    };
    if (i >= 0) {
      bucket[i] = row;
      _queue('institution_settings', tid, 'UPDATE', row);
    } else {
      bucket.add(row);
      _queue('institution_settings', tid, 'INSERT', row);
    }
    markDirty('institution_settings');
  }

  /// هل اللوحة هي افتراضي النظام (لا ضبط منشأة)؟
  static bool _isSystemDefaultPalette(InstitutionColors c) {
    final d = InstitutionColors.defaults;
    return c.sidebarBg.toUpperCase() == d.sidebarBg.toUpperCase() &&
        c.activeItem.toUpperCase() == d.activeItem.toUpperCase() &&
        c.primaryButton.toUpperCase() == d.primaryButton.toUpperCase() &&
        c.actionButton.toUpperCase() == d.actionButton.toUpperCase();
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

    // إعدادات المدرسة من عمودها. سجلٌّ لم يكتبه العمود بعد يُترك للمفاتيح
    // القديمة داخل `colors` أدناه، فلا يُصفَّر رسمٌ مضبوط بإعدادات فارغة
    final shared = row['settings'];
    if (shared is Map && shared.isNotEmpty) {
      await db.setSetting(institutionSettingsKey, jsonEncode(Map<String, dynamic>.from(shared)));
    }

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

      if (synced.containsKey('__official_stamp')) {
        final stamp = synced['__official_stamp'];
        await db.setSetting(institutionStampKey, stamp is String && stamp.isNotEmpty ? stamp : null);
      }

      final seatFee = synced[seatFeeColorKey];
      if (seatFee is num) await db.setSetting(seatReservationFeeKey, '${seatFee < 0 ? 0 : seatFee}');

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

  List<StudentEnrollment> enrollmentsOf(String studentId) => enrollments.where((e) => e.studentId == studentId).toList();

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
      queuePendingSync(pendingSyncs, tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
      markRecord('students', s.id);
      made++;
    }
    if (made > 0) {
      markDirty(_pendingTable);
      notifyListeners();
    }
    return made;
  }

  /// توليد كلمة مرور بوابة واحدة فقط — طالب أو ولي أمر، دون المساس بالأخرى.
  void generateStudentPortalCode(String studentId, {required bool forParent}) {
    requireSection('students');
    final s = studentById(studentId);
    if (s == null) throw StoreException('الطالب غير موجود');
    if (forParent) {
      s.parentPortalCode = newDistinctPortalCode(s.portalCode);
    } else {
      s.portalCode = newDistinctPortalCode(s.parentPortalCode);
    }
    s.updatedAt = _nowIso();
    s.syncStatus = 'pending';
    queuePendingSync(pendingSyncs, tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
    markRecord('students', s.id);
    markDirty(_pendingTable);
    notifyListeners();
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
    if (TenantService.hasMasterAccount && u == TenantService.masterUsername.trim().toLowerCase() && p == TenantService.masterPassword.trim()) {
      loggedIn = true;
      isMasterAdmin = true;
      currentTenant = null;
      roleName = 'المطور العام';
      await _saveSession();
      notifyListeners();
      return null;
    }

    final match = tenants.where((t) => t.username.trim().toLowerCase() == u && t.password.trim() == p).firstOrNull;

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
    await migrateOrphanedSections();
    await migrateEnrollmentRooms();
    await migrateWithdrawnStatus();
    dedupeAttendance();
    await mergeDuplicateSchoolSubjectGroups();
    if (!networkEnabled) return;
    // جلسة السحابة يجب أن تطابق المحلية؛ دون اتصال لا يُحكم
    final matches = await authMatchesLocalSession();
    if (matches == false) {
      await logout();
      return;
    }
    // الاستماع أولاً: لا يتوقف على نجاح خطوات الشبكة التي تليه
    await startRealtime();
    // اسحب هوية المنشأة قبل أي كتابة محلية — وإلا رُفعت الألوان الافتراضية فوق السحابة
    await _pullInstitutionIdentity();
    await hydrateInstitution();
    await deviceReceiptCode();
    await primeReceiptCounter();
    // مرفقٌ تعثّر رفعه على جهاز بلا اتصال يُعاد الآن، وإلا بقي على الجهاز وحده
    unawaited(retryPendingAttachments());
    unawaited(flushPendingNotices());
    // الدخول يسحب أولاً ثم يرفع — بلا رفعٍ فوري يسبق السحب
    startAutoSync();
    notifyListeners();
  }

  /// سحب صفّ الهوية وحده قبل المزامنة الكاملة — خفيف وسريع.
  Future<void> _pullInstitutionIdentity() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled) return;
    try {
      final rows = await supabaseSelect(
        'institution_settings',
        filters: {'id': 'eq.$tid'},
      );
      if (rows == null || rows.isEmpty) return;
      final cleaned = [
        for (final r in rows)
          Map<String, dynamic>.from(r)
            ..remove('tenant_id')
            ..['sync_status'] = 'synced',
      ];
      putRows('institution_settings', cleaned);
      // أسقط رفعاً معلّقاً بألوان افتراضية كان سيكتب فوق السحابة
      final pending = pendingSyncs.where((p) => p.tableName == 'institution_settings' && p.recordId == tid).toList();
      for (final p in pending) {
        final colors = p.payload?['colors'];
        if (colors is! Map) continue;
        final local = InstitutionColors.fromMap(Map<String, dynamic>.from(colors));
        if (_isSystemDefaultPalette(local)) {
          pendingSyncs.remove(p);
          markDirty(_pendingTable);
        }
      }
    } catch (_) {
      // بلا شبكة أو رفض: نُكمل بالهوية المحلية إن وُجدت
    }
  }

  /// هل جلسة الدخول السحابية تطابق الجلسة المحلية؟ — `authMatchesLocalSession`.
  ///
  /// `null` = تعذّر الحكم (دون اتصال أو خطأ): لا يُخرَج المستخدم إلا بـ `false`.
  Future<bool?> authMatchesLocalSession() async {
    if (!networkEnabled) return null;
    try {
      await SupabaseAuth.ensureFresh();
      if (!SupabaseAuth.signedIn) return false;
      if (isMasterAdmin) return SupabaseAuth.isDeveloper;
      // المطور يدخل أي منشأة من لوحته
      if (SupabaseAuth.isDeveloper) return true;
      final tid = tenantId;
      if (tid == null || tid.isEmpty) return false;
      return SupabaseAuth.role == 'tenant_admin' && SupabaseAuth.tenantId == tid;
    } catch (_) {
      return null;
    }
  }

  // ── التحديث اللحظي ─────────────────────────────────────────────────────────
  RealtimeListener? _realtime;

  bool get realtimeConnected => _realtime?.isConnected ?? false;

  /// فتح قناة الاستماع لتغييرات السحابة لهذه المنشأة.
  Future<void> startRealtime() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled) return;
    _realtime ??= RealtimeListener(tables: syncedTables, onChange: handleRemoteEvent, onJoined: handleRealtimeJoined, onBroadcast: handlePeerChanged);
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
      _scheduleAfterReconnect();
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
  static const autoPushDelay = Duration(seconds: 1);
  static const autoPullDelay = Duration(milliseconds: 1500);
  static const _resumePullGap = Duration(seconds: 60);

  /// بعد رجوع النت: ارفع سريعاً ما علّق، وأجّل السحب حتى تهدأ الواجهة.
  /// سحبٌ ثقيل فور الاتصال كان يجمّد الشاشة أثناء تسجيل حضور أو حفظ دفعة.
  static const reconnectPushDelay = Duration(milliseconds: 800);
  static const reconnectPullDelay = Duration(seconds: 8);

  bool autoSync = false;
  Timer? _autoPushTimer;
  Timer? _autoPullTimer;
  DateTime? _lastResumePull;
  DateTime? _lastReconnectArm;

  /// محاولات الرفع المتتالية التي تعثّرت بانقطاع — تحدد مهلة المحاولة التالية.
  int _pushFailures = 0;

  /// مهل إعادة الرفع بعد انقطاع: تتباعد ولا تتجاوز الدقيقة، وعودة الاتصال تختصرها.
  static const pushRetryDelays = [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 30), Duration(seconds: 60)];

  static Duration pushRetryDelay(int failures) => pushRetryDelays[(failures - 1).clamp(0, pushRetryDelays.length - 1)];

  /// رفع الطابور سريعاً وسحب مؤجّل — من رجوع النت أو إعادة الاشتراك، مرة واحدة.
  void _scheduleAfterReconnect() {
    final now = DateTime.now();
    // الاشتراك و`_setOffline(false)` يصلان معاً غالباً — لا نُعيد تسليح المؤقتين
    if (_lastReconnectArm != null && now.difference(_lastReconnectArm!) < const Duration(seconds: 2)) {
      return;
    }
    _lastReconnectArm = now;
    _pushFailures = 0;
    if (pendingSyncs.any((a) => a.retryCount < maxSyncRetries)) {
      scheduleAutoPush(reconnectPushDelay);
    }
    scheduleAutoPull(reconnectPullDelay);
  }

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
  static ({Duration? delay, bool stalled}) autoPushFollowUp(Map<int, int> attempted, Iterable<PendingSync> queue, int failures) {
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
    // مهلة بعد الرسم الأول — سحب فوري كان يجمّد الواجهة فور الدخول
    scheduleAutoPull(const Duration(milliseconds: 800));
    scheduleAutoPush(const Duration(seconds: 2));
  }

  /// لا اتصال بالسحابة: المزامنة التلقائية متوقفة حتى يعود، والواجهة تعرض ذلك
  /// بدل مؤشر يدور. التعديلات تبقى في الطابور وتُرفع فور عودة الاتصال.
  bool offline = false;
  Timer? _onlineWatch;
  static const onlineProbeEvery = Duration(seconds: 20);

  void _setOffline(bool value) {
    if (offline == value) return;
    offline = value;
    notifyListeners();
    _onlineWatch?.cancel();
    _onlineWatch = null;
    if (value) {
      _onlineWatch = Timer.periodic(onlineProbeEvery, (_) async {
        if (!autoSync) return;
        if (await probeCloud()) _setOffline(false);
      });
    } else {
      // عودة الاتصال: ارفع ما علّق، وأجّل السحب الثقيل
      _scheduleAfterReconnect();
    }
  }

  /// فحص الاتصال قبل مزامنة يدوية — يحدّث [offline] ويعيد النتيجة.
  Future<bool> checkOnline() async {
    if (!networkEnabled) return true;
    final online = await probeCloud();
    _setOffline(!online);
    return online;
  }

  void stopAutoSync() {
    autoSync = false;
    _onlineWatch?.cancel();
    _onlineWatch = null;
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
    scheduleAutoPush(const Duration(milliseconds: 600));
    // سحب بعد استقرار الشاشة — لا مع أول لمسة بعد فتح التطبيق
    scheduleAutoPull(reconnectPullDelay);
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
    // بلا شبكة لا تبدأ مزامنة تدور حتى مهلتها: مراقبة الاتصال تعيدها فور عودته
    if (networkEnabled) {
      if (push && !pendingSyncs.any((a) => a.retryCount < maxSyncRetries)) return;
      if (!await checkOnline() || !autoSync) return;
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
        // لا تسحب وأنت ترفع طابوراً: السحب يتجمّد الواجهة فوق عمليات المستخدم
        if (pendingSyncs.any((a) => a.retryCount < maxSyncRetries)) {
          scheduleAutoPush(const Duration(milliseconds: 500));
          scheduleAutoPull(reconnectPullDelay);
          return;
        }
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
    } else if (local != null && toTimestamp(record['updated_at']) <= toTimestamp(local['updated_at']) + stampToleranceMs) {
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
    institutionSettingsKey,
    institutionStampKey,
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
    sectionOrphanRepairKey,
    enrollmentRoomMigrationKey,
    withdrawnStatusMigrationKey,
    _kDeviceUser,
    _kReceiptLabel,
    _kReceiptCounter,
    _kDeviceUid,
    _kDeviceCode,
    _kDeviceCodeRegistered,
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
    if (previous != null && previous != tenant.id) await wipeAllData();

    // الإعدادات تُمحى بمالكها المكتوب معها لا بمؤشر البيانات: جهازٌ فقد المؤشر
    // (نسخة أقدم، أو إغلاقٌ قبل الحفظ) كان يُدخل رسم حجز مدرسة وأشهرها ورسومها
    // الإضافية على مدرسة جديدة لم تعتمد منها شيئاً.
    // مدرسة حُذفت وأُعيد إنشاؤها باسم المستخدم نفسه تحمل معرّفاً جديداً، فالاسم
    // لا يصلح دليلاً. وجهازٌ بلا مالكٍ مكتوب لا تبقى إعداداته إلا إذا كانت
    // بيانات المدرسة نفسها عليه.
    final owner = _settingsTenant;
    final foreign = owner == null ? previous != tenant.id : owner != tenant.id;
    if (foreign) await _clearTenantScopedSettings();

    await db.setSetting(_kDbTenant, tenant.id);
    await db.setSetting(_kSettingsTenant, tenant.id);

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
    // فهرس الطلاب وحده: لا شأن للبحث عن طالب بخمسين ألف رصد حضور
    _rebuildStudentIndex();
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
  static String studentDocPath(String tenantId, String studentId, String kind, String mime) => '$tenantId/$studentId/$kind.${storageExtensionForMime(mime)}';

  /// جلب مرفقات الطالب عند الطلب — المقابل لـ `getAttachments`.
  ///
  /// الملفان في المخزن والصف يحمل مساريهما، فيُنزَّلان عند فتح ملف الطالب وحده
  /// ويبقيان على الجهاز بعدها.
  Future<StudentAttachments?> loadAttachments(String studentId) async {
    final local = attachmentsByStudent[studentId];
    if (local != null && local.hasData) return local;
    if (!networkEnabled || tenantId == null) return local;

    try {
      final rows = await supabaseSelect('student_attachments', filters: {'id': 'eq.$studentId'}, limit: 1);
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

  Map<String, dynamic>? financeAttachment(String recordId) => _notices.where((r) => '${r['id']}' == recordId).firstOrNull;

  /// مسار الملف: مجلد لكل منشأة، فلا تقرأ مدرسة إشعارات غيرها.
  static String noticePath(String tenantId, String recordId, String mime) => '$tenantId/$recordId.${storageExtensionForMime(mime)}';

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
      _queue('finance_attachments', recordId, 'DELETE', null);
      markDirty('finance_attachments');
      notifyListeners();
      // حذف الملف السحابي في الخلفية — الواجهة لا تنتظر التخزين
      if (path.isNotEmpty) unawaited(storageRemove(noticeBucket, [path]));
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

    // الرفع في الخلفية: السند يظهر فوراً والصورة تلحق بالاتصال
    unawaited(_uploadNotice(row));
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
      final path = '${row['storage_path'] ?? ''}'.isNotEmpty ? '${row['storage_path']}' : noticePath(tid, '${row['id']}', file.mime);
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
    return installments.where((i) => i.studentId == studentId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  /// طلاب الشعبة — مطابق لـ `SchoolClasses.tsx`.
  ///
  /// المطابقة تامة كما في حفظ توزيع المواد (`studentBelongsToRoom`): كانت هنا
  /// باحتواء النص، فتعرض الشاشة طلاب «علمي 1» ضمن «علمي 10» ولا يسجّلهم الحفظ.
  /// الطالب بلا شعبة يُحسب على الشعبة فقط إن كانت الوحيدة لمرحلته، والمؤرشف
  /// خريجٌ لم يعد من طلاب أي شعبة.
  int _rosterStamp = -1;
  final _rosterCache = <String, List<Student>>{};

  List<Student> studentsOf(Classroom room) {
    // كشف كل شعبة محفوظ حتى يتغيّر الطلاب أو الشعب أو العام: شاشة الصفوف ترسم
    // كل الشعب في كل إطار، وتعديل دفعةٍ أو رصدٍ لا يغيّر من في أي شعبة.
    final stamp = Object.hash(_studentsStamp, _listStamp('rooms', rooms), viewedAcademicYearId);
    if (_rosterStamp != stamp) {
      _rosterStamp = stamp;
      _rosterCache.clear();
    }
    final key = '${room.id}|${room.name}|${room.gradeLevel}';
    final cached = _rosterCache[key];
    // نسخة: المستدعي قد يرتّب القائمة أو يحذف منها
    if (cached != null) return List.of(cached);
    final result = _computeStudentsOf(room);
    _rosterCache[key] = result;
    return List.of(result);
  }

  List<Student> _computeStudentsOf(Classroom room) {
    // قائمة الشعب تُقرأ مرة لا مرةً لكل طالب: كانت داخل الشرط، وشاشة الصفوف
    // تستدعي هذه الدالة لكل صف — فصار العدّ صفوفاً × طلاباً × صفوفاً.
    final yearRooms = roomsInViewedYear;
    final roomGrade = room.gradeLevel.trim();
    return studentsInViewedYear.where((s) {
      if (s.status == 'archived') return false;
      if (s.section.trim().isNotEmpty) return studentBelongsToRoom(s, room);
      if (roomGrade.isEmpty || s.gradeLevel.trim().isEmpty) return false;
      Classroom? only;
      for (final r in yearRooms) {
        if (!isSameGrade(r.gradeLevel, s.gradeLevel)) continue;
        if (only != null) return false; // أكثر من شعبة للمرحلة: لا نسبة تلقائية
        only = r;
      }
      return only != null && only.id == room.id;
    }).toList();
  }

  /// طلاب الشعبة في الحضور — مطابق لـ `Attendance.tsx`.
  ///
  /// النشطون في الشعبة، ومن رُصد له حضور في هذا الأسبوع لهذه الشعبة ولو
  /// انسحب أو أُرشف لاحقاً (الكشف سجل تاريخي).
  List<Student> attendanceRosterOf(Classroom room, {Iterable<String>? weekDates}) {
    final dates = (weekDates ?? schoolWeek().map((d) => d.dateStr)).toList();
    bool belongs(Student s) {
      if (s.section.trim().isNotEmpty) return studentBelongsToRoom(s, room);
      if (room.gradeLevel.trim().isEmpty || s.gradeLevel.trim().isEmpty) return false;
      final ofGrade = roomsInViewedYear.where((r) => isSameGrade(r.gradeLevel, s.gradeLevel)).toList();
      return ofGrade.length == 1 && ofGrade.first.id == room.id;
    }

    bool markedThisWeek(Student s) {
      for (final d in dates) {
        if (markFor(room.id, s.id, d) != null) return true;
      }
      return false;
    }

    return studentsInViewedYear.where((s) {
      if (markedThisWeek(s)) return true;
      if (s.status != 'active') return false;
      return belongs(s);
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
  String? attendanceInSession(String ownerId, String studentId, String date) => markFor(ownerId, studentId, date)?.status;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  bool _batchNotify = false;
  bool _queuedNotify = false;

  void _queue(String table, String recordId, String action, Map<String, dynamic>? payload) {
    // تعديل ثم تراجع عنه: السجل صار كما في السحابة، فتُسقط العملية المعلّقة
    // بدل رفعٍ لا يغيّر شيئاً وعدّادٍ يشير إلى تغيير غير موجود.
    if (action == 'UPDATE' && _isBackToSynced(table, recordId, payload)) {
      final had = pendingSyncs.any((p) => p.tableName == table && p.recordId == recordId);
      pendingSyncs.removeWhere((p) => p.tableName == table && p.recordId == recordId);
      markRecord(table, recordId);
      if (had) markDirty(_pendingTable);
      _notifyOrDefer();
      return;
    }

    queuePendingSync(pendingSyncs, tableName: table, recordId: recordId, action: action, payload: payload, tenantId: tenantId ?? '');
    markRecord(table, recordId, deleted: action == 'DELETE');
    markDirty(_pendingTable);
    _notifyOrDefer();
  }

  void _notifyOrDefer() {
    if (_batchNotify) {
      _queuedNotify = true;
      return;
    }
    notifyListeners();
  }

  /// يجمع عدة كتابات في إخطار واجهة واحد — لمس الحضور كان يعيد بناء الشاشة مرتين.
  void _withBatchedNotify(void Function() body) {
    _batchNotify = true;
    _queuedNotify = false;
    try {
      body();
    } finally {
      _batchNotify = false;
      if (_queuedNotify) notifyListeners();
    }
  }

  /// رصد حالة محددة لطالب في يوم. `null` يمسح الرصد.
  /// [ownerId] هو معرّف الصف (نظام مدرسة) أو المجموعة (نظام مركز).
  void setAttendance(String studentId, String date, String? status, {String? ownerId}) {
    requireSection('attendance');

    // ما تغيّر في هذه اللمسة، ليُرقَّع في الفهارس بدل إعادة بنائها كاملةً
    final wasValid = _indexRev == _markStamp;
    AttendanceMark? removed;
    AttendanceMark? touched;
    ClassSession? createdSession;

    _withBatchedNotify(() {
      final existing = markFor(ownerId, studentId, date);

      if (status == null) {
        if (existing == null) return;
        attendance.remove(existing);
        removed = existing;
        _queue('attendance', existing.id, 'DELETE', null);
        return;
      }

      // الجلسة تُنشأ عند الحاجة فقط، بعد التأكد من وجود ما يُرصد
      var sessionId = '';
      if (ownerId != null && ownerId.isNotEmpty) {
        final before = sessions.length;
        final sess = sessionFor(ownerId, date);
        sessionId = sess.id;
        if (sessions.length != before) createdSession = sess;
      }

      if (existing != null) {
        if (existing.status == status && (sessionId.isEmpty || existing.sessionId == sessionId)) {
          _completeSession(ownerId, date);
          return; // لا تغيير في السجل؛ الحصة تُكمَّل إن لم تكن
        }
        existing.status = status;
        existing.markedByUserId = currentUserId;
        if (sessionId.isNotEmpty) existing.sessionId = sessionId;
        existing.updatedAt = _nowIso();
        existing.syncStatus = 'pending';
        touched = existing;
        _queue('attendance', existing.id, 'UPDATE', existing.toCloud());
        _completeSession(ownerId, date);
        return;
      }

      final mark = AttendanceMark(
        id: attendanceIdFor(sessionId, studentId),
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
      touched = mark;
      _queue('attendance', mark.id, 'INSERT', mark.toCloud());
      _completeSession(ownerId, date);
    });

    _keepIndexes(wasValid, () {
      if (createdSession != null) _indexSession(createdSession!);
      if (removed != null) _unindexMark(removed!);
      if (touched != null) _indexMark(touched!);
    });
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

    // الفهارس صالحة الآن؟ إذاً تُرقَّع مع كل رصد وتبقى صالحة. كانت تسقط مع كل
    // طالب فتُعاد على عشرات الآلاف — مرة لكل طالب في الكشف.
    var keepIndex = _indexRev == _markStamp;

    var sessionId = '';
    if (ownerId != null && ownerId.isNotEmpty) {
      final before = sessions.length;
      final sess = sessionFor(ownerId, date);
      sessionId = sess.id;
      if (sessions.length != before && keepIndex) {
        _indexSession(sess);
        _indexRev = _markStamp;
      }
      keepIndex = keepIndex && _indexRev == _markStamp;
    }

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
        queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: existing.id, action: 'UPDATE', payload: existing.toCloud());
        markRecord('attendance', existing.id);
        if (keepIndex) {
          _indexMark(existing);
          _indexRev = _markStamp;
        }
        changed++;
        continue;
      }

      final mark = AttendanceMark(
        id: attendanceIdFor(sessionId, s.id),
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
      queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: mark.id, action: 'INSERT', payload: mark.toCloud());
      markRecord('attendance', mark.id);
      if (keepIndex) {
        _indexMark(mark);
        _indexRev = _markStamp;
      }
      changed++;
    }

    _completeSession(ownerId, date);
    if (changed > 0) {
      markDirty(_pendingTable);
      notifyListeners();
      // الإخطار يُبطل الفهارس، وقد رُقّعت سجلاً سجلاً أثناء الحلقة
      if (keepIndex) _indexRev = _markStamp;
    }
    return changed;
  }

  /// الحصة «مكتملة» بعد أي رصد — مطابق لـ `saveSessionAttendance`.
  void _completeSession(String? ownerId, String date) {
    if (ownerId == null || ownerId.isEmpty) return;
    final session = sessionFor(ownerId, date);
    if (session.status == 'completed') return;
    session.status = 'completed';
    session.updatedAt = _nowIso();
    session.syncStatus = 'pending';
    _queue('sessions', session.id, 'UPDATE', session.toCloud());
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
    final saturday = DateTime(now.year, now.month, now.day).subtract(Duration(days: distFromSaturday)).add(Duration(days: offsetWeeks * 7));
    const names = ['السبت', 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    final today = isoDate(now);
    return [
      for (var i = 0; i < 6; i++)
        () {
          final d = saturday.add(Duration(days: i));
          return SchoolDay(date: d, dateStr: isoDate(d), dayName: names[i], shortDate: '${d.day}/${d.month}', isToday: isoDate(d) == today);
        }(),
    ];
  }

  // ── فهارس فحص التكرار ────────────────────────────────────────────────────
  //
  // كل حفظ طالب يتحقق من تكرار الهوية والجوال، وكان يمسح الطلاب كلهم ويطبّع
  // رقم كل واحد منهم من جديد. الفهرسان يُبنيان مرة لكل تغيّر في الجدول.

  int _dupIndexStamp = -1;
  final _byNationalId = <String, List<Student>>{};

  /// الطلاب بآخر سبعة أرقام من جوالهم، مع الرقم المطبَّع — كل تطابقٍ صالح
  /// يشترك فيها، فتُطبَّق القاعدة الكاملة على هذه القلّة وحدها.
  final _byPhoneTail = <String, List<({Student student, String digits})>>{};

  void _rebuildDupIndexes() {
    final stamp = _listStamp('students', students);
    if (_dupIndexStamp == stamp) return;
    _dupIndexStamp = stamp;
    _byNationalId.clear();
    _byPhoneTail.clear();
    for (final s in students) {
      final nid = s.nationalId.trim();
      if (nid.isNotEmpty) _byNationalId.putIfAbsent(nid, () => []).add(s);
      final digits = digitsOnly(combinePhoneAndPrefix(s.phone, s.phonePrefix));
      if (digits.length < 7) continue; // لا يطابق رقماً من سبعة فأكثر أبداً
      _byPhoneTail
          .putIfAbsent(digits.substring(digits.length - 7), () => [])
          .add((student: s, digits: digits));
    }
  }

  Student? findByNationalId(String id, {String? exclude}) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    _rebuildDupIndexes();
    for (final s in _byNationalId[clean] ?? const <Student>[]) {
      if (exclude != null && s.id == exclude) continue;
      return s;
    }
    return null;
  }

  Student? findByPhone(String phone, {String? exclude}) {
    final digits = digitsOnly(combinePhoneAndPrefix(phone));
    if (digits.length < 7) return null;
    _rebuildDupIndexes();
    // المرشحون بترتيب القائمة نفسه، فيُعاد أولُ مطابقٍ كما كان المسح الكامل يعيده
    for (final c in _byPhoneTail[digits.substring(digits.length - 7)] ?? const []) {
      if (exclude != null && c.student.id == exclude) continue;
      final other = c.digits;
      // مطابق لـ checkPhoneExists: تطابق كامل أو آخر 7+ أرقام (مقدمات مختلفة)
      if (other == digits || other.endsWith(digits) || digits.endsWith(other)) {
        return c.student;
      }
    }
    return null;
  }

  void upsertStudent(
    Student incoming, {
    bool isNew = false,
    StudentAttachments? attachments,
    PlanDiscount? discount,
    EnrollmentPlanMode enrollmentMode = EnrollmentPlanMode.full,
    /// تنبيه لا منع: إخوة صغار يُسجَّلون برقم ولي أمرهم — كويب.
    bool allowDuplicatePhone = false,
    /// بنود خطة مخصصة عند التسجيل (بدل خطة المرحلة).
    List<PlanItem>? customPlanItems,
  }) {
    requireSection('students');
    if (!isValidNationalId(incoming.nationalId)) {
      throw StoreException('رقم الهوية غير صالح! يجب أن يتكون من 9 أرقام.');
    }
    final dupId = findByNationalId(incoming.nationalId, exclude: incoming.id);
    if (dupId != null) {
      throw StoreException('رقم الهوية (${incoming.nationalId}) مسجل مسبقاً للطالب "${dupId.fullName}" ولا يمكن تكراره.');
    }
    if (!isValidStudentPhone(incoming.phone, incoming.phonePrefix)) {
      throw StoreException('رقم جوال الطالب غير مكتمل! يجب إدخال ${phoneTargetLength(incoming.phonePrefix)} أرقام بعد المقدمة (${incoming.phonePrefix}).');
    }
    final dupPhone = findByPhone(incoming.phone, exclude: incoming.id);
    if (dupPhone != null && !allowDuplicatePhone) {
      throw StoreException('رقم جوال الطالب (${incoming.phone}) مسجل مسبقاً للطالب "${dupPhone.fullName}" ولا يمكن تكراره.');
    }
    if (incoming.fullName.trim().isEmpty) {
      throw StoreException('يرجى إدخال الاسم الرباعي للطالب.');
    }

    incoming.splitNameIfNeeded();
    incoming.updatedAt = _nowIso();
    incoming.syncStatus = 'pending';

    final useCustom = isNew && customPlanItems != null && customPlanItems.isNotEmpty;
    if (useCustom) {
      incoming.usesCustomPlan = true;
    }

    if (isNew && discount != null && discount.value > 0) {
      requireFinanceAction('finance.discount');
      incoming.planDiscountType = discount.percentage ? 'percentage' : 'fixed';
      incoming.planDiscountValue = discount.value;
      incoming.planDiscountReason = discount.reason;
      incoming.planDiscountFrom = discount.from ?? '';
      incoming.academicDiscountApplied = true;
      if (discount.percentage) {
        incoming.academicDiscountRate = discount.value;
      }
    }

    final i = students.indexWhere((e) => e.id == incoming.id);
    if (i >= 0) {
      final before = students[i];
      // تعديل وأنت تعرض سنة سابقة: الصف/الشعبة/الحالة تُكتب في اللقطة لا فوق سنته الحالية
      final viewingPast =
          before.academicYearId.isNotEmpty && before.academicYearId != viewedAcademicYearId;
      final snap = viewingPast
          ? studentYears.where((y) => y.id == studentYearRecordId(before.id, viewedAcademicYearId)).firstOrNull
          : null;
      if (snap != null) {
        snap
          ..gradeLevel = incoming.gradeLevel
          ..section = incoming.section
          ..status = incoming.status
          ..updatedAt = _nowIso()
          ..syncStatus = 'pending';
        _queue('student_years', snap.id, 'UPDATE', snap.toCloud());
        markDirty('student_years');
        incoming.gradeLevel = before.gradeLevel;
        incoming.section = before.section;
        incoming.status = before.status;
      }
      final placementChanged = before.section != incoming.section || before.gradeLevel != incoming.gradeLevel || before.status != incoming.status;
      final leftActive = (incoming.status == 'withdrawn' || incoming.status == 'archived') && before.status != incoming.status;
      incoming.balance = before.balance;
      incoming.createdAt = before.createdAt ?? incoming.createdAt;
      students[i] = incoming;
      _queue('students', incoming.id, 'UPDATE', incoming.toCloud());
      // تغيّر الشعبة أو المرحلة أو الحالة يعيد تشكيل عضويته في مواد شعبته
      if (placementChanged) syncStudentRoomEnrollments([incoming.id]);
      // منسحب/مؤرشف: إسقاط الأقساط المستقبلية كويب — وإلا يبقى ديناً وهمياً على الأجهزة
      if (leftActive) cancelFutureInstallments(incoming.id);
    } else {
      incoming.createdAt ??= _nowIso();
      incoming.academicYearId = incoming.academicYearId.isEmpty ? (operationalAcademicYear?.id ?? viewedAcademicYearId) : incoming.academicYearId;
      // رمز بوابة الطالب يُولَّد عند التسجيل، كما في StudentForm
      if (incoming.portalCode.trim().isEmpty) {
        incoming.portalCode = newPortalCode();
      }
      students.insert(0, incoming);
      _queue('students', incoming.id, 'INSERT', incoming.toCloud());

      // خطة مخصصة أو نسخة من خطة المرحلة — تُبنى دائماً حتى لو بلا بنود
      // فيُقيَّد رسم الحجز وحده (كـ buildStudentPlan على الويب).
      final custom = customPlanItems;
      final items = (useCustom && custom != null) ? custom : planItemsOf(planForStudent(incoming));
      for (final inst in _studentPlanInstallments(
        incoming,
        items: items,
        discount: useCustom ? null : discount,
        enrollmentMode: useCustom ? EnrollmentPlanMode.full : enrollmentMode,
        customIds: useCustom,
      )) {
        installments.add(inst);
        _queue('installments', inst.id, 'INSERT', inst.toCloud());
      }
      markDirty('installments');
      _persistStudentLedger(incoming);
      // دفعة حجز سابقة بلا قسط: تُربط بأول قسط بعد إنشاء الخطة
      applySeatCreditToFirstInstallment(incoming.id);
      if (discount != null && discount.value > 0) {
        _recordFinanceAudit(
          action: 'student_discount',
          summary: 'خصم تسجيل ${discount.percentage ? '${discount.value}%' : money(discount.value)}',
          studentId: incoming.id,
          amount: discount.value,
          reason: discount.reason,
        );
      }
      // طالب جديد بشعبة موجودة: يُسجَّل في مواد شعبته (مودل/معلمون/علامات)
      // كما عند نقل الشعبة أو تأكيد الانتظار — وإلا يبقى بلا تسجيلات.
      syncStudentRoomEnrollments([incoming.id]);
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
  double outstandingDue(String studentId) => overdueByStudent(installments.where((i) => i.studentId == studentId))[studentId] ?? 0;

  /// هل سدّد الطالب كل ما استُحق عليه حتى اليوم؟
  ///
  /// يعتمد على المستحق الحالّ لا على الرصيد الكامل (الذي يشمل الأقساط المجدولة).
  bool isSettledToDate(String studentId) => outstandingDue(studentId) <= cent;

  /// عدد كل سندات الطالب (مقبوضة وملغاة) — الملغى قيد في سجل القبض ويمنع الحذف.
  int countActivePayments(String studentId) => payments.where((p) => p.studentId == studentId).length;

  /// إسقاط أقساط لم تحن ولم يُدفع منها شيء — `StudentsService.cancelFutureInstallments`.
  ///
  /// عند الانسحاب/الأرشفة: المستحق والمدفوع يبقيان؛ المجدول يُحذف حتى لا يظهر ديناً.
  int cancelFutureInstallments(String studentId) {
    final victims = installments.where((i) => i.studentId == studentId && !i.isExempt && !isInstallmentDue(i) && i.paidAmount <= cent).toList();
    if (victims.isEmpty) return 0;

    var removed = 0;
    for (final row in victims) {
      final linked = payments.where((p) => !p.cancelled && p.installmentId == row.id).length;
      if (linked > 0) continue;
      queuePendingSync(pendingSyncs, tableName: 'installments', recordId: row.id, action: 'DELETE', payload: null);
      installments.removeWhere((i) => i.id == row.id);
      removed++;
    }
    if (removed > 0) {
      markDirty('installments');
      markDirty(_pendingTable);
      final stu = studentById(studentId);
      if (stu != null) _persistStudentLedger(stu);
    }
    return removed;
  }

  /// أرشفة طالب بدل الحذف — يُسقط الأقساط المستقبلية ويحتفظ بالسجل المالي.
  void archiveStudent(String id) {
    requireSection('students');
    final stu = studentById(id);
    if (stu == null) throw StoreException('الطالب غير موجود.');
    if (stu.status == 'archived') return;
    // كائن جديد حتى يقرأ upsert الفرق عن الحالة السابقة (لا تعديل بالرجوع)
    upsertStudent(Student.fromCloud({...stu.toCloud(), 'status': 'archived'}));
  }

  /// حذف طالب مع كل ما يتبعه — مطابق لـ `StudentsService.delete`.
  ///
  /// أي سند قبض (ولو ملغى) يمنع الحذف: السجل المالي لا يُمحى بحذف صاحبه.
  void deleteStudent(String id) {
    requireSection('students');
    final pays = countActivePayments(id);
    if (pays > 0) {
      throw StoreException(
        'لا يمكن حذف هذا الطالب لأن له $pays سند قبض (مقبوض أو ملغى). '
        'غيّر حالته إلى «منسحب» أو «مؤرشف» للاحتفاظ بالسجل المالي.',
      );
    }

    for (final inst in installments.where((i) => i.studentId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'DELETE', payload: null);
    }
    for (final a in attendance.where((a) => a.studentId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: a.id, action: 'DELETE', payload: null);
    }
    for (final e in enrollmentsOf(id)) {
      queuePendingSync(pendingSyncs, tableName: 'enrollments', recordId: e.id, action: 'DELETE', payload: null);
    }
    for (final e in evaluationsOfStudent(id)) {
      queuePendingSync(pendingSyncs, tableName: 'student_evaluations', recordId: e.id, action: 'DELETE', payload: null);
    }
    final yearRows = studentYears.where((y) => y.studentId == id).toList();
    for (final y in yearRows) {
      queuePendingSync(pendingSyncs, tableName: 'student_years', recordId: y.id, action: 'DELETE', payload: null);
    }

    students.removeWhere((s) => s.id == id);
    installments.removeWhere((i) => i.studentId == id);
    attendance.removeWhere((a) => a.studentId == id);
    enrollments.removeWhere((e) => e.studentId == id);
    studentYears.removeWhere((y) => y.studentId == id);
    final evalBucket = extraCloud['student_evaluations'];
    if (evalBucket != null) {
      evalBucket.removeWhere((row) => '${(row as Map)['student_id'] ?? ''}' == id);
    }
    final removedDocs = attachmentsByStudent.remove(id);
    if (removedDocs != null) {
      unawaited(_removeCloudAttachments(id, removedDocs.paths));
      _queue('student_attachments', id, 'DELETE', null);
    }
    _queue('students', id, 'DELETE', null);
    markDirty('students');
    markDirty('installments');
    markDirty('attendance');
    markDirty('enrollments');
    markDirty('student_years');
    markDirty('student_evaluations');
    markDirty('student_attachments');
  }

  /// رسم حجز دُفع قبل وجود أقساط: يُربط بأول قسط مفتوح — `applySeatCreditToFirstInstallment`.
  void applySeatCreditToFirstInstallment(String studentId) {
    final seat = payments
        .where((p) => p.studentId == studentId && !p.cancelled && p.purpose == 'seat_reservation' && (p.installmentId == null || p.installmentId!.isEmpty))
        .firstOrNull;
    if (seat == null) return;

    final open = installments.where((i) => i.studentId == studentId && i.remaining > cent).toList()..sort(compareInstallments);
    if (open.isEmpty) return;

    final inst = open.first;
    seat.installmentId = inst.id;
    seat.updatedAt = _nowIso();
    seat.syncStatus = 'pending';
    _queue('payments', seat.id, 'UPDATE', seat.toCloud());
    final stu = studentById(studentId);
    if (stu != null) _persistStudentLedger(stu);
    markDirty('payments');
  }

  /// أعلى رقم تسلسلي مستخدم لسنة معينة (ولرمز جهاز) ضمن قائمة أرقام سندات.
  /// مطابق لـ `FinanceService.maxSerialFor`.
  static int maxSerialFor(int year, Iterable<String> receiptNumbers, [String? code]) {
    var max = 1000;
    for (final raw in receiptNumbers) {
      final parsed = parseReceiptNumber(raw);
      if (parsed == null || parsed.year != year) continue;
      if ((parsed.code ?? '') != (code ?? '')) continue;
      if (parsed.serial > max) max = parsed.serial;
    }
    return max;
  }

  /// رقم السند مفككاً: رمز الجهاز (غائب في الأرقام القديمة) والسنة والتسلسل.
  static ({String? code, int year, int serial})? parseReceiptNumber(String raw) {
    final m = RegExp(r'^(?:([A-Z]{1,3})-)?(\d{4})\/(\d+)$').firstMatch(raw.trim());
    if (m == null) return null;
    return (code: m.group(1), year: int.parse(m.group(2)!), serial: int.parse(m.group(3)!));
  }

  /// آخر تسلسل رآه هذا الجهاز من السحابة، يُحدَّث قبل كل دفعة عند توفّر الاتصال.
  int _cloudSerialHint = 0;

  String _deviceUid() {
    var uid = db.settings[_kDeviceUid];
    if (uid == null || uid.isEmpty) {
      uid = newId();
      unawaited(db.setSetting(_kDeviceUid, uid));
    }
    return uid;
  }

  /// رمز هذا الجهاز في أرقام السندات (`K-2026/1001`) — `deviceReceiptCode`.
  ///
  /// جهازان بلا إنترنت كانا يُصدران الرقم نفسه؛ لكل جهاز تسلسله برمزه فلا يلتقيان.
  Future<String> deviceReceiptCode() async {
    final uid = _deviceUid();
    final registry = Map<String, ReceiptDeviceEntry>.from(settings.receiptDevices);
    var code = db.settings[_kDeviceCode] ?? '';
    final takenByOther = code.isNotEmpty && registry[code] != null && registry[code]!.deviceId != uid;

    if (code.isEmpty || takenByOther) {
      final taken = <String>{...registry.keys};
      for (final p in payments) {
        final parsed = parseReceiptNumber(p.receiptNumber);
        if (parsed?.code != null) taken.add(parsed!.code!);
      }
      final pool = <String>[];
      for (var i = 0; i < _receiptCodeLetters.length; i++) {
        pool.add(_receiptCodeLetters[i]);
      }
      for (var a = 0; a < _receiptCodeLetters.length; a++) {
        for (var b = 0; b < _receiptCodeLetters.length; b++) {
          pool.add('${_receiptCodeLetters[a]}${_receiptCodeLetters[b]}');
        }
      }
      final free = pool.where((c) => !taken.contains(c)).toList();
      final singles = free.where((c) => c.length == 1).toList();
      final candidates = singles.isNotEmpty ? singles : free;
      if (candidates.isEmpty) {
        code = 'Z${_rand.nextInt(900) + 100}';
      } else {
        code = candidates[_rand.nextInt(candidates.length)];
      }
      await db.setSetting(_kDeviceCode, code);
      await db.setSetting(_kDeviceCodeRegistered, null);
    }

    if (db.settings[_kDeviceCodeRegistered] != code) {
      try {
        await _writeSettings((prev) => prev.copyWith(
          receiptDevices: {
            ...registry,
            code: ReceiptDeviceEntry(
              deviceId: uid,
              label: receiptReceiver,
              registeredAt: _nowIso(),
            ),
          },
        ));
        await db.setSetting(_kDeviceCodeRegistered, code);
      } catch (_) {
        // يُعاد الحجز مع السند التالي
      }
    }
    return code;
  }

  /// استشارة السحابة عن أعلى رقم سند لهذه السنة ولهذا الجهاز.
  Future<void> primeReceiptCounter() async {
    final tid = tenantId;
    if (tid == null || !networkEnabled) return;
    final year = DateTime.now().year;
    final code = await deviceReceiptCode();
    final prefix = '$code-$year/';
    const page = 1000;
    var max = maxSerialFor(year, payments.map((p) => p.receiptNumber), code);
    for (var from = 0;; from += page) {
      final rows = await supabaseSelect(
        'payments',
        columns: 'receipt_number',
        filters: {'tenant_id': 'eq.$tid', 'receipt_number': 'like.$prefix%'},
        order: 'id.asc',
        limit: page,
        offset: from,
      );
      if (rows == null) break;
      final cloudMax = maxSerialFor(year, rows.map((r) => '${r['receipt_number'] ?? ''}'), code);
      if (cloudMax > max) max = cloudMax;
      if (rows.length < page) break;
    }
    if (max > _cloudSerialHint) _cloudSerialHint = max;
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
    final code = db.settings[_kDeviceCode];
    // بلا رمز مسجّل بعد: رقم قديم بلا بادئة حتى يُحجز الرمز عند أول اتصال
    if (code == null || code.isEmpty) {
      var max = maxSerialFor(year, payments.map((p) => p.receiptNumber));
      if (_receipt > max) max = _receipt;
      if (_cloudSerialHint > max) max = _cloudSerialHint;
      _receipt = max + 1 < 1001 ? 1001 : max + 1;
      unawaited(db.setSetting(_kReceiptCounter, '$_receipt'));
      return '$year/$_receipt';
    }
    var max = maxSerialFor(year, payments.map((p) => p.receiptNumber), code);
    if (_receipt > max) max = _receipt;
    if (_cloudSerialHint > max) max = _cloudSerialHint;
    _receipt = max + 1 < 1001 ? 1001 : max + 1;
    unawaited(db.setSetting(_kReceiptCounter, '$_receipt'));
    return '$code-$year/$_receipt';
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

  /// ترحيل حصص كشف الشعبة القديمة: كانت تكتب معرّف الشعبة في `group_id`.
  Future<int> migrateAttendanceIds() async {
    if (db.settings[attendanceIdMigrationKey] == 'true') return 0;

    final roomIds = {for (final r in rooms) r.id};
    var changed = 0;
    final now = _nowIso();

    for (final s in [...sessions]) {
      final looksLikeRoom =
          s.groupId.isNotEmpty && roomIds.contains(s.groupId) && (s.roomId.isEmpty || s.roomId == s.groupId);
      if (!looksLikeRoom) continue;

      final roomId = s.groupId;
      final wantedId = roomSessionIdFor(roomId, s.sessionDate);
      final start = (s.startTime.trim().isEmpty || s.startTime == '08:00') ? '00:00' : s.startTime;
      final end = (s.endTime.trim().isEmpty || s.endTime == '10:00') ? '23:59' : s.endTime;

      if (s.id == wantedId) {
        s.groupId = '';
        s.roomId = roomId;
        s.startTime = start;
        s.endTime = end;
        s.updatedAt = now;
        s.syncStatus = 'pending';
        _queue('sessions', s.id, 'UPDATE', s.toCloud());
        changed++;
        continue;
      }

      if (sessions.any((o) => o.id == wantedId && !identical(o, s))) {
        // معرّف حتمي موجود مسبقاً: أصلح القديم فقط واترك الحتمي
        s.groupId = '';
        s.roomId = roomId;
        s.startTime = start;
        s.endTime = end;
        s.updatedAt = now;
        s.syncStatus = 'pending';
        _queue('sessions', s.id, 'UPDATE', s.toCloud());
        changed++;
        continue;
      }

      final replacement = ClassSession(
        id: wantedId,
        groupId: '',
        sessionDate: s.sessionDate,
        startTime: start,
        endTime: end,
        teacherId: s.teacherId,
        roomId: roomId,
        status: s.status,
        substituteTeacherId: s.substituteTeacherId,
        notes: s.notes,
        syncStatus: 'pending',
        createdAt: s.createdAt ?? now,
        updatedAt: now,
      );

      for (final a in attendance.where((a) => a.sessionId == s.id).toList()) {
        final newAttId = attendanceIdFor(wantedId, a.studentId);
        pendingSyncs.removeWhere((p) => p.tableName == 'attendance' && p.recordId == a.id);
        final fresh = AttendanceMark(
          id: attendance.every((x) => x.id != newAttId) ? newAttId : a.id,
          studentId: a.studentId,
          date: a.date,
          status: a.status,
          sessionId: wantedId,
          markedByUserId: a.markedByUserId,
          notes: a.notes,
          syncStatus: 'pending',
          createdAt: a.createdAt ?? now,
          updatedAt: now,
        );
        final ai = attendance.indexOf(a);
        if (ai >= 0) attendance[ai] = fresh;
        _queue('attendance', fresh.id, 'INSERT', fresh.toCloud());
        if (a.id != fresh.id) _queue('attendance', a.id, 'DELETE', null);
      }

      pendingSyncs.removeWhere((p) => p.tableName == 'sessions' && p.recordId == s.id);
      sessions.removeWhere((x) => x.id == s.id);
      sessions.add(replacement);
      _queue('sessions', s.id, 'DELETE', null);
      _queue('sessions', wantedId, 'INSERT', replacement.toCloud());
      changed++;
    }

    await db.setSetting(attendanceIdMigrationKey, 'true');
    if (changed > 0) {
      markDirty('sessions');
      markDirty('attendance');
      markDirty(_pendingTable);
      notifyListeners();
    }
    return changed;
  }

  /// مطابق لـ `migrateReceiptNumbers`.
  Future<int> migrateReceiptNumbers({bool force = false}) async {
    if (!force && db.settings[receiptMigrationKey] == 'true') return 0;

    final currentYear = DateTime.now().year;
    final recPattern = RegExp(r'^REC-(\d{4})-(\d+)$', caseSensitive: false);
    final plainPattern = RegExp(r'^(\d+)$');
    // الأرقام ذات رمز الجهاز (`K-2026/1001`) صحيحة ولا تُمس
    final canonical = RegExp(r'^(?:[A-Z]{1,3}-)?\d{4}/\d+$');
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

  /// قبض من جهة أو شخص بلا ربط حساب طالب — نفس سندات الويب وترقيمها.
  GeneralIncome addGeneralIncome({
    required String title,
    required String category,
    required double amount,
    required DateTime date,
    String note = '',
    String method = 'cash',
    String reference = '',
    String senderName = '',
    String channel = '',
  }) {
    requireFinanceAction('finance.collect');
    if (title.trim().isEmpty) throw StoreException('اكتب اسم الجهة أو الشخص');
    if (category.trim().isEmpty) throw StoreException('اختر نوع الإيراد');
    if (amount <= 0) throw StoreException('أدخل مبلغاً صحيحاً أكبر من صفر');

    final now = _nowIso();
    final payment = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
      studentId: '',
      payerName: title.trim(),
      incomeCategory: category.trim(),
      amount: amount,
      method: method,
      date: date,
      purpose: generalIncomePurpose,
      notes: note.trim(),
      reference: reference.trim(),
      senderName: senderName.trim(),
      channel: channel.trim(),
      receivedByUserId: currentUserId,
      receivedByName: receiptReceiver,
      academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    payments.insert(0, payment);
    _queue('payments', payment.id, 'INSERT', payment.toCloud());
    markDirty('payments');
    notifyListeners();
    return GeneralIncome.fromPayment(payment);
  }

  /// تعديل بيان إيراد قبل إبطاله؛ يبقى رقم السند نفسه.
  GeneralIncome updateGeneralIncome(GeneralIncome income) {
    requireFinanceAction('finance.collect');
    final payment = payments.where((p) => p.id == income.id).firstOrNull;
    if (payment == null || !isGeneralIncomePurpose(payment.purpose)) {
      throw StoreException('سند الإيراد غير موجود');
    }
    if (payment.cancelled) throw StoreException('لا يمكن تعديل سند ملغى');
    if (income.title.trim().isEmpty || income.category.trim().isEmpty) {
      throw StoreException('الجهة ونوع الإيراد مطلوبان');
    }
    if (income.amount <= 0) throw StoreException('أدخل مبلغاً صحيحاً');
    payment
      ..payerName = income.title.trim()
      ..incomeCategory = income.category.trim()
      ..amount = income.amount
      ..date = income.date
      ..notes = income.note.trim()
      ..method = income.method
      ..updatedAt = _nowIso()
      ..syncStatus = 'pending';
    _queue('payments', payment.id, 'UPDATE', payment.toCloud());
    return GeneralIncome.fromPayment(payment);
  }

  /// الحذف المالي إبطالٌ لا إسقاط للسجل، حتى يبقى أثر السند في التقارير.
  Payment deleteGeneralIncome(String id, {required String reason}) {
    final payment = payments.where((p) => p.id == id).firstOrNull;
    if (payment == null || !isGeneralIncomePurpose(payment.purpose)) {
      throw StoreException('سند الإيراد غير موجود');
    }
    return voidPayment(payment, reason);
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
    double discountAmount = 0,
    String discountReason = '',
    double? originalAmount,
    double? totalDueAtPayment,
  }) {
    requireFinanceAction('finance.collect');
    final disc = discountAmount < 0 ? 0.0 : discountAmount;
    // amount = النقد المقبوض؛ original_amount = ما سُدِّد من الذمة قبل الخصم
    final cashReceived = amount < 0 ? 0.0 : amount;
    final totalSettled = originalAmount ?? (cashReceived + disc);
    if (totalSettled <= 0) throw StoreException('يرجى إدخال مبلغ صحيح');
    if (disc > totalSettled + cent) {
      throw StoreException('الخصم أكبر من المبلغ');
    }
    if (disc > cent) {
      requireFinanceAction('finance.discount');
    }

    final stu = studentById(studentId);
    if (stu == null) throw StoreException('يرجى اختيار الطالب أولاً');

    // المستحق وقت الدفع = ما حلّ موعده فقط — مطابق لـ PaymentForm `dueNow`
    final dueNow =
        totalDueAtPayment ??
        (() {
          final own = installments.where((i) => i.studentId == studentId).toList();
          if (own.isEmpty) return stu.balance < 0 ? stu.balance.abs() : 0.0;
          var total = 0.0;
          for (final i in own) {
            if (isInstallmentDue(i)) total += math.max(0.0, i.remaining);
          }
          return total;
        })();

    // سند الحجز يُربط بقسط الحجز (أو أول قسط مفتوح) — كما في finance.service.ts
    var linkedInstallmentId = installmentId;
    if ((linkedInstallmentId == null || linkedInstallmentId.isEmpty) && purpose == 'seat_reservation') {
      final open = installments.where((i) => i.studentId == studentId && i.remaining > cent).toList()..sort(compareInstallments);
      linkedInstallmentId = open.where((i) => i.title == seatTitle).map((i) => i.id).firstOrNull ?? open.firstOrNull?.id;
    }

    final p = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
      studentName: stu.fullName,
      receivedByName: receiptReceiver,
      studentId: studentId,
      amount: cashReceived,
      method: method,
      date: date,
      purpose: purpose,
      notes: notes,
      reference: reference,
      senderName: senderName,
      channel: channel,
      transferDate: transferDate,
      customMethodNotes: customMethodNotes,
      discountAmount: disc,
      discountReason: disc > 0 ? discountReason : '',
      originalAmount: disc > 0 ? totalSettled : null,
      installmentId: linkedInstallmentId,
      groupId: groupId,
      enrollmentId: enrollmentId,
      receivedByUserId: currentUserId,
      remainingAfter: 0,
      totalDueAtPayment: dueNow,
      academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    payments.insert(0, p);
    // المتبقي بنفس معيار «المطلوب وقت الدفع»: ما حلّ موعده — لا الرصيد الكامل
    _persistStudentLedger(stu);
    final dueInsts = installments.where((i) => i.studentId == studentId && isInstallmentDue(i));
    p.remainingAfter = ((dueInsts.fold<double>(0, (s, i) => s + math.max(0.0, chargeableAmount(i) - i.paidAmount)) * 100).round() / 100);
    queuePendingSync(pendingSyncs, tableName: 'payments', recordId: p.id, action: 'INSERT', payload: p.toCloud());
    markDirty('payments');
    markDirty(_pendingTable);
    if (disc > cent) {
      _recordFinanceAudit(
        action: 'payment_discount',
        summary: 'خصم ${money(disc)} عند القبض — سند ${p.receiptNumber}',
        studentId: studentId,
        entityId: p.id,
        amount: disc,
        reason: discountReason,
      );
    }
    notifyListeners();
    return p;
  }

  /// إبطال السند: يُلغى في يومه، ويصدر له سند عكس إن كان من يوم سابق.
  Payment voidPayment(Payment p, String reason) {
    requireFinanceAction('finance.cancel');
    if (reason.trim().isEmpty) {
      throw StoreException('اكتب سبب الإلغاء أو العكس');
    }
    if (dateOnly(p.date) == dateOnly(DateTime.now())) {
      cancelPayment(p, reason);
      return p;
    }
    return reversePayment(p, reason);
  }

  /// إلغاء سند اليوم فقط؛ التقارير السابقة لا تتغير بأثر رجعي.
  void cancelPayment(Payment p, [String reason = 'ملغاة من قبل الإدارة']) {
    requireFinanceAction('finance.cancel');
    if (p.cancelled) return;
    if (dateOnly(p.date) != dateOnly(DateTime.now())) {
      throw StoreException('السند من يوم سابق وتقرير يومه مُغلق: استخدم «عكس السند».');
    }
    if (p.reversedByPaymentId != null) {
      throw StoreException('السند معكوس مسبقاً');
    }
    p.cancelled = true;
    p.cancelReason = reason.trim();
    p.updatedAt = _nowIso();
    p.syncStatus = 'pending';
    if (p.reversesPaymentId case final originalId?) {
      final original = payments.where((item) => item.id == originalId).firstOrNull;
      if (original != null) {
        original
          ..reversedByPaymentId = null
          ..updatedAt = p.updatedAt
          ..syncStatus = 'pending';
        _queue('payments', original.id, 'UPDATE', original.toCloud());
      }
    }
    final stu = studentById(p.studentId);
    // السداد يُعاد اشتقاقه من السندات الباقية: القسط الذي غطّاه السند الملغى
    // يعود غير مسدَّد، وما فاض منه على غيره يعود كذلك
    if (stu != null) _persistStudentLedger(stu);
    _queue('payments', p.id, 'UPDATE', p.toCloud());
    _recordFinanceAudit(
      action: 'payment_cancel',
      summary: 'إلغاء السند ${p.receiptNumber} (${money(p.amount)})',
      studentId: p.studentId,
      studentName: p.studentName,
      entityId: p.id,
      amount: p.amount,
      reason: reason,
    );
  }

  /// سند سالب بتاريخ اليوم يقابل سنداً موجباً من يوم سابق.
  Payment reversePayment(Payment original, String reason) {
    requireFinanceAction('finance.cancel');
    if (reason.trim().isEmpty) throw StoreException('اكتب سبب العكس');
    if (original.cancelled) throw StoreException('السند ملغى أصلاً');
    if (original.reversedByPaymentId != null) {
      throw StoreException('السند معكوس مسبقاً');
    }
    if (original.amount <= 0) {
      throw StoreException('سند الرد أو العكس لا يُعكس');
    }

    final now = _nowIso();
    final reversal = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
      studentId: original.studentId,
      studentName: original.studentName,
      payerName: original.payerName,
      incomeCategory: original.incomeCategory,
      amount: -original.amount,
      method: original.method,
      date: DateTime.now(),
      purpose: reversalPurpose,
      notes: 'عكس السند ${original.receiptNumber} — ${reason.trim()}',
      discountAmount: original.discountAmount > 0 ? -original.discountAmount : 0,
      discountReason: original.discountReason,
      receivedByUserId: currentUserId,
      receivedByName: receiptReceiver,
      academicYearId: original.academicYearId,
      reversesPaymentId: original.id,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    payments.insert(0, reversal);
    original
      ..reversedByPaymentId = reversal.id
      ..updatedAt = now
      ..syncStatus = 'pending';
    _queue('payments', reversal.id, 'INSERT', reversal.toCloud());
    _queue('payments', original.id, 'UPDATE', original.toCloud());
    final student = studentById(original.studentId);
    if (student != null) _persistStudentLedger(student);
    _recordFinanceAudit(
      action: 'payment_reverse',
      summary: 'عكس السند ${original.receiptNumber} بالسند ${reversal.receiptNumber}',
      studentId: original.studentId,
      studentName: original.studentName,
      entityId: original.id,
      amount: original.amount,
      reason: reason,
    );
    markDirty('payments');
    notifyListeners();
    return reversal;
  }

  double studentCredit(String studentId) => math.max(0.0, (computeStudentBalance(studentId) * 100).round() / 100);

  double studentRefundable(String studentId) {
    final total = payments.where((p) => p.studentId == studentId && !p.cancelled).fold<double>(0, (sum, p) => sum + p.amount);
    return math.max(0.0, (total * 100).round() / 100);
  }

  /// رد مبلغ لولي الأمر بسند سالب مستقل بتاريخ اليوم.
  Payment refundStudentCredit(String studentId, {required double amount, required String method, required String reason}) {
    requireFinanceAction('finance.refund');
    if (reason.trim().isEmpty) throw StoreException('اكتب سبب الرد');
    final student = studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    final value = (amount * 100).round() / 100;
    if (value <= 0) throw StoreException('أدخل مبلغاً أكبر من صفر');
    final refundable = studentRefundable(studentId);
    if (value > refundable + cent) {
      throw StoreException('لا يمكن رد أكثر مما دفعه الطالب (${money(refundable)})');
    }
    final credit = studentCredit(studentId);
    final now = _nowIso();
    final refund = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
      studentId: studentId,
      studentName: student.fullName,
      amount: -value,
      method: method,
      date: DateTime.now(),
      purpose: 'refund',
      notes: reason.trim(),
      receivedByUserId: currentUserId,
      receivedByName: receiptReceiver,
      academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    payments.insert(0, refund);
    _queue('payments', refund.id, 'INSERT', refund.toCloud());
    _persistStudentLedger(student);
    _recordFinanceAudit(
      action: 'refund',
      summary:
          'رد ${money(value)} لولي الأمر — سند ${refund.receiptNumber}${value > credit + cent ? ' (أعاد ${money(value - credit)} مطلوباً على أقساطه)' : ''}',
      studentId: studentId,
      entityId: refund.id,
      amount: value,
      reason: reason,
    );
    markDirty('payments');
    notifyListeners();
    return refund;
  }

  double forfeitStudentCredit(String studentId, String reason) {
    requireFinanceAction('finance.refund');
    if (reason.trim().isEmpty) throw StoreException('اكتب سبب الإسقاط');
    final student = studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    final credit = studentCredit(studentId);
    if (credit <= cent) throw StoreException('لا رصيد للطالب');
    final now = _nowIso();
    final installment = Installment(
      id: '$extraIdPrefix${newId()}',
      studentId: studentId,
      title: 'إسقاط رصيد غير مسترد — ${reason.trim()}',
      amount: credit,
      dueDate: DateTime.now(),
      academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    installments.add(installment);
    _queue('installments', installment.id, 'INSERT', installment.toCloud());
    _persistStudentLedger(student);
    _recordFinanceAudit(
      action: 'credit_forfeit',
      summary: 'إسقاط رصيد ${money(credit)} غير مسترد',
      studentId: studentId,
      entityId: installment.id,
      amount: credit,
      reason: reason,
    );
    markDirty('installments');
    notifyListeners();
    return credit;
  }

  /// إعفاء قسط بالكامل مع سبب — يُسقطه من الرصيد والمستحق ولا يمسّه تسعير الخطة.
  void setInstallmentExempt(Installment inst, {required bool exempt, String reason = ''}) {
    setInstallmentDiscount(inst, kind: exempt ? 'exempt' : 'none', reason: reason);
  }

  void setInstallmentDiscount(Installment inst, {required String kind, double amount = 0, String reason = ''}) {
    final gross = ((inst.amount + inst.discountAmount) * 100).round() / 100;
    if (!can('finance.discount')) {
      final summary = kind == 'exempt'
          ? 'إعفاء من «${inst.title}» (${money(gross)})'
          : kind == 'amount'
          ? 'خصم ${money(amount)} على «${inst.title}»'
          : 'إزالة الخصم عن «${inst.title}»';
      submitFinanceRequest(
        kind: 'installment_discount',
        summary: summary,
        studentId: inst.studentId,
        targetId: inst.id,
        payload: {
          'input': {'kind': kind, 'amount': amount, 'reason': reason},
        },
        amount: kind == 'exempt' ? gross : (kind == 'amount' ? amount : null),
        reason: reason.trim().isEmpty ? 'إزالة خصم' : reason,
      );
      return;
    }
    requireFinanceAction('finance.discount');
    if (kind != 'none' && reason.trim().isEmpty) {
      throw StoreException('اكتب سبب الخصم أو الإعفاء');
    }
    final previous = inst.isExempt
        ? 'كان معفى'
        : inst.discountAmount > cent
        ? 'كان الخصم ${money(inst.discountAmount)}'
        : '';
    if (kind == 'amount') {
      amount = (amount * 100).round() / 100;
      if (amount <= 0) throw StoreException('أدخل مبلغ خصم أكبر من صفر');
      if (amount >= gross - cent) {
        throw StoreException('الخصم يساوي القسط أو يزيد عليه — استخدم «إعفاء كامل»');
      }
      inst
        ..discountAmount = amount
        ..discountReason = reason.trim()
        ..isExempt = false
        ..exemptReason = ''
        ..amount = ((gross - amount) * 100).round() / 100;
    } else if (kind == 'exempt') {
      inst
        ..amount = gross
        ..discountAmount = 0
        ..discountReason = ''
        ..isExempt = true
        ..exemptReason = reason.trim();
    } else {
      inst
        ..amount = gross
        ..discountAmount = 0
        ..discountReason = ''
        ..isExempt = false
        ..exemptReason = '';
    }
    inst
      ..status = installmentStatusFor(chargeableAmount(inst), inst.paidAmount)
      ..updatedAt = _nowIso()
      ..syncStatus = 'pending';
    final student = studentById(inst.studentId);
    if (student != null) _persistStudentLedger(student);
    _queue('installments', inst.id, 'UPDATE', inst.toCloud());
    _recordFinanceAudit(
      action: kind == 'amount'
          ? 'installment_discount'
          : kind == 'exempt'
          ? 'installment_exempt'
          : 'installment_discount_removed',
      summary: kind == 'amount'
          ? 'خصم ${money(amount)} على «${inst.title}»${previous.isEmpty ? '' : ' ($previous)'}'
          : kind == 'exempt'
          ? 'إعفاء من «${inst.title}» (${money(gross)})'
          : 'إزالة الخصم عن «${inst.title}»${previous.isEmpty ? '' : ' ($previous)'}',
      studentId: inst.studentId,
      entityId: inst.id,
      amount: kind == 'amount' ? amount : (kind == 'exempt' ? gross : null),
      reason: reason,
    );
    markDirty('installments');
    notifyListeners();
  }

  void removeInstallmentAdjustment(Installment inst, {String reason = ''}) {
    if (!can('finance.discount')) {
      submitFinanceRequest(
        kind: 'installment_remove',
        summary: 'حذف «${inst.title}» (${money(chargeableAmount(inst))})',
        studentId: inst.studentId,
        targetId: inst.id,
        payload: const {},
        amount: chargeableAmount(inst),
        reason: reason,
      );
      return;
    }
    requireFinanceAction('finance.discount');
    if (!isExtraChargeId(inst.id) && !isCustomInstallmentId(inst.id)) {
      throw StoreException('أقساط خطة المرحلة والرسوم الإضافية لا تُحذف من ملف الطالب — استخدم «إعفاء كامل».');
    }
    final value = chargeableAmount(inst);
    final student = studentById(inst.studentId);
    final now = _nowIso();
    unlinkAndDeleteInstallment(inst, now);
    if (student != null) _persistStudentLedger(student);
    _recordFinanceAudit(
      action: 'installment_removed',
      summary: 'حذف «${inst.title}» (${money(value)})',
      studentId: inst.studentId,
      entityId: inst.id,
      amount: value,
      reason: reason,
    );
    markDirty('installments');
    notifyListeners();
  }

  void setStudentPlanDiscount(String studentId, Map<String, dynamic>? discount, {String reason = ''}) {
    final value = (discount?['value'] as num?)?.toDouble() ?? 0;
    final type = '${discount?['type'] ?? ''}';
    final planDiscount = value > 0
        ? PlanDiscount(percentage: type == 'percentage', value: value, reason: '${discount?['reason'] ?? reason}'.trim(), from: discount?['from']?.toString())
        : null;
    setStudentPlanDiscountValue(studentId, planDiscount, requestReason: reason);
  }

  GradePlanSyncResult setStudentPlanDiscountValue(String studentId, PlanDiscount? discount, {String requestReason = ''}) {
    final student = studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    if (student.usesCustomPlan) {
      throw StoreException('الطالب على خطة مخصصة: عدّل مبالغ خطته مباشرة');
    }
    if (student.gradeLevel.trim().isEmpty) {
      throw StoreException('الطالب بلا مرحلة');
    }
    if (discount != null) {
      if (discount.value <= 0) throw StoreException('أدخل قيمة خصم أكبر من صفر');
      if (discount.percentage && discount.value >= 100) {
        throw StoreException('خصم 100% إعفاء كامل — استخدم الإعفاء على الأقساط');
      }
      if (discount.reason.trim().isEmpty) throw StoreException('اكتب سبب الخصم');
    }
    if (!can('finance.discount')) {
      final payload = discount == null
          ? <String, dynamic>{'discount': null}
          : <String, dynamic>{
              'discount': {'type': discount.percentage ? 'percentage' : 'fixed', 'value': discount.value, 'reason': discount.reason, 'from': discount.from},
            };
      submitFinanceRequest(
        kind: 'student_discount',
        summary: discount == null ? 'إزالة خصم الطالب' : 'خصم للطالب ${discount.percentage ? '${discount.value}%' : '${money(discount.value)} من كل قسط'}',
        studentId: studentId,
        payload: payload,
        reason: discount?.reason.isNotEmpty == true ? discount!.reason : (requestReason.trim().isEmpty ? 'إزالة خصم الطالب' : requestReason),
      );
      return GradePlanSyncResult();
    }
    requireFinanceAction('finance.discount');
    final previous = studentDiscountOf(student);
    final value = discount?.value ?? 0;
    final type = discount == null ? '' : (discount.percentage ? 'percentage' : 'fixed');
    final now = _nowIso();
    student
      ..planDiscountType = value > 0 ? type : null
      ..planDiscountValue = value > 0 ? value : 0
      ..planDiscountReason = discount?.reason.trim() ?? ''
      ..planDiscountFrom = discount?.from ?? ''
      ..academicDiscountApplied = discount != null
      ..academicDiscountRate = discount?.percentage == true ? value : 0
      ..updatedAt = now
      ..syncStatus = 'pending';
    _queue('students', student.id, 'UPDATE', student.toCloud());
    final result = GradePlanSync.run(
      this,
      student.gradeLevel,
      opts: GradePlanSyncOptions(apply: true, studentIds: {student.id}, includePaid: true, repriceOnly: true, discountChange: true),
    );
    _recordFinanceAudit(
      action: value > 0 ? 'student_discount' : 'student_discount_removed',
      summary: value > 0 ? 'خصم للطالب ${type == 'percentage' ? '$value%' : money(value)}' : 'إزالة خصم الطالب${previous == null ? '' : ' السابق'}',
      studentId: student.id,
      amount: (result.reprice.difference + result.repricePaid.difference).abs(),
      reason: discount?.reason ?? requestReason,
    );
    notifyListeners();
    return result;
  }

  /// رسم خاص بهذا الطالب، مستقل عن خطة المرحلة.
  Installment addExtraCharge({required String studentId, required String title, required double amount, required DateTime dueDate}) {
    final cleanTitle = title.trim();
    final value = (amount * 100).round() / 100;
    if (studentById(studentId) == null) throw StoreException('الطالب غير موجود');
    if (cleanTitle.isEmpty) throw StoreException('اكتب اسم الرسم');
    if (value <= 0) throw StoreException('أدخل مبلغاً أكبر من صفر');
    final now = _nowIso();
    final row = Installment(
      id: '$extraIdPrefix${newId()}',
      studentId: studentId,
      title: cleanTitle,
      amount: value,
      dueDate: dueDate,
      academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    installments.add(row);
    _queue('installments', row.id, 'INSERT', row.toCloud());
    final student = studentById(studentId)!;
    _persistStudentLedger(student);
    _recordFinanceAudit(action: 'extra_charge', summary: 'رسم خاص «${row.title}» ${money(value)}', studentId: studentId, entityId: row.id, amount: value);
    markDirty('installments');
    notifyListeners();
    return row;
  }

  /// يستبدل الأقساط غير المحمية بخطة خاصة ذات معرّفات `custom_*`.
  ({int added, int removed}) applyCustomPlan(String studentId, {required List<PlanItem> schedule, required String reason}) {
    requireFinanceAction('finance.discount');
    final student = studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    if (schedule.isEmpty) throw StoreException('حدّد عدد أقساط أكبر من صفر');
    if (schedule.any((i) => i.amount <= 0 || i.dueDate.trim().isEmpty)) {
      throw StoreException('حدّد مبلغ وتاريخ استحقاق صحيحين لكل قسط');
    }
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw StoreException('اكتب سبب الخطة المخصصة');
    final before = installments.where((i) => i.studentId == studentId).fold<double>(0, (sum, i) => sum + chargeableAmount(i));
    final now = _nowIso();
    var removed = 0;
    final replaceable = installments.where((row) {
      if (row.studentId != studentId) return false;
      if (!isStagePlanInstallmentId(row.id) && !isCustomInstallmentId(row.id)) {
        return false;
      }
      if (row.paidAmount > cent) return false;
      return !payments.any((p) => !p.cancelled && p.installmentId == row.id);
    }).toList();
    for (final row in replaceable) {
      unlinkAndDeleteInstallment(row, now);
      removed++;
    }

    final existingIds = {for (final row in installments.where((i) => i.studentId == studentId)) row.id};
    var added = 0;
    for (var index = 0; index < schedule.length; index++) {
      final item = schedule[index];
      final id = customInstallmentId('slot_${index + 1}', studentId);
      if (existingIds.contains(id)) continue;
      final row = Installment(
        id: id,
        studentId: studentId,
        title: item.title.trim().isEmpty ? 'قسط مخصص ${index + 1}' : item.title.trim(),
        amount: (item.amount * 100).round() / 100,
        dueDate: parseIsoDate(item.dueDate) ?? DateTime.now(),
        academicYearId: operationalAcademicYear?.id ?? viewedAcademicYearId,
        syncStatus: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      installments.add(row);
      _queue('installments', row.id, 'INSERT', row.toCloud());
      added++;
    }
    student
      ..usesCustomPlan = true
      ..exceptionReason = cleanReason
      ..updatedAt = now
      ..syncStatus = 'pending';
    _queue('students', student.id, 'UPDATE', student.toCloud());
    _persistStudentLedger(student);
    final after = installments.where((i) => i.studentId == studentId).fold<double>(0, (sum, i) => sum + chargeableAmount(i));
    _recordFinanceAudit(
      action: 'student_discount',
      summary: 'خطة مخصصة: مجموع الأقساط ${before.round()} ← ${after.round()} شيكل',
      studentId: studentId,
      amount: ((before - after) * 100).round() / 100,
      reason: cleanReason,
    );
    markDirty('students');
    markDirty('installments');
    notifyListeners();
    return (added: added, removed: removed);
  }

  /// نطاق اعتماد أقساط المرحلة — مطابق لـ `PlanReturnScope` في الويب.
  ///
  /// - [PlanReturnScope.all]: كل أقساط المرحلة (بما فيها ما فات).
  /// - [PlanReturnScope.future]: من تاريخ اليوم فصاعداً.
  /// - [PlanReturnScope.fromItem]: من قسط معيّن فما بعده.
  static const _kPlanScopeAll = 'all';
  static const _kPlanScopeFuture = 'future';
  static const _kPlanScopeFromItem = 'from_item';

  /// اعتماد خطة مرحلة على طلاب: إسقاط غير المدفوع حسب النمط، ثم إضافة بنود الخطة.
  ///
  /// مطابق لـ `StudentsService.adoptGradePlan`.
  /// - `dropUnpaid: 'custom'`: إرجاع من مخصصة.
  /// - `dropUnpaid: 'plans'`: نقل صف — يُزال غير المدفوع من المخصصة وأقساط المرحلة القديمة.
  ({int students, int removed, int added}) adoptGradePlan({
    required Iterable<String> studentIds,
    required String gradeName,
    bool setGradeLevel = false,
    String planScope = _kPlanScopeAll,
    String? fromPlanItemId,
    String? fromDueDate,
    String dropUnpaid = 'custom',
    bool onlyCustomPlanStudents = false,
    bool apply = false,
  }) {
    final drop = dropUnpaid == 'plans' ? 'plans' : 'custom';
    if (apply) {
      if (drop == 'plans') {
        // نقل صف من نموذج الطالب: صلاحية الطلاب تكفي (كالويب)
        requireSection('students', const ['finance.discount']);
      } else {
        requireFinanceAction('finance.discount');
      }
    }

    final planGrade = gradeName.trim();
    if (planGrade.isEmpty) throw StoreException('حدّد المرحلة');

    var scope = planScope;
    if (fromDueDate != null && fromDueDate.trim().isNotEmpty && scope != _kPlanScopeFromItem) {
      scope = _kPlanScopeFromItem;
    }
    if (scope == _kPlanScopeFromItem &&
        (fromPlanItemId == null || fromPlanItemId.trim().isEmpty) &&
        (fromDueDate == null || fromDueDate.trim().isEmpty)) {
      throw StoreException('حدّد القسط الذي يبدأ منه الاحتساب');
    }

    final today = isoDate(DateTime.now());
    final now = _nowIso();
    final plans = gradePlans();
    final fee = plans[planGrade.toLowerCase()];
    final items = [...planItemsOf(fee)]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    List<PlanItem> scoped;
    if (scope == _kPlanScopeFuture) {
      scoped = [
        for (final i in items)
          if ((i.dueDate.length >= 10 ? i.dueDate.substring(0, 10) : i.dueDate).compareTo(today) >= 0) i,
      ];
    } else if (scope == _kPlanScopeFromItem) {
      var startIdx = -1;
      final fromId = fromPlanItemId?.trim() ?? '';
      if (fromId.isNotEmpty) {
        startIdx = items.indexWhere((i) => i.id == fromId);
      }
      if (startIdx < 0 && fromDueDate != null && fromDueDate.trim().isNotEmpty) {
        final from = fromDueDate.trim().length >= 10 ? fromDueDate.trim().substring(0, 10) : fromDueDate.trim();
        startIdx = items.indexWhere((i) {
          final due = i.dueDate.length >= 10 ? i.dueDate.substring(0, 10) : i.dueDate;
          return due.compareTo(from) >= 0;
        });
      }
      if (startIdx < 0) throw StoreException('القسط المختار غير موجود في خطة هذه المرحلة');
      scoped = items.sublist(startIdx);
    } else {
      scoped = items;
    }

    final idFilter = studentIds.toSet();
    final candidates = students.where((s) {
      if (!idFilter.contains(s.id)) return false;
      if (s.status == 'archived' || s.status == 'withdrawn') return false;
      if (onlyCustomPlanStudents && !s.usesCustomPlan) return false;
      return true;
    }).toList();

    var resultStudents = 0;
    var resultRemoved = 0;
    var resultAdded = 0;
    final yearId = operationalAcademicYear?.id ?? viewedAcademicYearId;

    for (final student in candidates) {
      final own = installments.where((i) => i.studentId == student.id).toList();
      final byId = {for (final i in own) i.id: i};

      final toRemove = <Installment>[];
      for (final row in own) {
        if (row.paidAmount > cent || row.isExempt) continue;
        final dropCustom = isCustomInstallmentId(row.id);
        final dropStage = drop == 'plans' && isStagePlanInstallmentId(row.id);
        if (!dropCustom && !dropStage) continue;
        toRemove.add(row);
      }

      final toAdd = [
        for (final item in scoped)
          if (!byId.containsKey(planInstallmentId(item.id, student.id))) item,
      ];
      final needsFlagClear = student.usesCustomPlan;
      final needsGrade = setGradeLevel && student.gradeLevel.trim().toLowerCase() != planGrade.toLowerCase();

      if (toRemove.isEmpty && toAdd.isEmpty && !needsFlagClear && !needsGrade) continue;

      resultStudents++;
      resultRemoved += toRemove.length;
      resultAdded += toAdd.length;
      if (!apply) continue;

      final discount = studentDiscountOf(student);
      final addRows = toInstallments(
        [
          for (final item in toAdd)
            StudentPlanRow(
              id: planInstallmentId(item.id, student.id),
              title: item.title,
              amount: planInstallmentAmount(item.amount, item.dueDate, discount),
              dueDate: item.dueDate,
              originalAmount: item.amount,
            ),
        ],
        student.id,
        now,
        academicYearId: yearId,
      );

      for (final row in toRemove) {
        if (payments.any((p) => !p.cancelled && p.installmentId == row.id)) {
          resultRemoved--;
          continue;
        }
        unlinkAndDeleteInstallment(row, now);
      }

      for (final row in addRows) {
        installments.add(row);
        _queue('installments', row.id, 'INSERT', row.toCloud());
      }

      student
        ..usesCustomPlan = false
        ..updatedAt = now
        ..syncStatus = 'pending';
      if (setGradeLevel) student.gradeLevel = planGrade;
      _queue('students', student.id, 'UPDATE', student.toCloud());
      _persistStudentLedger(student);
    }

    if (apply && resultStudents > 0) {
      markDirty('students');
      markDirty('installments');
      notifyListeners();
    }
    return (students: resultStudents, removed: resultRemoved, added: resultAdded);
  }

  /// إرجاع طلاب الخطة المخصصة لاعتماد خطة مرحلتهم — `returnCustomStudentsToGradePlan`.
  ({int students, int removed, int added}) returnCustomStudentsToGradePlan({
    Iterable<String>? studentIds,
    String? gradeName,
    String? fromDueDate,
    String planScope = _kPlanScopeFuture,
    String? fromPlanItemId,
    bool apply = false,
  }) {
    final ids = studentIds?.toList() ??
        [
          for (final s in students)
            if (s.status == 'active' && s.usesCustomPlan) s.id,
        ];
    if (ids.isEmpty) return (students: 0, removed: 0, added: 0);

    final explicitGrade = gradeName?.trim() ?? '';
    if (explicitGrade.isEmpty) {
      final byGrade = <String, List<String>>{};
      for (final id in ids) {
        final s = studentById(id);
        if (s == null || !s.usesCustomPlan) continue;
        final g = s.gradeLevel.trim();
        if (g.isEmpty) continue;
        (byGrade[g] ??= []).add(id);
      }
      var totalStudents = 0;
      var totalRemoved = 0;
      var totalAdded = 0;
      for (final entry in byGrade.entries) {
        final part = adoptGradePlan(
          studentIds: entry.value,
          gradeName: entry.key,
          planScope: planScope,
          fromPlanItemId: fromPlanItemId,
          fromDueDate: fromDueDate,
          dropUnpaid: 'custom',
          onlyCustomPlanStudents: true,
          apply: apply,
        );
        totalStudents += part.students;
        totalRemoved += part.removed;
        totalAdded += part.added;
      }
      return (students: totalStudents, removed: totalRemoved, added: totalAdded);
    }

    return adoptGradePlan(
      studentIds: ids,
      gradeName: explicitGrade,
      planScope: planScope,
      fromPlanItemId: fromPlanItemId,
      fromDueDate: fromDueDate,
      dropUnpaid: 'custom',
      onlyCustomPlanStudents: true,
      apply: apply,
    );
  }

  /// نقل طالب لمرحلة أخرى مالياً — `transferStudentsToGrade`.
  ({int students, int removed, int added}) transferStudentsToGrade({
    required Iterable<String> studentIds,
    required String newGradeName,
    String planScope = _kPlanScopeFuture,
    String? fromPlanItemId,
    bool apply = false,
  }) =>
      adoptGradePlan(
        studentIds: studentIds,
        gradeName: newGradeName,
        setGradeLevel: true,
        planScope: planScope,
        fromPlanItemId: fromPlanItemId,
        dropUnpaid: 'plans',
        onlyCustomPlanStudents: false,
        apply: apply,
      );

  /// إلغاء الخطة الخاصة واعتماد خطة المرحلة (نطاق مستقبلي افتراضياً كالويب).
  ({int students, int removed, int added}) returnToGradePlan(
    String studentId, {
    String planScope = _kPlanScopeFuture,
    String? fromPlanItemId,
    bool apply = true,
  }) {
    final student = studentById(studentId);
    if (student == null) throw StoreException('الطالب غير موجود');
    if (!student.usesCustomPlan) return (students: 0, removed: 0, added: 0);
    if (student.gradeLevel.trim().isEmpty) throw StoreException('الطالب بلا مرحلة');
    return returnCustomStudentsToGradePlan(
      studentIds: [studentId],
      gradeName: planScope == _kPlanScopeFromItem ? student.gradeLevel : null,
      planScope: planScope,
      fromPlanItemId: fromPlanItemId,
      apply: apply,
    );
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
    payments: payments.where((p) => p.studentId == studentId),
  );

  /// إعادة حساب أرصدة كل الطلاب من سجلاتهم — تُستدعى بعد كل سحب.
  ///
  /// تصحيح محلي لا يُرفع: كل جهاز يصل إلى النتيجة نفسها من السجلات نفسها، فلا
  /// داعي لجولة كتابة جديدة تُشعل تضارباً آخر. تعيد عدد الأرصدة المصحَّحة.
  @override
  int recalculateAllBalances() {
    if (!tablesReady(const ['students', 'payments', 'installments'])) return 0;
    var corrected = 0;
    var installmentsFixed = false;
    _recalculateAllBalancesSync(
      onCorrected: () => corrected++,
      onInstallmentsFixed: () => installmentsFixed = true,
    );
    if (installmentsFixed) markDirty('installments');
    if (corrected > 0) markDirty('students');
    if (corrected > 0 || installmentsFixed) notifyListeners();
    return corrected;
  }

  /// كالمزامنة أعلاه مع إفساح إطار كل بضعة طلاب — لا يحبس الواجهة ثوانٍ.
  @override
  Future<int> recalculateAllBalancesYielding() async {
    if (!tablesReady(const ['students', 'payments', 'installments'])) return 0;
    var corrected = 0;
    var installmentsFixed = false;
    var n = 0;
    final paymentsByStudent = <String, List<Payment>>{};
    var bi = 0;
    for (final p in payments) {
      if (p.studentId.isEmpty) continue;
      (paymentsByStudent[p.studentId] ??= []).add(p);
      if (++bi % 250 == 0) await Future<void>.delayed(Duration.zero);
    }
    final installmentsByStudent = <String, List<Installment>>{};
    bi = 0;
    for (final i in installments) {
      if (i.studentId.isEmpty) continue;
      (installmentsByStudent[i.studentId] ??= []).add(i);
      if (++bi % 250 == 0) await Future<void>.delayed(Duration.zero);
    }
    final enrollmentsByStudent = <String, List<StudentEnrollment>>{};
    bi = 0;
    for (final e in enrollments) {
      if (e.studentId.isEmpty) continue;
      (enrollmentsByStudent[e.studentId] ??= []).add(e);
      if (++bi % 250 == 0) await Future<void>.delayed(Duration.zero);
    }
    const none = <Never>[];
    for (final student in students) {
      final pays = paymentsByStudent[student.id] ?? none;
      final insts = installmentsByStudent[student.id] ?? none;
      final enrs = enrollmentsByStudent[student.id] ?? none;
      final allocated = allocatePaymentsToInstallments(insts, pays);
      for (final inst in insts) {
        final paid = allocated[inst.id] ?? 0;
        final status = installmentStatusFor(chargeableAmount(inst), paid);
        if ((inst.paidAmount - paid).abs() <= cent && inst.status == status) continue;
        inst.paidAmount = paid;
        inst.status = status;
        installmentsFixed = true;
      }
      final computed = balanceFrom(enrollments: enrs, installments: insts, payments: pays);
      if ((student.balance - computed).abs() > 0.01) {
        student.balance = computed;
        student.updatedAt = _nowIso();
        corrected++;
      }
      if (++n % 15 == 0) await Future<void>.delayed(Duration.zero);
    }
    if (installmentsFixed) markDirty('installments');
    if (corrected > 0) markDirty('students');
    if (corrected > 0 || installmentsFixed) notifyListeners();
    return corrected;
  }

  void _recalculateAllBalancesSync({
    required void Function() onCorrected,
    required void Function() onInstallmentsFixed,
  }) {
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
    for (final student in students) {
      final pays = paymentsByStudent[student.id] ?? none;
      final insts = installmentsByStudent[student.id] ?? none;
      final enrs = enrollmentsByStudent[student.id] ?? none;
      final allocated = allocatePaymentsToInstallments(insts, pays);
      for (final inst in insts) {
        final paid = allocated[inst.id] ?? 0;
        final status = installmentStatusFor(chargeableAmount(inst), paid);
        if ((inst.paidAmount - paid).abs() <= cent && inst.status == status) continue;
        inst.paidAmount = paid;
        inst.status = status;
        onInstallmentsFixed();
      }
      final computed = balanceFrom(enrollments: enrs, installments: insts, payments: pays);
      if ((student.balance - computed).abs() <= 0.01) continue;
      student.balance = computed;
      student.updatedAt = _nowIso();
      onCorrected();
    }
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
      final status = installmentStatusFor(chargeableAmount(inst), paid);
      if ((inst.paidAmount - paid).abs() <= cent && inst.status == status) continue;
      inst.paidAmount = paid;
      inst.status = status;
      inst.updatedAt = now;
      inst.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'UPDATE', payload: inst.toCloud(), tenantId: tenantId ?? '');
      markDirty('installments');
      queued = true;
    }

    final computed = balanceFrom(enrollments: enrollments.where((e) => e.studentId == student.id), installments: insts, payments: pays);
    if ((student.balance - computed).abs() > 0.01) {
      student.balance = computed;
      student.updatedAt = now;
      student.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'students', recordId: student.id, action: 'UPDATE', payload: student.toCloud(), tenantId: tenantId ?? '');
      markDirty('students');
      queued = true;
    }
    if (queued) markDirty(_pendingTable);
    return computed;
  }

  /// واجهات لـ `GradePlanSync` — نفس المنطق الداخلي دون تعريض `_queue`.
  String nowIsoForSync() => _nowIso();

  /// واجهة ضيقة لأداة نسخ هيكل العام كي تسجل الصفوف في طابور المزامنة.
  void queueYearStructureInsert(String table, String id, Map<String, dynamic> row) {
    _queue(table, id, 'INSERT', row);
    markDirty(table);
  }

  /// يحفظ نظام العلامات الحالي كلقطة للعام المغلق.
  Future<void> snapshotGradingForYear(String yearId) async {
    await _writeSettings((prev) {
      final next = Map<String, GradingSettings>.from(prev.gradingByYear);
      next[yearId] = gradingSettings;
      return prev.copyWith(gradingByYear: next);
    });
  }

  void unlinkAndDeleteInstallment(Installment inst, String now) {
    for (final p in payments.where((p) => p.installmentId == inst.id)) {
      p.installmentId = null;
      p.updatedAt = now;
      p.syncStatus = 'pending';
      _queue('payments', p.id, 'UPDATE', p.toCloud());
    }
    installments.removeWhere((i) => i.id == inst.id);
    _queue('installments', inst.id, 'DELETE', null);
  }

  void queueInstallmentUpdate(Installment inst) => _queue('installments', inst.id, 'UPDATE', inst.toCloud());

  void queueInstallmentInsert(Installment inst) => _queue('installments', inst.id, 'INSERT', inst.toCloud());

  void persistStudentLedgerPublic(Student student) => _persistStudentLedger(student);

  /// تحديث رصيد الطالب المخبّأ من سجلاته ورفعه إن تغيّر.
  void _refreshBalance(Student student) => _persistStudentLedger(student);

  List<DueItem> dueItems() {
    // تُستدعى من شريط التنقّل في كل إعادة رسم، وحسابها يمرّ على كل الأقساط
    // والطلاب. تتبع جداولها الثلاثة وحدها، لا كل تغيّر في المخزن.
    final stamp = Object.hash(
      _listStamp('installments', installments),
      _listStamp('students', students),
      tableRev('academic_years'),
      viewedAcademicYearId,
    );
    if (_dueRev == stamp) return _dueCache;
    _dueRev = stamp;
    _dueCache = _computeDueItems();
    return _dueCache;
  }

  List<DueItem> _computeDueItems() {
    final today = dateOnly(DateTime.now());
    final list = <DueItem>[];

    // نداء واحد لأقساط العام: قراءته تمرّ على الجدول كله
    final yearInstallments = installmentsInViewedYear;

    // صاحب الخطة يظهر ولو أقساطه كلها مسددة أو مجدولة — لا يُضاف له سطر «رسوم مستحقة»
    final studentsWithPlan = {
      for (final i in yearInstallments) i.studentId,
    };

    // فهرس الطلاب يُبنى مرة قبل الحلقة، لا يُسأل عنه مع كل قسط
    _rebuildStudentIndex();
    final todayKey = dayKey(today);

    for (final inst in yearInstallments) {
      // `today` محسوب فوق: بلا تمريره تُنادى `DateTime.now()` لكل قسط، أي
      // عشرة آلاف نداء في كل إعادة حساب — وهي تتكرر مع كل تعديل في المخزن
      final dueKey = dayKey(inst.dueDate);
      if (dueKey > todayKey) continue;
      final unpaid = math.max(0.0, chargeableAmount(inst) - inst.paidAmount);
      if (unpaid <= cent) continue;
      final student = _studentIndex[inst.studentId];
      if (student == null) continue;
      list.add(
        DueItem(
          id: inst.id,
          student: student,
          title: inst.title,
          amount: unpaid,
          dueDate: inst.dueDate,
          late: dueKey < todayKey,
          scheduled: false,
          installmentId: inst.id,
        ),
      );
    }

    for (final s in studentsInViewedYear) {
      if (s.balance >= 0 || studentsWithPlan.contains(s.id)) continue;
      list.add(DueItem(
        id: 'debt-${s.id}',
        student: s,
        title: 'رسوم مستحقة',
        amount: s.balance.abs(),
        dueDate: today,
        late: false,
      ));
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
  List<StudentEnrollment> enrollmentsInGroup(String groupId) => enrollments.where((e) => e.groupId == groupId && e.isActive).toList();

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

    if (g.academicYearId.isEmpty) g.academicYearId = viewedAcademicYearId;
    g.updatedAt = _nowIso();
    g.syncStatus = 'pending';
    final i = groups.indexWhere((e) => e.id == g.id);
    if (i >= 0) {
      g.createdAt = groups[i].createdAt;
      if (g.academicYearId.isEmpty) g.academicYearId = groups[i].academicYearId;
      groups[i] = g;
      _queue('groups', g.id, 'UPDATE', g.toCloud());
    } else {
      g.createdAt = _nowIso();
      groups.add(g);
      _queue('groups', g.id, 'INSERT', g.toCloud());
    }
  }

  /// دمج مجموعات المدرسة المكررة — `SettingsService.mergeDuplicateSchoolSubjectGroups`.
  ///
  /// كان كل أستاذ يدرّس نفس المادة لأكثر من شعبة يحصل على سجل مستقل لكل شعبة.
  /// تُدمج في الأقدم، وتُنقل التسجيلات والدرجات، وتُؤرشف المكررات.
  Future<void> mergeDuplicateSchoolSubjectGroups() async {
    try {
      final schoolGroups = groups.where((g) => g.isActive && g.isSchoolGroup).toList();
      final buckets = <String, List<Group>>{};
      for (final g in schoolGroups) {
        final key = '${g.subjectId}|${g.teacherId}|${normalizeAcademicText(g.gradeLevel)}';
        (buckets[key] ??= []).add(g);
      }

      final now = _nowIso();
      final tid = tenantId;
      final online = networkEnabled && tid != null;

      for (final bucket in buckets.values) {
        if (bucket.length < 2) continue;
        bucket.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
        final primary = bucket.first;
        final duplicates = bucket.skip(1);
        final roomIds = {...primary.allRoomIds};

        for (final dup in duplicates) {
          if (online) {
            try {
              await Future.wait([
                supabaseUpdate(
                  'course_sections',
                  {'tenant_id': 'eq.$tid', 'group_id': 'eq.${dup.id}'},
                  {'group_id': primary.id},
                ),
                supabaseUpdate(
                  'course_items',
                  {'tenant_id': 'eq.$tid', 'group_id': 'eq.${dup.id}'},
                  {'group_id': primary.id},
                ),
              ]);
            } catch (_) {}
          }

          roomIds.addAll(dup.allRoomIds);

          for (final e in enrollments.where((e) => e.groupId == dup.id).toList()) {
            final already = enrollments.any((pe) => pe.groupId == primary.id && pe.studentId == e.studentId);
            if (already) {
              enrollments.remove(e);
              _queue('enrollments', e.id, 'DELETE', null);
            } else {
              final moved = StudentEnrollment(
                id: e.id,
                studentId: e.studentId,
                groupId: primary.id,
                roomId: e.roomId,
                enrolledAt: e.enrolledAt,
                status: e.status,
                customPrice: e.customPrice,
                appliedPrice: e.appliedPrice,
                discountReason: e.discountReason,
                syncStatus: 'pending',
                createdAt: e.createdAt,
                updatedAt: now,
              );
              final ei = enrollments.indexOf(e);
              if (ei >= 0) enrollments[ei] = moved;
              _queue('enrollments', moved.id, 'UPDATE', moved.toCloud());
            }
          }

          final evalBucket = extraCloud['student_evaluations'];
          if (evalBucket != null) {
            for (var i = 0; i < evalBucket.length; i++) {
              final row = evalBucket[i];
              if ('${row['group_id']}' != dup.id) continue;
              row['group_id'] = primary.id;
              row['updated_at'] = now;
              _queue('student_evaluations', '${row['id']}', 'UPDATE', {
                'id': row['id'],
                'group_id': primary.id,
                'updated_at': now,
              });
            }
          }

          dup.status = 'archived';
          dup.roomIds = [];
          dup.roomId = '';
          dup.updatedAt = now;
          dup.syncStatus = 'pending';
          _queue('groups', dup.id, 'UPDATE', {
            'id': dup.id,
            'status': 'archived',
            'room_ids': <String>[],
            'updated_at': now,
          });
        }

        final roomIdsArr = roomIds.toList();
        final primaryRoomId =
            primary.roomId.isNotEmpty && roomIdsArr.contains(primary.roomId) ? primary.roomId : (roomIdsArr.isEmpty ? '' : roomIdsArr.first);
        final subject = subjectById(primary.subjectId);
        final teacher = teacherById(primary.teacherId);
        primary
          ..roomId = primaryRoomId
          ..roomIds = roomIdsArr
          ..name = '${subject?.name ?? 'مادة'} - ${teacher?.name ?? 'معلم'}'
          ..updatedAt = now
          ..syncStatus = 'pending';
        _queue('groups', primary.id, 'UPDATE', {
          'id': primary.id,
          'room_id': primaryRoomId.isEmpty ? null : primaryRoomId,
          'room_ids': roomIdsArr,
          'name': primary.name,
          'updated_at': now,
        });
      }
    } catch (_) {
      // صيانة عند الإقلاع: فشلها لا يمنع الدخول
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
  List<Group> sectionSubjectGroups(String roomId) => groups.where((g) => g.isActive && g.includesRoom(roomId)).toList();

  /// المواد التي تنطبق على مرحلة — مطابق لـ `getGradeApplicableSubjects`.
  /// المادة العامة تنطبق على الجميع، والمرحلة تُطابَق تماماً: كان «حادي عشر»
  /// يطابق «حادي عشر علمي» فتُعرض مواد الفرع الآخر.
  List<SubjectItem> gradeApplicableSubjects(String? gradeLevel) =>
      subjects.where((s) => subjectCoversGrade(s, gradeLevel)).toList();

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
  int saveSectionSubjectAssignments({required String roomId, required String gradeLevel, required String roomName, required Map<String, String> assignments}) {
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
              .where((s) => s.status == 'active' && belongsToSection(section: s.section, grade: s.gradeLevel, roomName: sectionName, roomGrade: grade))
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
            : student != null && sectionIds.contains(e.studentId) && !otherRooms.any((r) => studentBelongsToRoom(student, r));
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
          .where(
            (g) =>
                g.isActive &&
                g.id != current?.id &&
                g.subjectId == subjectId &&
                g.teacherId == teacherId &&
                isSameGrade(g.gradeLevel, grade) &&
                !g.includesRoom(roomId),
          )
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
      final target = room == null ? const <Group>[] : activeGroups.where((g) => g.isSchoolGroup && g.includesRoom(room.id)).toList();
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
  StudentEnrollment enrollStudent({required String studentId, required String groupId, double? customPrice, String discountReason = ''}) {
    requireSection('classes');
    final student = studentById(studentId);
    if (student == null) throw StoreException('يرجى اختيار الطالب أولاً');
    final group = groupById(groupId);
    if (group == null) throw StoreException('يرجى اختيار المجموعة أولاً');

    final existing = enrollments.where((e) => e.studentId == studentId && e.groupId == groupId && e.isActive).firstOrNull;
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
      throw StoreException('لا يمكن إلغاء هذا التسجيل لأن عليه $linked سند قبض مسجَّل. ألغِ السندات أولاً.');
    }
    final removed = enrollments.where((e) => e.id == enrollmentId).firstOrNull;
    enrollments.removeWhere((e) => e.id == enrollmentId);
    _queue('enrollments', enrollmentId, 'DELETE', null);
    final owner = removed == null ? null : studentById(removed.studentId);
    if (owner != null) _refreshBalance(owner);
  }

  // ── الجلسات (المقابل لـ attendance.service.ts) ──────────────────────────────

  /// معرّف حتمي لحصة مادة — `AttendanceService.sessionIdFor`.
  static String sessionIdFor(String groupId, String dateStr) => 'ses_${groupId}_$dateStr';

  /// معرّف حتمي لكشف الشعبة اليومي — `AttendanceService.roomSessionIdFor`.
  static String roomSessionIdFor(String roomId, String dateStr) => 'ses_room_${roomId}_$dateStr';

  /// معرّف حضور حتمي — `AttendanceService.attendanceIdFor`.
  static String attendanceIdFor(String sessionId, String studentId) => 'att_${sessionId}_$studentId';

  /// إيجاد جلسة كشف شعبة لتاريخ، أو إنشاؤها بالصيغة الصحيحة (شعبة في `room_id`).
  ClassSession sessionFor(String roomId, String dateStr) {
    final wantedId = roomSessionIdFor(roomId, dateStr);
    final found = sessions.where((s) {
      if (s.id == wantedId) return true;
      if (s.sessionDate != dateStr) return false;
      // الحديثة: room_id؛ القديمة الخاطئة: group_id = معرّف الشعبة
      return s.roomId == roomId || s.groupId == roomId;
    }).firstOrNull;
    if (found != null) {
      // ترحيل صامت للصيغة القديمة إن وُجدت
      if (found.groupId == roomId && (found.roomId.isEmpty || found.roomId == roomId)) {
        found.groupId = '';
        found.roomId = roomId;
        if (found.startTime.trim().isEmpty) found.startTime = '00:00';
        if (found.endTime.trim().isEmpty) found.endTime = '23:59';
        found.updatedAt = _nowIso();
        found.syncStatus = 'pending';
        _queue('sessions', found.id, 'UPDATE', found.toCloud());
      }
      return found;
    }

    final created = ClassSession(
      id: wantedId,
      groupId: '',
      sessionDate: dateStr,
      startTime: '00:00',
      endTime: '23:59',
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
    if (t.academicYearId.isEmpty) t.academicYearId = viewedAcademicYearId;
    t.updatedAt = _nowIso();
    t.syncStatus = 'pending';
    final i = teachers.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      t.createdAt = teachers[i].createdAt;
      if (t.academicYearId.isEmpty) t.academicYearId = teachers[i].academicYearId;
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
    if (s.academicYearId.isEmpty) s.academicYearId = viewedAcademicYearId;
    s.updatedAt = _nowIso();
    s.syncStatus = 'pending';
    final i = subjects.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      s.createdAt = subjects[i].createdAt;
      if (s.academicYearId.isEmpty) s.academicYearId = subjects[i].academicYearId;
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
    r.updatedAt = _nowIso();
    r.syncStatus = 'pending';
    final i = rooms.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      final existing = rooms[i];
      final oldName = existing.name.trim();
      // الويب يعقّم الاسم عند تغييره فقط — تعيين المربي كان يعيد التعقيم فيفصل
      // اسم الصف عن حقل section لدى الطلاب فيفرغ الكشف على الجوال وحده.
      final nameUnchanged = r.name.trim() == oldName;
      if (nameUnchanged) {
        r.name = existing.name;
      } else {
        r.name = r.gradeLevel.trim().isEmpty ? r.name.trim() : sanitizeSectionName(r.name, r.gradeLevel);
      }
      if (r.academicYearId.isEmpty) r.academicYearId = viewedAcademicYearId;
      r.createdAt = existing.createdAt;
      if (r.academicYearId.isEmpty) r.academicYearId = existing.academicYearId;
      if (!nameUnchanged && oldName.isNotEmpty && oldName != r.name) {
        _renameStudentSection(
          Classroom(
            id: existing.id,
            name: oldName,
            gradeLevel: existing.gradeLevel,
            teacherId: existing.teacherId,
            academicYearId: existing.academicYearId.isEmpty ? r.academicYearId : existing.academicYearId,
          ),
          r.name,
        );
      }
      rooms[i] = r;
      _queue('rooms', r.id, 'UPDATE', r.toCloud());
    } else {
      // مرحلة في حقلها: تكرارها داخل اسم الشعبة يُنتج أسماء مزدوجة في الكشوف
      r.name = r.gradeLevel.trim().isEmpty ? r.name.trim() : sanitizeSectionName(r.name, r.gradeLevel);
      if (r.academicYearId.isEmpty) r.academicYearId = viewedAcademicYearId;
      r.createdAt = _nowIso();
      rooms.add(r);
      _queue('rooms', r.id, 'INSERT', r.toCloud());
    }
  }

  /// طلاب شعبة بعينها: الاسم والمرحلة والعام معاً — `studentsOfRoom` في الويب.
  List<Student> studentsOfRoom(Classroom room) => students.where((s) {
        if (!studentBelongsToRoom(s, room)) return false;
        if (room.academicYearId.isEmpty || s.academicYearId.isEmpty) return true;
        return s.academicYearId == room.academicYearId;
      }).toList();

  /// نقل طلاب شعبة إلى اسمها الجديد بعد تغييره — فقط طلاب تلك المرحلة/العام.
  void _renameStudentSection(Classroom room, String newName) {
    for (final s in studentsOfRoom(room)) {
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
        final candidates = student == null ? const <Classroom>[] : groupRooms.where((r) => studentBelongsToRoom(student, r)).toList();
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
      final oldRoom = Classroom(
        id: r.id,
        name: oldName,
        gradeLevel: r.gradeLevel,
        teacherId: r.teacherId,
        academicYearId: r.academicYearId,
      );
      _renameStudentSection(oldRoom, clean);
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

  /// إعادة ربط الطلاب الذين انفصل قسمهم عن اسم الصف بعد تعقيم خاطئ.
  ///
  /// تعيين المربي كان يعيد تنقية الاسم ويقطع القوس الختامي أو يترك عند الطالب
  /// شكلاً قديماً؛ المطابقة وحدها لا تُصلِح السحابة — نوحّد النص ونرفعه.
  Future<int> migrateOrphanedSections() async {
    if (db.settings[sectionOrphanRepairKey] == 'true') return 0;

    var changed = 0;
    final now = _nowIso();

    // 1) أسماء صفوف فسدت أو تحتاج إعادة تنقية بالمنطق الصحيح
    for (final r in List.of(rooms)) {
      if (r.gradeLevel.trim().isEmpty) continue;
      final clean = sanitizeSectionName(r.name, r.gradeLevel);
      if (clean.isEmpty || clean == r.name) continue;
      final oldName = r.name.trim();
      r.name = clean;
      r.updatedAt = now;
      r.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'rooms', recordId: r.id, action: 'UPDATE', payload: r.toCloud());
      _renameStudentSection(
        Classroom(
          id: r.id,
          name: oldName,
          gradeLevel: r.gradeLevel,
          teacherId: r.teacherId,
          academicYearId: r.academicYearId,
        ),
        clean,
      );
      changed++;
    }

    // 2) طلاب قسمهم لا يطابق أي صف حرفياً لكن يطابق بعد التنقية صفاً واحداً
    for (final s in students) {
      if (s.status == 'archived') continue;
      final section = s.section.trim();
      if (section.isEmpty) continue;

      final sameYear = (Classroom r) =>
          r.academicYearId.isEmpty || s.academicYearId.isEmpty || r.academicYearId == s.academicYearId;

      final exact = rooms.where((r) => sameYear(r) && studentBelongsToRoom(s, r)).toList();
      if (exact.length == 1) {
        final room = exact.first;
        if (s.section.trim() == room.name.trim()) continue;
        s.section = room.name;
        s.updatedAt = now;
        s.syncStatus = 'pending';
        queuePendingSync(pendingSyncs, tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
        changed++;
        continue;
      }
      if (exact.isNotEmpty) continue;

      final grade = s.gradeLevel.trim();
      final san = sanitizeSectionName(section, grade);
      if (san.isEmpty) continue;
      final candidates = rooms.where((r) {
        if (!sameYear(r)) return false;
        if (grade.isNotEmpty && r.gradeLevel.trim().isNotEmpty && !isSameGrade(grade, r.gradeLevel)) {
          return false;
        }
        final roomSan = sanitizeSectionName(r.name, r.gradeLevel);
        return isSameSectionName(san, r.name) || isSameSectionName(san, roomSan);
      }).toList();
      if (candidates.length != 1) continue;

      s.section = candidates.first.name;
      s.updatedAt = now;
      s.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'students', recordId: s.id, action: 'UPDATE', payload: s.toCloud());
      changed++;
    }

    if (changed > 0) {
      markDirty('rooms');
      markDirty('students');
      markDirty(_pendingTable);
      notifyListeners();
      scheduleAutoPush();
    }
    await db.setSetting(sectionOrphanRepairKey, 'true');
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
      for (final s in studentsOfRoom(room)) {
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
      if (f.academicYearId.isEmpty) f.academicYearId = gradeFees[i].academicYearId;
      gradeFees[i] = f;
    }
    _queue('grade_fees', f.id, 'UPDATE', f.toCloud());
  }

  void addGradeFee(GradeFee f, {String initialSection = ''}) {
    requireSection('settings');
    if (f.gradeName.trim().isEmpty) throw StoreException('يرجى إدخال اسم المرحلة أو الصف');
    if (f.monthlyFee < 0) throw StoreException('يرجى إدخال رسم شهري صحيح');
    if (f.academicYearId.isEmpty) f.academicYearId = viewedAcademicYearId;
    f.createdAt = _nowIso();
    f.updatedAt = _nowIso();
    f.syncStatus = 'pending';
    gradeFees.add(f);
    _queue('grade_fees', f.id, 'INSERT', f.toCloud());
    if (initialSection.trim().isNotEmpty) {
      upsertRoom(Classroom(
        id: newId(),
        name: initialSection.trim(),
        gradeLevel: f.gradeName,
        teacherId: '',
        capacity: 25,
        tier: f.tier,
        academicYearId: f.academicYearId,
      ));
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
    final before = users[i];
    final hadUsersAccess = _userCanManageUsers(before);
    final keepsUsersAccess = _userCanManageUsers(u);
    if (hadUsersAccess && !keepsUsersAccess) {
      final others = users.where((x) => x.id != u.id && _userCanManageUsers(x)).length;
      if (others == 0) {
        throw StoreException(
          'هذا آخر حساب يدير المستخدمين والصلاحيات. امنح الصلاحية لحساب آخر أولاً.',
        );
      }
    }
    u.updatedAt = _nowIso();
    u.syncStatus = 'pending';
    u.createdAt = before.createdAt;
    users[i] = u;
    _queue('users', u.id, 'UPDATE', u.toCloud());
  }

  void deleteUser(String id) {
    requireSection('settings.users');
    final target = users.where((u) => u.id == id).firstOrNull;
    if (target != null &&
        normalizeRole(target.role) == 'admin' &&
        target.isActive) {
      final admins = users.where((u) => normalizeRole(u.role) == 'admin' && u.isActive).length;
      if (admins <= 1) {
        throw StoreException('لا يمكن حذف آخر حساب مدير في النظام. عيّن مديراً آخر أولاً.');
      }
    }
    if (users.length <= 1) throw StoreException('لا يمكن حذف المستخدم الوحيد في النظام');
    users.removeWhere((u) => u.id == id);
    _queue('users', id, 'DELETE', null);
  }

  bool _userCanManageUsers(AppUser u) {
    if (!u.isActive) return false;
    return effectiveSections(u.capabilities, u.role).contains('settings.users');
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

    final name = (currentTenant?.ownerName.trim().isNotEmpty ?? false) ? currentTenant!.ownerName.trim() : (currentTenant?.name.trim() ?? '');
    final owner = AppUser(id: id, name: name.isEmpty ? 'مدير المنشأة' : name, role: 'admin', capabilities: [...allSections])
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

  Future<int> initialPull({PullProgressCallback? onProgress}) async {
    final tid = tenantId;
    if (tid == null) throw StoreException('لا توجد منشأة نشطة على هذا الجهاز.');
    if (!networkEnabled) {
      throw StoreException('لا يمكن تهيئة الجهاز دون اتصال بالإنترنت.');
    }
    final res = await sync.pullFromCloud(tid, onProgress: onProgress);
    cleanLocalDemoUsers();
    await hydrateInstitution();
    await settleAcademicYears();
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
  /// أخٌ مسجَّل لوليّ الأمر نفسه، بحثاً برقم هويته — مقابل `findSibling` في الويب.
  ///
  /// كلمة بوابة وليّ الأمر تُولَّد لكل طالب على حدة، فما لم يأخذ الأخ الثاني
  /// كلمة أخيه لم يدخل الأب إلا على أحدهما.
  Student? siblingByParentNationalId(String parentNationalId, {String? exclude}) {
    final clean = parentNationalId.trim();
    if (clean.isEmpty) return null;
    for (final s in students) {
      if (s.id == exclude) continue;
      if (s.parentPortalCode.trim().isEmpty) continue;
      if (s.parentNationalId.trim() != clean) continue;
      if (s.status != 'active' && s.status != 'pending') continue;
      return s;
    }
    return null;
  }

  List<AppUser> get setupCandidates {
    final active = users.where((u) => u.isActive).toList();
    // مدير المنشأة أولاً ودائماً، كقائمة الويب. كان يظهر فقط حين لا مستخدم
    // غيره، فجهازٌ سحب مستخدمي المدرسة لا يجد صاحبها نفسه ليُهيّئ به الجهاز.
    final owner = ensureOwnerAdmin();
    return [owner, ...active.where((u) => u.id != owner.id)];
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
    final tenantPass = (currentTenant?.password.trim().isNotEmpty ?? false) ? currentTenant!.password.trim() : _tenantPass.trim();
    return tenantPass.isNotEmpty && e == tenantPass;
  }

  /// تثبيت هوية الجهاز وإنهاء التهيئة.
  Future<void> completeInitialSetup(AppUser user) async {
    await setDeviceIdentity(user, user.name);
    final tid = tenantId;
    if (tid != null) await db.setSetting(initialSetupKey(tid), 'true');
    await db.setSetting(_kSetupPending, null);
    _setupPending = false;
    // إشعار الواجهة أولاً — زر الاستمرار لا ينتظر قرصاً ومزامنة ثقيلة
    notifyListeners();
    await flush();
    // ما تراكم أثناء التهيئة يُرفع بعد استقرار الشاشة الأولى
    resumeAutoSync();
  }

  /// استئناف المزامنة بعد أن تُغلق بوابة التهيئة.
  void resumeAutoSync() {
    if (!autoSync) {
      startAutoSync();
      return;
    }
    scheduleAutoPush(const Duration(milliseconds: 800));
    scheduleAutoPull(reconnectPullDelay);
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

  /// حارس أفعال المالية الحساسة؛ يُستدعى في الخدمة لا في الزر وحده.
  void requireFinanceAction(String action) {
    if (!financeActions.contains(action)) {
      throw StoreException('إجراء مالي غير معروف');
    }
    requireSection(action);
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

  /// تعديل علامة مرصودة أو حذفها — `userCanEditGrades`: المدير دائماً، ولمن مُنح `evaluations.edit`.
  bool get canEditGrades {
    final me = deviceUser;
    if (me == null) return true;
    if (!me.isActive) return false;
    if (normalizeRole(me.role) == 'admin') return true;
    return can('evaluations.edit');
  }

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

  static List<Map<String, dynamic>> _rows<T>(Iterable<T> items, Map<String, dynamic> Function(T) cloud, String Function(T) status) => [
    for (final e in items) _row(cloud(e), status(e)),
  ];

  // ── بحث بالمعرّف لسجلات الحفظ ─────────────────────────────────────────────
  //
  // حفظ سجلٍّ واحد على القرص كان يبحث عنه بمسح الجدول كله: رصدُ حضورٍ يمسح
  // خمسين ألفاً، و«الكل حاضر» لشعبة يمسحها مرة لكل طالب. الفهرس هنا يُتحقّق منه
  // عند كل استعمال — السجل في موضعه يحمل المعرّف نفسه — فإن تغيّر الجدول من
  // مسارٍ آخر أُعيد بناؤه، ولا تُعاد نتيجة قديمة أبداً.
  final _idIndexes = <String, ({Object list, Map<String, int> map})>{};

  T? _byId<T>(String table, List<T> list, String id, String Function(T) idOf) {
    final cached = _idIndexes[table];
    if (cached != null && identical(cached.list, list)) {
      final i = cached.map[id];
      if (i != null && i < list.length && idOf(list[i]) == id) return list[i];
    }
    // الفهرس قديم أو غائب أو السجل ليس فيه: بناءٌ واحد ثم حكمٌ نهائي
    final map = <String, int>{for (var i = 0; i < list.length; i++) idOf(list[i]): i};
    _idIndexes[table] = (list: list, map: map);
    final i = map[id];
    return i == null ? null : list[i];
  }

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
        final e = _byId('subjects', subjects, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'rooms':
        final e = _byId('rooms', rooms, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'grade_fees':
        final e = _byId('grade_fees', gradeFees, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'users':
        final e = _byId('users', users, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'payments':
        final e = _byId('payments', payments, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'installments':
        final e = _byId('installments', installments, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'attendance':
        final e = _byId('attendance', attendance, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'tenants':
        return tenants.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'groups':
        final e = _byId('groups', groups, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'enrollments':
        final e = _byId('enrollments', enrollments, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'sessions':
        final e = _byId('sessions', sessions, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'academic_years':
        final e = _byId('academic_years', academicYears, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'student_years':
        final e = _byId('student_years', studentYears, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'finance_requests':
        final e = _byId('finance_requests', financeRequests, id, (e) => e.id);
        return e == null ? null : _row(e.toCloud(), e.syncStatus);
      case 'audit_log':
        final e = _byId('audit_log', financeAudit, id, (e) => e.id);
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
      case 'academic_years':
        return _rows(academicYears, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'student_years':
        return _rows(studentYears, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'finance_requests':
        return _rows(financeRequests, (e) => e.toCloud(), (e) => e.syncStatus);
      case 'audit_log':
        return _rows(financeAudit, (e) => e.toCloud(), (e) => e.syncStatus);
      default:
        return extraCloud[table] ?? [];
    }
  }

  /// خرائط المعرّفات لكل جدول بين دفعات السحب، مع ختم الجدول بعد آخر دفعة.
  ///
  /// كانت الخريطة تُبنى للجدول كله مع كل دفعة: السحب الأول لخمسين ألف رصدٍ على
  /// دفعات من 1500 يبني ملايين المداخل على خيط الواجهة. تُعاد الآن ما دام لم
  /// يمسّ الجدولَ مسارٌ آخر بين دفعتين — كل تعديل آخر يمرّ على ختمه فيُسقطها.
  final _putIndex = <String, ({Object list, Map<String, int> map, int rev})>{};

  /// قائمة الجدول ومستخرج معرّفه — لبناء خريطة المعرّفات خارج `putRows`.
  (List<Object?>, String Function(Object?))? _listFor(String table) {
    String idOfModel(Object? e) => (e as dynamic).id as String;
    return switch (table) {
      'students' => (students, idOfModel),
      'teachers' => (teachers, idOfModel),
      'subjects' => (subjects, idOfModel),
      'rooms' => (rooms, idOfModel),
      'grade_fees' => (gradeFees, idOfModel),
      'users' => (users, idOfModel),
      'payments' => (payments, idOfModel),
      'installments' => (installments, idOfModel),
      'attendance' => (attendance, (e) => (e as AttendanceMark).id),
      'groups' => (groups, idOfModel),
      'enrollments' => (enrollments, idOfModel),
      'sessions' => (sessions, idOfModel),
      'academic_years' => (academicYears, idOfModel),
      'student_years' => (studentYears, idOfModel),
      'finance_requests' => (financeRequests, idOfModel),
      'audit_log' => (financeAudit, idOfModel),
      _ => null,
    };
  }

  /// خريطة المعرّفات تُبنى قبل أول دفعة، على شرائح بينها فرصٌ للرسم.
  ///
  /// كانت تُبنى داخل أول `putRows` دفعةً واحدة: جدول حضورٍ بخمسين ألف سجل
  /// يوقف الإطار عشرات الميلي ثانية في أول كل مزامنة. إن تغيّر الجدول أثناء
  /// البناء أُعيد من أوله، فلا تُحفظ خريطةٌ لا تطابق ما في الذاكرة.
  @override
  Future<void> prepareApply(String table) async {
    final entry = _listFor(table);
    if (entry == null) return;
    final (list, idOf) = entry;
    final cached = _putIndex[table];
    if (cached != null &&
        identical(cached.list, list) &&
        cached.rev == tableRev(table) &&
        cached.map.length == list.length) {
      return; // صالحة من المزامنة السابقة
    }

    const slice = 500;
    for (var attempt = 0; attempt < 3; attempt++) {
      final rev = tableRev(table);
      final map = <String, int>{};
      var aborted = false;
      for (var i = 0; i < list.length; i++) {
        map[idOf(list[i])] = i;
        if ((i + 1) % slice == 0) {
          await Future<void>.delayed(Duration.zero);
          if (tableRev(table) != rev || !identical(list, _listFor(table)?.$1)) {
            aborted = true; // عُدّل الجدول أثناء البناء: من جديد
            break;
          }
        }
      }
      if (aborted) continue;
      if (tableRev(table) != rev) continue;
      _putIndex[table] = (list: list, map: map, rev: rev);
      return;
    }
    // جدولٌ لا يهدأ: تبنيها أول دفعة كما كانت
  }

  @override
  void putRows(String table, List<Map<String, dynamic>> rows) {
    loadedTables.add(table);
    final revBefore = tableRev(table);
    // فهارس الحضور صالحة الآن؟ إذاً تُرقَّع بالصفوف الواصلة بدل بنائها من جديد
    // الجلسات تُعاد فهرستها كاملةً: تغيّر تاريخ جلسة أو شعبتها يترك مفاتيح قديمة
    final marksValid = table == 'attendance' && _indexRev == _markStamp;
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

    // ما استُبدل وما أُضيف من أرصدة — لترقيع فهارسها
    final replacedMarks = <AttendanceMark>[];
    final touchedMarks = <AttendanceMark>[];

    // خريطة id→فهرس: كان indexWhere لكل صف يصير O(n²) عند سحب آلاف الطلاب
    void upsertList<T>(
      List<T> list,
      T Function(Map<String, dynamic>) parse,
      String Function(T) idOf,
      void Function(int, T) setAt,
      void Function(T) add,
    ) {
      final cached = _putIndex[table];
      final trusted = cached != null &&
          identical(cached.list, list) &&
          cached.rev == revBefore &&
          cached.map.length == list.length;
      final indexById = trusted
          ? cached.map
          : <String, int>{for (var i = 0; i < list.length; i++) idOf(list[i]): i};
      for (final r in rows) {
        final item = parse(r);
        final id = idOf(item);
        final i = indexById[id];
        if (i != null) {
          final old = list[i];
          if (old is AttendanceMark) replacedMarks.add(old);
          setAt(i, item);
        } else {
          indexById[id] = list.length;
          add(item);
        }
        if (item is AttendanceMark) touchedMarks.add(item);
      }
      _putIndex[table] = (list: list, map: indexById, rev: tableRev(table));
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
      case 'academic_years':
        upsertList(academicYears, AcademicYear.fromCloud, (e) => e.id, (i, e) => academicYears[i] = e, academicYears.add);
      case 'student_years':
        upsertList(studentYears, StudentYear.fromCloud, (e) => e.id, (i, e) => studentYears[i] = e, studentYears.add);
      case 'finance_requests':
        upsertList(financeRequests, FinanceRequest.fromCloud, (e) => e.id, (i, e) => financeRequests[i] = e, financeRequests.add);
      case 'audit_log':
        upsertList(financeAudit, FinanceAuditEntry.fromCloud, (e) => e.id, (i, e) => financeAudit[i] = e, financeAudit.add);
      default:
        final bucket = extraCloud.putIfAbsent(table, () => []);
        final indexById = <String, int>{
          for (var i = 0; i < bucket.length; i++) '${bucket[i]['id']}': i,
        };
        for (final r in rows) {
          final id = '${r['id']}';
          final i = indexById[id];
          if (i != null) {
            bucket[i] = r;
          } else {
            indexById[id] = bucket.length;
            bucket.add(r);
          }
        }
    }

    _keepIndexes(marksValid, () {
      for (final old in replacedMarks) {
        _unindexMark(old);
      }
      for (final m in touchedMarks) {
        _indexMark(m);
      }
    });
  }

  /// إلحاق تاريخ الجلسة بكل سجل حضور قادم من السحابة.
  List<Map<String, dynamic>> _withSessionDates(List<Map<String, dynamic>> rows) {
    final byId = {for (final s in sessions) s.id: s.sessionDate};
    return [
      for (final r in rows)
        if ('${r['session_date'] ?? ''}'.isNotEmpty) r else if (byId['${r['session_id'] ?? ''}'] case final d?) {...r, 'session_date': d} else r,
    ];
  }

  @override
  void removeIds(String table, List<String> ids) {
    if (ids.isEmpty) return;
    // جدول مؤجّل غير محمّل: احذف من القرص فقط
    if (deferredTables.contains(table) && !loadedTables.contains(table)) {
      forgetServerStamps(table, ids);
      unawaited(db.deleteRecords(table, ids));
      return;
    }
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
      case 'academic_years':
        academicYears.removeWhere((e) => set.contains(e.id));
      case 'student_years':
        studentYears.removeWhere((e) => set.contains(e.id));
      case 'finance_requests':
        financeRequests.removeWhere((e) => set.contains(e.id));
      case 'audit_log':
        financeAudit.removeWhere((e) => set.contains(e.id));
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
      case 'academic_years':
        stamp(academicYears.where((e) => e.id == id).firstOrNull);
      case 'student_years':
        stamp(studentYears.where((e) => e.id == id).firstOrNull);
      case 'finance_requests':
        stamp(financeRequests.where((e) => e.id == id).firstOrNull);
      case 'audit_log':
        stamp(financeAudit.where((e) => e.id == id).firstOrNull);
    }
  }

  @override
  Future<void> onPulled() async {
    await hydrateInstitution();
    await settleAcademicYears();
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope missing');
    return scope!.notifier!;
  }
}
