import '../data/phone.dart';

const currency = '₪';
const appName = 'نظام الإدارة المدرسي';
const appVersion = '1.2.4';

/// مطابق لـ GRADE_LEVELS في types/student.ts
const gradeLevels = [
  'ثاني عشر علمي',
  'ثاني عشر أدبي',
  'حادي عشر علمي',
  'حادي عشر أدبي',
  'عاشر',
  'أخرى (إدخال يدوي)',
];

const gradeLevelsFilter = [
  'ثاني عشر علمي',
  'ثاني عشر أدبي',
  'حادي عشر علمي',
  'حادي عشر أدبي',
  'عاشر',
];

/// مطابق لقائمة الأحياء في StudentForm.tsx
const neighborhoods = [
  'الرمال',
  'الشجاعية',
  'الزيتون',
  'الدرج',
  'التفاح',
  'الصبرة',
  'النصر',
  'الشيخ رضوان',
  'تل الهوا',
  'الشيخ عجلين',
  'مخيم الشاطئ',
  'الكرامة',
  'المقوسي',
  'جُحر الديك',
  'التوام',
  'عباد الرحمن',
  'اليرموك',
  'المنارة',
  'الميناء',
  'الكتيبة',
  'الساحة',
  'أنصار',
  'أخرى',
];

const guardianRelations = [
  'أب',
  'أم',
  'أخ',
  'أخت',
  'عم',
  'خال',
  'جد',
  'جدة',
  'وصي قانوني',
  'أخرى',
];

const referralSources = [
  'سوشيال ميديا (فيسبوك / انستغرام / تيك توك)',
  'صديق أو زميل',
  'إعلانات ممولة',
  'لافتة أو مقر المركز',
  'زيارة سابقة / طالب قديم',
  'أخرى',
];

const housingTypes = [
  'ملك',
  'إيجار',
  'خيمة',
  'مركز إيواء',
  'استضافة',
  'منزل متضرر جزئياً',
  'أخرى',
];

const paymentMethodNames = {
  'cash': 'نقداً',
  'jawwal_pay': 'محفظة جوال بي',
  'palpay': 'محفظة بال بي',
  'bop': 'بنك فلسطين',
  'bank_transfer': 'تحويل بنكي',
  'other': 'أخرى',
};

const paymentPurposeNames = {
  'monthly_fee': 'رسوم شهرية',
  'installment': 'سداد دفعة قسط مجدول',
  'seat_reservation': 'حجز مقعد',
  'extra_sessions': 'حصص ومجموعات إضافية',
  'other': 'أخرى',
};

/// مطابق لـ Teacher.payment_type في types/common.ts
const teacherPaymentTypes = {
  'percentage': 'نسبة مئوية (%)',
  'per_student': 'مبلغ ثابت لكل طالب (₪)',
  'per_hour': 'أجر بالساعة (₪)',
  'fixed_monthly': 'راتب شهري مقطوع (₪)',
};

const educationalStageTiers = {
  'secondary': 'المرحلة الثانوية (10 - 12)',
  'middle': 'المرحلة الإعدادية (5 - 9)',
  'primary': 'المرحلة الابتدائية (1 - 4)',
  'kindergarten': 'رياض الأطفال',
};

String stageTierLabel(String id) => educationalStageTiers[id] ?? 'المرحلة الثانوية (10 - 12)';

String money(num value) {
  final abs = value.abs();
  final n = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  return '$n $currency';
}

/// رقم بلا كسر عشري زائد: 90 لا 90.0، و 87.5 كما هي.
/// تُستعمل لعرض الدرجات — «الدرجة 90.0 من 100.0» صياغة تبدو خطأً في العرض.
String trimNum(num value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();

/// الجنس كما يُعرض ويُحفظ في Center: «ذكر» أو «أنثى».
///
/// بعض السجلات تصل من السحابة بالإنجليزية (`male`/`female`) من مصدر غير
/// النسختين؛ تُقرأ هنا بالعربية، ويعود حفظها بالعربية عند أول تعديل.
/// اسم المرحلة بلا لاحقة الجنس — «ثاني عشر علمي ذكور» ← «ثاني عشر علمي».
String _gradeCore(String grade) =>
    grade.replaceAll(RegExp(r'\s*(ذكور|إناث|بنين|بنات)\s*'), ' ').trim();

const _gradeWords =
    r'\(?(12 علمي|11 علمي|11 أدبي|12 أدبي|ثاني عشر|حادي عشر|توجيهي|عاشر|تاسع|ثامن|سابع|سادس|خامس|رابع|ثالث|ثاني|أول)\)?';
const _branchWords = r'\(?(علمي|أدبي|شرعي|صناعي|تجاري|ريادة|أعمال|بنين|بنات|ذكور|إناث)\)?';

/// أسماء الأشهر الميلادية — مطابق لـ `GREGORIAN_MONTHS`.
const gregorianMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// حالات الطالب — مطابق لـ `STUDENT_STATUS_CONFIG` في types/student.ts.
///
/// «بانتظار التأكيد» يضعها الترفيع السنوي وحده فلا تُختار يدوياً، و«غير نشط»
/// أُدمجت في «منسحب» لأنهما كانتا بمعنى واحد.
const studentStatusLabels = {
  'active': 'نشط',
  'pending': 'بانتظار التأكيد',
  'withdrawn': 'منسحب',
  'archived': 'مؤرشف',
};

/// لون الحالة كما في النسخة المكتبية.
const studentStatusColors = {
  'active': 0xFFE88C15,
  'pending': 0xFFEAB308,
  'withdrawn': 0xFF737A68,
  'archived': 0xFF94A3B8,
};

/// الحالة القديمة `inactive` تُقرأ «منسحب» حتى تُرحَّل سجلاتها.
String studentStatusLabel(String status) =>
    studentStatusLabels[status == 'inactive' ? 'withdrawn' : status] ?? status;

/// تنقية اسم الشعبة ومنع تكرار اسم المرحلة داخله — مطابق لـ `sanitizeSectionName`.
///
/// المرحلة محدَّدة في حقلها، فكتابتها داخل الاسم تُنتج «ثاني عشر علمي — ثاني عشر
/// علمي (أ)» في الكشوف والجداول. «أ» أو «عاشر أ» أو «شعبة أ» كلها ← «شعبة (أ)».
String sanitizeSectionName(String rawName, [String gradeLevel = '']) {
  if (rawName.trim().isEmpty) return '';
  var clean = rawName.trim().replaceAll(RegExp(r'^(فصل|صف)\s+'), '').trim();

  final grade = _gradeCore(gradeLevel);
  if (grade.isNotEmpty) {
    clean = clean.replaceAll(RegExp(RegExp.escape(grade)), '').trim();
  }

  clean = clean.replaceAll(RegExp(_gradeWords), '').trim();
  clean = clean.replaceAll(RegExp(_branchWords), '').trim();
  clean = clean.replaceAll(RegExp(r'^[(\-\s]+|[)\-\s]+$'), '').trim();

  if (RegExp(r'^[\u0621-\u064A0-9]$').hasMatch(clean)) return 'شعبة ($clean)';
  if (clean.isEmpty) return 'شعبة (1)';
  if (RegExp(r'^(شعبة|قاعة|مجموعة|غرفة)').hasMatch(clean)) return clean;
  return 'شعبة $clean';
}

/// تنقية اسم المجموعة ومنع تكرار المادة أو المرحلة — مطابق لـ `sanitizeGroupName`.
String sanitizeGroupName(String rawName, {String subject = '', String gradeLevel = ''}) {
  if (rawName.trim().isEmpty) return '';
  var clean = rawName.trim();

  if (subject.trim().isNotEmpty) {
    clean = clean.replaceAll(RegExp(RegExp.escape(subject.trim())), '').trim();
  }
  final grade = _gradeCore(gradeLevel);
  if (grade.isNotEmpty) {
    clean = clean.replaceAll(RegExp(RegExp.escape(grade)), '').trim();
  }

  clean = clean.replaceAll(RegExp(r'\(?(12 علمي|11 علمي|11 أدبي|12 أدبي|عاشر)\)?'), '').trim();
  clean = clean.replaceAll(RegExp(r'^[(\-\s]+|[)\-\s]+$'), '').trim();

  if (clean.isEmpty) return 'المجموعة 1';
  if (RegExp(r'^[\u0621-\u064A0-9]$').hasMatch(clean)) return 'شعبة ($clean)';
  return clean;
}

/// العام الدراسي من التاريخ — مطابق لـ `getAcademicYear` في utils.ts.
///
/// يبدأ العام مع آب: من آب إلى كانون الأول «السنة / السنة+1»، ومن كانون الثاني
/// إلى تموز «السنة-1 / السنة». كتابته ثابتة في الكشوف كانت تُقادم مع كل عام.
String academicYear([DateTime? at]) {
  final date = at ?? DateTime.now();
  if (date.month >= 8) return '${date.year} / ${date.year + 1}';
  return '${date.year - 1} / ${date.year}';
}

String genderLabel(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty) return 'ذكر';
  if (const {'male', 'm', 'boy', 'ذكر'}.contains(v)) return 'ذكر';
  if (const {'female', 'f', 'girl', 'أنثى', 'انثى'}.contains(v)) return 'أنثى';
  return raw!.trim();
}

String formatDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$day/$m/$y';
}

String isoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? parseIsoDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final part = raw.split('T').first.trim();
  final bits = part.split('-');
  if (bits.length != 3) return DateTime.tryParse(raw);
  final y = int.tryParse(bits[0]);
  final m = int.tryParse(bits[1]);
  final d = int.tryParse(bits[2]);
  if (y == null || m == null || d == null) return DateTime.tryParse(raw);
  return DateTime(y, m, d);
}

bool isValidNationalId(String raw) => RegExp(r'^\d{9}$').hasMatch(raw.trim());

bool isValidStudentPhone(String raw, [String prefix = '059']) {
  final parsed = parsePhoneAndPrefix(raw);
  final active = raw.trim().startsWith('05') || raw.trim().startsWith('+') ? parsed.prefix : prefix;
  return isPhoneComplete(parsed.number, active);
}

/// ترتيب الدفعات: الأحدث أولاً، ثم بالرقم التسلسلي تنازلياً.
/// مطابق لـ `sortPayments` في finance.service.ts.
void sortPayments(List<Payment> list) {
  int serial(String receipt) {
    final parts = receipt.split('/');
    if (parts.length != 2) return 0;
    return int.tryParse(parts[1]) ?? 0;
  }

  list.sort((a, b) {
    final ta = DateTime.tryParse(a.createdAt ?? '')?.millisecondsSinceEpoch ?? a.date.millisecondsSinceEpoch;
    final tb = DateTime.tryParse(b.createdAt ?? '')?.millisecondsSinceEpoch ?? b.date.millisecondsSinceEpoch;
    if (ta != tb) return tb.compareTo(ta);
    return serial(b.receiptNumber).compareTo(serial(a.receiptNumber));
  });
}

class StoreException implements Exception {
  StoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Student {
  Student({
    required this.id,
    required this.fullName,
    required this.gradeLevel,
    required this.section,
    required this.phone,
    required this.parentName,
    required this.parentPhone,
    required this.balance,
    this.firstName = '',
    this.lastName = '',
    this.phonePrefix = '059',
    this.parentPhonePrefix = '059',
    this.nationalId = '',
    this.neighborhood = '',
    this.relation = 'أب',
    this.gender = 'ذكر',
    this.notes = '',
    this.status = 'active',
    this.hasException = false,
    this.detailedAddress = '',
    this.referralSource = 'سوشيال ميديا (فيسبوك / انستغرام / تيك توك)',
    this.schoolName = '',
    this.birthDate = '',
    this.birthPlace = 'غزة',
    this.nationality = 'فلسطينية',
    this.previousSchool = '',
    this.gpa = '',
    this.housingStatus = 'ملك',
    this.originalArea = '',
    this.healthStatus = 'سليم',
    this.medicalCondition = '',
    this.parentJob = '',
    this.parentSecondaryPhone = '',
    this.email = '',
    this.guardianDeclaration = false,
    this.initialRating = 0,
    this.seatReservationPaid = false,
    this.seatReservationDiscounted = false,
    this.paymentPlan = 'full',
    this.paymentStatus = 'unpaid',
    this.academicDiscountApplied = false,
    this.academicDiscountRate = 0,
    this.exceptionReason = '',
    this.customMonthlyFee,
    this.portalCode = '',
    this.parentPortalCode = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
    DateTime? enrolledAt,
  }) : enrolledAt = enrolledAt ?? DateTime.now();

  final String id;
  String firstName;
  String lastName;
  String fullName;
  String gradeLevel;
  String section;
  String phone;
  String phonePrefix;
  String parentName;
  String parentPhone;
  String parentPhonePrefix;
  String nationalId;
  String neighborhood;
  String relation;
  String gender;
  String notes;
  String status;
  double balance;
  bool hasException;
  DateTime enrolledAt;
  String detailedAddress;
  String referralSource;
  String schoolName;
  String birthDate;
  String birthPlace;
  String nationality;
  String previousSchool;
  String gpa;
  String housingStatus;
  String originalArea;
  String healthStatus;
  String medicalCondition;
  String parentJob;
  String parentSecondaryPhone;
  String email;
  bool guardianDeclaration;
  int initialRating;
  bool seatReservationPaid;
  bool seatReservationDiscounted;
  String paymentPlan;
  String paymentStatus;
  bool academicDiscountApplied;
  double academicDiscountRate;
  String exceptionReason;
  double? customMonthlyFee;

  /// رمز دخول الطالب إلى بوابته — ست خانات.
  String portalCode;

  /// كلمة مرور ولي الأمر لبوابة المتابعة — يدخل بها برقم هوية ابنه.
  /// لا تساوي كلمة الطالب، وإلا أنتج الإدخال الواحد حسابين مختلفين.
  String parentPortalCode;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  String get guardianRelationship => relation;
  set guardianRelationship(String v) => relation = v;

  DateTime get enrollmentDate => enrolledAt;
  set enrollmentDate(DateTime v) => enrolledAt = v;

  /// «نشط» وحدها لا تُعرض على البطاقات: الباقي حالةٌ تستحق الانتباه.
  bool get isActiveStudent => status == 'active';

  String get statusLabel => studentStatusLabel(status);

  bool get hasFlexibleException => hasException;
  set hasFlexibleException(bool v) => hasException = v;

  bool get isDebtor => balance < 0;
  String get initial {
    final t = fullName.trim();
    return t.isEmpty ? 'ط' : t.substring(0, 1);
  }

  Map<String, dynamic> toCloud() {
    splitNameIfNeeded();
    return {
      'id': id,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'phone': phone,
      'phone_prefix': phonePrefix,
      'parent_name': parentName,
      'guardian_relationship': relation,
      'parent_phone': parentPhone,
      'parent_phone_prefix': parentPhonePrefix,
      'national_id': nationalId,
      'grade_level': gradeLevel,
      'gender': gender,
      'status': status,
      'balance': balance,
      'neighborhood': neighborhood,
      'detailed_address': detailedAddress,
      'referral_source': referralSource,
      'section': section,
      'school_name': schoolName,
      'enrollment_date': isoDate(enrolledAt),
      'birth_date': birthDate,
      'birth_place': birthPlace,
      'nationality': nationality,
      'previous_school': previousSchool,
      'gpa': gpa,
      'housing_status': housingStatus,
      'original_area': originalArea,
      'health_status': healthStatus,
      'medical_condition': medicalCondition,
      'parent_job': parentJob,
      'parent_secondary_phone': parentSecondaryPhone,
      'email': email,
      'guardian_declaration': guardianDeclaration,
      'initial_rating': initialRating,
      'seat_reservation_paid': seatReservationPaid,
      'seat_reservation_discounted': seatReservationDiscounted,
      'payment_plan': paymentPlan,
      'payment_status': paymentStatus,
      'academic_discount_applied': academicDiscountApplied,
      'academic_discount_rate': academicDiscountRate,
      'exception_reason': exceptionReason,
      'custom_monthly_fee': customMonthlyFee,
      'portal_code': portalCode.isEmpty ? null : portalCode,
      'parent_portal_code': parentPortalCode.isEmpty ? null : parentPortalCode,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  void splitNameIfNeeded() {
    if (firstName.trim().isNotEmpty) return;
    final parts = fullName.trim().split(RegExp(r'\s+'));
    firstName = parts.isEmpty ? '' : parts.first;
    lastName = parts.length <= 1 ? firstName : parts.skip(1).join(' ');
  }

  factory Student.fromCloud(Map<String, dynamic> m) {
    final full = (m['full_name'] as String?)?.trim().isNotEmpty == true
        ? m['full_name'] as String
        : ['${m['first_name'] ?? ''}', '${m['last_name'] ?? ''}'].where((e) => e.trim().isNotEmpty).join(' ');
    return Student(
      id: '${m['id']}',
      firstName: '${m['first_name'] ?? ''}',
      lastName: '${m['last_name'] ?? ''}',
      fullName: full,
      gradeLevel: '${m['grade_level'] ?? ''}',
      section: '${m['section'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      phonePrefix: '${m['phone_prefix'] ?? parsePhoneAndPrefix('${m['phone'] ?? ''}').prefix}',
      parentName: '${m['parent_name'] ?? ''}',
      parentPhone: '${m['parent_phone'] ?? ''}',
      parentPhonePrefix: '${m['parent_phone_prefix'] ?? parsePhoneAndPrefix('${m['parent_phone'] ?? ''}').prefix}',
      nationalId: '${m['national_id'] ?? ''}',
      neighborhood: '${m['neighborhood'] ?? ''}',
      relation: '${m['guardian_relationship'] ?? 'أب'}',
      gender: '${m['gender'] ?? 'ذكر'}',
      notes: '${m['notes'] ?? ''}',
      status: '${m['status'] ?? 'active'}',
      balance: (m['balance'] as num?)?.toDouble() ?? 0,
      enrolledAt: parseIsoDate('${m['enrollment_date'] ?? ''}') ?? DateTime.now(),
      detailedAddress: '${m['detailed_address'] ?? ''}',
      referralSource: '${m['referral_source'] ?? ''}',
      schoolName: '${m['school_name'] ?? ''}',
      birthDate: '${m['birth_date'] ?? ''}'.split('T').first,
      birthPlace: '${m['birth_place'] ?? 'غزة'}',
      nationality: '${m['nationality'] ?? 'فلسطينية'}',
      previousSchool: '${m['previous_school'] ?? ''}',
      gpa: '${m['gpa'] ?? ''}',
      housingStatus: '${m['housing_status'] ?? 'ملك'}',
      originalArea: '${m['original_area'] ?? ''}',
      healthStatus: '${m['health_status'] ?? 'سليم'}',
      medicalCondition: '${m['medical_condition'] ?? ''}',
      parentJob: '${m['parent_job'] ?? ''}',
      parentSecondaryPhone: '${m['parent_secondary_phone'] ?? ''}',
      email: '${m['email'] ?? ''}',
      guardianDeclaration: m['guardian_declaration'] == true,
      initialRating: (m['initial_rating'] as num?)?.toInt() ?? 0,
      seatReservationPaid: m['seat_reservation_paid'] == true,
      seatReservationDiscounted: m['seat_reservation_discounted'] == true,
      paymentPlan: '${m['payment_plan'] ?? 'full'}',
      paymentStatus: '${m['payment_status'] ?? 'unpaid'}',
      academicDiscountApplied: m['academic_discount_applied'] == true,
      academicDiscountRate: (m['academic_discount_rate'] as num?)?.toDouble() ?? 0,
      exceptionReason: '${m['exception_reason'] ?? ''}',
      customMonthlyFee: (m['custom_monthly_fee'] as num?)?.toDouble(),
      portalCode: '${m['portal_code'] ?? ''}',
      parentPortalCode: '${m['parent_portal_code'] ?? ''}',
      syncStatus: '${m['sync_status'] ?? 'synced'}',
      createdAt: m['created_at']?.toString(),
      updatedAt: m['updated_at']?.toString(),
    );
  }
}

class StudentAttachments {
  StudentAttachments({
    required this.id,
    this.studentIdPhoto = '',
    this.birthCertificate = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String studentIdPhoto;
  String birthCertificate;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  bool get isEmpty => studentIdPhoto.isEmpty && birthCertificate.isEmpty;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id_photo': studentIdPhoto,
        'birth_certificate': birthCertificate,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory StudentAttachments.fromCloud(Map<String, dynamic> m) => StudentAttachments(
        id: '${m['id']}',
        studentIdPhoto: '${m['student_id_photo'] ?? ''}',
        birthCertificate: '${m['birth_certificate'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class Classroom {
  Classroom({
    required this.id,
    required this.name,
    required this.gradeLevel,
    required this.teacherId,
    this.capacity = 25,
    this.notes = '',
    this.tier = 'secondary',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;
  String gradeLevel;
  String teacherId;
  int capacity;
  String notes;
  String tier;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'name': name,
        'capacity': capacity,
        'grade_level': gradeLevel,
        'stage_tier': tier,
        'homeroom_teacher_id': teacherId.isEmpty ? null : teacherId,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Classroom.fromCloud(Map<String, dynamic> m) => Classroom(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        gradeLevel: '${m['grade_level'] ?? ''}',
        teacherId: '${m['homeroom_teacher_id'] ?? ''}',
        capacity: (m['capacity'] as num?)?.toInt() ?? 25,
        notes: '${m['notes'] ?? ''}',
        tier: '${m['stage_tier'] ?? 'secondary'}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class Teacher {
  Teacher({
    required this.id,
    required this.name,
    required this.phone,
    required this.subject,
    this.rate = 70,
    this.email = '',
    this.paymentType = 'percentage',
    this.notes = '',
    this.nationalId = '',
    this.portalCode = '',
    this.subjectIds = const [],
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;
  String phone;
  String subject;
  double rate;
  String email;
  String paymentType;
  String notes;

  /// رقم هوية المعلم — اسم المستخدم في بوابة المعلم.
  String nationalId;

  /// رمز دخول المعلم إلى بوابته — ست خانات.
  String portalCode;
  List<String> subjectIds;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'subject_ids': subjectIds,
        'payment_type': paymentType,
        'payment_rate': rate,
        'national_id': nationalId.isEmpty ? null : nationalId,
        'portal_code': portalCode.isEmpty ? null : portalCode,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Teacher.fromCloud(Map<String, dynamic> m) {
    final ids = <String>[];
    final raw = m['subject_ids'];
    if (raw is List) {
      for (final e in raw) {
        ids.add('$e');
      }
    }
    return Teacher(
      id: '${m['id']}',
      name: '${m['name'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      subject: '${m['subject'] ?? ''}',
      rate: (m['payment_rate'] as num?)?.toDouble() ?? 0,
      email: '${m['email'] ?? ''}',
      paymentType: '${m['payment_type'] ?? 'percentage'}',
      notes: '${m['notes'] ?? ''}',
      nationalId: '${m['national_id'] ?? ''}',
      portalCode: '${m['portal_code'] ?? ''}',
      subjectIds: ids,
      syncStatus: '${m['sync_status'] ?? 'synced'}',
      createdAt: m['created_at']?.toString(),
      updatedAt: m['updated_at']?.toString(),
    );
  }
}

class SubjectItem {
  SubjectItem({
    required this.id,
    required this.name,
    required this.code,
    this.gradeLevel = 'عام / كل المراحل',
    this.description = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;
  String code;
  String gradeLevel;
  String description;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'name': name,
        'code': code,
        'grade_level': gradeLevel,
        'description': description,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory SubjectItem.fromCloud(Map<String, dynamic> m) => SubjectItem(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        code: '${m['code'] ?? ''}',
        gradeLevel: '${m['grade_level'] ?? 'عام / كل المراحل'}',
        description: '${m['description'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class GradeFee {
  GradeFee({
    required this.id,
    required this.gradeName,
    required this.monthlyFee,
    this.tier = 'secondary',
    this.orderIndex = 0,
    this.isCustom = false,
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String gradeName;
  double monthlyFee;
  String tier;
  int orderIndex;
  bool isCustom;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'grade_name': gradeName,
        'monthly_fee': monthlyFee,
        'order_index': orderIndex,
        'is_custom': isCustom,
        'stage_tier': tier,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory GradeFee.fromCloud(Map<String, dynamic> m) => GradeFee(
        id: '${m['id']}',
        gradeName: '${m['grade_name'] ?? ''}',
        monthlyFee: (m['monthly_fee'] as num?)?.toDouble() ?? 0,
        tier: '${m['stage_tier'] ?? 'secondary'}',
        orderIndex: (m['order_index'] as num?)?.toInt() ?? 0,
        isCustom: m['is_custom'] == true,
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class Payment {
  Payment({
    required this.id,
    required this.receiptNumber,
    required this.studentId,
    required this.amount,
    required this.method,
    required this.date,
    this.purpose = 'monthly_fee',
    this.notes = '',
    this.reference = '',
    this.senderName = '',
    this.channel = '',
    this.transferDate = '',
    this.customMethodNotes = '',
    this.discountAmount = 0,
    this.discountReason = '',
    this.originalAmount,
    this.studentName = '',
    this.receivedByName = '',
    this.installmentId,
    this.groupId,
    this.enrollmentId,
    this.receivedByUserId = '',
    this.remainingAfter = 0,
    this.totalDueAtPayment = 0,
    this.cancelled = false,
    this.cancelReason = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String receiptNumber;
  final String studentId;
  final double amount;
  final String method;
  final DateTime date;
  final String purpose;
  String notes;
  final String reference;
  final String senderName;
  final String channel;
  String transferDate;
  String customMethodNotes;

  /// خصم مطبَّق على هذه الدفعة — يُحتسب ائتماناً كالمبلغ عند حساب الرصيد.
  final double discountAmount;
  final String discountReason;

  /// المبلغ قبل الخصم إن وُجد.
  final double? originalAmount;

  /// لقطة وقت الإصدار: اسم الطالب واسم المستلم كما كانا حينها، فلا يتغيّر سند
  /// قديم بأثر رجعي إذا تغيّر الاسم أو هوية الجهاز لاحقاً. محلية لكل جهاز كما في
  /// النسخة المكتبية — لا عمود لها في السحابة فتُصفّى عند الرفع.
  String studentName;
  String receivedByName;
  final String? installmentId;
  final String? groupId;
  final String? enrollmentId;

  /// من قبض الدفعة — مطابق لـ `received_by_user_id`.
  String receivedByUserId;
  double remainingAfter;
  double totalDueAtPayment;
  bool cancelled;
  String cancelReason;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'receipt_number': receiptNumber,
        'student_id': studentId,
        'installment_id': installmentId,
        'group_id': groupId,
        'enrollment_id': enrollmentId,
        'received_by_user_id': receivedByUserId.isEmpty ? null : receivedByUserId,
        'amount': amount,
        'payment_method': method,
        'payment_date': isoDate(date),
        'payment_purpose': purpose,
        'transfer_channel': channel,
        'transfer_date': transferDate,
        'custom_method_notes': customMethodNotes,
        'discount_amount': discountAmount,
        'discount_reason': discountReason.isEmpty ? null : discountReason,
        'original_amount': originalAmount,
        'student_name': studentName.isEmpty ? null : studentName,
        'received_by_name': receivedByName.isEmpty ? null : receivedByName,
        'sender_name': senderName,
        'reference_number': reference,
        'total_due_at_payment': totalDueAtPayment,
        'remaining_balance_after': remainingAfter,
        'is_cancelled': cancelled,
        'cancelled_reason': cancelReason,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Payment.fromCloud(Map<String, dynamic> m) => Payment(
        id: '${m['id']}',
        receiptNumber: '${m['receipt_number'] ?? ''}',
        studentId: '${m['student_id'] ?? ''}',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        method: '${m['payment_method'] ?? 'cash'}',
        date: parseIsoDate('${m['payment_date'] ?? ''}') ?? DateTime.now(),
        purpose: '${m['payment_purpose'] ?? 'monthly_fee'}',
        notes: '${m['notes'] ?? ''}',
        reference: '${m['reference_number'] ?? ''}',
        senderName: '${m['sender_name'] ?? ''}',
        channel: '${m['transfer_channel'] ?? ''}',
        transferDate: '${m['transfer_date'] ?? ''}'.split('T').first,
        customMethodNotes: '${m['custom_method_notes'] ?? ''}',
        discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
        discountReason: '${m['discount_reason'] ?? ''}',
        originalAmount: (m['original_amount'] as num?)?.toDouble(),
        studentName: '${m['student_name'] ?? ''}',
        receivedByName: '${m['received_by_name'] ?? ''}',
        installmentId: m['installment_id']?.toString(),
        groupId: m['group_id']?.toString(),
        enrollmentId: m['enrollment_id']?.toString(),
        receivedByUserId: '${m['received_by_user_id'] ?? ''}',
        remainingAfter: (m['remaining_balance_after'] as num?)?.toDouble() ?? 0,
        totalDueAtPayment: (m['total_due_at_payment'] as num?)?.toDouble() ?? 0,
        cancelled: m['is_cancelled'] == true,
        cancelReason: '${m['cancelled_reason'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

/// أنواع التقييم — مطابق لـ `EVALUATION_TYPE_LABELS` في types/evaluation.ts
const evaluationTypeNames = {
  'quiz': 'اختبار قصير',
  'monthly': 'اختبار شهري',
  'final': 'امتحان نهائي',
  'activity': 'نشاط وواجبات',
  'behavior': 'سلوك ومواظبة',
};

/// تقييم ودرجة طالب — المقابل لـ `StudentEvaluation` في types/evaluation.ts.
///
/// ليس ملاحظة عابرة كما كان: عنوان ودرجة من درجة قصوى وتاريخ ونوع، وهي
/// الحقول التي أضافتها هجرة `20260910_evaluations_expansion.sql`.
class Evaluation {
  Evaluation({
    required this.id,
    required this.studentId,
    required this.title,
    required this.score,
    this.groupId = '',
    this.subjectId = '',
    this.teacherId = '',
    this.maxScore = 100,
    this.evaluationDate = '',
    this.type = 'quiz',
    this.notes = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String studentId;
  String groupId;
  String subjectId;
  String teacherId;
  String title;
  double score;
  double maxScore;
  String evaluationDate;
  String type;
  String notes;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  /// النسبة المئوية. الدرجة القصوى صفراً تعني تقييماً بلا وزن لا قسمةً على صفر.
  int get percent {
    if (maxScore <= 0) return 0;
    // درجة تتجاوز القصوى — خطأ إدخال أو قصوى عُدّلت بعد الرصد — كانت تُخرج
    // نسبة كـ 112%، وتُفسد المعدل العام معها
    return ((score / maxScore) * 100).round().clamp(0, 100);
  }

  /// النجاح عند 50% فأكثر — نفس العتبة في `stats` بصفحة Evaluations.tsx
  bool get passed => percent >= 50;

  String get typeLabel => evaluationTypeNames[type] ?? type;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id': studentId,
        'group_id': groupId.isEmpty ? null : groupId,
        'subject_id': subjectId.isEmpty ? null : subjectId,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'title': title,
        'score': score,
        'max_score': maxScore,
        'evaluation_date': evaluationDate,
        'type': type,
        'notes': notes.isEmpty ? null : notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  factory Evaluation.fromCloud(Map<String, dynamic> m) => Evaluation(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        subjectId: '${m['subject_id'] ?? ''}',
        teacherId: '${m['teacher_id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        score: (m['score'] as num?)?.toDouble() ?? 0,
        // العمود أُضيف بافتراضي 100؛ صفٌّ قديم بلا قيمة لا يجوز أن يصير 0
        maxScore: (m['max_score'] as num?)?.toDouble() ?? 100,
        evaluationDate: '${m['evaluation_date'] ?? ''}'.split('T').first,
        type: '${m['type'] ?? 'quiz'}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

/// طرق صرف سندات المصروفات وأجور المعلمين — مطابق لـ
/// `Expense.payment_method` و `TeacherPayout.payment_method` في types/payment.ts.
/// أضيق من `paymentMethodNames` عمداً: المحافظ الإلكترونية للقبض لا للصرف.
const expenseMethodNames = {
  'cash': 'نقداً',
  'bank_transfer': 'تحويل بنكي',
  'cheque': 'شيك',
  'other': 'أخرى',
};

/// بنود المصروفات كما تظهر في نافذة «تسجيل سند صرف جديد» في Finance.tsx
const expenseCategories = [
  'تشغيل وإيجار',
  'ضيافة ونظافة',
  'قرطاسية ومطبوعات',
  'صيانة ومعدات',
  'كهرباء وإنترنت',
  'أخرى',
];

/// «أخرى» تُعرض «مصاريف أخرى» في القائمة وتُحفظ «أخرى» — كما في النسخة المكتبية
String expenseCategoryLabel(String id) => id == 'أخرى' ? 'مصاريف أخرى' : id;

/// سند صرف تشغيلي — المقابل لـ `Expense` في types/payment.ts
class Expense {
  Expense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.recordedByUserId = '',
    this.recordedByName = '',
    this.method = 'cash',
    this.notes = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String category;
  String description;
  double amount;
  String expenseDate;
  String recordedByUserId;

  /// اسم من سجّل السند لحظة تسجيله — لقطة محلية لا تتغير بأثر رجعي.
  String recordedByName;
  String method;
  String notes;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'category': category,
        'description': description,
        'amount': amount,
        'expense_date': expenseDate,
        'recorded_by_user_id': recordedByUserId.isEmpty ? null : recordedByUserId,
        'recorded_by_name': recordedByName.isEmpty ? null : recordedByName,
        'payment_method': method,
        'notes': notes.isEmpty ? null : notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  factory Expense.fromCloud(Map<String, dynamic> m) => Expense(
        id: '${m['id']}',
        category: '${m['category'] ?? ''}',
        description: '${m['description'] ?? ''}',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        expenseDate: '${m['expense_date'] ?? ''}'.split('T').first,
        recordedByUserId: '${m['recorded_by_user_id'] ?? ''}',
        recordedByName: '${m['recorded_by_name'] ?? ''}',
        method: '${m['payment_method'] ?? 'cash'}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

/// دفعة أجر معلم — المقابل لـ `TeacherPayout` في types/payment.ts
class TeacherPayout {
  TeacherPayout({
    required this.id,
    required this.teacherId,
    required this.amount,
    required this.paymentDate,
    this.groupId = '',
    this.periodStart = '',
    this.periodEnd = '',
    this.paidByUserId = '',
    this.teacherName = '',
    this.paidByName = '',
    this.method = 'cash',
    this.notes = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String teacherId;
  String groupId;
  double amount;
  String periodStart;
  String periodEnd;
  String paymentDate;
  String paidByUserId;

  /// لقطة وقت الصرف: اسم المعلم واسم من صرف، محليتان لا تتغيران بأثر رجعي.
  String teacherName;
  String paidByName;
  String method;
  String notes;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'teacher_id': teacherId,
        'group_id': groupId.isEmpty ? null : groupId,
        'amount': amount,
        'period_start': periodStart.isEmpty ? null : periodStart,
        'period_end': periodEnd.isEmpty ? null : periodEnd,
        'payment_date': paymentDate,
        'paid_by_user_id': paidByUserId.isEmpty ? null : paidByUserId,
        'teacher_name': teacherName.isEmpty ? null : teacherName,
        'paid_by_name': paidByName.isEmpty ? null : paidByName,
        'payment_method': method,
        'notes': notes.isEmpty ? null : notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  factory TeacherPayout.fromCloud(Map<String, dynamic> m) => TeacherPayout(
        id: '${m['id']}',
        teacherId: '${m['teacher_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        periodStart: '${m['period_start'] ?? ''}'.split('T').first,
        periodEnd: '${m['period_end'] ?? ''}'.split('T').first,
        paymentDate: '${m['payment_date'] ?? ''}'.split('T').first,
        paidByUserId: '${m['paid_by_user_id'] ?? ''}',
        teacherName: '${m['teacher_name'] ?? ''}',
        paidByName: '${m['paid_by_name'] ?? ''}',
        method: '${m['payment_method'] ?? 'cash'}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class Installment {
  Installment({
    required this.id,
    required this.studentId,
    required this.title,
    required this.amount,
    required this.dueDate,
    this.paidAmount = 0,
    this.exception = false,
    this.exceptionNotes = '',
    this.status = 'unpaid',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String studentId;
  String title;
  double amount;
  DateTime dueDate;
  double paidAmount;
  bool exception;
  String exceptionNotes;
  String status;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  double get remaining {
    final r = amount - paidAmount;
    if (r < 0) return 0;
    return r;
  }

  bool get isPaid => remaining <= 0;

  /// الحالة المعتمدة المشتقّة من المبالغ — لا تعتمد على قيمة مخزّنة قد تكون قديمة.
  String get _effectiveStatus {
    if (paidAmount <= 0) return 'unpaid';
    if (paidAmount >= amount) return 'paid';
    return 'partially_paid';
  }

  /// إعادة حساب الحالة بعد أي تغيّر في المسدَّد.
  /// القيم المعتمدة هي `unpaid | partially_paid | paid` فقط.
  void refreshStatus() => status = _effectiveStatus;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id': studentId,
        'title': title,
        'amount': amount,
        'due_date': isoDate(dueDate),
        'paid_amount': paidAmount,
        'status': _effectiveStatus,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Installment.fromCloud(Map<String, dynamic> m) => Installment(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        title: '${m['title'] ?? 'قسط'}',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        dueDate: parseIsoDate('${m['due_date'] ?? ''}') ?? DateTime.now(),
        paidAmount: (m['paid_amount'] as num?)?.toDouble() ?? 0,
        status: '${m['status'] ?? 'pending'}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class AttendanceMark {
  AttendanceMark({
    required this.studentId,
    required this.date,
    required this.status,
    String? id,
    this.sessionId = '',
    this.markedByUserId = '',
    this.notes = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  }) : id = id ?? 'att-$studentId-$date';

  final String id;
  final String studentId;
  final String date;
  String status;
  String sessionId;
  String markedByUserId;
  String notes;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        // عمود محلي فقط: `sanitizePayload` يُسقطه قبل الرفع، ويبقى على القرص
        // حتى لا يضيع اليوم المرصود عند إعادة تشغيل التطبيق.
        'session_date': date,
        'session_id': sessionId.isEmpty ? null : sessionId,
        'student_id': studentId,
        'status': status,
        'marked_by_user_id': markedByUserId.isEmpty ? null : markedByUserId,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AttendanceMark.fromCloud(Map<String, dynamic> m) => AttendanceMark(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        date: '${m['session_date'] ?? m['created_at'] ?? ''}'.split('T').first,
        status: '${m['status'] ?? ''}',
        sessionId: '${m['session_id'] ?? ''}',
        markedByUserId: '${m['marked_by_user_id'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.role,
    this.email = '',
    this.isActive = true,
    this.capabilities = const [],
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;
  String role;
  String email;
  bool isActive;
  List<String> capabilities;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'is_active': isActive,
        'capabilities': capabilities,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AppUser.fromCloud(Map<String, dynamic> m) {
    final caps = <String>[];
    final raw = m['capabilities'];
    if (raw is List) {
      for (final e in raw) {
        caps.add('$e');
      }
    }
    return AppUser(
      id: '${m['id']}',
      name: '${m['name'] ?? ''}',
      role: '${m['role'] ?? ''}',
      email: '${m['email'] ?? ''}',
      isActive: m['is_active'] != false,
      capabilities: caps,
      syncStatus: '${m['sync_status'] ?? 'synced'}',
      createdAt: m['created_at']?.toString(),
      updatedAt: m['updated_at']?.toString(),
    );
  }
}

/// مطابق لـ `types/tenant.ts` في النسخة المكتبية.
class Tenant {
  Tenant({
    required this.id,
    required this.name,
    required this.code,
    required this.username,
    required this.password,
    required this.expiresAt,
    this.ownerName = '',
    this.ownerPhone = '',
    this.notes = '',
    this.planType = 'rental',
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String name;
  String code;
  String username;
  String password;
  DateTime expiresAt;
  String ownerName;
  String ownerPhone;
  String notes;

  /// `rental` = محدد المدة، `lifetime` = دائم.
  String planType;
  bool active;
  String? createdAt;
  String? updatedAt;

  String get plan => planType;
  set plan(String v) => planType = v;

  bool get isLifetime => planType == 'lifetime';

  String get status => active ? 'active' : 'suspended';

  Map<String, dynamic> toCloud() => {
        'id': id,
        'code': code,
        'name': name,
        'app_username': username,
        // `app_password` حُذف من القاعدة: المصادقة صارت عبر Supabase Auth،
        // وكلمات المرور تُدار بدالة السيرفر لا بكتابة عمود من التطبيق

        'plan_type': planType,
        'status': status,
        'expires_at': planType == 'lifetime' ? null : expiresAt.toUtc().toIso8601String(),
        'owner_name': ownerName,
        'owner_phone': ownerPhone,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Tenant.fromCloud(Map<String, dynamic> m) => Tenant(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        code: '${m['code'] ?? ''}',
        username: '${m['app_username'] ?? ''}',
        password: '${m['app_password'] ?? ''}',
        expiresAt: parseIsoDate(m['expires_at']) ?? DateTime.now().add(const Duration(days: 365)),
        ownerName: '${m['owner_name'] ?? ''}',
        ownerPhone: '${m['owner_phone'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        planType: '${m['plan_type'] ?? 'rental'}',
        active: '${m['status'] ?? 'active'}' != 'suspended',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

/// يوم في الأسبوع المدرسي — مطابق لـ `WeekDayInfo` في Attendance.tsx.
class SchoolDay {
  const SchoolDay({
    required this.date,
    required this.dateStr,
    required this.dayName,
    required this.shortDate,
    required this.isToday,
  });

  final DateTime date;
  final String dateStr;
  final String dayName;
  final String shortDate;
  final bool isToday;
}

/// حالات الحضور — مطابق لـ `AttendanceStatus` في types/attendance.ts.
const attendanceStatusNames = {
  'present': 'حاضر',
  'absent': 'غائب',
  'excused': 'معذور',
};

/// أيام الأسبوع — مطابق لـ DAYS_OF_WEEK في shared/constants.ts (0 = الأحد).
const daysOfWeek = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

String daysNames(List<int> days) {
  if (days.isEmpty) return 'غير محدد';
  final sorted = [...days]..sort();
  return sorted.map((d) => daysOfWeek[d % 7]).join('، ');
}

/// «16:00:00» → «16:00»، والفارغ يبقى فارغاً.
///
/// مجموعات مواد الشعب تُنشأ بلا وقت في النسخة المكتبية، وقصّ الفارغ كان يرمي
/// `RangeError` فيتوقّف السحب كله عند أول مجموعة منها.
String _hhmm(Object? raw) {
  final text = '${raw ?? ''}'.trim();
  return text.length < 5 ? '' : text.substring(0, 5);
}

/// المجموعة الدراسية — مطابق لـ `Group` في types/common.ts.
class Group {
  Group({
    required this.id,
    required this.name,
    required this.subjectId,
    required this.teacherId,
    this.roomId = '',
    this.gradeLevel = '',
    this.pricePerMonth = 0,
    this.maxStudents,
    List<int>? days,
    this.startTime = '16:00',
    this.endTime = '18:00',
    this.status = 'active',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  }) : days = days ?? <int>[];

  final String id;
  String name;
  String subjectId;
  String teacherId;
  String roomId;
  String gradeLevel;
  double pricePerMonth;
  int? maxStudents;
  List<int> days;
  String startTime;
  String endTime;

  /// `active | archived | pending`
  String status;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  bool get isActive => status == 'active';

  String get daysLabel => daysNames(days);

  String get timeLabel => startTime.isEmpty || endTime.isEmpty ? 'غير محدد' : '$startTime - $endTime';

  /// مجموعة مادة شعبة: وعاء يربط معلم المادة بطلاب الشعبة، بلا أيام ولا رسوم.
  /// تُميَّز عن مجموعة المركز بأنها معلّقة على صف ولا موعد لها.
  bool get isSectionSubject => roomId.isNotEmpty && days.isEmpty;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'name': name,
        'subject_id': subjectId.isEmpty ? null : subjectId,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'room_id': roomId.isEmpty ? null : roomId,
        'grade_level': gradeLevel,
        'price_per_month': pricePerMonth,
        'max_students': maxStudents,
        'days': days,
        'start_time': startTime,
        'end_time': endTime,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Group.fromCloud(Map<String, dynamic> m) {
    final rawDays = m['days'];
    final days = <int>[];
    if (rawDays is List) {
      for (final d in rawDays) {
        final n = int.tryParse('$d');
        if (n != null) days.add(n);
      }
    }
    return Group(
      id: '${m['id']}',
      name: '${m['name'] ?? ''}',
      subjectId: '${m['subject_id'] ?? ''}',
      teacherId: '${m['teacher_id'] ?? ''}',
      roomId: '${m['room_id'] ?? ''}',
      gradeLevel: '${m['grade_level'] ?? ''}',
      pricePerMonth: (m['price_per_month'] as num?)?.toDouble() ?? 0,
      maxStudents: (m['max_students'] as num?)?.toInt(),
      days: days,
      startTime: _hhmm(m['start_time']),
      endTime: _hhmm(m['end_time']),
      status: '${m['status'] ?? 'active'}',
      syncStatus: '${m['sync_status'] ?? 'synced'}',
      createdAt: m['created_at']?.toString(),
      updatedAt: m['updated_at']?.toString(),
    );
  }
}

/// تسجيل طالب في مجموعة — مطابق لـ `StudentEnrollment` في types/student.ts.
class StudentEnrollment {
  StudentEnrollment({
    required this.id,
    required this.studentId,
    required this.groupId,
    DateTime? enrolledAt,
    this.status = 'active',
    this.customPrice,
    this.appliedPrice,
    this.discountReason = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  }) : enrolledAt = enrolledAt ?? DateTime.now();

  final String id;
  final String studentId;
  final String groupId;
  DateTime enrolledAt;

  /// `active | withdrawn | completed | paused`
  String status;
  double? customPrice;

  /// السعر المطبَّق فعلياً لحظة التسجيل — يُثبَّت حتى لا يتغيّر عكس القيد المالي
  /// إذا عُدّل سعر المجموعة لاحقاً.
  double? appliedPrice;
  String discountReason;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  bool get isActive => status == 'active';

  Map<String, dynamic> toCloud() => {
        'id': id,
        'student_id': studentId,
        'group_id': groupId,
        'enrolled_at': enrolledAt.toUtc().toIso8601String(),
        'status': status,
        'custom_price': customPrice,
        'applied_price': appliedPrice,
        'discount_reason': discountReason,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory StudentEnrollment.fromCloud(Map<String, dynamic> m) => StudentEnrollment(
        id: '${m['id']}',
        studentId: '${m['student_id'] ?? ''}',
        groupId: '${m['group_id'] ?? ''}',
        enrolledAt: parseIsoDate('${m['enrolled_at'] ?? m['enrollment_date'] ?? ''}') ?? DateTime.now(),
        status: '${m['status'] ?? 'active'}',
        customPrice: (m['custom_price'] as num?)?.toDouble(),
        appliedPrice: (m['applied_price'] as num?)?.toDouble(),
        discountReason: '${m['discount_reason'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

/// جلسة دراسية — مطابق لـ `ClassSession` في types/attendance.ts.
class ClassSession {
  ClassSession({
    required this.id,
    required this.groupId,
    required this.sessionDate,
    this.startTime = '08:00',
    this.endTime = '10:00',
    this.teacherId = '',
    this.roomId = '',
    this.status = 'scheduled',
    this.substituteTeacherId = '',
    this.notes = '',
    this.syncStatus = 'synced',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String groupId;

  /// `YYYY-MM-DD`
  String sessionDate;
  String startTime;
  String endTime;
  String teacherId;
  String roomId;

  /// `completed | scheduled | cancelled | substituted`
  String status;
  String substituteTeacherId;
  String notes;
  String syncStatus;
  String? createdAt;
  String? updatedAt;

  Map<String, dynamic> toCloud() => {
        'id': id,
        'group_id': groupId.isEmpty ? null : groupId,
        'session_date': sessionDate,
        'start_time': startTime,
        'end_time': endTime,
        'teacher_id': teacherId.isEmpty ? null : teacherId,
        'substitute_teacher_id': substituteTeacherId.isEmpty ? null : substituteTeacherId,
        'room_id': roomId.isEmpty ? null : roomId,
        'status': status,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ClassSession.fromCloud(Map<String, dynamic> m) => ClassSession(
        id: '${m['id']}',
        groupId: '${m['group_id'] ?? ''}',
        sessionDate: '${m['session_date'] ?? ''}'.split('T').first,
        startTime: '${m['start_time'] ?? '08:00'}',
        endTime: '${m['end_time'] ?? '10:00'}',
        teacherId: '${m['teacher_id'] ?? ''}',
        roomId: '${m['room_id'] ?? ''}',
        status: '${m['status'] ?? 'scheduled'}',
        substituteTeacherId: '${m['substitute_teacher_id'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status'] ?? 'synced'}',
        createdAt: m['created_at']?.toString(),
        updatedAt: m['updated_at']?.toString(),
      );
}

class DueItem {
  DueItem({
    required this.id,
    required this.student,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.late,
    this.scheduled = false,
    this.installmentId,
  });

  final String id;
  final Student student;
  final String title;
  final double amount;
  final DateTime dueDate;
  final bool late;

  /// قسط لم يحن موعده بعد: مسجَّل ومعروف، لكنه ليس مطلوباً اليوم.
  final bool scheduled;
  final String? installmentId;

  String get stageLabel {
    if (late) return 'متأخر عن السداد';
    if (scheduled) return 'مجدول';
    return 'مستحق';
  }
}

class SyncRow {
  SyncRow(this.table, this.count, [this.action = '']);
  final String table;
  final int count;
  final String action;
}

class PendingSync {
  PendingSync({
    required this.id,
    required this.tableName,
    required this.recordId,
    required this.action,
    this.payload,
    required this.createdAt,
    this.tenantId = '',
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptAt,
  });

  int id;
  String tableName;
  String recordId;
  String action;
  Map<String, dynamic>? payload;
  String createdAt;

  /// المنشأة التي نشأت العملية تحتها. جهاز انتقل إلى منشأة أخرى قبل أن يرفع
  /// طابوره كان يرفع عمليات الأولى إلى سحابة الثانية.
  String tenantId;
  int retryCount;
  String? lastError;
  String? lastAttemptAt;

  Map<String, dynamic> toJson() => {
        'table_name': tableName,
        'record_id': recordId,
        'action': action,
        'payload': payload,
        'created_at': createdAt,
        'tenant_id': tenantId,
        'retry_count': retryCount,
        'last_error': lastError,
        'last_attempt_at': lastAttemptAt,
      };

  factory PendingSync.fromJson(Map<String, dynamic> m) => PendingSync(
        id: int.tryParse('${m['id'] ?? 0}') ?? 0,
        tableName: '${m['table_name'] ?? ''}',
        recordId: '${m['record_id'] ?? ''}',
        action: '${m['action'] ?? ''}',
        payload: m['payload'] == null ? null : Map<String, dynamic>.from(m['payload'] as Map),
        createdAt: '${m['created_at'] ?? ''}',
        tenantId: '${m['tenant_id'] ?? ''}',
        retryCount: int.tryParse('${m['retry_count'] ?? 0}') ?? 0,
        lastError: m['last_error']?.toString(),
        lastAttemptAt: m['last_attempt_at']?.toString(),
      );
}

class PendingSummary {
  PendingSummary({required this.total, required this.rows, required this.items});
  final int total;
  final List<SyncRow> rows;
  final List<PendingSummaryItem> items;
}

class PendingSummaryItem {
  PendingSummaryItem({required this.table, required this.action, required this.label, required this.at});
  final String table;
  final String action;
  final String label;
  final String at;
}

class RemoteChangeSummary {
  RemoteChangeSummary({required this.total, required this.rows, required this.items, this.since});
  final int total;
  final List<SyncRow> rows;
  final List<PendingSummaryItem> items;
  final String? since;
}

/// حصيلة السحب من السحابة، مع الجداول التي تعذّر جلبها ولماذا.
class PullOutcome {
  const PullOutcome({
    required this.pulled,
    required this.removed,
    this.failedTables = const {},
  });

  final int pulled;
  final int removed;

  /// اسم الجدول السحابي ← سبب الفشل.
  final Map<String, String> failedTables;

  bool get isComplete => failedTables.isEmpty;
}

class SyncResult {
  SyncResult({required this.success, required this.message, this.pushed = 0, this.pulled = 0, this.failed = 0, this.removed = 0});
  final bool success;
  final String message;
  final int pushed;
  final int pulled;
  final int failed;
  final int removed;
}
