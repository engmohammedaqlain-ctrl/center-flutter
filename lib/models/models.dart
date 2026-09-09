const currency = '₪';
const appName = 'نظام الإدارة المدرسي';
const appVersion = '1.2.2';

const gradeLevels = [
  'عاشر',
  'حادي عشر علمي',
  'حادي عشر أدبي',
  'ثاني عشر علمي',
  'ثاني عشر أدبي',
];

const neighborhoods = [
  'الرمال',
  'الشجاعية',
  'الزيتون',
  'الدرج',
  'التفاح',
  'النصر',
  'الشيخ رضوان',
  'تل الهوا',
  'مخيم الشاطئ',
  'أخرى',
];

const guardianRelations = ['أب', 'أم', 'أخ', 'أخت', 'عم', 'خال', 'جد', 'جدة', 'وصي قانوني'];

const paymentMethodNames = {
  'cash': 'نقداً',
  'jawwal_pay': 'محفظة جوال بي',
  'palpay': 'محفظة بال بي',
  'bop': 'بنك فلسطين',
  'other': 'أخرى',
};

const paymentPurposeNames = {
  'monthly_fee': 'رسوم شهرية',
  'installment': 'سداد دفعة قسط مجدول',
  'seat_reservation': 'حجز مقعد',
  'extra_sessions': 'حصص ومجموعات إضافية',
  'other': 'أخرى',
};

String money(num value) {
  final abs = value.abs();
  final n = abs % 1 == 0 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  return '$n $currency';
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

bool isValidNationalId(String raw) => RegExp(r'^\d{9}$').hasMatch(raw.trim());

bool isValidStudentPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 10 && digits.startsWith('05');
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
    this.nationalId = '',
    this.neighborhood = '',
    this.relation = 'أب',
    this.gender = 'ذكر',
    this.notes = '',
    this.status = 'active',
    this.hasException = false,
    DateTime? enrolledAt,
  }) : enrolledAt = enrolledAt ?? DateTime.now();

  final String id;
  String fullName;
  String gradeLevel;
  String section;
  String phone;
  String parentName;
  String parentPhone;
  String nationalId;
  String neighborhood;
  String relation;
  String gender;
  String notes;
  String status;
  double balance;
  bool hasException;
  DateTime enrolledAt;

  bool get isDebtor => balance < 0;
  String get initial {
    final t = fullName.trim();
    return t.isEmpty ? 'ط' : t.substring(0, 1);
  }
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
  });

  final String id;
  String name;
  String gradeLevel;
  String teacherId;
  int capacity;
  String notes;
  String tier;
}

class Teacher {
  Teacher({
    required this.id,
    required this.name,
    required this.phone,
    required this.subject,
    this.rate = 3000,
  });

  final String id;
  String name;
  String phone;
  String subject;
  double rate;
}

class SubjectItem {
  SubjectItem({
    required this.id,
    required this.name,
    required this.code,
    this.gradeLevel = 'عام / كل المراحل',
  });

  final String id;
  String name;
  String code;
  String gradeLevel;
}

class GradeFee {
  GradeFee({
    required this.id,
    required this.gradeName,
    required this.monthlyFee,
    this.tier = 'secondary',
  });

  final String id;
  String gradeName;
  double monthlyFee;
  String tier;
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
    this.installmentId,
    this.remainingAfter = 0,
    this.cancelled = false,
    this.cancelReason = '',
  });

  final String id;
  final String receiptNumber;
  final String studentId;
  final double amount;
  final String method;
  final DateTime date;
  final String purpose;
  final String notes;
  final String reference;
  final String senderName;
  final String channel;
  final String? installmentId;
  double remainingAfter;
  bool cancelled;
  String cancelReason;
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
  });

  final String id;
  final String studentId;
  final String title;
  final double amount;
  final DateTime dueDate;
  double paidAmount;
  bool exception;

  double get remaining {
    final r = amount - paidAmount;
    if (r < 0) return 0;
    return r;
  }

  bool get isPaid => remaining <= 0;
}

class AttendanceMark {
  AttendanceMark({required this.studentId, required this.date, required this.status});
  final String studentId;
  final String date;
  String status;
}

class AppUser {
  AppUser({required this.id, required this.name, required this.role});
  final String id;
  String name;
  String role;
}

class Tenant {
  Tenant({
    required this.id,
    required this.name,
    required this.code,
    required this.username,
    required this.password,
    required this.expiresAt,
    this.ownerPhone = '',
    this.plan = 'rental',
    this.active = true,
  });

  final String id;
  String name;
  String code;
  String username;
  String password;
  DateTime expiresAt;
  String ownerPhone;
  String plan;
  bool active;
}

class DueItem {
  DueItem({
    required this.id,
    required this.student,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.late,
    required this.exception,
    this.installmentId,
  });

  final String id;
  final Student student;
  final String title;
  final double amount;
  final DateTime dueDate;
  final bool late;
  final bool exception;
  final String? installmentId;

  String get stageLabel {
    if (exception) return 'استثناء';
    if (late) return 'متأخر عن السداد';
    return 'مستحق';
  }
}

class SyncRow {
  SyncRow(this.table, this.count);
  final String table;
  final int count;
}
