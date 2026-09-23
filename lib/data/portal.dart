import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'academic_matching.dart';
import 'attendance_days.dart';
import 'balance.dart';
import 'grading.dart';
import 'institution.dart';
import 'payment_methods.dart';
import 'supabase.dart';

/// بوابة الطالب والمعلم — المقابل لـ `features/portal/portal.service.ts`
/// و`features/moodle/moodle.service.ts`.
///
/// بوابة سحابية بحتة: الدخول برقم الهوية ورمز من ست خانات، ثم تُقرأ بيانات
/// صاحبها من Supabase مباشرةً. لا تمرّ بمخزن الجهاز ولا بجلسة المنشأة، فقد
/// تُفتح على هاتف طالب لا علاقة له بجهاز الإدارة.
///
/// الإعلانات الصفّية أُزيلت كما في النسخة المكتبية: هجرة المودل
/// (`20260911_micro_moodle.sql`) حذفت جدولها نهائياً، وحلّ محلها المودل.

const _uuid = Uuid();

String _nowIso() => DateTime.now().toUtc().toIso8601String();

/// قائمة قيم لمرشّح `in` في PostgREST، كل قيمة بين علامتي تنصيص.

/// اسم الطالب من صفّ البوابة: `full_name` إن وُجد، وإلا الاسمان معاً.
///
/// صفوف تُخزَّن باسمين منفصلين و`full_name` فارغ، فكان الكشف يظهر بلا أسماء.
Map<String, dynamic> _withFullName(Map<String, dynamic> row) {
  final full = '${row['full_name'] ?? ''}'.trim();
  if (full.isNotEmpty) return row;
  final joined = [
    '${row['first_name'] ?? ''}'.trim(),
    '${row['last_name'] ?? ''}'.trim(),
  ].where((p) => p.isNotEmpty).join(' ');
  if (joined.isEmpty) return row;
  return {...row, 'full_name': joined};
}

/// أعمدة العرض في البوابة — بلا بيانات شخصية، ومنها الاسمان للصفوف التي لا
/// تحمل `full_name` جاهزاً.
/// أسماء طلاب البوابة بلا PII — للرصد والحضور.
const _portalStudentCols = 'id,first_name,last_name,full_name,section,grade_level,status';

/// تفاصيل طالب شعبة المربي: تواصل + كلمات مرور — بلا أرصدة ومالية.
const _homeroomStudentCols =
    'id,first_name,last_name,full_name,section,grade_level,status,gender,'
    'phone,phone_prefix,parent_name,parent_phone,parent_phone_prefix,'
    'national_id,parent_national_id,portal_code,parent_portal_code';

String _inList(Iterable<String> values) => 'in.(${values.map((v) => '"$v"').join(',')})';

/// صفوف لا بدّ أن تصل. `null` من [supabaseSelect] يعني أن السحابة لم تُجب،
/// فيُرمى بدل أن يُبتلع كأنه «لا صفوف»: القارئ عنده كاشٌ يعرضه ومؤشر اتصال
/// يرفعه — وابتلاعه كان يُري المعلم سحابةً خضراء وهو بلا شبكة.
Future<List<Map<String, dynamic>>> _must(
  String what,
  Future<List<Map<String, dynamic>>?> request,
) async =>
    await request ?? (throw PortalUnavailable(what));

/// السحابة لم تُجب: شبكة مقطوعة أو طلب مرفوض — لا «أجابت بلا صفوف».
class PortalUnavailable implements Exception {
  const PortalUnavailable(this.what);

  final String what;

  @override
  String toString() => 'تعذّر جلب $what من السحابة';
}

/// حساب في البوابة: طالب أو معلم.
/// ابن في جلسة وليّ الأمر: يُفتح ملفه بالدخول برقم هويته وكلمة وليّ الأمر نفسها.
class PortalChild {
  const PortalChild({
    required this.id,
    required this.name,
    this.nationalId = '',
    this.gradeLevel = '',
    this.section = '',
  });

  final String id;
  final String name;
  final String nationalId;
  final String gradeLevel;
  final String section;

  /// الاسم الأول وحده — شريط الأبناء ضيّق، والاسم الكامل يملؤه بابن واحد.
  String get shortName => name.trim().split(RegExp(r'\s+')).first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'national_id': nationalId,
        'grade_level': gradeLevel,
        'section': section,
      };

  factory PortalChild.fromJson(Map<String, dynamic> m) => PortalChild(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}',
        nationalId: '${m['national_id'] ?? ''}',
        gradeLevel: '${m['grade_level'] ?? ''}',
        section: '${m['section'] ?? ''}',
      );
}

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
    this.studentName = '',
    this.parentNationalId = '',
    this.children = const [],
  });

  final String id;
  final String name;
  final String nationalId;
  final String portalCode;

  /// `student` أو `teacher` أو `parent`.
  final String role;
  final String tenantId;
  final String phone;
  final String email;
  final String gradeLevel;
  final String section;
  final List<String> subjectIds;
  final String tenantName;

  /// لولي الأمر: اسم ابنه الذي يتابعه. `id` هنا معرّف الطالب نفسه.
  final String studentName;

  /// رقم هوية وليّ الأمر: به يدخل، وبه يبدّل بين أبنائه.
  final String parentNationalId;

  /// أبناء وليّ الأمر في هذه المنشأة — جلسة وليّ الأمر وحدها.
  final List<PortalChild> children;

  bool get isTeacher => role == 'teacher';

  bool get isParent => role == 'parent';

  String get roleLabel => switch (role) {
        'teacher' => 'معلم',
        'parent' => 'ولي أمر',
        _ => 'طالب',
      };

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
        'student_name': studentName,
        'parent_national_id': parentNationalId,
        'children': [for (final c in children) c.toJson()],
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
        studentName: '${m['student_name'] ?? ''}',
        parentNationalId: '${m['parent_national_id'] ?? ''}',
        children: [
          for (final c in (m['children'] as List? ?? const []))
            if (c is Map) PortalChild.fromJson(Map<String, dynamic>.from(c)),
        ],
      );
}

/// هوية المنشأة كما تُعرض داخل البوابة — ومعها وسائل الدفع المضبوطة، لأن
/// الطالب يرى مسمّى الوسيلة في سنداته.
class PortalBranding {
  const PortalBranding({
    this.name = appName,
    this.logo = '',
    this.colors = InstitutionColors.defaults,
    this.paymentMethods = defaultPaymentMethods,
    this.gradingScheme = GradingScheme.empty,
  });

  final String name;
  final String logo;
  final InstitutionColors colors;
  final List<PaymentMethodItem> paymentMethods;

  /// مخطط العلامات من `colors.__grading_scheme` — كما في بوابة الويب.
  final GradingScheme gradingScheme;

  /// مطابق لـ `getPaymentMethodLabel`.
  String methodLabel(String key) {
    final id = key.trim();
    if (id.isEmpty) return '-';
    for (final m in paymentMethods) {
      if (m.id == id) return m.name;
    }
    return paymentMethodNames[id] ?? id;
  }
}

/// مادة يدرسها الطالب مع معلمها وموعدها.
class PortalSubject {
  const PortalSubject({
    required this.subjectName,
    required this.teacherName,
    required this.groupName,
    this.groupId = '',
    this.days = const [],
    this.startTime = '',
    this.endTime = '',
    this.roomName = '',
    this.roomId = '',
  });

  final String groupId;
  final String subjectName;
  final String teacherName;
  final String groupName;
  final List<int> days;
  final String startTime;
  final String endTime;
  final String roomName;

  /// شعبة هذا الطالب داخل المادة — لتصفية وحدات المودل حسب `room_ids`.
  final String roomId;
}

/// تقييم معلم لطالب في مادة.
class StudentEvaluation {
  const StudentEvaluation({
    required this.id,
    required this.studentId,
    this.groupId = '',
    this.teacherId = '',
    this.subjectId = '',
    this.title = '',
    this.score,
    this.maxScore = 100,
    this.evaluationDate = '',
    this.type = 'quiz',
    this.notes = '',
    this.term = '',
    this.componentId = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.subjectName = '',
    this.teacherName = '',
  });

  final String id;
  final String studentId;
  final String groupId;
  final String teacherId;
  final String subjectId;

  /// عنوان التقييم أو الاختبار — أُضيف بهجرة `20260910_evaluations_expansion`
  final String title;
  final double? score;

  /// الدرجة القصوى. العمود أُضيف بافتراضي 100، وصفٌّ قديم بلا قيمة
  /// لا يجوز أن يصير صفراً وإلا صارت كل نسبة صفراً.
  final double maxScore;
  final String evaluationDate;
  final String type;
  final String notes;

  /// ربط بمخطط علامات المدرسة: `term_1` / `term_2` ومعرّف المكوّن.
  final String term;
  final String componentId;
  final String createdAt;
  final String updatedAt;

  /// للعرض فقط — تُملأ عند الجلب ولا تُرفع.
  final String subjectName;
  final String teacherName;

  StudentEvaluation copyWith({double? score}) => StudentEvaluation(
        id: id,
        studentId: studentId,
        groupId: groupId,
        teacherId: teacherId,
        subjectId: subjectId,
        title: title,
        score: score ?? this.score,
        maxScore: maxScore,
        evaluationDate: evaluationDate,
        type: type,
        notes: notes,
        term: term,
        componentId: componentId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        subjectName: subjectName,
        teacherName: teacherName,
      );

  /// النسبة المئوية للدرجة، أو `null` إن لم تُرصد درجة بعد.
  int? get percent {
    final s = score;
    if (s == null || maxScore <= 0) return null;
    return ((s / maxScore) * 100).round();
  }

  /// النجاح عند 50% فأكثر — نفس العتبة في Evaluations.tsx
  bool get passed => (percent ?? 0) >= 50;

  String get typeLabel => evaluationTypeNames[type] ?? type;

  StudentEvaluation withNames({required String subjectName, required String teacherName}) => StudentEvaluation(
        id: id,
        studentId: studentId,
        groupId: groupId,
        teacherId: teacherId,
        subjectId: subjectId,
        title: title,
        score: score,
        maxScore: maxScore,
        evaluationDate: evaluationDate,
        type: type,
        notes: notes,
        term: term,
        componentId: componentId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        subjectName: subjectName,
        teacherName: teacherName,
      );

  /// تحويل للشكل الذي يقرأه `computeTermGrade` / `subjectGradeSummaries`.
  Evaluation toEvaluation() => Evaluation(
        id: id,
        studentId: studentId,
        title: title,
        score: score ?? 0,
        groupId: groupId,
        subjectId: subjectId,
        teacherId: teacherId,
        maxScore: maxScore,
        evaluationDate: evaluationDate,
        type: type,
        notes: notes,
        term: term,
        componentId: componentId,
      );

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id': studentId,
        'group_id': groupId.isEmpty ? null : groupId,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'subject_id': subjectId.isEmpty ? null : subjectId,
        'title': title,
        'score': score,
        'max_score': maxScore,
        'evaluation_date': evaluationDate.isEmpty ? null : evaluationDate,
        'type': type,
        'notes': notes.isEmpty ? null : notes,
        'term': term.isEmpty ? null : term,
        'component_id': componentId.isEmpty ? null : componentId,
        'created_at': createdAt.isEmpty ? null : createdAt,
        'updated_at': updatedAt.isEmpty ? null : updatedAt,
      };

  factory StudentEvaluation.fromCloud(Map<String, dynamic> m) => StudentEvaluation(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        teacherId: '${m['teacher_id'] ?? ''}',
        subjectId: '${m['subject_id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        score: (m['score'] as num?)?.toDouble(),
        maxScore: (m['max_score'] as num?)?.toDouble() ?? 100,
        evaluationDate: '${m['evaluation_date'] ?? ''}'.split('T').first,
        type: '${m['type'] ?? 'quiz'}',
        notes: '${m['notes'] ?? ''}',
        term: '${m['term'] ?? ''}',
        componentId: '${m['component_id'] ?? ''}',
        createdAt: '${m['created_at'] ?? ''}',
        updatedAt: '${m['updated_at'] ?? ''}',
      );
}

/// قسط كما يراه الطالب — مطابق لبند `installments` في `StudentFinancialSummary`.
class PortalInstallment {
  const PortalInstallment({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.paidAmount,
    required this.status,
    required this.isDueNow,
    this.isScheduled = false,
  });

  final String id;
  final String title;
  final double amount;

  /// `yyyy-mm-dd`
  final String dueDate;
  final double paidAmount;

  /// `paid | unpaid | partially_paid`
  final String status;

  /// حلّ موعده عبر `isInstallmentDue` — مطلوب الآن لا قسطٌ مجدول.
  final bool isDueNow;

  /// لم يحن موعده بعد — مقابل `isScheduled` في بوابة الويب.
  final bool isScheduled;

  double get remaining => (amount - paidAmount) < 0 ? 0 : amount - paidAmount;
}

/// خلاصة مالية الطالب — مطابق لـ `StudentFinancialSummary`.
class PortalFinance {
  const PortalFinance({
    this.totalDue = 0,
    this.totalPaid = 0,
    this.remainingBalance = 0,
    this.scheduledRemaining = 0,
    this.currentDue = 0,
    this.installments = const [],
    this.payments = const [],
  });

  /// مجموع `chargeableAmount` للأقساط الحالّة فقط.
  final double totalDue;
  final double totalPaid;

  /// مرادف لـ [scheduledRemaining] — توافق مع الشاشات القديمة.
  final double remainingBalance;

  /// المتبقي من الأقساط التي لم يحن موعدها — «مجدول لاحقاً».
  final double scheduledRemaining;

  /// المستحق حالياً من `dueAndScheduled` — يطابق ملف الطالب في الإدارة.
  final double currentDue;
  final List<PortalInstallment> installments;
  final List<Payment> payments;

  /// الحساب نفسه في `getStudentPortalData` (~718–761 على الويب).
  factory PortalFinance.compute({
    required double? studentBalance,
    required List<Installment> installments,
    required List<Payment> payments,
    DateTime? today,
  }) {
    final day = today ?? startOfToday();
    final sorted = [...installments]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final active = payments.where((p) => !p.cancelled).toList();
    sortPayments(active);

    final dueOnly = sorted.where((i) => isInstallmentDue(i, day));
    final totalDue = dueOnly.fold<double>(0, (a, i) => a + chargeableAmount(i));
    final totalPaid = active.fold<double>(0, (a, p) => a + p.amount);
    final buckets = dueAndScheduled(sorted, fallbackBalance: studentBalance, today: day);

    return PortalFinance(
      totalDue: totalDue,
      totalPaid: totalPaid,
      remainingBalance: buckets.scheduled,
      scheduledRemaining: buckets.scheduled,
      currentDue: buckets.due,
      installments: [
        for (final i in sorted)
          () {
            final dueNow = isInstallmentDue(i, day);
            return PortalInstallment(
              id: i.id,
              title: i.title,
              amount: chargeableAmount(i),
              dueDate: isoDate(i.dueDate),
              paidAmount: i.paidAmount,
              status: const {'paid', 'unpaid', 'partially_paid'}.contains(i.status) ? i.status : 'unpaid',
              isDueNow: dueNow,
              isScheduled: !dueNow,
            );
          }(),
      ],
      payments: active,
    );
  }
}

/// إحصاء حضور الطالب.
class PortalAttendance {
  const PortalAttendance({
    this.total = 0,
    this.present = 0,
    this.absent = 0,
    this.excused = 0,
    this.records = const [],
  });

  final int total;
  final int present;
  final int absent;
  final int excused;
  final List<AttendanceMark> records;

  /// نسبة الالتزام: الحاضر من المرصود.
  int get rate => total == 0 ? 100 : ((present / total) * 100).round();
}

/// كل ما تعرضه بوابة الطالب.
class StudentPortalData {
  const StudentPortalData({
    required this.student,
    this.branding = const PortalBranding(),
    this.subjects = const [],
    this.evaluations = const [],
    this.attendance = const PortalAttendance(),
    this.finance = const PortalFinance(),
    this.features,
  });

  final Student student;
  final PortalBranding branding;
  final List<PortalSubject> subjects;
  final List<StudentEvaluation> evaluations;
  final PortalAttendance attendance;
  final PortalFinance finance;

  /// ميزات المنشأة كما في `tenants.features` — لإخفاء تبويبات البوابة.
  final Map<String, dynamic>? features;
}

/// صف يدرّسه المعلم مع طلابه.
class TeacherClass {
  const TeacherClass({
    required this.group,
    required this.students,
    this.subjectName = '',
    this.roomName = '',
    this.rooms = const [],
  });

  final Group group;
  final List<Student> students;
  final String subjectName;
  final String roomName;

  /// شعب المادة بمعرّفاتها — الحضور يُكتب في كشف الشعبة اليومي بمعرّفها.
  final List<PortalRoom> rooms;

  /// معرّف الشعبة المطابقة للاسم، أو الشعبة الوحيدة إن لم يُحدَّد اسم.
  String roomIdFor(String sectionName) {
    final want = sectionName.trim();
    if (want.isEmpty) return rooms.length == 1 ? rooms.first.id : '';
    for (final r in rooms) {
      if (isSameSectionName(r.name, want)) return r.id;
    }
    return rooms.length == 1 ? rooms.first.id : '';
  }
}

/// شعبة كما تحتاجها البوابة: معرّفها واسمها ومرحلتها.
class PortalRoom {
  const PortalRoom({required this.id, required this.name, this.gradeLevel = ''});

  final String id;
  final String name;
  final String gradeLevel;
}

/// شعبة يكون المعلم مربيها — طلابها لمتابعة «صفي» بلا مالية.
class HomeroomClass {
  const HomeroomClass({
    required this.room,
    required this.students,
  });

  final PortalRoom room;
  final List<Student> students;
}

/// كل ما تعرضه بوابة المعلم.
class TeacherPortalData {
  const TeacherPortalData({
    this.branding = const PortalBranding(),
    this.classes = const [],
    this.homerooms = const [],
    this.subjects = const [],
    this.features,
    this.complete = true,
  });

  /// هل أجابت السحابة عن كل ما لا غنى عنه (المجموعات، الشعب، الطلاب)؟
  ///
  /// `supabaseSelect` يعيد `null` عند انقطاع الشبكة كما يعيد قائمة فارغة عند
  /// نجاحٍ بلا صفوف. بلا التمييز بينهما كانت البوابة بلا نت تبني نسخة فارغة
  /// وتكتبها فوق كشوف الجهاز، فيفتح المعلم بوابته بلا صفوف ولا طلاب ولا شعبة
  /// يربّيها — ولا تعود حتى ينجح سحبٌ كامل. ما كان ناقصاً يُعرض ولا يُحفظ.
  final bool complete;

  final PortalBranding branding;
  final List<TeacherClass> classes;

  /// شعب يكون المستخدم مربيها — تبويب «صفي».
  final List<HomeroomClass> homerooms;
  final List<SubjectItem> subjects;

  /// ميزات المنشأة كما في `tenants.features`.
  final Map<String, dynamic>? features;
}

/// نتيجة محاولة دخول: إما حساب واحد، أو عدّة حسابات يختار منها المستخدم.
class PortalLoginResult {
  const PortalLoginResult({this.users = const [], this.error, this.offline = false});

  final List<PortalUser> users;
  final String? error;

  /// لم يصل ردّ من السيرفر أصلاً — لا رفضَ لبيانات الدخول.
  ///
  /// جلسة محفوظة لا تُتلف لأجل انقطاع شبكة: المعلم يفتح التطبيق بلا نت فيجد
  /// نفسه مخرَجاً، ولا يستطيع الدخول من جديد لأن الدخول نفسه يحتاج شبكة.
  final bool offline;

  bool get ok => error == null && users.isNotEmpty;
}

// ── المودل المصغّر (المقابل لـ types/moodle.ts) ──────────────────────────────

/// `term_1 | term_2 | other` — و`general` قيمة قديمة تُقرأ «أخرى».
const academicTermLabels = {
  'term_1': 'الفصل الأول',
  'term_2': 'الفصل الثاني',
  'other': 'أخرى',
  'general': 'أخرى',
};

const courseItemTypeLabels = {
  'file': 'ورقة عمل / ملخص',
  'link': 'رابط فيديو / شرح',
  'assignment': 'واجب منزلي',
  'note': 'ملاحظة تعليمية',
};

/// مادة أو واجب داخل وحدة دراسية.
class CourseItem {
  const CourseItem({
    required this.id,
    required this.sectionId,
    required this.groupId,
    required this.title,
    required this.type,
    this.tenantId = '',
    this.contentUrl = '',
    this.fileName = '',
    this.fileSize,
    this.description = '',
    this.dueDate = '',
    this.sortOrder = 0,
    this.createdAt = '',
  });

  final String id;
  final String tenantId;
  final String sectionId;
  final String groupId;
  final String title;

  /// `file | link | assignment | note`
  final String type;
  final String contentUrl;
  final String fileName;
  final int? fileSize;
  final String description;

  /// `yyyy-mm-dd` للواجب، وفارغ لغيره.
  final String dueDate;
  final int sortOrder;
  final String createdAt;

  String get typeLabel => courseItemTypeLabels[type] ?? type;

  /// انتهى موعد التسليم قبل اليوم.
  bool isOverdue([DateTime? now]) {
    if (dueDate.isEmpty) return false;
    return dueDate.compareTo(isoDate(now ?? DateTime.now())) < 0;
  }

  /// أُضيف خلال آخر 48 ساعة — كان لشارة «جديد»؛ بقي للاختبارات والمزامنة.
  bool isNew([DateTime? now]) {
    final created = DateTime.tryParse(createdAt);
    if (created == null) return false;
    return (now ?? DateTime.now()).difference(created).inHours < 48;
  }

  Map<String, dynamic> toCloud() => {
        'id': id,
        'tenant_id': tenantId,
        'section_id': sectionId,
        'group_id': groupId,
        'title': title,
        'type': type,
        'content_url': contentUrl.isEmpty ? null : contentUrl,
        'file_name': fileName.isEmpty ? null : fileName,
        'file_size': fileSize,
        'description': description.isEmpty ? null : description,
        'due_date': dueDate.isEmpty ? null : dueDate,
        'sort_order': sortOrder,
        'created_at': createdAt.isEmpty ? _nowIso() : createdAt,
      };

  factory CourseItem.fromCloud(Map<String, dynamic> m) => CourseItem(
        id: '${m['id']}',
        tenantId: '${m['tenant_id'] ?? ''}',
        sectionId: '${m['section_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        type: '${m['type'] ?? 'note'}',
        contentUrl: '${m['content_url'] ?? ''}',
        fileName: '${m['file_name'] ?? ''}',
        fileSize: (m['file_size'] as num?)?.toInt(),
        description: '${m['description'] ?? ''}',
        dueDate: '${m['due_date'] ?? ''}'.split('T').first,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: '${m['created_at'] ?? ''}',
      );
}

/// تطبيع روابط يوتيوب ودرايف وغيرها لتُفتح بسلاسة داخل التطبيق.
String polishExternalLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return url.trim();
  final host = uri.host.toLowerCase();

  if (host == 'youtu.be' || host == 'www.youtu.be') {
    final id = uri.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
    if (id != null && id.isNotEmpty) {
      return Uri.https('www.youtube.com', '/watch', {'v': id}).toString();
    }
  }
  if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) {
      return Uri.https('www.youtube.com', '/watch', {'v': v}).toString();
    }
    final shorts = RegExp(r'/shorts/([^/?]+)').firstMatch(uri.path);
    if (shorts != null) {
      return Uri.https('www.youtube.com', '/watch', {'v': shorts[1]}).toString();
    }
  }

  if (host.contains('drive.google.com')) {
    final file = RegExp(r'/file/d/([^/]+)').firstMatch(uri.path);
    if (file != null) {
      return 'https://drive.google.com/file/d/${file[1]}/preview';
    }
    final openId = uri.queryParameters['id'];
    if (openId != null && openId.isNotEmpty) {
      return 'https://drive.google.com/file/d/$openId/preview';
    }
  }

  if (host.contains('docs.google.com') ||
      host.contains('sheets.google.com') ||
      host.contains('slides.google.com')) {
    final path = uri.path;
    if (path.contains('/edit') || path.endsWith('/view') || path.contains('/view')) {
      return url.replaceFirst(RegExp(r'/(edit|view)[^/]*'), '/preview');
    }
  }

  return url.trim();
}

/// وحدة بلا شعب محددة لكل شعب المادة؛ وإلا لشعبها وحدها — مطابق لـ `sectionVisibleToRoom`.
bool sectionVisibleToRoom(CourseSection section, String? roomId) {
  if (section.roomIds.isEmpty) return true;
  return roomId != null && roomId.isNotEmpty && section.roomIds.contains(roomId);
}

/// وحدة أو قسم دراسي لمادة (مجموعة) في فصل — وقد تُخصَّص لشعب معيّنة.
class CourseSection {
  const CourseSection({
    required this.id,
    required this.groupId,
    required this.term,
    required this.title,
    this.tenantId = '',
    this.sortOrder = 0,
    this.isVisible = true,
    this.createdAt = '',
    this.items = const [],
    this.roomIds = const [],
  });

  final String id;
  final String tenantId;
  final String groupId;
  final String term;
  final String title;
  final int sortOrder;
  final bool isVisible;
  final String createdAt;
  final List<CourseItem> items;

  /// شعب الوحدة من شعب المادة؛ فارغ = كل شعب المادة.
  final List<String> roomIds;

  String get termLabel => academicTermLabels[term] ?? term;

  /// الوحدة لكل الشعب (لا تقييد).
  bool get forAllRooms => roomIds.isEmpty;

  CourseSection copyWith({
    bool? isVisible,
    List<CourseItem>? items,
    List<String>? roomIds,
  }) =>
      CourseSection(
        id: id,
        tenantId: tenantId,
        groupId: groupId,
        term: term,
        title: title,
        sortOrder: sortOrder,
        isVisible: isVisible ?? this.isVisible,
        createdAt: createdAt,
        items: items ?? this.items,
        roomIds: roomIds ?? this.roomIds,
      );

  Map<String, dynamic> toCloud() => {
        'id': id,
        'tenant_id': tenantId,
        'group_id': groupId,
        'term': term,
        'title': title,
        'sort_order': sortOrder,
        'is_visible': isVisible,
        'room_ids': roomIds.isEmpty ? null : roomIds,
        'created_at': createdAt.isEmpty ? _nowIso() : createdAt,
      };

  factory CourseSection.fromCloud(Map<String, dynamic> m) => CourseSection(
        id: '${m['id']}',
        tenantId: '${m['tenant_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        term: '${m['term'] ?? 'term_1'}',
        title: '${m['title'] ?? ''}',
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        isVisible: m['is_visible'] != false,
        createdAt: '${m['created_at'] ?? ''}',
        roomIds: [
          if (m['room_ids'] is List)
            for (final id in m['room_ids'] as List)
              if ('$id'.trim().isNotEmpty) '$id',
        ],
      );
}

/// اسم الشعبة بلا تكرار المرحلة — مطابق لـ `cleanGroupName` في TeacherPortal.tsx.
///
/// «فصل عاشر (عاشر (أ))» ← «شعبة (أ)»، و«ثاني عشر علمي (12 علمي)» ← «شعبة 1».
String cleanGroupName(String? groupName, [String? gradeLevel]) {
  if (groupName == null || groupName.isEmpty) return 'شعبة';
  var trimmed = groupName.trim();

  // فك التداخل: أعمق قوسين يحملان حرف الشعبة
  final parens = RegExp(r'\(([^()]+)\)').allMatches(trimmed).toList();
  if (parens.isNotEmpty) {
    final deepest = parens.last.group(0)!.replaceAll(RegExp(r'[()]'), '').trim();
    if (deepest.isNotEmpty && !deepest.contains('علمي') && !deepest.contains('أدبي') && deepest != gradeLevel) {
      return deepest.startsWith('شعبة') ? deepest : 'شعبة ($deepest)';
    }
  }

  if (trimmed.startsWith('فصل ')) trimmed = trimmed.substring(4).trim();

  if (gradeLevel != null && gradeLevel.isNotEmpty) {
    final cleanGrade = gradeLevel.replaceAll(RegExp(r'\s*(ذكور|إناث|بنين|بنات)\s*'), '').trim();
    if (trimmed.contains(cleanGrade) || trimmed.contains('12 علمي') || trimmed.contains('11 علمي')) {
      final remainder = trimmed
          .replaceFirst(cleanGrade, '')
          .replaceAll(RegExp(r'\(12 علمي\)|\(11 علمي\)|\(11 أدبي\)|\(12 أدبي\)'), '')
          .replaceAll(RegExp(r'[()]'), '')
          .trim();
      return remainder.isEmpty ? 'شعبة 1' : (remainder.startsWith('شعبة') ? remainder : 'شعبة $remainder');
    }
  }

  return trimmed;
}

class PortalService {
  const PortalService();

  static const materialsBucket = 'course_materials';

  /// أقصى حجم لملف مادة — 10 ميجابايت كما في حاوية التخزين.
  static const maxMaterialBytes = 10 * 1024 * 1024;

  /// معرّف حصة حتمي: الشعبة نفسها في اليوم نفسه = الحصة نفسها على كل جهاز.
  /// مطابق لـ `AttendanceService.sessionIdFor`.
  static String sessionIdFor(String groupId, String date) => 'ses_${groupId}_$date';

  /// كشف الشعبة اليومي — نفس صيغة الإدارة (`AppStore.roomSessionIdFor`)، فما
  /// يرصده المعلم هو ما تراه الإدارة، لا كشف حصةٍ منفصل لكل مادة.
  static String roomSessionIdFor(String roomId, String date) => 'ses_room_${roomId}_$date';

  /// مطابق لـ `AttendanceService.attendanceIdFor`.
  static String attendanceIdFor(String sessionId, String studentId) => 'att_${sessionId}_$studentId';

  /// هل الطالب من شعبة القاعة — بديل المجموعة التي لا تسجيلات يدوية لها.
  /// مطابق لـ `getTeacherClasses`: مطابقة تامة، فلا تُدخل «علمي 1» طلاب
  /// «علمي 10»، ولا يصير الطالب بلا مرحلة عضواً في كل شعبة.
  static bool studentInRoom(Student s, {required String roomName, required String roomGrade}) =>
      s.status == 'active' &&
      belongsToSection(section: s.section, grade: s.gradeLevel, roomName: roomName, roomGrade: roomGrade);

  /// دخول الطلاب وأولياء الأمور والمعلمين — المقابل لـ `loginWithPortalCode`.
  ///
  /// التحقق في دالة السيرفر `portal-login` بمفتاح الخدمة، لا بقراءة الجداول: القاعدة
  /// محمية بـ RLS، والجهاز لا يرى رموز الدخول ولا يقارنها. عند التطابق الفريد تعيد
  /// الدالة رمزاً لمرة واحدة يُستبدل بجلسة تحمل دور الشخص ومنشأته ومعرّفه، فلا يصل
  /// إلا إلى ما يخصّه.
  ///
  /// تطابقٌ في أكثر من منشأة أو دور يُعيد الخيارات، ويُعاد الاستدعاء بالخيار
  /// المختار في [choice] — ويُتحقق من الرمز من جديد.
  Future<PortalLoginResult> login(String nationalId, String portalCode, {PortalUser? choice}) async {
    final id = nationalId.trim();
    final code = portalCode.trim();
    if (id.isEmpty || code.isEmpty) {
      return const PortalLoginResult(error: 'يرجى إدخال رقم الهوية ورمز الدخول');
    }

    final data = await supabaseInvoke(
      'portal-login',
      {
        'national_id': id,
        'portal_code': code,
        if (choice != null) 'tenant_id': choice.tenantId,
        if (choice != null) 'role': choice.role,
        if (choice != null) 'user_id': choice.id,
      },
      // قبل الدخول لا جلسة للطالب أو وليّ أمره؛ وتوكن إدارةٍ قديم على الجهاز
      // كانت بوابة الدوال ترفضه فيظهر الخطأ كأنه انقطاع إنترنت
      anonymous: true,
    );

    final error = data['error'];
    if (error != null) {
      return PortalLoginResult(error: '$error', offline: data[kOfflineFlag] == true);
    }

    final choices = [
      for (final c in (data['choices'] as List? ?? const []))
        if (c is Map) userFromChoice(Map<String, dynamic>.from(c)),
    ];
    if (choices.length > 1) {
      // وليّ أمر له أكثر من ابن في المدرسة نفسها: هذه ليست مدارس ليختار بينها،
      // بل أبناؤه. يُفتح أولهم، ويبدّل بينهم من شريط الأبناء داخل البوابة.
      final first = choices.first;
      final sameFamily = choice == null &&
          first.isParent &&
          choices.every((u) => u.isParent && u.tenantId == first.tenantId);
      if (sameFamily) return login(nationalId, portalCode, choice: first);
      return PortalLoginResult(users: choices);
    }

    final tokenHash = '${data['token_hash'] ?? ''}';
    final matched = data['choice'];
    if (tokenHash.isEmpty || matched is! Map) {
      return const PortalLoginResult(error: 'رقم الهوية أو كلمة المرور غير صحيحة');
    }
    if (!await supabaseVerifyTokenHash(tokenHash)) {
      return const PortalLoginResult(error: 'تعذّر فتح جلسة البوابة، حاول مجدداً');
    }
    return PortalLoginResult(users: [userFromChoice(Map<String, dynamic>.from(matched))]);
  }

  /// فتح ملف ابن آخر لوليّ الأمر.
  ///
  /// الجلسة مبنية على طالب واحد — معرّفه في التوكن وعليه تقوم سياسات القراءة —
  /// فالتبديل دخولٌ جديد برقم هوية وليّ الأمر وكلمته نفسها، والاختيار يقع على
  /// حساب الابن المطلوب. لا تتغيّر صلاحية واحدة في النظام.
  Future<PortalLoginResult> switchToChild(PortalUser session, String childId) async {
    final parentId = session.parentNationalId.trim().isNotEmpty
        ? session.parentNationalId.trim()
        : session.nationalId.trim();
    if (parentId.isEmpty || session.portalCode.isEmpty || childId.isEmpty) {
      return const PortalLoginResult(error: 'بيانات الدخول غير مكتملة');
    }
    return login(
      parentId,
      session.portalCode,
      choice: PortalUser(
        id: childId,
        name: session.name,
        nationalId: parentId,
        portalCode: session.portalCode,
        role: 'parent',
        tenantId: session.tenantId,
        tenantName: session.tenantName,
      ),
    );
  }

  /// خيار دخول كما تعيده الدالة: `{tenant_id, tenant_name, role, user: {...}}`.
  static PortalUser userFromChoice(Map<String, dynamic> c) {
    final user = c['user'] is Map ? Map<String, dynamic>.from(c['user'] as Map) : const <String, dynamic>{};
    return PortalUser(
      id: '${user['id'] ?? ''}',
      name: '${user['name'] ?? ''}',
      nationalId: '${user['national_id'] ?? ''}',
      portalCode: '${user['portal_code'] ?? ''}',
      role: '${c['role'] ?? user['role'] ?? 'student'}',
      tenantId: '${c['tenant_id'] ?? user['tenant_id'] ?? ''}',
      phone: '${user['phone'] ?? ''}',
      email: '${user['email'] ?? ''}',
      gradeLevel: '${user['grade_level'] ?? ''}',
      section: '${user['section'] ?? ''}',
      subjectIds: [for (final e in (user['subject_ids'] as List? ?? const [])) '$e'],
      tenantName: '${c['tenant_name'] ?? user['tenant_name'] ?? 'منشأة غير محددة'}',
      studentName: '${user['student_name'] ?? ''}',
      parentNationalId: '${user['parent_national_id'] ?? ''}',
      children: [
        for (final ch in (user['children'] as List? ?? const []))
          if (ch is Map) PortalChild.fromJson(Map<String, dynamic>.from(ch)),
      ],
    );
  }

  /// هوية المنشأة للعرض داخل البوابة — مطابق لـ `getPortalBranding`.
  Future<PortalBranding> branding(String tenantId) async {
    final rows = await supabaseSelect(
      'institution_settings',
      filters: {'id': 'eq.$tenantId'},
      limit: 1,
    );
    if (rows == null || rows.isEmpty) return const PortalBranding();
    final row = rows.first;
    final colors = row['colors'];
    final colorMap = colors is Map ? Map<String, dynamic>.from(colors) : const <String, dynamic>{};
    return PortalBranding(
      name: '${row['institution_name'] ?? ''}'.trim().isEmpty ? appName : '${row['institution_name']}',
      logo: '${row['logo'] ?? ''}',
      colors: colors is Map ? InstitutionColors.fromMap(colorMap) : InstitutionColors.defaults,
      paymentMethods: decodePaymentMethods(colorMap[customPaymentMethodsColorKey]),
      gradingScheme: GradingScheme.fromMap(
        colorMap['__grading_scheme'] is Map
            ? Map<String, dynamic>.from(colorMap['__grading_scheme'] as Map)
            : const {},
      ),
    );
  }

  /// ميزات المنشأة للبوابات — قراءة عمود `tenants.features` إن سمحت السياسات.
  Future<Map<String, dynamic>?> tenantFeatures(String tenantId) async {
    final rows = await supabaseSelect(
      'tenants',
      filters: {'id': 'eq.$tenantId'},
      columns: 'features',
      limit: 1,
    );
    final raw = rows?.firstOrNull?['features'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  // ── بوابة الطالب ───────────────────────────────────────────────────────────

  Future<StudentPortalData?> studentData(PortalUser user) async {
    final tenant = {'tenant_id': 'eq.${user.tenantId}'};

    final rows = await supabaseSelect('students', filters: {'id': 'eq.${user.id}'}, limit: 1);
    if (rows == null || rows.isEmpty) return null;
    final student = Student.fromCloud(rows.first);

    // سجلات الطالب نفسه المكرّرة داخل المنشأة (رقم الهوية نفسه): تُجمع كلها كي
    // لا يختفي حضور أو سند سُجّل على السجل الآخر — كمعرّفات `candidateIds`.
    final ids = <String>{user.id};
    final nationalId = student.nationalId.trim().isNotEmpty ? student.nationalId.trim() : user.nationalId.trim();
    if (nationalId.isNotEmpty) {
      final twins = await supabaseSelect(
        'students',
        filters: {...tenant, 'national_id': 'eq.$nationalId'},
        columns: 'id',
      );
      for (final t in twins ?? const <Map<String, dynamic>>[]) {
        ids.add('${t['id']}');
      }
    }
    final byStudent = {'student_id': _inList(ids)};

    final results = await Future.wait([
      branding(user.tenantId),
      tenantFeatures(user.tenantId),
      supabaseSelect('enrollments', filters: byStudent),
      supabaseSelect('groups', filters: tenant),
      // أسماء المعلمين عبر portal_teachers (RLS للطالب) — جدول teachers محجوب عنه
      supabaseSelect('portal_teachers', filters: tenant, columns: 'id,name'),
      supabaseSelect('subjects', filters: tenant, columns: 'id,name'),
      supabaseSelect('rooms', filters: tenant, columns: 'id,name'),
      supabaseSelect('installments', filters: byStudent),
      supabaseSelect('payments', filters: byStudent),
      supabaseSelect('attendance', filters: byStudent),
      supabaseSelect('student_evaluations', filters: byStudent),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];


    final groupById = {for (final g in at(3)) '${g['id']}': g};
    final teacherName = {for (final t in at(4)) '${t['id']}': '${t['name'] ?? ''}'};
    final subjectName = {for (final s in at(5)) '${s['id']}': '${s['name'] ?? ''}'};
    final roomName = {for (final r in at(6)) '${r['id']}': '${r['name'] ?? ''}'};

    // مادة لكل تسجيل نشط، كما في `subjectsWithTeachers`
    final subjects = <PortalSubject>[];
    for (final e in at(2)) {
      if ('${e['status'] ?? 'active'}' != 'active') continue;
      final gid = '${e['group_id']}';
      final g = groupById[gid];
      final groupRoomIds = g == null
          ? const <String>[]
          : Group.fromCloud(g).allRoomIds;
      final groupRooms = [
        for (final id in groupRoomIds)
          if (roomName[id] != null) (id: id, name: roomName[id]!),
      ];
      // تسجيله مختوم بشعبته، وإلا فبالاسم — لا تخمين بأول شعبة
      final enrollRoom = '${e['room_id'] ?? ''}'.trim();
      final studentSection = student.section.trim().toLowerCase();
      final ({String id, String name})? own = groupRooms.length <= 1
          ? (groupRooms.isEmpty ? null : groupRooms.first)
          : groupRooms.where((r) => r.id == enrollRoom).firstOrNull ??
              groupRooms
                  .where((r) => studentSection.isNotEmpty && r.name.trim().toLowerCase() == studentSection)
                  .firstOrNull;
      final r = own ?? (groupRooms.isEmpty ? null : groupRooms.first);
      subjects.add(PortalSubject(
        groupId: gid,
        subjectName: g == null ? 'مادة دراسية' : (subjectName['${g['subject_id']}'] ?? 'مادة دراسية'),
        teacherName: g == null ? 'معلم غير محدد' : (teacherName['${g['teacher_id']}'] ?? 'معلم غير محدد'),
        groupName: '${g?['name'] ?? 'شعبة'}',
        days: [for (final d in (g?['days'] as List? ?? const [])) int.tryParse('$d') ?? 0],
        startTime: '${g?['start_time'] ?? ''}',
        endTime: '${g?['end_time'] ?? ''}',
        roomName: r?.name ?? '',
        roomId: own?.id ?? '',
      ));
    }

    // الحضور: تاريخه في الحصة المرتبطة، فتُجلب حصصه وحدها
    final sessionIds = at(9).map((r) => '${r['session_id'] ?? ''}').where((s) => s.isNotEmpty).toSet();
    final sessionRows = <Map<String, dynamic>>[];
    if (sessionIds.isNotEmpty) {
      final sessions = await supabaseSelect(
        'sessions',
        filters: {'id': _inList(sessionIds)},
        columns: 'id,session_date,group_id',
      );
      sessionRows.addAll(sessions ?? const []);
    }
    final sessionObjs = [
      for (final s in sessionRows)
        ClassSession(
          id: '${s['id']}',
          groupId: '${s['group_id'] ?? ''}',
          sessionDate: '${s['session_date'] ?? ''}'.split('T').first,
          roomId: '',
        ),
    ];
    final rawMarks = <AttendanceMark>[];
    for (final r in at(9)) {
      final raw = '${r['status'] ?? ''}';
      // «متأخر» أُلغيت من النظام: كل ما ليس حاضراً أو مأذوناً غياب
      final status = raw == 'present' ? 'present' : (raw == 'excused' ? 'excused' : 'absent');
      rawMarks.add(AttendanceMark.fromCloud({...r, 'status': status}));
    }
    // يوم بيوم: غياب يوم رصده ست مواد كان يُعدّ ستة أيام غياب
    final days = dailyAttendance(rawMarks, sessionObjs);
    final present = days.where((d) => d.status == 'present').length;
    final absent = days.where((d) => d.status == 'absent').length;
    final excused = days.where((d) => d.status == 'excused').length;
    final marks = [
      for (final d in days)
        AttendanceMark(
          id: d.date,
          studentId: student.id,
          date: d.date,
          status: d.status,
        ),
    ];

    final evaluations = [
      for (final r in at(10))
        () {
          final e = StudentEvaluation.fromCloud(r);
          return e.withNames(
            subjectName: subjectName[e.subjectId] ?? 'مادة دراسية',
            teacherName: teacherName[e.teacherId] ?? 'معلم المادة',
          );
        }(),
    ]..sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));

    return StudentPortalData(
      student: student,
      branding: results[0] as PortalBranding,
      features: results[1] as Map<String, dynamic>?,
      subjects: subjects,
      evaluations: evaluations,
      attendance: PortalAttendance(
        total: marks.length,
        present: present,
        absent: absent,
        excused: excused,
        records: marks,
      ),
      finance: PortalFinance.compute(
        studentBalance: student.balance,
        installments: at(7).map(Installment.fromCloud).toList(),
        payments: at(8).map(Payment.fromCloud).toList(),
      ),
    );
  }

  // ── بوابة المعلم ───────────────────────────────────────────────────────────

  /// أسماء طلاب البوابة بلا PII — عبر `portal_students` إن وُجدت، وإلا أعمدة محدودة.
  /// طلاب مراحل بعينها — لمدرسة لا تسجّل الطلاب في المجموعات، فشعبة المادة
  /// هي ما يربط المعلم بطلابه. أعمدة آمنة بلا بيانات شخصية.
  /// `null` = لم تُجب السحابة. القائمة الفارغة = أجابت ولا طلاب.
  Future<List<Student>?> _portalStudentsOfGrades(
    Set<String> grades,
    Map<String, String> tenant,
  ) async {
    final filters = {...tenant, 'grade_level': _inList(grades)};
    // المنظر قد ينجح بلا صفوف لقيد RLS — عندها يُجرَّب الجدول قبل الاستسلام،
    // وإلا بقي كشف الشعبة فارغاً والسحابة مليئة بطلابها.
    final viaView = await supabaseSelect('portal_students', filters: filters, columns: _portalStudentCols);
    if (viaView != null && viaView.isNotEmpty) {
      return [for (final r in viaView) Student.fromCloud(_withFullName(r))];
    }
    final rows = await supabaseSelect('students', filters: filters, columns: _portalStudentCols);
    if (rows != null) return [for (final r in rows) Student.fromCloud(_withFullName(r))];
    return viaView == null ? null : const [];
  }

  /// `null` = لم تُجب السحابة. القائمة الفارغة = أجابت ولا طلاب.
  Future<List<Map<String, dynamic>>?> _portalStudentRows(
    Set<String> enrolledIds,
    Map<String, String> tenant,
  ) async {
    if (enrolledIds.isEmpty) return const [];
    final idFilter = {'id': _inList(enrolledIds)};

    final viaView = await supabaseSelect(
      'portal_students',
      filters: {...tenant, ...idFilter},
      columns: _portalStudentCols,
    );
    if (viaView != null && viaView.isNotEmpty) return [for (final r in viaView) _withFullName(r)];

    final rows = await supabaseSelect('students', filters: idFilter, columns: _portalStudentCols);
    if (rows != null) return [for (final r in rows) _withFullName(r)];
    return viaView == null ? null : const [];
  }

  /// بحث أسماء طلاب بمعرّفاتهم — لسجل التقييمات حين يغيب الطالب عن كشف الشعبة الحالية.
  Future<Map<String, String>> studentNamesByIds(Set<String> ids, String tenantId) async {
    final clean = {for (final id in ids) if (id.trim().isNotEmpty) id.trim()};
    if (clean.isEmpty) return const {};
    final rows = await _portalStudentRows(clean, {'tenant_id': 'eq.$tenantId'}) ?? const [];
    return {
      for (final r in rows)
        if ('${r['id']}'.isNotEmpty)
          '${r['id']}': () {
            final full = '${r['full_name'] ?? ''}'.trim();
            if (full.isNotEmpty) return full;
            final name = '${r['name'] ?? ''}'.trim();
            return name;
          }(),
    }..removeWhere((_, v) => v.isEmpty);
  }

  Future<TeacherPortalData> teacherData(PortalUser user) async {
    final tenant = {'tenant_id': 'eq.${user.tenantId}'};

    // المعلم نفسه قد يُسجَّل مرتين في المنشأة: رقم الهوية يجمع مجموعاته كلها
    final teacherIds = <String>{user.id};
    if (user.nationalId.trim().isNotEmpty) {
      final twins = await supabaseSelect(
        'teachers',
        filters: {...tenant, 'national_id': 'eq.${user.nationalId.trim()}'},
        columns: 'id',
      );
      for (final t in twins ?? const <Map<String, dynamic>>[]) {
        teacherIds.add('${t['id']}');
      }
    }

    final results = await Future.wait([
      branding(user.tenantId),
      tenantFeatures(user.tenantId),
      supabaseSelect('groups', filters: {...tenant, 'teacher_id': _inList(teacherIds)}),
      supabaseSelect('subjects', filters: tenant),
      supabaseSelect('rooms', filters: tenant),
      supabaseSelect('teachers', filters: {...tenant, 'id': 'eq.${user.id}'}, columns: 'academic_year_id', limit: 1),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

    // عمود الردّ: المجموعات والشعب. سقوط أيٍّ منهما يعني أن السحابة لم تُجب،
    // فما يُبنى بعده ناقص ولا يصلح أن يُكتب فوق نسخة الجهاز.
    var complete = results[2] != null && results[4] != null;

    final teacherYearId = () {
      final rows = at(5);
      if (rows.isEmpty) return null;
      final id = '${rows.first['academic_year_id'] ?? ''}';
      return id.isEmpty ? null : id;
    }();

    final groups = at(2)
        .map(Group.fromCloud)
        .where((g) => g.isActive)
        .where((g) => g.isSchoolGroup) // المدرسة فقط — بلا مجموعات مركز مدفوعة/مجدولة
        .where((g) {
          // مجموعات عام سجل المعلم فقط — وإلا تظهر صفوف أعوام سابقة بعد الإغلاق
          if (teacherYearId == null) return true;
          return g.academicYearId.isEmpty || g.academicYearId == teacherYearId;
        })
        .toList();
    final subjects = at(3).map(SubjectItem.fromCloud).toList();
    final subjectName = {for (final s in subjects) s.id: s.name};
    final rooms = {for (final r in at(4)) '${r['id']}': r};

    // طلاب التسجيلات فقط — عبر portal_students إن وُجدت (بلا PII)، وإلا أعمدة محدودة
    final enrollmentRows = groups.isEmpty
        ? const <Map<String, dynamic>>[]
        : await supabaseSelect('enrollments', filters: {'group_id': _inList(groups.map((g) => g.id))});
    if (enrollmentRows == null) complete = false;
    final enrollments = enrollmentRows ?? const <Map<String, dynamic>>[];
    final enrolledIds = {
      for (final e in enrollments)
        if ('${e['status'] ?? 'active'}' == 'active') '${e['student_id']}',
    }..removeWhere((id) => id.isEmpty);
    final studentRows = await _portalStudentRows(enrolledIds, tenant);
    if (studentRows == null) complete = false;
    var students = (studentRows ?? const <Map<String, dynamic>>[]).map(Student.fromCloud).toList();

    // المدرسة تُسند المادة للشعبة: الطلاب يُعرفون بشعبتهم لا بتسجيل كلٍّ منهم
    // في المادة. فيُجلب طلاب مراحل شعب المعلم دائماً، ويُطابَقون بالشعبة أدناه.
    final gradesOfRooms = <String>{
      for (final g in groups)
        for (final id in g.allRoomIds)
          if (rooms[id] != null) '${rooms[id]!['grade_level'] ?? ''}'.trim(),
    }..removeWhere((g) => g.isEmpty);
    if (gradesOfRooms.isNotEmpty) {
      final ofGrades = await _portalStudentsOfGrades(gradesOfRooms, tenant);
      if (ofGrades == null) complete = false;
      final seen = {for (final s in students) s.id};
      students = [...students, ...?ofGrades?.where((s) => !seen.contains(s.id))];
    }
    final byId = {for (final s in students) s.id: s};

    final classes = <TeacherClass>[];
    for (final group in groups) {
      var list = [
        for (final e in enrollments)
          if ('${e['group_id']}' == group.id && '${e['status'] ?? 'active'}' == 'active' && byId['${e['student_id']}'] != null)
            byId['${e['student_id']}']!,
      ];

      // طلاب شعب المادة يُضافون لمسجّليها: الشعبة هي ما يربط المعلم بطلابه
      final groupRooms = [
        for (final id in group.allRoomIds)
          if (rooms[id] != null) rooms[id]!,
      ];
      if (groupRooms.isNotEmpty) {
        final seen = {for (final s in list) s.id};
        list = [
          ...list,
          for (final s in students)
            if (!seen.contains(s.id) &&
                groupRooms.any((room) => studentBelongsToRoom(s, Classroom.fromCloud(room))))
              s,
        ];
      }

      classes.add(TeacherClass(
        group: group,
        students: list,
        subjectName: subjectName[group.subjectId] ?? '',
        roomName: groupRooms.map((room) => '${room['name'] ?? ''}').join('، '),
        rooms: [
          for (final room in groupRooms)
            PortalRoom(
              id: '${room['id'] ?? ''}',
              name: '${room['name'] ?? ''}',
              gradeLevel: '${room['grade_level'] ?? ''}',
            ),
        ],
      ));
    }

    final homerooms = await _homeroomClasses(teacherIds, tenant, teacherYearId, rooms);
    if (homerooms == null) complete = false;

    return TeacherPortalData(
      branding: results[0] as PortalBranding,
      features: results[1] as Map<String, dynamic>?,
      classes: classes,
      subjects: subjects,
      homerooms: homerooms ?? const [],
      complete: complete,
    );
  }

  /// شعب المربي وطلابها بتفاصيل التواصل وكلمات المرور — بلا حقول مالية.
  /// `null` = لم تُجب السحابة عن طلاب الشعب.
  Future<List<HomeroomClass>?> _homeroomClasses(
    Set<String> teacherIds,
    Map<String, String> tenant,
    String? teacherYearId,
    Map<String, Map<String, dynamic>> roomsById,
  ) async {
    final mine = <Map<String, dynamic>>[
      for (final room in roomsById.values)
        if (teacherIds.contains('${room['homeroom_teacher_id'] ?? ''}')) room,
    ];
    if (mine.isEmpty) return const [];

    // صفوف العام الحالي فقط إن عُرف عام المعلم
    final filtered = [
      for (final room in mine)
        if (teacherYearId == null ||
            '${room['academic_year_id'] ?? ''}'.isEmpty ||
            '${room['academic_year_id']}' == teacherYearId)
          room,
    ];
    if (filtered.isEmpty) return const [];

    final grades = <String>{
      for (final r in filtered)
        if ('${r['grade_level'] ?? ''}'.trim().isNotEmpty) '${r['grade_level']}'.trim(),
    };

    // جلب الطلاب: جدول students قد يرجع [] بسبب RLS للمعلم (نجاح بلا صفوف)
    // فلا نكتفي بـ ?? — إن فرغ نجرّب portal_students ثم بدون فلتر مرحلة.
    // أجابت السحابة ولو مرة واحدة؟ لو لم تُجب قط فالشبكة مقطوعة، لا الشعبة خالية.
    var answered = false;
    Future<List<Map<String, dynamic>>> fetch({
      required String table,
      required String columns,
      Map<String, String> extra = const {},
    }) async {
      final rows = await supabaseSelect(table, filters: {...tenant, ...extra}, columns: columns);
      if (rows != null) answered = true;
      return rows ?? const [];
    }

    var rows = <Map<String, dynamic>>[];
    if (grades.isNotEmpty) {
      rows = await fetch(table: 'students', columns: _homeroomStudentCols, extra: {'grade_level': _inList(grades)});
      if (rows.isEmpty) {
        rows = await fetch(table: 'portal_students', columns: _portalStudentCols, extra: {'grade_level': _inList(grades)});
      }
    }
    // بلا نتائج بفلتر المرحلة: اجلب كل طلاب المنشأة المتاحين للبوابة وطابِق محلياً
    if (rows.isEmpty) {
      rows = await fetch(table: 'portal_students', columns: _portalStudentCols);
      if (rows.isEmpty) {
        rows = await fetch(table: 'students', columns: _homeroomStudentCols);
      }
    }
    if (!answered) return null;

    final students = [for (final r in rows) Student.fromCloud(_withFullName(r))];
    final out = <HomeroomClass>[];
    for (final room in filtered) {
      final classroom = Classroom.fromCloud(room);
      // studentBelongsToRoom ي容忍 «أ» مقابل «شعبة (أ)» — studentInRoom كان يُفرّغ القائمة
      final list = [
        for (final s in students)
          if (s.status != 'withdrawn' && studentBelongsToRoom(s, classroom)) s,
      ]..sort((a, b) => a.fullName.compareTo(b.fullName));
      out.add(
        HomeroomClass(
          room: PortalRoom(
            id: classroom.id,
            name: classroom.name,
            gradeLevel: classroom.gradeLevel,
          ),
          students: list,
        ),
      );
    }
    out.sort((a, b) {
      final g = a.room.gradeLevel.compareTo(b.room.gradeLevel);
      return g != 0 ? g : a.room.name.compareTo(b.room.name);
    });
    return out;
  }

  /// تقييمات طالب واحد — لملف «صفي» عند المربي.
  Future<List<StudentEvaluation>> studentEvaluations(String studentId) async {
    if (studentId.isEmpty) return const [];
    final rows = await _must(
      'تقييمات الطالب',
      supabaseSelect(
        'student_evaluations',
        filters: {'student_id': 'eq.$studentId'},
        order: 'created_at.desc',
      ),
    );
    return [for (final r in rows) StudentEvaluation.fromCloud(r)];
  }

  /// ملخص حضور طالب على أيام معلومة.
  Future<Map<String, String>> studentAttendanceMarks({
    required String studentId,
    required String roomId,
    required List<String> dates,
  }) async {
    if (studentId.isEmpty || roomId.isEmpty || dates.isEmpty) return {};
    final sessionIds = {for (final d in dates) PortalService.roomSessionIdFor(roomId, d)};
    final rows = await _must(
      'حضور الطالب',
      supabaseSelect(
        'attendance',
        filters: {
          'session_id': 'in.(${sessionIds.join(',')})',
          'student_id': 'eq.$studentId',
        },
        columns: 'session_id,status',
      ),
    );
    final bySession = {
      for (final r in rows) '${r['session_id']}': '${r['status'] ?? ''}',
    };
    return {
      for (final d in dates)
        if ((bySession[PortalService.roomSessionIdFor(roomId, d)] ?? '').isNotEmpty)
          d: bySession[PortalService.roomSessionIdFor(roomId, d)]!,
    };
  }

  /// الحصة القائمة لهذه الشعبة واليوم إن وُجدت — أنشأها جهاز الإدارة بمعرّف
  /// آخر — وإلا فالمعرّف الحتمي. إنشاء حصة ثانية لليوم نفسه كان يشطر الرصد.
  /// كشف الشعبة ليوم: القائم إن وُجد (قد تكون الإدارة أنشأته)، وإلا الحتمي.
  Future<String> _roomSessionFor(String roomId, String date) async {
    final existing = await supabaseSelect(
      'sessions',
      filters: {'room_id': 'eq.$roomId', 'session_date': 'eq.$date'},
      columns: 'id',
      limit: 1,
    );
    if (existing != null && existing.isNotEmpty) return '${existing.first['id']}';
    return roomSessionIdFor(roomId, date);
  }

  /// رصد يوم للمعلم: دمج كشف الشعبة + حصة المادة حسب أحدث `updated_at`
  /// — المقابل لـ `PortalService.getTeacherDayAttendance`.
  Future<Map<String, String>> getTeacherDayAttendance({
    required String groupId,
    required String date,
    required Map<String, String> roomOf,
  }) async {
    if (groupId.isEmpty || date.isEmpty || roomOf.isEmpty) return {};

    final subjectSessionId = sessionIdFor(groupId, date);
    String? roomSessionOf(String studentId) {
      final roomId = roomOf[studentId];
      return roomId == null || roomId.isEmpty ? null : roomSessionIdFor(roomId, date);
    }

    final roomIds = roomOf.values.where((r) => r.isNotEmpty).toSet();
    final sessionIds = {
      subjectSessionId,
      for (final r in roomIds) roomSessionIdFor(r, date),
    };

    final rows = await _must(
      'رصد اليوم',
      supabaseSelect(
        'attendance',
        filters: {'session_id': 'in.(${sessionIds.join(',')})'},
        columns: 'session_id,student_id,status,updated_at,notes',
      ),
    );

    final chosen = <String, Map<String, dynamic>>{};
    for (final rec in rows) {
      final studentId = '${rec['student_id'] ?? ''}';
      if (!roomOf.containsKey(studentId)) continue;
      final sessionId = '${rec['session_id'] ?? ''}';
      if (sessionId != subjectSessionId && sessionId != roomSessionOf(studentId)) continue;
      final prev = chosen[studentId];
      final at = '${rec['updated_at'] ?? ''}';
      if (prev == null || at.compareTo('${prev['updated_at'] ?? ''}') > 0) {
        chosen[studentId] = rec;
      }
    }

    return {
      for (final e in chosen.entries) e.key: '${e.value['status'] ?? 'present'}',
    };
  }

  /// رصد أسبوع للمعلم بدمج الشعبة/المادة لكل يوم.
  Future<Map<String, Map<String, String>>> weekTeacherAttendance({
    required String groupId,
    required List<String> dates,
    required Map<String, String> roomOf,
  }) async {
    final out = <String, Map<String, String>>{};
    for (final date in dates) {
      final day = await getTeacherDayAttendance(groupId: groupId, date: date, roomOf: roomOf);
      if (day.isNotEmpty) out[date] = day;
    }
    return out;
  }

  /// كشف حضور الشعبة ليومٍ: الطالب ← (حالته، معرّف سجله).
  /// رصد الأسبوع كلّه لشعبة: `{تاريخ: {معرّف الطالب: الحالة}}`.
  ///
  /// طلبان لا اثنا عشر: كشوف الأيام دفعةً، ثم رصدها دفعةً — شريط الأيام عند
  /// المعلم يُظهر اكتمال كل يوم كما يُظهره عند الإدارة.
  Future<Map<String, Map<String, String>>> weekAttendance(String roomId, List<String> dates) async {
    if (roomId.isEmpty || dates.isEmpty) return {};

    final sessions = await _must(
      'حصص الأسبوع',
      supabaseSelect(
        'sessions',
        filters: {
          'room_id': 'eq.$roomId',
          'session_date': 'in.(${dates.join(',')})',
        },
        columns: 'id,session_date',
      ),
    );

    final dateOf = <String, String>{
      for (final r in sessions) '${r['id']}': '${r['session_date'] ?? ''}'.split('T').first,
    };
    if (dateOf.isEmpty) return {};

    final rows = await supabaseSelect(
      'attendance',
      filters: {'session_id': 'in.(${dateOf.keys.join(',')})'},
      columns: 'session_id,student_id,status',
    );

    final out = <String, Map<String, String>>{};
    for (final r in rows ?? const <Map<String, dynamic>>[]) {
      final date = dateOf['${r['session_id']}'];
      if (date == null || date.isEmpty) continue;
      out.putIfAbsent(date, () => {})['${r['student_id']}'] = '${r['status'] ?? 'present'}';
    }
    return out;
  }

  Future<Map<String, ({String status, String id})>> sessionAttendance(String roomId, String date) async {
    final sessionId = await _roomSessionFor(roomId, date);
    final rows = await supabaseSelect(
      'attendance',
      filters: {'session_id': 'eq.$sessionId'},
      columns: 'id,student_id,status',
    );
    return {
      for (final r in rows ?? const <Map<String, dynamic>>[])
        '${r['student_id']}': (status: '${r['status'] ?? 'present'}', id: '${r['id']}'),
    };
  }

  /// رصد حضور اليوم لشعبة من بوابة المعلم.
  ///
  /// يكتب في كشف الشعبة اليومي نفسه الذي تكتب فيه الإدارة — لا كشف حصة لكل
  /// مادة — فالغياب يُرصد مرة واحدة ويراه الطرفان.
  ///
  /// سجل الطالب القائم يُحدَّث بمعرّفه نفسه: التصالح على (الكشف، الطالب) مع
  /// معرّف جديد كان يستبدل المفتاح الأساسي فيبقى السجل القديم يتيماً على الأجهزة.
  ///
  /// [changedStudentIds] إن وُجدت: تُرفع أرصدة هؤلاء فقط (delta) بدل يوم كامل،
  /// فيبقى لمس الحضور سريعاً على الشبكة الضعيفة.
  Future<void> saveAttendance({
    required String roomId,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
    Set<String>? changedStudentIds,
  }) async {
    final sessionId = await _roomSessionFor(roomId, date);
    final now = _nowIso();

    await supabaseUpsert('sessions', [
      {
        'id': sessionId,
        'group_id': null,
        'teacher_id': teacher.id,
        'room_id': roomId,
        'session_date': date,
        'start_time': '00:00',
        'end_time': '23:59',
        'status': 'completed',
        'tenant_id': teacher.tenantId,
        'updated_at': now,
      }
    ]);

    final toUpsert = changedStudentIds == null
        ? statuses
        : {
            for (final id in changedStudentIds)
              if (statuses.containsKey(id)) id: statuses[id]!,
          };
    if (toUpsert.isEmpty) return;

    final existing = await supabaseSelect(
      'attendance',
      filters: {
        'session_id': 'eq.$sessionId',
        if (changedStudentIds != null && changedStudentIds.isNotEmpty)
          'student_id': _inList(changedStudentIds),
      },
      columns: 'id,student_id',
    );
    final idOf = {
      for (final r in existing ?? const <Map<String, dynamic>>[]) '${r['student_id']}': '${r['id']}',
    };

    await supabaseUpsert(
      'attendance',
      [
        for (final entry in toUpsert.entries)
          {
            'id': idOf[entry.key] ?? attendanceIdFor(sessionId, entry.key),
            'session_id': sessionId,
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

  // ── الدرجات والتقييمات ────────────────────────────────────────────────────

  /// تقييمات شعبة، الأحدث أولاً — `getEvaluationsByGroup`.
  Future<List<StudentEvaluation>> groupEvaluations(String groupId) async {
    final rows = await _must(
      'درجات المادة',
      supabaseSelect('student_evaluations', filters: {'group_id': 'eq.$groupId'}),
    );
    return rows.map(StudentEvaluation.fromCloud).toList()
      ..sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
  }

  /// كشف درجات الشعبة دفعة واحدة — `saveBatchEvaluations`.
  Future<void> saveEvaluations(List<StudentEvaluation> batch, String tenantId) {
    final now = _nowIso();
    return supabaseUpsert('student_evaluations', [
      for (final e in batch) {...e.toCloud(), 'tenant_id': tenantId, 'created_at': now, 'updated_at': now},
    ]);
  }

  Future<void> deleteEvaluation(String id) => supabaseDelete('student_evaluations', {'id': 'eq.$id'});

  /// تعديل علامة مرصودة — مقابل `EvaluationService.updateScore` في الويب.
  Future<void> updateEvaluationScore(String id, double score) => supabaseUpdate(
        'student_evaluations',
        {'id': 'eq.$id'},
        {'score': score, 'updated_at': _nowIso()},
      );

  // ── المودل (المقابل لـ moodle.service.ts) ─────────────────────────────────

  /// وحدات مادة مع موادها — `fetchGroupSections`. «أخرى» تشمل القيمة القديمة `general`.
  ///
  /// [roomId] شعبة الطالب: يرى وحدات كل الشعب ووحدات شعبته. بلا شعبة (المعلم) = الكل.
  Future<List<CourseSection>> groupSections({
    required String tenantId,
    required String groupId,
    String term = 'all',
    bool includeHidden = false,
    String? roomId,
  }) async {
    final filters = <String, String>{'tenant_id': 'eq.$tenantId', 'group_id': 'eq.$groupId'};
    if (term == 'other' || term == 'general') {
      filters['term'] = 'in.(general,other)';
    } else if (term != 'all') {
      filters['term'] = 'eq.$term';
    }
    if (!includeHidden) filters['is_visible'] = 'eq.true';

    final rows = await _must(
      'وحدات المادة',
      supabaseSelect('course_sections', filters: filters, order: 'sort_order.asc,created_at.asc'),
    );
    if (rows.isEmpty) return const [];
    var sections = rows.map(CourseSection.fromCloud).toList();
    if (roomId != null && roomId.isNotEmpty) {
      sections = [for (final s in sections) if (sectionVisibleToRoom(s, roomId)) s];
    }
    if (sections.isEmpty) return const [];

    final itemRows = await supabaseSelect(
      'course_items',
      filters: {'tenant_id': 'eq.$tenantId', 'section_id': _inList(sections.map((s) => s.id))},
      order: 'sort_order.asc,created_at.asc',
    );
    final bySection = <String, List<CourseItem>>{};
    for (final r in itemRows ?? const <Map<String, dynamic>>[]) {
      final item = CourseItem.fromCloud(r);
      bySection.putIfAbsent(item.sectionId, () => []).add(item);
    }
    return [for (final s in sections) s.copyWith(items: bySection[s.id] ?? const [])];
  }

  Future<CourseSection> createSection({
    required String tenantId,
    required String groupId,
    required String term,
    required String title,
    int sortOrder = 0,
    List<String>? roomIds,
  }) async {
    final section = CourseSection(
      id: _uuid.v4(),
      tenantId: tenantId,
      groupId: groupId,
      term: term,
      title: title.trim(),
      sortOrder: sortOrder,
      createdAt: _nowIso(),
      roomIds: roomIds ?? const [],
    );
    await supabaseUpsert('course_sections', [section.toCloud()]);
    return section;
  }

  /// تحديث شعب الوحدة أو عنوانها — فارغ = كل شعب المادة.
  Future<void> updateSection(
    String sectionId, {
    String? title,
    String? term,
    bool? isVisible,
    List<String>? roomIds,
  }) async {
    final patch = <String, dynamic>{
      if (title != null) 'title': title,
      if (term != null) 'term': term,
      if (isVisible != null) 'is_visible': isVisible,
      if (roomIds != null) 'room_ids': roomIds.isEmpty ? null : roomIds,
    };
    if (patch.isEmpty) return;
    await supabaseUpdate('course_sections', {'id': 'eq.$sectionId'}, patch);
  }

  /// كتابة وحدة جاهزة (بمعرّفها) — تسمح ببنائها على الجهاز ثم رفعها لاحقاً.
  Future<void> saveSection(CourseSection section) => supabaseUpsert('course_sections', [section.toCloud()]);

  /// كتابة مادة جاهزة (بمعرّفها).
  Future<void> saveItem(CourseItem item) => supabaseUpsert('course_items', [item.toCloud()]);

  Future<void> setSectionVisible(String sectionId, bool visible) =>
      supabaseUpdate('course_sections', {'id': 'eq.$sectionId'}, {'is_visible': visible});

  /// حذف وحدة وملفات موادها غير المشتركة مع شعب أخرى.
  Future<void> deleteSection(CourseSection section, String tenantId) async {
    final paths = [
      for (final it in section.items)
        if (materialPath(it.contentUrl) != null) materialPath(it.contentUrl)!,
    ];
    final removable = await _unsharedFiles(paths, tenantId, sectionId: section.id);
    if (removable.isNotEmpty) await storageRemove(materialsBucket, removable);
    await supabaseDelete('course_sections', {'id': 'eq.${section.id}', 'tenant_id': 'eq.$tenantId'});
  }

  /// مسار الملف داخل الحاوية من رابطه العام، أو `null` لرابط خارجي.
  static String? materialPath(String url) {
    const marker = '/$materialsBucket/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    final rest = url.substring(i + marker.length);
    return rest.isEmpty ? null : Uri.decodeComponent(rest);
  }

  /// رابط فتح مادة — مطابق لـ `MoodleService.openMaterial`.
  ///
  /// حاوية المواد صارت خاصة: الرابط المحفوظ في `content_url` لا يُفتح مباشرةً،
  /// بل يُوقَّع لساعة عند كل فتح، وكان أي ملف دراسي يفتحه من يملك رابطه بلا
  /// تسجيل دخول. الروابط الخارجية (يوتيوب وغيره) تعود كما هي.
  Future<String?> materialOpenUrl(String contentUrl) async {
    final url = contentUrl.trim();
    if (url.isEmpty) return null;
    final path = materialPath(url);
    if (path == null) return url;
    return storageSignedUrl(materialsBucket, path);
  }

  /// نوع الملف المسموح من امتداده، أو `null` لغير المدعوم (PDF والصور وحدها).
  static String? materialMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  /// رفع ملف مادة — `uploadMaterialFile`. يُعيد الرابط العام، ويرمي برسالة عربية.
  Future<String> uploadMaterial({
    required List<int> bytes,
    required String fileName,
    required String tenantId,
  }) async {
    if (bytes.length > maxMaterialBytes) {
      throw const PortalException('حجم الملف يتجاوز الحد الأقصى المسموح به (10 ميجابايت)');
    }
    final mime = materialMime(fileName);
    if (mime == null) throw const PortalException('نوع الملف غير مدعوم؛ يُسمح بملفات PDF والصور فقط');

    final ext = fileName.split('.').last.toLowerCase();
    final path = '$tenantId/${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.$ext';
    try {
      return await storageUpload(materialsBucket, path, bytes, mime);
    } catch (_) {
      throw const PortalException('فشل رفع الملف إلى السحابة');
    }
  }

  Future<CourseItem> createItem(CourseItem draft) async {
    final item = CourseItem(
      id: _uuid.v4(),
      tenantId: draft.tenantId,
      sectionId: draft.sectionId,
      groupId: draft.groupId,
      title: draft.title.trim(),
      type: draft.type,
      contentUrl: draft.contentUrl,
      fileName: draft.fileName,
      fileSize: draft.fileSize,
      description: draft.description.trim(),
      dueDate: draft.type == 'assignment' ? draft.dueDate : '',
      sortOrder: draft.sortOrder,
      createdAt: _nowIso(),
    );
    await supabaseUpsert('course_items', [item.toCloud()]);
    return item;
  }

  Future<void> deleteItem(CourseItem item, String tenantId) async {
    final path = materialPath(item.contentUrl);
    if (path != null) {
      final removable = await _unsharedFiles([path], tenantId, itemId: item.id);
      if (removable.isNotEmpty) await storageRemove(materialsBucket, removable);
    }
    await supabaseDelete('course_items', {'id': 'eq.${item.id}', 'tenant_id': 'eq.$tenantId'});
  }

  /// ملفات لا يشير إليها عنصر آخر — نسخ القسم ينسخ الرابط لا الملف.
  Future<List<String>> _unsharedFiles(
    List<String> paths,
    String tenantId, {
    String? itemId,
    String? sectionId,
  }) async {
    final removable = <String>[];
    for (final path in paths) {
      final fileName = path.split('/').last;
      if (fileName.isEmpty) continue;
      try {
        final rows = await supabaseSelect(
          'course_items',
          columns: 'id,section_id,content_url',
          filters: {
            'tenant_id': 'eq.$tenantId',
            'content_url': 'like.%/course_materials/%$fileName%',
          },
        );
        if (rows == null) continue; // عند التعذّر يبقى الملف
        final others = rows.where((r) {
          if (itemId != null && '${r['id']}' == itemId) return false;
          if (sectionId != null && '${r['section_id']}' == sectionId) return false;
          return true;
        });
        if (others.isEmpty) removable.add(path);
      } catch (_) {
        // ملف زائد في المخزن أهون من مادة معطوبة
      }
    }
    return removable;
  }

  /// نسخ وحدة بموادها إلى شعب أخرى — `copySectionToGroups`. يُعيد عدد الشعب.
  ///
  /// الملف نفسه لا يُنسخ: المواد المنسوخة تشير إلى الرابط ذاته.
  Future<int> copySectionToGroups(CourseSection section, List<String> groupIds, String tenantId) async {
    var count = 0;
    for (final gid in groupIds) {
      final copy = CourseSection(
        id: _uuid.v4(),
        tenantId: tenantId,
        groupId: gid,
        term: section.term,
        title: section.title,
        sortOrder: section.sortOrder,
        isVisible: section.isVisible,
        createdAt: _nowIso(),
      );
      try {
        await supabaseUpsert('course_sections', [copy.toCloud()]);
      } catch (_) {
        continue;
      }
      if (section.items.isNotEmpty) {
        await supabaseUpsert('course_items', [
          for (final it in section.items)
            CourseItem(
              id: _uuid.v4(),
              tenantId: tenantId,
              sectionId: copy.id,
              groupId: gid,
              title: it.title,
              type: it.type,
              contentUrl: it.contentUrl,
              fileName: it.fileName,
              fileSize: it.fileSize,
              description: it.description,
              dueDate: it.dueDate,
              sortOrder: it.sortOrder,
              createdAt: _nowIso(),
            ).toCloud(),
        ]);
      }
      count++;
    }
    return count;
  }
}

/// خطأ برسالة جاهزة للعرض.
class PortalException implements Exception {
  const PortalException(this.message);
  final String message;

  @override
  String toString() => message;
}
