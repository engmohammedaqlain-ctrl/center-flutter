import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'institution.dart';
import 'local_db.dart';
import 'permissions.dart';
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

  bool loggedIn = false;
  bool isMasterAdmin = false;
  String institutionName = '';
  String roleName = 'مدير النظام';
  Tenant? currentTenant;

  @override
  final pendingSyncs = <PendingSync>[];
  /// جداول تُزامَن كما هي دون نموذج مخصّص بعد.
  final extraCloud = <String, List<Map<String, dynamic>>>{
    'teacher_payouts': [],
    'expenses': [],
    'cashbox_shifts': [],
    'institution_settings': [],
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

  void markDirty(String table) {
    if (_loading) return;
    _dirty.add(table);
    _scheduleFlush();
  }

  void markAllDirty() {
    if (_loading) return;
    _dirty
      ..addAll(ownedTables)
      ..addAll(extraCloud.keys)
      ..add(_pendingTable);
    _scheduleFlush();
  }

  static const _pendingTable = '__pending_syncs';

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
    if (_dirty.isEmpty) return;
    final tables = _dirty.toList();
    _dirty.clear();
    for (final t in tables) {
      await db.saveTable(t, _rowsForPersist(t));
    }
  }

  List<Map<String, dynamic>> _rowsForPersist(String table) {
    if (table == _pendingTable) {
      return [
        for (var i = 0; i < pendingSyncs.length; i++) {'id': '$i', ...pendingSyncs[i].toJson()},
      ];
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
        if (entry.key == _pendingTable) {
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
    } finally {
      _loading = false;
    }
    await _resolveSetupGate();
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

  String get lastUsername => db.settings[_kLastUsername] ?? '';

  void _restoreSession() {
    final s = db.settings;
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
    roleName = me == null ? 'مدير النظام' : roleLabel(me.role);
  }

  Future<void> _saveSession() async {
    await db.setSetting(_kLoggedIn, loggedIn ? 'true' : null);
    await db.setSetting(_kMasterAdmin, isMasterAdmin ? 'true' : null);
    await db.setSetting(_kTenantId, currentTenant?.id);
  }

  // ── إعدادات المنشأة (المقابل لـ institution.ts) ─────────────────────────────
  String get institutionType => db.settings[institutionTypeKey] ?? 'school';
  bool get isSchool => institutionType == 'school';

  String get institutionLogo => db.settings[institutionLogoKey] ?? '';

  InstitutionColors get institutionColors {
    final raw = db.settings[institutionColorsKey];
    if (raw == null || raw.isEmpty) return InstitutionColors.defaults;
    try {
      return InstitutionColors.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return InstitutionColors.defaults;
    }
  }

  /// رسم حجز المقعد. قيمته الافتراضية 0 حتى تعتمد الإدارة رقماً صراحةً —
  /// تثبيته بـ 50 في الكود قاعدة عمل مخترعة.
  double get seatReservationFee {
    final n = double.tryParse(db.settings[seatReservationFeeKey] ?? '');
    return n == null || n < 0 ? 0 : n;
  }

  Future<void> setSeatReservationFee(double value) async {
    await db.setSetting(seatReservationFeeKey, '${value < 0 ? 0 : value}');
    notifyListeners();
  }

  Future<void> saveInstitution({
    String? type,
    String? name,
    String? logo,
    InstitutionColors? colors,
  }) async {
    if (type != null) await db.setSetting(institutionTypeKey, type);
    if (name != null) {
      institutionName = name.trim();
      await db.setSetting(institutionNameKey, institutionName.isEmpty ? null : institutionName);
    }
    if (logo != null) await db.setSetting(institutionLogoKey, logo.isEmpty ? null : logo);
    if (colors != null) await db.setSetting(institutionColorsKey, jsonEncode(colors.toMap()));
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
      'institution_type': institutionType,
      'institution_name': institutionName,
      'logo': institutionLogo.isEmpty ? null : institutionLogo,
      'colors': institutionColors.toMap(),
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
    final type = '${row['institution_type'] ?? ''}'.trim();
    final logo = row['logo'];
    final colors = row['colors'];
    if (type.isNotEmpty) await db.setSetting(institutionTypeKey, type);
    if (name.isNotEmpty) {
      institutionName = name;
      await db.setSetting(institutionNameKey, name);
    }
    if (logo is String && logo.isNotEmpty) await db.setSetting(institutionLogoKey, logo);
    if (colors is Map) {
      await db.setSetting(institutionColorsKey, jsonEncode(Map<String, dynamic>.from(colors)));
    }
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
  bool get isMaster => isMasterAdmin;

  int get pendingPush {
    cleanupBogusDemoUserSyncs(pendingSyncs);
    return pendingSyncs.length;
  }

  int get pendingPull => sync.remotePendingCount;

  List<SyncRow> get pendingRows => sync.getPendingSummary().rows;

  String newId() => _uuid.v4();

  /// تسجيل الدخول — مطابق لتسلسل `LandingPage.handleLogin`:
  /// 1) حساب المطور، 2) المنشآت من السحابة، 3) المنشأة المحفوظة على الجهاز.
  Future<String?> login(String username, String password) async {
    final u = username.trim().toLowerCase();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) {
      return 'أدخل اسم المستخدم وكلمة المرور';
    }

    await db.setSetting(_kLastUsername, username.trim());

    if (u == TenantService.masterUsername && p == TenantService.masterPassword) {
      loggedIn = true;
      isMasterAdmin = true;
      currentTenant = null;
      roleName = 'المطور العام';
      await _saveSession();
      await refreshTenantsFromCloud();
      notifyListeners();
      return null;
    }

    // تحديث القائمة من السحابة قبل المطابقة، وإلا بقي الجهاز على نسخة قديمة
    await refreshTenantsFromCloud();

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
    if (!networkEnabled) return;
    await primeReceiptCounter();
    await sync.checkRemoteChanges();
    await startRealtime();
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
      onChange: (table) {
        // وصول تغيير من جهاز آخر: نُحدِّث عدّاد السحب ونُخطر الشاشات
        unawaited(_onRemoteChange(table));
      },
    );
    await _realtime!.connect(tid);
  }

  Future<void> stopRealtime() async {
    await _realtime?.disconnect();
    _realtime = null;
  }

  DateTime _lastRemotePoke = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _onRemoteChange(String table) async {
    // تجميع الأحداث المتلاحقة بدل استعلام لكل صف
    final now = DateTime.now();
    if (now.difference(_lastRemotePoke).inMilliseconds < 1200) return;
    _lastRemotePoke = now;
    await sync.checkRemoteChanges();
    notifyListeners();
  }

  Future<void> _enterTenant(Tenant tenant) async {
    loggedIn = true;
    isMasterAdmin = false;
    currentTenant = tenant;
    _tenantUser = tenant.username;
    _tenantPass = tenant.password;
    await db.setSetting(_kCustomUser, tenant.username);
    await db.setSetting(_kCustomPass, tenant.password);
    // اسم العرض يُكتب مرة واحدة: لو خصّصه المدير فلا يُدهس عند كل دخول
    if (institutionName.trim().isEmpty) {
      institutionName = tenant.name;
      await db.setSetting(institutionNameKey, tenant.name);
    }
    final me = deviceUserId == null ? null : users.where((x) => x.id == deviceUserId).firstOrNull;
    roleName = me == null ? 'مدير النظام' : roleLabel(me.role);
    await _saveSession();
    await hydrateInstitution();
    await _resolveSetupGate(freshLogin: true);
    await afterEnter();
    notifyListeners();
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
    await stopRealtime();
    loggedIn = false;
    isMasterAdmin = false;
    currentTenant = null;
    _setupPending = false;
    await _saveSession();
    notifyListeners();
  }

  Student? studentById(String id) {
    for (final s in students) {
      if (s.id == id) return s;
    }
    return null;
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

  List<Student> studentsOf(Classroom room) {
    return students.where((s) {
      final g = (s.gradeLevel).trim();
      final r = (room.gradeLevel).trim();
      if (g.isNotEmpty && r.isNotEmpty && g != r) return false;
      final sec = s.section.trim();
      final name = room.name.trim();
      return sec == name || sec.contains(name) || name.contains(sec);
    }).toList();
  }

  String? attendanceOf(String studentId, String date) {
    for (final a in attendance) {
      if (a.studentId == studentId && a.date == date) return a.status;
    }
    return null;
  }

  /// حالة الحضور لطالب في تاريخ ضمن صف/مجموعة محددة.
  /// يمر عبر الجلسة كما في النسخة المكتبية بدل مطابقة التاريخ وحده.
  String? attendanceInSession(String ownerId, String studentId, String date) {
    final session = sessions
        .where((s) => s.sessionDate == date && (s.groupId == ownerId || s.roomId == ownerId))
        .firstOrNull;
    if (session == null) return attendanceOf(studentId, date);
    final rec = attendance
        .where((a) => a.studentId == studentId && (a.sessionId == session.id || a.date == date))
        .firstOrNull;
    return rec?.status;
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  void _queue(String table, String recordId, String action, Map<String, dynamic>? payload) {
    queuePendingSync(
      pendingSyncs,
      tableName: table,
      recordId: recordId,
      action: action,
      payload: payload,
    );
    markDirty(table);
    markDirty(_pendingTable);
    notifyListeners();
  }

  /// رصد حالة محددة لطالب في يوم. `null` يمسح الرصد.
  /// [ownerId] هو معرّف الصف (نظام مدرسة) أو المجموعة (نظام مركز).
  void setAttendance(String studentId, String date, String? status, {String? ownerId}) {
    final sessionId = ownerId == null ? '' : sessionFor(ownerId, date, school: isSchool).id;
    final existing = attendance
        .where((a) => a.studentId == studentId && (a.date == date))
        .firstOrNull;

    if (status == null) {
      if (existing != null) {
        attendance.remove(existing);
        _queue('attendance', existing.id, 'DELETE', null);
      }
      return;
    }

    if (existing != null) {
      existing.status = status;
      existing.markedByUserId = currentUserId;
      if (sessionId.isNotEmpty) existing.sessionId = sessionId;
      existing.updatedAt = _nowIso();
      existing.syncStatus = 'pending';
      _queue('attendance', existing.id, 'UPDATE', existing.toCloud());
      return;
    }

    final mark = AttendanceMark(
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
    final current = ownerId == null
        ? attendanceOf(studentId, date)
        : attendanceInSession(ownerId, studentId, date);
    final next = switch (current) {
      null => 'absent',
      'absent' => 'present',
      _ => null,
    };
    setAttendance(studentId, date, next, ownerId: ownerId);
  }

  void markAllPresent(String date, List<Student> list, {String? ownerId}) {
    if (list.isEmpty) return;
    final sessionId = ownerId == null ? '' : sessionFor(ownerId, date, school: isSchool).id;
    for (final s in list) {
      final existing = attendance.where((a) => a.studentId == s.id && a.date == date).firstOrNull;
      if (existing != null) {
        existing.status = 'present';
        existing.markedByUserId = currentUserId;
        if (sessionId.isNotEmpty) existing.sessionId = sessionId;
        existing.updatedAt = _nowIso();
        existing.syncStatus = 'pending';
        queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: existing.id, action: 'UPDATE', payload: existing.toCloud());
        continue;
      }
      final mark = AttendanceMark(
        studentId: s.id,
        date: date,
        status: 'present',
        sessionId: sessionId,
        markedByUserId: currentUserId,
        syncStatus: 'pending',
        createdAt: _nowIso(),
        updatedAt: _nowIso(),
      );
      attendance.add(mark);
      queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: mark.id, action: 'INSERT', payload: mark.toCloud());
    }
    markDirty('attendance');
    markDirty(_pendingTable);
    notifyListeners();
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
      incoming.balance = students[i].balance;
      incoming.createdAt = students[i].createdAt ?? incoming.createdAt;
      students[i] = incoming;
      _queue('students', incoming.id, 'UPDATE', incoming.toCloud());
    } else {
      incoming.createdAt ??= _nowIso();
      // رسم حجز المقعد يُقرأ من الإعدادات ولا يُقيَّد إن لم تعتمد الإدارة قيمة له.
      // لا تُولَّد أقساط تلقائياً: النسخة المكتبية تُنشئ الأقساط فقط إن مُرِّرت
      // صراحةً، والطالب الجديد يبدأ برصيد صفر.
      if (incoming.seatReservationPaid) {
        incoming.balance = incoming.balance + seatReservationFee;
      }
      students.insert(0, incoming);
      _queue('students', incoming.id, 'INSERT', incoming.toCloud());
    }

    if (attachments != null) {
      final existed = attachmentsByStudent.containsKey(incoming.id);
      final hasAny = !attachments.isEmpty;
      if (!hasAny) {
        if (existed) {
          attachmentsByStudent.remove(incoming.id);
          _queue('student_attachments', incoming.id, 'DELETE', null);
          markDirty('student_attachments');
        }
      } else {
        attachments.updatedAt = _nowIso();
        attachments.syncStatus = 'pending';
        attachmentsByStudent[incoming.id] = attachments;
        _queue('student_attachments', incoming.id, existed ? 'UPDATE' : 'INSERT', attachments.toCloud());
        markDirty('student_attachments');
      }
    }
    markDirty('students');
  }

  /// حذف طالب مع كل ما يتبعه.
  ///
  /// السندات المالية لا تُحذف ولا تُترك يتيمة: وجود سند قبض غير ملغى يمنع الحذف،
  /// لأن سجل القبض المالي لا يُمحى بحذف صاحبه. مطابق لـ `StudentsService.delete`.
  void deleteStudent(String id) {
    final active = payments.where((p) => p.studentId == id && !p.cancelled).length;
    if (active > 0) {
      throw StoreException(
        'لا يمكن حذف هذا الطالب لأن عليه $active سند قبض مسجَّل. '
        'يمكنك تغيير حالته إلى "منسحب" للاحتفاظ بالسجل المالي، أو إلغاء السندات أولاً.',
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
    if (attachmentsByStudent.remove(id) != null) {
      queuePendingSync(pendingSyncs, tableName: 'student_attachments', recordId: id, action: 'DELETE', payload: null);
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
    if (amount <= 0) throw StoreException('يرجى إدخال مبلغ صحيح');
    final stu = studentById(studentId);
    if (stu == null) throw StoreException('يرجى اختيار الطالب أولاً');

    final totalDue = stu.balance < 0 ? stu.balance.abs() : 0.0;
    stu.balance += amount;
    stu.updatedAt = _nowIso();
    stu.syncStatus = 'pending';
    final remaining = stu.balance < 0 ? stu.balance.abs() : 0.0;

    if (installmentId != null) {
      for (final inst in installments) {
        if (inst.id == installmentId) {
          inst.paidAmount += amount;
          inst.refreshStatus();
          inst.updatedAt = _nowIso();
          inst.syncStatus = 'pending';
          queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'UPDATE', payload: inst.toCloud());
          markDirty('installments');
        }
      }
    }

    final p = Payment(
      id: newId(),
      receiptNumber: _nextReceipt(),
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
      remainingAfter: remaining == 0 && totalDue == 0 ? 0 : remaining,
      totalDueAtPayment: totalDue,
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    payments.insert(0, p);
    queuePendingSync(pendingSyncs, tableName: 'payments', recordId: p.id, action: 'INSERT', payload: p.toCloud());
    queuePendingSync(pendingSyncs, tableName: 'students', recordId: stu.id, action: 'UPDATE', payload: stu.toCloud());
    markDirty('payments');
    markDirty('students');
    markDirty(_pendingTable);
    notifyListeners();
    return p;
  }

  void cancelPayment(Payment p, [String reason = 'ملغاة من قبل الإدارة']) {
    if (p.cancelled) return;
    p.cancelled = true;
    p.cancelReason = reason;
    p.updatedAt = _nowIso();
    p.syncStatus = 'pending';
    final stu = studentById(p.studentId);
    if (stu != null) {
      stu.balance -= p.amount;
      stu.updatedAt = _nowIso();
      stu.syncStatus = 'pending';
      queuePendingSync(pendingSyncs, tableName: 'students', recordId: stu.id, action: 'UPDATE', payload: stu.toCloud());
    }
    if (p.installmentId != null) {
      for (final inst in installments) {
        if (inst.id == p.installmentId) {
          final next = inst.paidAmount - p.amount;
          inst.paidAmount = next < 0 ? 0 : next;
          inst.refreshStatus();
          inst.updatedAt = _nowIso();
          inst.syncStatus = 'pending';
          queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'UPDATE', payload: inst.toCloud());
          markDirty('installments');
        }
      }
    }
    _queue('payments', p.id, 'UPDATE', p.toCloud());
    markDirty('students');
  }

  List<DueItem> dueItems() {
    final today = dateOnly(DateTime.now());
    final list = <DueItem>[];
    final withInst = <String>{};

    for (final inst in installments) {
      if (inst.isPaid) continue;
      final student = studentById(inst.studentId);
      if (student == null) continue;
      withInst.add(student.id);
      final late = dateOnly(inst.dueDate).isBefore(today);
      list.add(
        DueItem(
          id: inst.id,
          student: student,
          title: inst.title,
          amount: inst.remaining,
          dueDate: inst.dueDate,
          late: late,
          exception: inst.exception || student.hasException,
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
          exception: s.hasException,
        ),
      );
    }

    list.sort((a, b) {
      if (a.exception && !b.exception) return 1;
      if (!a.exception && b.exception) return -1;
      return a.dueDate.compareTo(b.dueDate);
    });
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

  /// حذف مجموعة. التسجيلات القائمة تمنع الحذف حتى لا تُترك يتيمة.
  void deleteGroup(String id) {
    final active = enrollmentCount(id);
    if (active > 0) {
      throw StoreException(
        'لا يمكن حذف هذه المجموعة لأن بها $active طالباً مسجَّلاً. '
        'ألغِ تسجيل الطلاب أولاً، أو غيّر حالة المجموعة إلى "مؤرشفة".',
      );
    }
    for (final e in enrollments.where((e) => e.groupId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'enrollments', recordId: e.id, action: 'DELETE', payload: null);
    }
    for (final sess in sessions.where((s) => s.groupId == id)) {
      queuePendingSync(pendingSyncs, tableName: 'sessions', recordId: sess.id, action: 'DELETE', payload: null);
    }
    enrollments.removeWhere((e) => e.groupId == id);
    sessions.removeWhere((s) => s.groupId == id);
    groups.removeWhere((g) => g.id == id);
    _queue('groups', id, 'DELETE', null);
    markDirty('enrollments');
    markDirty('sessions');
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
    return enrollment;
  }

  void updateEnrollmentStatus(String enrollmentId, String status) {
    final e = enrollments.where((x) => x.id == enrollmentId).firstOrNull;
    if (e == null) return;
    e.status = status;
    e.updatedAt = _nowIso();
    e.syncStatus = 'pending';
    _queue('enrollments', e.id, 'UPDATE', e.toCloud());
  }

  void deleteEnrollment(String enrollmentId) {
    final linked = payments.where((p) => p.enrollmentId == enrollmentId && !p.cancelled).length;
    if (linked > 0) {
      throw StoreException(
        'لا يمكن إلغاء هذا التسجيل لأن عليه $linked سند قبض مسجَّل. ألغِ السندات أولاً.',
      );
    }
    enrollments.removeWhere((e) => e.id == enrollmentId);
    _queue('enrollments', enrollmentId, 'DELETE', null);
  }

  // ── الجلسات (المقابل لـ attendance.service.ts) ──────────────────────────────

  /// إيجاد جلسة لتاريخ ومجموعة/قاعة، أو إنشاؤها.
  ClassSession sessionFor(String ownerId, String dateStr, {bool school = true}) {
    final found = sessions
        .where((s) => s.sessionDate == dateStr && (s.groupId == ownerId || s.roomId == ownerId))
        .firstOrNull;
    if (found != null) return found;

    final group = school ? null : groupById(ownerId);
    final created = ClassSession(
      id: newId(),
      groupId: ownerId,
      sessionDate: dateStr,
      startTime: group?.startTime ?? '08:00',
      endTime: group?.endTime ?? '10:00',
      teacherId: group?.teacherId ?? '',
      roomId: school ? ownerId : (group?.roomId ?? ''),
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

  void deleteTeacher(String id) {
    teachers.removeWhere((t) => t.id == id);
    _queue('teachers', id, 'DELETE', null);
  }

  void upsertSubject(SubjectItem s) {
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

  void deleteSubject(String id) {
    subjects.removeWhere((s) => s.id == id);
    _queue('subjects', id, 'DELETE', null);
  }

  void upsertRoom(Classroom r) {
    if (r.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم الصف / الشعبة');
    r.updatedAt = _nowIso();
    r.syncStatus = 'pending';
    final i = rooms.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      r.createdAt = rooms[i].createdAt;
      rooms[i] = r;
      _queue('rooms', r.id, 'UPDATE', r.toCloud());
    } else {
      r.createdAt = _nowIso();
      rooms.add(r);
      _queue('rooms', r.id, 'INSERT', r.toCloud());
    }
  }

  void deleteRoom(String id) {
    rooms.removeWhere((r) => r.id == id);
    _queue('rooms', id, 'DELETE', null);
  }

  void updateGradeFee(GradeFee f) {
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
    final count = students.where((s) => s.gradeLevel.trim().toLowerCase() == f.gradeName.trim().toLowerCase()).length;
    if (count > 0) {
      throw StoreException(
        'لا يمكن حذف مرحلة "${f.gradeName}" لوجود ($count) طالب مسجلين بها حالياً.\nيرجى نقل أو تعديل مراحل هؤلاء الطلاب أولاً قبل حذف المرحلة الدراسية.',
      );
    }
    gradeFees.removeWhere((e) => e.id == f.id);
    _queue('grade_fees', f.id, 'DELETE', null);
  }

  void updateUser(AppUser u) {
    final i = users.indexWhere((e) => e.id == u.id);
    if (i < 0) return;
    u.updatedAt = _nowIso();
    u.syncStatus = 'pending';
    u.createdAt = users[i].createdAt;
    users[i] = u;
    _queue('users', u.id, 'UPDATE', u.toCloud());
  }

  void deleteUser(String id) {
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
    if (db.settings[initialSetupKey(tid)] == 'true') {
      _setupPending = false;
      return;
    }
    // جهاز يحمل بيانات محلية من قبل هذه الميزة يُعتبر مهيَّأً
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
      capabilities: [...allCapabilities],
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

  /// المستخدمون النشطون المتاحون لاختيار هوية الجهاز.
  List<AppUser> get setupCandidates {
    final active = users.where((u) => u.isActive).toList();
    if (active.isEmpty) return [ensureOwnerAdmin()];
    return active;
  }

  /// كلمات المرور المقبولة لتثبيت صلاحية مدير على هذا الجهاز.
  /// مطابق لشرط `handleFinishSetup`: كلمة المنشأة أو المفتاح العام أو المطور.
  bool isAdminSetupPasswordValid(String entered) {
    final e = entered.trim();
    if (e.isEmpty) return false;
    final tenantPass = (currentTenant?.password.trim().isNotEmpty ?? false)
        ? currentTenant!.password.trim()
        : _tenantPass.trim();
    return e == 'school2026' || e == TenantService.masterPassword || (tenantPass.isNotEmpty && e == tenantPass);
  }

  /// تثبيت هوية الجهاز وإنهاء التهيئة.
  Future<void> completeInitialSetup(AppUser user) async {
    await setDeviceIdentity(user, user.name);
    final tid = tenantId;
    if (tid != null) await db.setSetting(initialSetupKey(tid), 'true');
    _setupPending = false;
    await flush();
    notifyListeners();
  }

  /// إعادة فتح التهيئة (لتغيير هوية الجهاز لاحقاً من الإعدادات).
  Future<void> resetInitialSetup() async {
    final tid = tenantId;
    if (tid != null) await db.setSetting(initialSetupKey(tid), null);
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

  /// الصلاحيات الفعلية للمستخدم المثبَّت على هذا الجهاز.
  ///
  /// الجهاز الذي لم تُثبَّت عليه هوية بعد يعمل بصلاحية المدير الكاملة — وهو
  /// السلوك نفسه في النسخة المكتبية قبل أن يختار المدير حساباً للجهاز.
  List<String> get myCapabilities {
    final me = deviceUser;
    if (me == null) return defaultCapsFor('admin');
    if (!me.isActive) return const [];
    return effectiveCapabilities(me.capabilities, me.role);
  }

  /// هل يملك مستخدم هذا الجهاز هذه القدرة؟ الحساب الموقوف لا يملك شيئاً.
  bool can(String capability) => myCapabilities.contains(capability);

  /// هل يستطيع فتح هذا القسم؟
  bool canOpenSection(String section) {
    final needed = sectionCapability[section];
    return needed == null || can(needed);
  }

  /// اسم المستلم على سند القبض — مطابق لـ `getReceiptReceiverLabel()`.
  String get receiptReceiver {
    if (receiptReceiverLabel.trim().isNotEmpty) return receiptReceiverLabel.trim();
    return deviceUser?.name ?? 'موظف الاستقبال';
  }

  void addUser(AppUser u) {
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
    notifyListeners();
  }

  void deleteTenant(String id) {
    tenants.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  Map<String, dynamic>? recordOf(String table, String id) {
    switch (table) {
      case 'students':
        return studentById(id)?.toCloud();
      case 'student_attachments':
        return attachmentsByStudent[id]?.toCloud();
      case 'teachers':
        return teacherById(id)?.toCloud();
      case 'subjects':
        return subjects.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'rooms':
        return rooms.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'grade_fees':
        return gradeFees.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'users':
        return users.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'payments':
        return payments.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'installments':
        return installments.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'attendance':
        return attendance.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'groups':
        return groups.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'enrollments':
        return enrollments.where((e) => e.id == id).firstOrNull?.toCloud();
      case 'sessions':
        return sessions.where((e) => e.id == id).firstOrNull?.toCloud();
      default:
        return extraCloud[table]?.where((e) => '${e['id']}' == id).firstOrNull;
    }
  }

  @override
  List<Map<String, dynamic>> allOf(String table) {
    switch (table) {
      case 'students':
        return students.map((e) => e.toCloud()).toList();
      case 'student_attachments':
        return attachmentsByStudent.values.map((e) => e.toCloud()).toList();
      case 'teachers':
        return teachers.map((e) => e.toCloud()).toList();
      case 'subjects':
        return subjects.map((e) => e.toCloud()).toList();
      case 'rooms':
        return rooms.map((e) => e.toCloud()).toList();
      case 'grade_fees':
        return gradeFees.map((e) => e.toCloud()).toList();
      case 'users':
        return users.map((e) => e.toCloud()).toList();
      case 'payments':
        return payments.map((e) => e.toCloud()).toList();
      case 'installments':
        return installments.map((e) => e.toCloud()).toList();
      case 'attendance':
        return attendance.map((e) => e.toCloud()).toList();
      case 'groups':
        return groups.map((e) => e.toCloud()).toList();
      case 'enrollments':
        return enrollments.map((e) => e.toCloud()).toList();
      case 'sessions':
        return sessions.map((e) => e.toCloud()).toList();
      default:
        return extraCloud[table] ?? [];
    }
  }

  @override
  void putRows(String table, List<Map<String, dynamic>> rows) {
    markDirty(table);
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

  @override
  void removeIds(String table, List<String> ids) {
    markDirty(table);
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
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope missing');
    return scope!.notifier!;
  }
}
