import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'academic_matching.dart';
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
String _inList(Iterable<String> values) => 'in.(${values.map((v) => '"$v"').join(',')})';

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
    this.studentName = '',
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
  });

  final String name;
  final String logo;
  final InstitutionColors colors;
  final List<PaymentMethodItem> paymentMethods;

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
  });

  final String groupId;
  final String subjectName;
  final String teacherName;
  final String groupName;
  final List<int> days;
  final String startTime;
  final String endTime;
  final String roomName;
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
  final String createdAt;
  final String updatedAt;

  /// للعرض فقط — تُملأ عند الجلب ولا تُرفع.
  final String subjectName;
  final String teacherName;

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
        createdAt: createdAt,
        updatedAt: updatedAt,
        subjectName: subjectName,
        teacherName: teacherName,
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
  });

  final String id;
  final String title;
  final double amount;

  /// `yyyy-mm-dd`
  final String dueDate;
  final double paidAmount;

  /// `paid | unpaid | partially_paid`
  final String status;

  /// حلّ موعده (أو لا موعد له): مطلوب الآن لا قسطٌ قادم.
  final bool isDueNow;

  double get remaining => (amount - paidAmount) < 0 ? 0 : amount - paidAmount;
}

/// خلاصة مالية الطالب — مطابق لـ `StudentFinancialSummary`.
class PortalFinance {
  const PortalFinance({
    this.totalDue = 0,
    this.totalPaid = 0,
    this.remainingBalance = 0,
    this.currentDue = 0,
    this.installments = const [],
    this.payments = const [],
  });

  /// إجمالي الرسوم: مجموع الأقساط كلها.
  final double totalDue;
  final double totalPaid;

  /// المتبقي لكامل العام، ومنه أقساط لم يحن موعدها.
  final double remainingBalance;

  /// المستحق حالياً — يطابق الرصيد المحاسبي للطالب في صفحته بالإدارة.
  final double currentDue;
  final List<PortalInstallment> installments;
  final List<Payment> payments;

  /// الحساب نفسه في `getStudentPortalData`.
  ///
  /// المستحق حالياً هو دين الطالب المسجَّل إن كان عليه دين؛ وإلا فالأقساط التي
  /// حلّ موعدها ناقص المسدَّد، بحدٍّ أعلى هو المتبقي لكامل العام.
  factory PortalFinance.compute({
    required double? studentBalance,
    required List<Installment> installments,
    required List<Payment> payments,
    DateTime? today,
  }) {
    final todayStr = isoDate(today ?? DateTime.now());
    final sorted = [...installments]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final active = payments.where((p) => !p.cancelled).toList();
    sortPayments(active);

    final totalDue = sorted.fold<double>(0, (a, i) => a + i.amount);
    final totalPaid = active.fold<double>(0, (a, p) => a + p.amount);
    final remaining = (totalDue - totalPaid) < 0 ? 0.0 : totalDue - totalPaid;

    double currentDue;
    if (studentBalance != null && studentBalance < 0) {
      currentDue = studentBalance.abs();
    } else {
      final pastOrCurrent = sorted
          .where((i) => isoDate(i.dueDate).compareTo(todayStr) <= 0)
          .fold<double>(0, (a, i) => a + i.amount);
      currentDue = (pastOrCurrent - totalPaid).clamp(0, remaining).toDouble();
    }

    return PortalFinance(
      totalDue: totalDue,
      totalPaid: totalPaid,
      remainingBalance: remaining,
      currentDue: currentDue,
      installments: [
        for (final i in sorted)
          PortalInstallment(
            id: i.id,
            title: i.title,
            amount: i.amount,
            dueDate: isoDate(i.dueDate),
            paidAmount: i.paidAmount,
            status: const {'paid', 'unpaid', 'partially_paid'}.contains(i.status) ? i.status : 'unpaid',
            isDueNow: isoDate(i.dueDate).compareTo(todayStr) <= 0,
          ),
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
  });

  final Student student;
  final PortalBranding branding;
  final List<PortalSubject> subjects;
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
    this.subjects = const [],
  });

  final PortalBranding branding;
  final List<TeacherClass> classes;
  final List<SubjectItem> subjects;
}

/// نتيجة محاولة دخول: إما حساب واحد، أو عدّة حسابات يختار منها المستخدم.
class PortalLoginResult {
  const PortalLoginResult({this.users = const [], this.error});

  final List<PortalUser> users;
  final String? error;

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

  /// أُضيف خلال آخر 48 ساعة — شارة «جديد» عند الطالب.
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

/// وحدة أو قسم دراسي لشعبة في فصل.
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

  String get termLabel => academicTermLabels[term] ?? term;

  CourseSection copyWith({bool? isVisible, List<CourseItem>? items}) => CourseSection(
        id: id,
        tenantId: tenantId,
        groupId: groupId,
        term: term,
        title: title,
        sortOrder: sortOrder,
        isVisible: isVisible ?? this.isVisible,
        createdAt: createdAt,
        items: items ?? this.items,
      );

  Map<String, dynamic> toCloud() => {
        'id': id,
        'tenant_id': tenantId,
        'group_id': groupId,
        'term': term,
        'title': title,
        'sort_order': sortOrder,
        'is_visible': isVisible,
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
    if (error != null) return PortalLoginResult(error: '$error');

    final choices = [
      for (final c in (data['choices'] as List? ?? const []))
        if (c is Map) userFromChoice(Map<String, dynamic>.from(c)),
    ];
    if (choices.length > 1) return PortalLoginResult(users: choices);

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
    );
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
      supabaseSelect('enrollments', filters: byStudent),
      supabaseSelect('groups', filters: tenant),
      supabaseSelect('teachers', filters: tenant, columns: 'id,name'),
      supabaseSelect('subjects', filters: tenant, columns: 'id,name'),
      supabaseSelect('rooms', filters: tenant, columns: 'id,name'),
      supabaseSelect('installments', filters: byStudent),
      supabaseSelect('payments', filters: byStudent),
      supabaseSelect('attendance', filters: byStudent),
      supabaseSelect('student_evaluations', filters: byStudent),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

    final groupById = {for (final g in at(2)) '${g['id']}': g};
    final teacherName = {for (final t in at(3)) '${t['id']}': '${t['name'] ?? ''}'};
    final subjectName = {for (final s in at(4)) '${s['id']}': '${s['name'] ?? ''}'};
    final roomName = {for (final r in at(5)) '${r['id']}': '${r['name'] ?? ''}'};

    // مادة لكل تسجيل نشط، كما في `subjectsWithTeachers`
    final subjects = <PortalSubject>[];
    for (final e in at(1)) {
      if ('${e['status'] ?? 'active'}' != 'active') continue;
      final gid = '${e['group_id']}';
      final g = groupById[gid];
      subjects.add(PortalSubject(
        groupId: gid,
        subjectName: g == null ? 'مادة دراسية' : (subjectName['${g['subject_id']}'] ?? 'مادة دراسية'),
        teacherName: g == null ? 'معلم غير محدد' : (teacherName['${g['teacher_id']}'] ?? 'معلم غير محدد'),
        groupName: '${g?['name'] ?? 'شعبة'}',
        days: [for (final d in (g?['days'] as List? ?? const [])) int.tryParse('$d') ?? 0],
        startTime: '${g?['start_time'] ?? ''}',
        endTime: '${g?['end_time'] ?? ''}',
        roomName: g == null ? '' : (roomName['${g['room_id']}'] ?? ''),
      ));
    }

    // الحضور: تاريخه في الحصة المرتبطة، فتُجلب حصصه وحدها
    final sessionIds = at(8).map((r) => '${r['session_id'] ?? ''}').where((s) => s.isNotEmpty).toSet();
    final sessionDate = <String, String>{};
    if (sessionIds.isNotEmpty) {
      final sessions = await supabaseSelect(
        'sessions',
        filters: {'id': _inList(sessionIds)},
        columns: 'id,session_date',
      );
      for (final s in sessions ?? const <Map<String, dynamic>>[]) {
        sessionDate['${s['id']}'] = '${s['session_date'] ?? ''}'.split('T').first;
      }
    }
    final marks = <AttendanceMark>[];
    var present = 0, absent = 0, excused = 0;
    for (final r in at(8)) {
      final raw = '${r['status'] ?? ''}';
      // «متأخر» أُلغيت من النظام: كل ما ليس حاضراً أو مأذوناً غياب
      final status = raw == 'present' ? 'present' : (raw == 'excused' ? 'excused' : 'absent');
      final date = sessionDate['${r['session_id']}'] ?? '${r['created_at'] ?? ''}'.split('T').first;
      marks.add(AttendanceMark.fromCloud({...r, 'status': status, 'session_date': date}));
      switch (status) {
        case 'present':
          present++;
        case 'excused':
          excused++;
        default:
          absent++;
      }
    }
    marks.sort((a, b) => b.date.compareTo(a.date));

    final evaluations = [
      for (final r in at(9))
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
        installments: at(6).map(Installment.fromCloud).toList(),
        payments: at(7).map(Payment.fromCloud).toList(),
      ),
    );
  }

  // ── بوابة المعلم ───────────────────────────────────────────────────────────

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
      supabaseSelect('groups', filters: {...tenant, 'teacher_id': _inList(teacherIds)}),
      supabaseSelect('subjects', filters: tenant),
      supabaseSelect('rooms', filters: tenant),
      supabaseSelect('students', filters: tenant),
    ]);

    List<Map<String, dynamic>> at(int i) =>
        (results[i] as List<Map<String, dynamic>>?) ?? const <Map<String, dynamic>>[];

    final groups = at(1).map(Group.fromCloud).where((g) => g.isActive).toList();
    final subjects = at(2).map(SubjectItem.fromCloud).toList();
    final subjectName = {for (final s in subjects) s.id: s.name};
    final rooms = {for (final r in at(3)) '${r['id']}': r};
    final students = at(4).map(Student.fromCloud).toList();
    final byId = {for (final s in students) s.id: s};

    final enrollments = groups.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await supabaseSelect('enrollments', filters: {'group_id': _inList(groups.map((g) => g.id))})) ??
            const <Map<String, dynamic>>[];

    final classes = <TeacherClass>[];
    for (final group in groups) {
      var list = [
        for (final e in enrollments)
          if ('${e['group_id']}' == group.id && '${e['status'] ?? 'active'}' == 'active' && byId['${e['student_id']}'] != null)
            byId['${e['student_id']}']!,
      ];

      // بلا تسجيلات: طلاب شعبها أنفسهم. الموديل الواحد يشترك فيه أكثر من شعبة،
      // فتُؤخذ كلها لا الأساسية وحدها
      final groupRooms = [
        for (final id in group.allRoomIds)
          if (rooms[id] != null) rooms[id]!,
      ];
      if (list.isEmpty && groupRooms.isNotEmpty) {
        list = students
            .where((s) => groupRooms.any((room) => studentInRoom(
                  s,
                  roomName: '${room['name'] ?? ''}',
                  roomGrade: '${room['grade_level'] ?? ''}',
                )))
            .toList();
      }

      classes.add(TeacherClass(
        group: group,
        students: list,
        subjectName: subjectName[group.subjectId] ?? '',
        roomName: groupRooms.map((room) => '${room['name'] ?? ''}').join('، '),
      ));
    }

    return TeacherPortalData(
      branding: results[0] as PortalBranding,
      classes: classes,
      subjects: subjects,
    );
  }

  /// الحصة القائمة لهذه الشعبة واليوم إن وُجدت — أنشأها جهاز الإدارة بمعرّف
  /// آخر — وإلا فالمعرّف الحتمي. إنشاء حصة ثانية لليوم نفسه كان يشطر الرصد.
  Future<String> _sessionFor(String groupId, String date) async {
    final existing = await supabaseSelect(
      'sessions',
      filters: {'group_id': 'eq.$groupId', 'session_date': 'eq.$date'},
      columns: 'id',
      limit: 1,
    );
    if (existing != null && existing.isNotEmpty) return '${existing.first['id']}';
    return sessionIdFor(groupId, date);
  }

  /// كشف حضور حصة محفوظ: الطالب ← (حالته، معرّف سجله).
  Future<Map<String, ({String status, String id})>> sessionAttendance(String groupId, String date) async {
    final sessionId = await _sessionFor(groupId, date);
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

  /// رصد حضور صفّ من بوابة المعلم — مطابق لـ `saveTeacherAttendance`.
  ///
  /// سجل الطالب القائم يُحدَّث بمعرّفه نفسه: التصالح على (الحصة، الطالب) مع
  /// معرّف جديد كان يستبدل المفتاح الأساسي فيبقى السجل القديم يتيماً على الأجهزة.
  Future<void> saveAttendance({
    required Group group,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
  }) async {
    final sessionId = await _sessionFor(group.id, date);
    final now = _nowIso();

    await supabaseUpsert('sessions', [
      {
        'id': sessionId,
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
    final existing = await supabaseSelect(
      'attendance',
      filters: {'session_id': 'eq.$sessionId'},
      columns: 'id,student_id',
    );
    final idOf = {for (final r in existing ?? const <Map<String, dynamic>>[]) '${r['student_id']}': '${r['id']}'};

    await supabaseUpsert(
      'attendance',
      [
        for (final entry in statuses.entries)
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
    final rows = await supabaseSelect('student_evaluations', filters: {'group_id': 'eq.$groupId'});
    return (rows ?? const <Map<String, dynamic>>[]).map(StudentEvaluation.fromCloud).toList()
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

  // ── المودل (المقابل لـ moodle.service.ts) ─────────────────────────────────

  /// وحدات شعبة مع موادها — `fetchGroupSections`. «أخرى» تشمل القيمة القديمة `general`.
  Future<List<CourseSection>> groupSections({
    required String tenantId,
    required String groupId,
    String term = 'all',
    bool includeHidden = false,
  }) async {
    final filters = <String, String>{'tenant_id': 'eq.$tenantId', 'group_id': 'eq.$groupId'};
    if (term == 'other' || term == 'general') {
      filters['term'] = 'in.(general,other)';
    } else if (term != 'all') {
      filters['term'] = 'eq.$term';
    }
    if (!includeHidden) filters['is_visible'] = 'eq.true';

    final rows = await supabaseSelect('course_sections', filters: filters, order: 'sort_order.asc,created_at.asc');
    if (rows == null || rows.isEmpty) return const [];
    final sections = rows.map(CourseSection.fromCloud).toList();

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
  }) async {
    final section = CourseSection(
      id: _uuid.v4(),
      tenantId: tenantId,
      groupId: groupId,
      term: term,
      title: title.trim(),
      sortOrder: sortOrder,
      createdAt: _nowIso(),
    );
    await supabaseUpsert('course_sections', [section.toCloud()]);
    return section;
  }

  Future<void> setSectionVisible(String sectionId, bool visible) =>
      supabaseUpdate('course_sections', {'id': 'eq.$sectionId'}, {'is_visible': visible});

  /// حذف وحدة وملفات موادها. موادها تُحذف بالتتابع في قاعدة البيانات.
  Future<void> deleteSection(CourseSection section, String tenantId) async {
    await storageRemove(materialsBucket, [
      for (final it in section.items)
        if (materialPath(it.contentUrl) != null) materialPath(it.contentUrl)!,
    ]);
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
    if (path != null) await storageRemove(materialsBucket, [path]);
    await supabaseDelete('course_items', {'id': 'eq.${item.id}', 'tenant_id': 'eq.$tenantId'});
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
