import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'phone.dart';
import 'sync.dart';

class AppStore extends ChangeNotifier implements SyncLocalStore {
  AppStore._() {
    sync = SyncService(this);
    _seed();
  }

  static final AppStore instance = AppStore._();

  late final SyncService sync;

  bool loggedIn = false;
  bool isMasterAdmin = false;
  String institutionName = 'مدرسة الأمل الخاصة';
  String roleName = 'مدير النظام';
  Tenant? currentTenant;

  final pendingSyncs = <PendingSync>[];
  final extraCloud = <String, List<Map<String, dynamic>>>{
    'groups': [],
    'enrollments': [],
    'sessions': [],
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

  String _tenantUser = 'amal';
  String _tenantPass = 'amal2026';
  int _receipt = 1040;
  final _uuid = const Uuid();

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

  String? login(String username, String password) {
    final u = username.trim().toLowerCase();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) {
      return 'أدخل اسم المستخدم وكلمة المرور';
    }
    if (u == 'anas' && p == 'anas2026') {
      loggedIn = true;
      isMasterAdmin = true;
      currentTenant = null;
      roleName = 'المطور العام';
      notifyListeners();
      return null;
    }
    final tenant = tenants.where((t) => t.username.trim().toLowerCase() == u && t.password == p).firstOrNull;
    if (tenant != null) {
      if (!tenant.active) return 'اشتراك هذه المنشأة غير سارٍ';
      if (tenant.expiresAt.isBefore(DateTime.now())) return 'انتهت مدة اشتراك هذه المنشأة';
      loggedIn = true;
      isMasterAdmin = false;
      currentTenant = tenant;
      institutionName = tenant.name;
      _tenantUser = tenant.username;
      _tenantPass = tenant.password;
      roleName = 'مدير النظام';
      notifyListeners();
      return null;
    }
    if (u == _tenantUser && p == _tenantPass) {
      loggedIn = true;
      isMasterAdmin = false;
      currentTenant = tenants.where((t) => t.username == _tenantUser).firstOrNull ?? tenants.firstOrNull;
      notifyListeners();
      return null;
    }
    return 'اسم المستخدم أو كلمة المرور غير صحيحة';
  }

  void logout() {
    loggedIn = false;
    isMasterAdmin = false;
    currentTenant = null;
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

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  void _queue(String table, String recordId, String action, Map<String, dynamic>? payload) {
    queuePendingSync(
      pendingSyncs,
      tableName: table,
      recordId: recordId,
      action: action,
      payload: payload,
    );
    notifyListeners();
  }

  void setAttendance(String studentId, String date, String? status) {
    attendance.removeWhere((a) => a.studentId == studentId && a.date == date);
    if (status != null) {
      final mark = AttendanceMark(
        studentId: studentId,
        date: date,
        status: status,
        syncStatus: 'pending',
        updatedAt: _nowIso(),
      );
      attendance.add(mark);
      _queue('attendance', mark.id, 'INSERT', mark.toCloud());
    } else {
      final id = 'att-$studentId-$date';
      _queue('attendance', id, 'DELETE', null);
      notifyListeners();
    }
  }

  void markAllPresent(String date, List<Student> list) {
    for (final s in list) {
      attendance.removeWhere((a) => a.studentId == s.id && a.date == date);
      final mark = AttendanceMark(
        studentId: s.id,
        date: date,
        status: 'present',
        syncStatus: 'pending',
        updatedAt: _nowIso(),
      );
      attendance.add(mark);
      queuePendingSync(pendingSyncs, tableName: 'attendance', recordId: mark.id, action: 'INSERT', payload: mark.toCloud());
    }
    notifyListeners();
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
      students.insert(0, incoming);
      _queue('students', incoming.id, 'INSERT', incoming.toCloud());
      if (isNew) {
        final fee = incoming.customMonthlyFee ?? feeFor(incoming.gradeLevel)?.monthlyFee ?? 200;
        incoming.balance = -(fee * 4);
        final today = DateTime.now();
        for (var p = 1; p <= 4; p++) {
          final inst = Installment(
            id: newId(),
            studentId: incoming.id,
            title: 'القسط الدراسي ($p)',
            amount: fee,
            dueDate: DateTime(today.year, today.month + (p - 1), 10),
            syncStatus: 'pending',
            createdAt: _nowIso(),
            updatedAt: _nowIso(),
          );
          installments.add(inst);
          queuePendingSync(
            pendingSyncs,
            tableName: 'installments',
            recordId: inst.id,
            action: 'INSERT',
            payload: inst.toCloud(),
          );
        }
      }
    }

    if (attachments != null) {
      final existed = attachmentsByStudent.containsKey(incoming.id);
      attachments.updatedAt = _nowIso();
      attachments.syncStatus = 'pending';
      attachmentsByStudent[incoming.id] = attachments;
      _queue('student_attachments', incoming.id, existed ? 'UPDATE' : 'INSERT', attachments.toCloud());
    }
  }

  void deleteStudent(String id) {
    students.removeWhere((s) => s.id == id);
    payments.removeWhere((p) => p.studentId == id);
    installments.removeWhere((i) => i.studentId == id);
    attendance.removeWhere((a) => a.studentId == id);
    attachmentsByStudent.remove(id);
    _queue('students', id, 'DELETE', null);
    queuePendingSync(pendingSyncs, tableName: 'student_attachments', recordId: id, action: 'DELETE', payload: null);
  }

  String _nextReceipt() {
    final year = DateTime.now().year;
    var max = 1000;
    for (final p in payments) {
      final parts = p.receiptNumber.split('/');
      if (parts.length == 2 && parts[0] == '$year') {
        final n = int.tryParse(parts[1]) ?? 0;
        if (n > max) max = n;
      }
    }
    if (_receipt > max) max = _receipt;
    _receipt = max + 1;
    return '$year/$_receipt';
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
          inst.updatedAt = _nowIso();
          inst.syncStatus = 'pending';
          queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'UPDATE', payload: inst.toCloud());
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
      remainingAfter: remaining == 0 && totalDue == 0 ? 0 : remaining,
      totalDueAtPayment: totalDue,
      syncStatus: 'pending',
      createdAt: _nowIso(),
      updatedAt: _nowIso(),
    );
    payments.insert(0, p);
    queuePendingSync(pendingSyncs, tableName: 'payments', recordId: p.id, action: 'INSERT', payload: p.toCloud());
    queuePendingSync(pendingSyncs, tableName: 'students', recordId: stu.id, action: 'UPDATE', payload: stu.toCloud());
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
          inst.updatedAt = _nowIso();
          inst.syncStatus = 'pending';
          queuePendingSync(pendingSyncs, tableName: 'installments', recordId: inst.id, action: 'UPDATE', payload: inst.toCloud());
        }
      }
    }
    _queue('payments', p.id, 'UPDATE', p.toCloud());
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

  void addGradeFee(GradeFee f) {
    f.createdAt = _nowIso();
    f.updatedAt = _nowIso();
    f.syncStatus = 'pending';
    gradeFees.add(f);
    _queue('grade_fees', f.id, 'INSERT', f.toCloud());
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
      default:
        return extraCloud[table] ?? [];
    }
  }

  @override
  void putRows(String table, List<Map<String, dynamic>> rows) {
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
      default:
        extraCloud[table]?.removeWhere((e) => set.contains('${e['id']}'));
    }
  }

  @override
  void markSynced(String table, String id) {
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
    }
  }

  @override
  void notifySync() => notifyListeners();

  void _seed() {
    tenants.addAll([
      Tenant(
        id: 'tn1',
        name: 'مدرسة الأمل الخاصة',
        code: 'AMAL-01',
        username: 'amal',
        password: 'amal2026',
        expiresAt: DateTime.now().add(const Duration(days: 280)),
        ownerPhone: '0599000001',
      ),
      Tenant(
        id: 'tn2',
        name: 'مدرسة النور',
        code: 'NOOR-02',
        username: 'noor',
        password: 'noor2026',
        expiresAt: DateTime.now().add(const Duration(days: 40)),
        ownerPhone: '0599000002',
      ),
    ]);

    users.addAll([
      AppUser(id: 'u1', name: 'أحمد عبد الله', role: 'مدير'),
      AppUser(id: 'u2', name: 'سارة خالد', role: 'سكرتير'),
    ]);

    teachers.addAll([
      Teacher(id: 't1', name: 'أ. محمود الزهار', phone: '0599123456', subject: 'الرياضيات', rate: 3200, email: 'mahmoud@school.ps'),
      Teacher(id: 't2', name: 'أ. وفاء عاشور', phone: '0568112233', subject: 'اللغة العربية', rate: 3000),
      Teacher(id: 't3', name: 'أ. رامي البيطار', phone: '0598776655', subject: 'اللغة الإنجليزية', rate: 3100),
      Teacher(id: 't4', name: 'د. كمال الشرفا', phone: '0592881122', subject: 'الفيزياء', rate: 3300),
      Teacher(id: 't5', name: 'أ. مريم النجار', phone: '0569443322', subject: 'الكيمياء', rate: 2900),
    ]);

    subjects.addAll([
      SubjectItem(id: 's1', name: 'الرياضيات', code: 'MATH'),
      SubjectItem(id: 's2', name: 'اللغة العربية', code: 'ARB'),
      SubjectItem(id: 's3', name: 'اللغة الإنجليزية', code: 'ENG'),
      SubjectItem(id: 's4', name: 'الفيزياء', code: 'PHY', gradeLevel: 'حادي عشر علمي'),
      SubjectItem(id: 's5', name: 'الكيمياء', code: 'CHM', gradeLevel: 'ثاني عشر علمي'),
    ]);

    gradeFees.addAll([
      GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: 180, orderIndex: 1),
      GradeFee(id: 'g2', gradeName: 'حادي عشر علمي', monthlyFee: 220, orderIndex: 2),
      GradeFee(id: 'g3', gradeName: 'حادي عشر أدبي', monthlyFee: 200, orderIndex: 3),
      GradeFee(id: 'g4', gradeName: 'ثاني عشر علمي', monthlyFee: 250, orderIndex: 4),
      GradeFee(id: 'g5', gradeName: 'ثاني عشر أدبي', monthlyFee: 230, orderIndex: 5),
    ]);

    rooms.addAll([
      Classroom(id: 'r1', name: 'عاشر (أ)', gradeLevel: 'عاشر', teacherId: 't1', notes: 'الطابق الأول - قاعة 1'),
      Classroom(id: 'r2', name: 'عاشر (ب)', gradeLevel: 'عاشر', teacherId: 't2', notes: 'الطابق الأول - قاعة 2'),
      Classroom(id: 'r3', name: '11 علمي', gradeLevel: 'حادي عشر علمي', teacherId: 't4', notes: 'الطابق الثاني - قاعة 3'),
      Classroom(id: 'r4', name: '11 أدبي', gradeLevel: 'حادي عشر أدبي', teacherId: 't3', notes: 'الطابق الثاني - قاعة 4'),
      Classroom(id: 'r5', name: '12 علمي', gradeLevel: 'ثاني عشر علمي', teacherId: 't1', notes: 'الطابق الثالث - قاعة 5'),
      Classroom(id: 'r6', name: '12 أدبي', gradeLevel: 'ثاني عشر أدبي', teacherId: 't2', notes: 'الطابق الثالث - قاعة 6'),
    ]);

    const names = [
      ['محمد أحمد النجار', 'عاشر', 'عاشر (أ)', 'خالد النجار', 0],
      ['سارة محمود خضير', 'عاشر', 'عاشر (أ)', 'محمود خضير', 1],
      ['عمر يوسف الشوا', 'عاشر', 'عاشر (ب)', 'يوسف الشوا', 2],
      ['مريم وليد اليازجي', 'عاشر', 'عاشر (ب)', 'وليد اليازجي', 3],
      ['أحمد سامي الريس', 'حادي عشر علمي', '11 علمي', 'سامي الريس', 0],
      ['ياسمين كمال شعت', 'حادي عشر علمي', '11 علمي', 'كمال شعت', 1],
      ['بلال فؤاد حرز الله', 'حادي عشر أدبي', '11 أدبي', 'فؤاد حرز الله', 2],
      ['سلمى نبيل أبو حصيرة', 'حادي عشر أدبي', '11 أدبي', 'نبيل أبو حصيرة', 0],
      ['عبد الله حسن صيام', 'ثاني عشر علمي', '12 علمي', 'حسن صيام', 1],
      ['آية رامي الجعبري', 'ثاني عشر علمي', '12 علمي', 'رامي الجعبري', 4],
      ['ماجد هاني عابد', 'ثاني عشر أدبي', '12 أدبي', 'هاني عابد', 0],
      ['رنا سليم أبو لبن', 'ثاني عشر أدبي', '12 أدبي', 'سليم أبو لبن', 2],
    ];

    final today = DateTime.now();
    for (var i = 0; i < names.length; i++) {
      final row = names[i];
      final id = 'st$i';
      final grade = row[1] as String;
      final fee = feeFor(grade)?.monthlyFee ?? 200;
      final pattern = row[4] as int;
      var totalPaid = 0.0;
      const instCount = 4;

      for (var p = 1; p <= instCount; p++) {
        final due = DateTime(today.year, today.month + (p - 3), 10);
        var paid = 0.0;
        if (pattern == 0) {
          paid = fee;
        } else if (pattern == 1 && p <= 2) {
          paid = fee;
        } else if (pattern == 2 && p == 1) {
          paid = fee;
        } else if (pattern == 3 && p <= 1) {
          paid = fee;
        }
        totalPaid += paid;
        installments.add(
          Installment(
            id: 'in$i$p',
            studentId: id,
            title: 'القسط الدراسي ($p)',
            amount: fee,
            dueDate: due,
            paidAmount: paid,
          ),
        );
        if (paid > 0) {
          payments.add(
            Payment(
              id: 'pay$i$p',
              receiptNumber: '${today.year}/${1001 + payments.length}',
              studentId: id,
              amount: paid,
              method: p.isEven ? 'cash' : 'jawwal_pay',
              date: due.subtract(const Duration(days: 2)),
              purpose: 'installment',
              notes: 'سداد القسط الدراسي ($p)',
              reference: p.isOdd ? 'TRX-${9000 + i * 10 + p}' : '',
              installmentId: 'in$i$p',
              remainingAfter: ((fee * instCount) - totalPaid).clamp(0, fee * instCount).toDouble(),
            ),
          );
        }
      }

      final student = Student(
        id: id,
        fullName: row[0] as String,
        gradeLevel: grade,
        section: row[2] as String,
        phone: '0599${(100000 + i * 137).toString().padLeft(6, '0')}',
        phonePrefix: '059',
        parentName: row[3] as String,
        parentPhone: '0598${(200000 + i * 137).toString().padLeft(6, '0')}',
        parentPhonePrefix: '059',
        nationalId: '${400000000 + i * 1357}',
        neighborhood: neighborhoods[i % (neighborhoods.length - 1)],
        detailedAddress: i == 0 ? 'شارع النفق، بجوار مسجد الهدى' : '',
        referralSource: referralSources[i % referralSources.length],
        balance: totalPaid - (fee * instCount),
        gender: i.isOdd ? 'أنثى' : 'ذكر',
        notes: i == 3 ? 'لديه شقيق في المدرسة - خصم إخوة' : 'طالب منتظم في الدوام',
        enrolledAt: today.subtract(const Duration(days: 60)),
        birthPlace: 'غزة',
        nationality: 'فلسطينية',
      );
      student.splitNameIfNeeded();
      students.add(student);

      final d0 = isoDate(today);
      final d1 = isoDate(today.subtract(const Duration(days: 1)));
      if (i % 5 == 0) {
        attendance.add(AttendanceMark(studentId: id, date: d0, status: 'absent'));
      } else if (i % 2 == 0) {
        attendance.add(AttendanceMark(studentId: id, date: d0, status: 'present'));
      }
      if (i % 3 != 0) {
        attendance.add(AttendanceMark(studentId: id, date: d1, status: 'present'));
      }
    }

    payments.sort((a, b) => b.date.compareTo(a.date));
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
