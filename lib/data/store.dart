import 'package:flutter/widgets.dart';

import '../models/models.dart';

class AppStore extends ChangeNotifier {
  AppStore._() {
    _seed();
  }

  static final AppStore instance = AppStore._();

  bool loggedIn = false;
  bool isMasterAdmin = false;
  String institutionName = 'مدرسة الأمل الخاصة';
  String roleName = 'مدير النظام';
  int pendingPush = 0;
  int pendingPull = 0;
  final pendingRows = <SyncRow>[];

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

  int _seq = 80;
  int _receipt = 1040;

  String newId() => 'id-${_seq++}';

  String? login(String username, String password) {
    final u = username.trim().toLowerCase();
    final p = password.trim();
    if (u.isEmpty || p.isEmpty) {
      return 'أدخل اسم المستخدم وكلمة المرور';
    }
    if (u == 'anas' && p == 'anas2026') {
      loggedIn = true;
      isMasterAdmin = true;
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
      notifyListeners();
      return null;
    }
    return 'اسم المستخدم أو كلمة المرور غير صحيحة';
  }

  void logout() {
    loggedIn = false;
    isMasterAdmin = false;
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

  void _touch([String table = 'تعديل']) {
    pendingPush += 1;
    final i = pendingRows.indexWhere((r) => r.table == table);
    if (i >= 0) {
      pendingRows[i] = SyncRow(table, pendingRows[i].count + 1);
    } else {
      pendingRows.add(SyncRow(table, 1));
    }
  }

  void setAttendance(String studentId, String date, String? status) {
    attendance.removeWhere((a) => a.studentId == studentId && a.date == date);
    if (status != null) {
      attendance.add(AttendanceMark(studentId: studentId, date: date, status: status));
    }
    _touch('الحضور');
    notifyListeners();
  }

  void markAllPresent(String date, List<Student> list) {
    for (final s in list) {
      attendance.removeWhere((a) => a.studentId == s.id && a.date == date);
      attendance.add(AttendanceMark(studentId: s.id, date: date, status: 'present'));
    }
    _touch('الحضور');
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
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    for (final s in students) {
      if (exclude != null && s.id == exclude) continue;
      final other = s.phone.replaceAll(RegExp(r'\D'), '');
      if (other == digits) return s;
    }
    return null;
  }

  void upsertStudent(Student incoming, {bool isNew = false}) {
    if (!isValidNationalId(incoming.nationalId)) {
      throw StoreException('رقم الهوية غير صالح! يجب أن يتكون من 9 أرقام.');
    }
    final dupId = findByNationalId(incoming.nationalId, exclude: incoming.id);
    if (dupId != null) {
      throw StoreException('رقم الهوية (${incoming.nationalId}) مسجل مسبقاً للطالب "${dupId.fullName}" ولا يمكن تكراره.');
    }
    if (!isValidStudentPhone(incoming.phone)) {
      throw StoreException('رقم جوال الطالب غير صالح! يجب أن يتكون من 10 أرقام (مثال: 059xxxxxxx).');
    }
    final dupPhone = findByPhone(incoming.phone, exclude: incoming.id);
    if (dupPhone != null) {
      throw StoreException('رقم جوال الطالب (${incoming.phone}) مسجل مسبقاً للطالب "${dupPhone.fullName}" ولا يمكن تكراره.');
    }
    if (incoming.fullName.trim().isEmpty) {
      throw StoreException('يرجى إدخال الاسم الرباعي للطالب.');
    }

    final i = students.indexWhere((e) => e.id == incoming.id);
    if (i >= 0) {
      incoming.balance = students[i].balance;
      students[i] = incoming;
    } else {
      students.insert(0, incoming);
      if (isNew) {
        final fee = feeFor(incoming.gradeLevel)?.monthlyFee ?? 200;
        incoming.balance = -(fee * 4);
        final today = DateTime.now();
        for (var p = 1; p <= 4; p++) {
          installments.add(
            Installment(
              id: newId(),
              studentId: incoming.id,
              title: 'القسط الدراسي ($p)',
              amount: fee,
              dueDate: DateTime(today.year, today.month + (p - 1), 10),
            ),
          );
        }
      }
    }
    _touch('الطلاب');
    notifyListeners();
  }

  void deleteStudent(String id) {
    students.removeWhere((s) => s.id == id);
    payments.removeWhere((p) => p.studentId == id);
    installments.removeWhere((i) => i.studentId == id);
    attendance.removeWhere((a) => a.studentId == id);
    _touch('الطلاب');
    notifyListeners();
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
    String? installmentId,
  }) {
    if (amount <= 0) throw StoreException('يرجى إدخال مبلغ صحيح');
    final stu = studentById(studentId);
    if (stu == null) throw StoreException('يرجى اختيار الطالب أولاً');

    final totalDue = stu.balance < 0 ? stu.balance.abs() : 0.0;
    stu.balance += amount;
    final remaining = stu.balance < 0 ? stu.balance.abs() : 0.0;

    if (installmentId != null) {
      for (final inst in installments) {
        if (inst.id == installmentId) {
          inst.paidAmount += amount;
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
      installmentId: installmentId,
      remainingAfter: remaining == 0 && totalDue == 0 ? 0 : remaining,
    );
    payments.insert(0, p);
    _touch('المقبوضات');
    notifyListeners();
    return p;
  }

  void cancelPayment(Payment p, [String reason = 'ملغاة من قبل الإدارة']) {
    if (p.cancelled) return;
    p.cancelled = true;
    p.cancelReason = reason;
    final stu = studentById(p.studentId);
    if (stu != null) stu.balance -= p.amount;
    if (p.installmentId != null) {
      for (final inst in installments) {
        if (inst.id == p.installmentId) {
          final next = inst.paidAmount - p.amount;
          inst.paidAmount = next < 0 ? 0 : next;
        }
      }
    }
    _touch('المقبوضات');
    notifyListeners();
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

  void confirmPush() {
    pendingPush = 0;
    pendingRows.clear();
    notifyListeners();
  }

  void confirmPull() {
    pendingPull = 0;
    notifyListeners();
  }

  void upsertTeacher(Teacher t) {
    if (t.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المعلم');
    final i = teachers.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      teachers[i] = t;
    } else {
      teachers.add(t);
    }
    _touch('المدرسين');
    notifyListeners();
  }

  void deleteTeacher(String id) {
    teachers.removeWhere((t) => t.id == id);
    _touch('المدرسين');
    notifyListeners();
  }

  void upsertSubject(SubjectItem s) {
    if (s.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المادة');
    final i = subjects.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      subjects[i] = s;
    } else {
      subjects.add(s);
    }
    _touch('المواد');
    notifyListeners();
  }

  void deleteSubject(String id) {
    subjects.removeWhere((s) => s.id == id);
    _touch('المواد');
    notifyListeners();
  }

  void upsertRoom(Classroom r) {
    if (r.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم الصف / الشعبة');
    final i = rooms.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      rooms[i] = r;
    } else {
      rooms.add(r);
    }
    _touch('الشعب والصفوف');
    notifyListeners();
  }

  void deleteRoom(String id) {
    rooms.removeWhere((r) => r.id == id);
    _touch('الشعب والصفوف');
    notifyListeners();
  }

  void updateGradeFee(GradeFee f) {
    if (f.monthlyFee < 0) throw StoreException('يرجى إدخال رسم شهري صحيح');
    final i = gradeFees.indexWhere((e) => e.id == f.id);
    if (i >= 0) gradeFees[i] = f;
    _touch('المراحل الدراسية');
    notifyListeners();
  }

  void addGradeFee(GradeFee f) {
    gradeFees.add(f);
    _touch('المراحل الدراسية');
    notifyListeners();
  }

  void addUser(AppUser u) {
    if (u.name.trim().isEmpty) throw StoreException('يرجى إدخال اسم المستخدم');
    users.add(u);
    _touch('المستخدمين');
    notifyListeners();
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
      Teacher(id: 't1', name: 'أ. محمود الزهار', phone: '0599123456', subject: 'الرياضيات', rate: 3200),
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
      GradeFee(id: 'g1', gradeName: 'عاشر', monthlyFee: 180),
      GradeFee(id: 'g2', gradeName: 'حادي عشر علمي', monthlyFee: 220),
      GradeFee(id: 'g3', gradeName: 'حادي عشر أدبي', monthlyFee: 200),
      GradeFee(id: 'g4', gradeName: 'ثاني عشر علمي', monthlyFee: 250),
      GradeFee(id: 'g5', gradeName: 'ثاني عشر أدبي', monthlyFee: 230),
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

      students.add(
        Student(
          id: id,
          fullName: row[0] as String,
          gradeLevel: grade,
          section: row[2] as String,
          phone: '0599${(100000 + i * 137).toString().padLeft(6, '0')}',
          parentName: row[3] as String,
          parentPhone: '0598${(200000 + i * 137).toString().padLeft(6, '0')}',
          nationalId: '${400000000 + i * 1357}',
          neighborhood: neighborhoods[i % neighborhoods.length],
          balance: totalPaid - (fee * instCount),
          gender: i.isOdd ? 'أنثى' : 'ذكر',
          notes: i == 3 ? 'لديه شقيق في المدرسة - خصم إخوة' : 'طالب منتظم في الدوام',
          enrolledAt: today.subtract(const Duration(days: 60)),
        ),
      );

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
    pendingPush = 3;
    pendingPull = 1;
    pendingRows.addAll([SyncRow('الطلاب', 1), SyncRow('الحضور', 2)]);
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
