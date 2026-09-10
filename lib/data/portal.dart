import '../models/models.dart';
import 'institution.dart';
import 'supabase.dart';

/// بوابة الطالب والمعلم — المقابل لـ `features/portal/portal.service.ts`.
///
/// بوابة سحابية بحتة: الدخول برقم الهوية ورمز من ست خانات، ثم تُقرأ بيانات
/// صاحبها من Supabase مباشرةً. لا تمرّ بمخزن الجهاز ولا بجلسة المنشأة، فقد
/// تُفتح على هاتف طالب لا علاقة له بجهاز الإدارة.

/// حساب في البوابة: طالب أو معلم.
class PortalUser {
  const PortalUser({
    required this.id,
    required this.name,
    required this.nationalId,
    required this.portalCode,
    required this.role,
    required this.tenantId,
    this.phone = '',
    this.email = '',
    this.gradeLevel = '',
    this.section = '',
    this.subjectIds = const [],
    this.tenantName = '',
  });

  final String id;
  final String name;
  final String nationalId;
  final String portalCode;

  /// `student` أو `teacher`.
  final String role;
  final String tenantId;
  final String phone;
  final String email;
  final String gradeLevel;
  final String section;
  final List<String> subjectIds;
  final String tenantName;

  bool get isTeacher => role == 'teacher';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'national_id': nationalId,
        'portal_code': portalCode,
        'role': role,
        'tenant_id': tenantId,
        'phone': phone,
        'email': email,
        'grade_level': gradeLevel,
        'section': section,
        'subject_ids': subjectIds,
        'tenant_name': tenantName,
      };

  factory PortalUser.fromJson(Map<String, dynamic> m) => PortalUser(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        nationalId: '${m['national_id'] ?? ''}',
        portalCode: '${m['portal_code'] ?? ''}',
        role: '${m['role'] ?? 'student'}',
        tenantId: '${m['tenant_id'] ?? ''}',
        phone: '${m['phone'] ?? ''}',
        email: '${m['email'] ?? ''}',
        gradeLevel: '${m['grade_level'] ?? ''}',
        section: '${m['section'] ?? ''}',
        subjectIds: [for (final e in (m['subject_ids'] as List? ?? const [])) '$e'],
        tenantName: '${m['tenant_name'] ?? ''}',
      );
}

/// هوية المنشأة كما تُعرض داخل البوابة.
class PortalBranding {
  const PortalBranding({this.name = appName, this.logo = '', this.colors = InstitutionColors.defaults});

  final String name;
  final String logo;
  final InstitutionColors colors;
}

/// مادة يدرسها الطالب مع معلمها وموعدها.
class PortalSubject {
  const PortalSubject({
    required this.subjectName,
    required this.teacherName,
    required this.groupName,
    this.days = const [],
    this.startTime = '',
    this.endTime = '',
    this.roomName = '',
  });

  final String subjectName;
  final String teacherName;
  final String groupName;
  final List<int> days;
  final String startTime;
  final String endTime;
  final String roomName;
}

/// إعلان صفّي ينشره المعلم.
class ClassAnnouncement {
  const ClassAnnouncement({
    required this.id,
    required this.groupId,
    required this.title,
    required this.content,
    this.teacherId = '',
    this.teacherName = '',
    this.groupName = '',
    this.imageUrl = '',
    this.createdAt = '',
  });

  final String id;
  final String groupId;
  final String title;
  final String content;
  final String teacherId;
  final String teacherName;
  final String groupName;
  final String imageUrl;
  final String createdAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'group_id': groupId,
        'title': title,
        'content': content,
        'image_url': imageUrl.isEmpty ? null : imageUrl,
        'created_at': createdAt.isEmpty ? null : createdAt,
      };

  factory ClassAnnouncement.fromCloud(Map<String, dynamic> m) => ClassAnnouncement(
        id: '${m['id']}',
        groupId: '${m['group_id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        content: '${m['content'] ?? ''}',
        teacherId: '${m['teacher_id'] ?? ''}',
        imageUrl: '${m['image_url'] ?? ''}',
        createdAt: '${m['created_at'] ?? ''}',
      );
}

/// تقييم معلم لطالب في مادة.
class StudentEvaluation {
  const StudentEvaluation({
    required this.id,
    required this.studentId,
    this.teacherId = '',
    this.subjectId = '',
    this.score,
    this.notes = '',
    this.createdAt = '',
  });

  final String id;
  final String studentId;
  final String teacherId;
  final String subjectId;
  final double? score;
  final String notes;
  final String createdAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id': studentId,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'subject_id': subjectId.isEmpty ? null : subjectId,
        'score': score,
        'notes': notes,
        'created_at': createdAt.isEmpty ? null : createdAt,
      };

  factory StudentEvaluation.fromCloud(Map<String, dynamic> m) => StudentEvaluation(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        teacherId: '${m['teacher_id'] ?? ''}',
        subjectId: '${m['subject_id'] ?? ''}',
        score: (m['score'] as num?)?.toDouble(),
        notes: '${m['notes'] ?? ''}',
        createdAt: '${m['created_at'] ?? ''}',
      );
}

/// خلاصة مالية الطالب كما تُعرض له.
class PortalFinance {
  const PortalFinance({
    this.totalDue = 0,
    this.totalPaid = 0,
    this.remaining = 0,
    this.installments = const [],
    this.payments = const [],
  });

  final double totalDue;
  final double totalPaid;

  /// الباقي بذمّة الطالب (موجب يعني مطلوباً منه).
  final double remaining;
  final List<Installment> installments;
  final List<Payment> payments;
}

/// إحصاء حضور الطالب.
class PortalAttendance {
  const PortalAttendance({
    this.total = 0,
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.excused = 0,
    this.records = const [],
  });

  final int total;
  final int present;
  final int absent;
  final int late;
  final int excused;
  final List<AttendanceMark> records;

  /// نسبة الالتزام: الحاضر والمتأخر من المرصود.
  int get rate => total == 0 ? 100 : (((present + late) / total) * 100).round();
}

/// كل ما تعرضه بوابة الطالب.
class StudentPortalData {
  const StudentPortalData({
    required this.student,
    this.branding = const PortalBranding(),
    this.subjects = const [],
    this.announcements = const [],
    this.evaluations = const [],
    this.attendance = const PortalAttendance(),
    this.finance = const PortalFinance(),
  });

  final Student student;
  final PortalBranding branding;
  final List<PortalSubject> subjects;
  final List<ClassAnnouncement> announcements;
  final List<StudentEvaluation> evaluations;
  final PortalAttendance attendance;
  final PortalFinance finance;
}

/// صف يدرّسه المعلم مع طلابه.
class TeacherClass {
  const TeacherClass({
    required this.group,
    required this.students,
    this.subjectName = '',
    this.roomName = '',
  });

  final Group group;
  final List<Student> students;
  final String subjectName;
  final String roomName;
}

/// كل ما تعرضه بوابة المعلم.
class TeacherPortalData {
  const TeacherPortalData({
    this.branding = const PortalBranding(),
    this.classes = const [],
    this.announcements = const [],
    this.subjects = const [],
  });

  final PortalBranding branding;
  final List<TeacherClass> classes;
  final List<ClassAnnouncement> announcements;
  final List<SubjectItem> subjects;
}

/// نتيجة محاولة دخول: إما حساب واحد، أو عدّة حسابات يختار منها المستخدم.
class PortalLoginResult {
  const PortalLoginResult({this.users = const [], this.error});

  final List<PortalUser> users;
  final String? error;

  bool get ok => error == null && users.isNotEmpty;
}

class PortalService {
  const PortalService();

  /// دخول برقم الهوية ورمز البوابة.
  ///
  /// قد يكون الرقم نفسه مسجَّلاً في أكثر من منشأة — أو طالباً ومعلماً معاً —
  /// فتُعاد كل المطابقات ليختار المستخدم.
  Future<PortalLoginResult> login(String nationalId, String portalCode) async {
    final id = nationalId.trim();
    final code = portalCode.trim();
    if (id.isEmpty || code.isEmpty) {
      return const PortalLoginResult(error: 'يرجى إدخال رقم الهوية ورمز الدخول');
    }

    final filters = {'national_id': 'eq.$id', 'portal_code': 'eq.$code'};
    final teachers = await supabaseSelect(
      'teachers',
      filters: filters,
      columns: 'id,name,phone,email,subject_ids,national_id,portal_code,tenant_id',
    );
    final students = await supabaseSelect(
      'students',
      filters: filters,
      columns:
          'id,first_name,last_name,full_name,national_id,portal_code,phone,email,grade_level,section,tenant_id',
    );

    if (teachers == null && students == null) {
      return const PortalLoginResult(error: 'تعذّر الاتصال بالسحابة. تحقق من الإنترنت.');
    }

    final names = await _tenantNames();
    final users = <PortalUser>[];

    for (final t in teachers ?? const <Map<String, dynamic>>[]) {
      final tid = '${t['tenant_id'] ?? ''}';
      users.add(PortalUser(
        id: '${t['id']}',
        name: '${t['name'] ?? ''}',
        nationalId: '${t['national_id'] ?? ''}',
        portalCode: '${t['portal_code'] ?? ''}',
        role: 'teacher',
        tenantId: tid,
        phone: '${t['phone'] ?? ''}',
        email: '${t['email'] ?? ''}',
        subjectIds: [for (final e in (t['subject_ids'] as List? ?? const [])) '$e'],
        tenantName: names[tid] ?? 'منشأة غير محددة',
      ));
    }

    for (final s in students ?? const <Map<String, dynamic>>[]) {
      final tid = '${s['tenant_id'] ?? ''}';
      final full = '${s['full_name'] ?? ''}'.trim();
      users.add(PortalUser(
        id: '${s['id']}',
        name: full.isNotEmpty ? full : '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim(),
        nationalId: '${s['national_id'] ?? ''}',
        portalCode: '${s['portal_code'] ?? ''}',
        role: 'student',
        tenantId: tid,
        phone: '${s['phone'] ?? ''}',
        email: '${s['email'] ?? ''}',
        gradeLevel: '${s['grade_level'] ?? ''}',
        section: '${s['section'] ?? ''}',
        tenantName: names[tid] ?? 'منشأة غير محددة',
      ));
    }

    if (users.isEmpty) {
      return const PortalLoginResult(error: 'رقم الهوية أو رمز الدخول غير صحيح');
    }
    return PortalLoginResult(users: users);
  }

  Future<Map<String, String>> _tenantNames() async {
    final rows = await supabaseSelect('tenants', columns: 'id,name');
    return {for (final r in rows ?? const <Map<String, dynamic>>[]) '${r['id']}': '${r['name'] ?? ''}'};
  }

  /// هوية المنشأة للعرض داخل البوابة.
  Future<PortalBranding> branding(String tenantId) async {
    final rows = await supabaseSelect(
      'institution_settings',
      filters: {'id': 'eq.$tenantId'},
      limit: 1,
    );
    if (rows == null || rows.isEmpty) return const PortalBranding();
    final row = rows.first;
    final colors = row['colors'];
    return PortalBranding(
      name: '${row['institution_name'] ?? ''}'.trim().isEmpty ? appName : '${row['institution_name']}',
      logo: '${row['logo'] ?? ''}',
      colors: colors is Map ? InstitutionColors.fromMap(Map<String, dynamic>.from(colors)) : InstitutionColors.defaults,
    );
  }

  // ── بوابة الطالب ───────────────────────────────────────────────────────────

  Future<StudentPortalData?> studentData(PortalUser user) async {
    final tenant = {'tenant_id': 'eq.${user.tenantId}'};

    final rows = await supabaseSelect('students', filters: {'id': 'eq.${user.id}'}, limit: 1);
    if (rows == null || rows.isEmpty) return null;
    final student = Student.fromCloud(rows.first);

    final results = await Future.wait([
      branding(user.tenantId),
      supabaseSelect('enrollments', filters: {'student_id': 'eq.${user.id}'}),
      supabaseSelect('groups', filters: tenant),
      supabaseSelect('teachers', filters: tenant),
      supabaseSelect('subjects', filters: tenant),
      supabaseSelect('rooms', filters: tenant),
      supabaseSelect('installments', filters: {'student_id': 'eq.${user.id}'}),
      supabaseSelect('payments', filters: {'student_id': 'eq.${user.id}'}),
      supabaseSelect('attendance', filters: {'student_id': 'eq.${user.id}'}),
      supabaseSelect('sessions', filters: tenant),
      supabaseSelect('student_evaluations', filters: {'student_id': 'eq.${user.id}'}),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

    final enrollments = at(1);
    final groups = at(2);
    final teachers = at(3);
    final subjects = at(4);
    final rooms = at(5);

    final groupIds = enrollments
        .where((e) => '${e['status'] ?? 'active'}' == 'active')
        .map((e) => '${e['group_id']}')
        .toSet();

    final subjectName = {for (final s in subjects) '${s['id']}': '${s['name'] ?? ''}'};
    final teacherName = {for (final t in teachers) '${t['id']}': '${t['name'] ?? ''}'};
    final roomName = {for (final r in rooms) '${r['id']}': '${r['name'] ?? ''}'};

    final mySubjects = <PortalSubject>[];
    for (final g in groups.where((g) => groupIds.contains('${g['id']}'))) {
      mySubjects.add(PortalSubject(
        subjectName: subjectName['${g['subject_id']}'] ?? 'مادة',
        teacherName: teacherName['${g['teacher_id']}'] ?? '—',
        groupName: '${g['name'] ?? ''}',
        days: [for (final d in (g['days'] as List? ?? const [])) int.tryParse('$d') ?? 0],
        startTime: '${g['start_time'] ?? ''}',
        endTime: '${g['end_time'] ?? ''}',
        roomName: roomName['${g['room_id']}'] ?? '',
      ));
    }

    // إعلانات صفوف الطالب فقط
    final announcements = <ClassAnnouncement>[];
    if (groupIds.isNotEmpty) {
      final rows = await supabaseSelect(
        'class_announcements',
        filters: {...tenant, 'group_id': 'in.(${groupIds.join(',')})'},
        order: 'created_at.desc',
        limit: 50,
      );
      for (final r in rows ?? const <Map<String, dynamic>>[]) {
        final a = ClassAnnouncement.fromCloud(r);
        announcements.add(ClassAnnouncement(
          id: a.id,
          groupId: a.groupId,
          title: a.title,
          content: a.content,
          teacherId: a.teacherId,
          teacherName: teacherName[a.teacherId] ?? '',
          groupName: '${groups.firstWhere((g) => '${g['id']}' == a.groupId, orElse: () => const {})['name'] ?? ''}',
          imageUrl: a.imageUrl,
          createdAt: a.createdAt,
        ));
      }
    }

    // الحضور: تاريخه في الجلسة المرتبطة
    final sessionDate = {for (final s in at(9)) '${s['id']}': '${s['session_date'] ?? ''}'};
    final marks = <AttendanceMark>[];
    var present = 0, absent = 0, late = 0, excused = 0;
    for (final r in at(8)) {
      final mark = AttendanceMark.fromCloud({...r, 'session_date': sessionDate['${r['session_id']}'] ?? ''});
      marks.add(mark);
      switch (mark.status) {
        case 'present':
          present++;
        case 'absent':
          absent++;
        case 'late':
          late++;
        case 'excused':
          excused++;
      }
    }
    marks.sort((a, b) => b.date.compareTo(a.date));

    final installments = at(6).map(Installment.fromCloud).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final payments = at(7).map(Payment.fromCloud).where((p) => !p.cancelled).toList();
    sortPayments(payments);

    final totalDue = installments.fold<double>(0, (a, i) => a + i.amount);
    final totalPaid = payments.fold<double>(0, (a, p) => a + p.amount);

    return StudentPortalData(
      student: student,
      branding: results[0] as PortalBranding,
      subjects: mySubjects,
      announcements: announcements,
      evaluations: at(10).map(StudentEvaluation.fromCloud).toList(),
      attendance: PortalAttendance(
        total: marks.length,
        present: present,
        absent: absent,
        late: late,
        excused: excused,
        records: marks,
      ),
      finance: PortalFinance(
        totalDue: totalDue,
        totalPaid: totalPaid,
        remaining: student.balance < 0 ? student.balance.abs() : 0,
        installments: installments,
        payments: payments,
      ),
    );
  }

  // ── بوابة المعلم ───────────────────────────────────────────────────────────

  Future<TeacherPortalData> teacherData(PortalUser user) async {
    final tenant = {'tenant_id': 'eq.${user.tenantId}'};

    final results = await Future.wait([
      branding(user.tenantId),
      supabaseSelect('groups', filters: {...tenant, 'teacher_id': 'eq.${user.id}'}),
      supabaseSelect('subjects', filters: tenant),
      supabaseSelect('rooms', filters: tenant),
      supabaseSelect('enrollments', filters: tenant),
      supabaseSelect('students', filters: tenant),
      supabaseSelect('class_announcements',
          filters: {...tenant, 'teacher_id': 'eq.${user.id}'}, order: 'created_at.desc', limit: 50),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

    final subjects = at(2).map(SubjectItem.fromCloud).toList();
    final subjectName = {for (final s in subjects) s.id: s.name};
    final roomName = {for (final r in at(3)) '${r['id']}': '${r['name'] ?? ''}'};
    final byId = {for (final s in at(5)) '${s['id']}': Student.fromCloud(s)};

    final classes = <TeacherClass>[];
    for (final row in at(1)) {
      final group = Group.fromCloud(row);
      if (!group.isActive) continue;
      final ids = at(4)
          .where((e) => '${e['group_id']}' == group.id && '${e['status'] ?? 'active'}' == 'active')
          .map((e) => '${e['student_id']}');
      classes.add(TeacherClass(
        group: group,
        students: [for (final id in ids) if (byId[id] != null) byId[id]!],
        subjectName: subjectName[group.subjectId] ?? '',
        roomName: roomName[group.roomId] ?? '',
      ));
    }

    return TeacherPortalData(
      branding: results[0] as PortalBranding,
      classes: classes,
      announcements: at(6).map(ClassAnnouncement.fromCloud).toList(),
      subjects: subjects,
    );
  }

  /// نشر إعلان صفّي.
  Future<void> publishAnnouncement(ClassAnnouncement a, String tenantId) {
    return supabaseUpsert('class_announcements', [
      {...a.toCloud(), 'tenant_id': tenantId, 'created_at': DateTime.now().toUtc().toIso8601String()},
    ]);
  }

  Future<void> deleteAnnouncement(String id) => supabaseDelete('class_announcements', {'id': 'eq.$id'});

  /// تسجيل تقييم لطالب.
  Future<void> saveEvaluation(StudentEvaluation e, String tenantId) {
    return supabaseUpsert('student_evaluations', [
      {...e.toCloud(), 'tenant_id': tenantId, 'created_at': DateTime.now().toUtc().toIso8601String()},
    ]);
  }

  /// رصد حضور صفّ من بوابة المعلم — يرفع الجلسة ثم سجلات الحضور.
  ///
  /// التصالح على (الجلسة، الطالب) لأن القيد الفريد في السحابة عليهما، لا
  /// على المعرّف: صفٌّ جديد لطالب له رصد في الجلسة نفسها كان يُرفض.
  Future<void> saveAttendance({
    required Group group,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
    required String Function() newId,
  }) async {
    final sessionId = newId();
    final now = DateTime.now().toUtc().toIso8601String();

    // جلسة قائمة لهذا الصف واليوم إن وُجدت، وإلا ننشئ واحدة
    final existing = await supabaseSelect(
      'sessions',
      filters: {'group_id': 'eq.${group.id}', 'session_date': 'eq.$date'},
      limit: 1,
    );
    final id = (existing != null && existing.isNotEmpty) ? '${existing.first['id']}' : sessionId;

    await supabaseUpsert('sessions', [
      {
        'id': id,
        'group_id': group.id,
        'teacher_id': teacher.id,
        'room_id': group.roomId.isEmpty ? null : group.roomId,
        'session_date': date,
        'start_time': group.startTime.isEmpty ? '08:00' : group.startTime,
        'end_time': group.endTime.isEmpty ? '10:00' : group.endTime,
        'status': 'completed',
        'tenant_id': teacher.tenantId,
        'updated_at': now,
      }
    ]);

    if (statuses.isEmpty) return;
    await supabaseUpsert(
      'attendance',
      [
        for (final entry in statuses.entries)
          {
            'id': newId(),
            'session_id': id,
            'student_id': entry.key,
            'status': entry.value,
            'marked_by_user_id': teacher.id,
            'tenant_id': teacher.tenantId,
            'updated_at': now,
          }
      ],
      onConflict: 'tenant_id,session_id,student_id',
    );
  }
}
