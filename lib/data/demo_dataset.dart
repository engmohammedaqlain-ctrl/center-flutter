/// مولّد البيانات التجريبية — المقابل لـ `buildDemoDataset` في `demoData.ts`: مدرسة كاملة بأعوامها
/// وكادرها وطلابها وأقساطها وسنداتها وحضورها وعلاماتها ومصروفاتها ورواتبها ومحتوى المودل، صفوفاً
/// بأعمدة السحابة. لا يكتب شيئاً: من يستدعيه يرفعه (المدرسة التجريبية) أو يحقنه.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'balance.dart';
import 'demo_images.dart';
import 'fee_plan.dart';
import 'teacher_salary.dart';

const _uuid = Uuid();
String _uid() => _uuid.v4();

/// بداية العام الدراسي الذي يقع فيه التاريخ (يبدأ في آب) — `demoYearStart`.
int demoYearStart(DateTime date) => date.month >= 8 ? date.year : date.year - 1;

/// وسائل الدفع المعتمدة في الديمو — `DEMO_PAYMENT_METHODS`.
const demoPaymentMethods = <Map<String, dynamic>>[
  {'id': 'cash', 'name': 'نقداً', 'type': 'cash', 'is_default': true, 'enabled': true},
  {'id': 'bop', 'name': 'بنك فلسطين', 'type': 'bank', 'is_default': true, 'enabled': true},
  {'id': 'arabbank', 'name': 'البنك العربي', 'type': 'bank', 'is_default': false, 'enabled': true},
  {'id': 'palpay', 'name': 'محفظة بال باي', 'type': 'wallet', 'is_default': true, 'enabled': true},
  {'id': 'jawwal_pay', 'name': 'محفظة جوال باي', 'type': 'wallet', 'is_default': true, 'enabled': true},
];

/// جداول الديمو بترتيب الرفع (الأب قبل ابنه) — `DEMO_TABLES`.
const demoTables = [
  'academic_years', 'users', 'grade_fees', 'subjects', 'teachers', 'rooms', 'groups', 'students',
  'enrollments', 'installments', 'payments', 'finance_attachments', 'student_attachments', 'student_years',
  'student_sections', 'sessions', 'attendance', 'student_evaluations', 'expenses', 'teacher_payouts',
  'finance_requests', 'audit_log', 'payment_requests',
];

/// حسابات البوابة للتجربة: معلم وطالب ومتأخر وولي أمر — `DemoLogins`.
class DemoLogins {
  DemoLogins({required this.teacher, required this.student, required this.overdue, required this.parent});

  final ({String name, String nationalId, String portalCode}) teacher;
  final ({String name, String nationalId, String portalCode, String parentPortalCode}) student;
  final ({String name, String nationalId, String portalCode}) overdue;
  ({String name, String nationalId, String parentPortalCode, List<String> children}) parent;
}

/// ما يولّده المولّد — `DemoDataset`. الصور في الصفوف بايتات PNG تحت مفاتيح `_png_*`، تُرفع ثم تُحذف.
class DemoDataset {
  DemoDataset({
    required this.rows,
    required this.currentAcademicYearId,
    required this.principal,
    required this.seatFee,
    required this.transferImage,
    required this.moodleSections,
    required this.moodleItems,
    required this.logins,
  });

  final Map<String, List<Map<String, dynamic>>> rows;
  final String currentAcademicYearId;
  final Map<String, dynamic> principal;
  final double seatFee;
  final List<int> transferImage;
  final List<Map<String, dynamic>> moodleSections;
  final List<Map<String, dynamic>> moodleItems;
  DemoLogins logins;
}

/// هويات وكلمات بوابة عشوائية لكل توليد: لا يتكرر حساب بين مدرستين، والهوية تبدأ بصفر — `demoCredentials`.
class _Credentials {
  final _used = <String>{};
  final _rand = math.Random();

  String _draw(String Function() make) {
    var v = make();
    while (_used.contains(v)) {
      v = make();
    }
    _used.add(v);
    return v;
  }

  String _digits(int n) => List.generate(n, (_) => _rand.nextInt(10)).join();
  String nationalId() => _draw(() => '0${_digits(8)}');
  String code() => _draw(() => '${100000 + _rand.nextInt(900000)}');
}

typedef _Seed = ({
  String first,
  String last,
  String gender,
  int roomIdx,
  String scenario,
  String? status,
  String? notes,
  String? parentName,
  String? parentPhone,
  String? family,
  bool attachment,
  bool previousYear,
  String? health,
  String? medical,
  String? birthDate,
  String? parentJob,
  int? fromRoomIdx,
});

_Seed _s(
  String first,
  String last,
  String gender,
  int roomIdx,
  String scenario, {
  String? status,
  String? notes,
  String? parentName,
  String? parentPhone,
  String? family,
  bool attachment = false,
  bool previousYear = false,
  String? health,
  String? medical,
  String? birthDate,
  String? parentJob,
  int? fromRoomIdx,
}) =>
    (
      first: first,
      last: last,
      gender: gender,
      roomIdx: roomIdx,
      scenario: scenario,
      status: status,
      notes: notes,
      parentName: parentName,
      parentPhone: parentPhone,
      family: family,
      attachment: attachment,
      previousYear: previousYear,
      health: health,
      medical: medical,
      birthDate: birthDate,
      parentJob: parentJob,
      fromRoomIdx: fromRoomIdx,
    );

String _two(int n) => n.toString().padLeft(2, '0');

/// توليد بيانات الديمو كاملة دون أي كتابة — `buildDemoDataset`. [tenantId] يُختم به ما يحتاجه
/// (مسارات الصور والمودل)، وبلاه لا يُولَّد المودل. [keptUsers] حسابات الجهاز تبقى بدل الكادر التجريبي.
Future<DemoDataset> buildDemoDataset({
  String? tenantId,
  List<Map<String, dynamic>> keptUsers = const [],
  String? keptName,
  String? keptUserId,
  DemoImages? images,
}) async {
  images ??= await DemoImages.render();

  // يوم الديمو هو اليوم الحقيقي داخل العام الذي يحويه، محصوراً بين بدايته ونهايته
  final realNow = DateTime.now();
  final y1 = demoYearStart(realNow);
  final yearStartDay = DateTime(y1, 8, 20, 12);
  final yearEnd = DateTime(y1 + 1, 7, 10, 12);
  var t0 = realNow.isBefore(yearStartDay) ? yearStartDay : (realNow.isAfter(yearEnd) ? yearEnd : realNow);
  final today = DateTime(t0.year, t0.month, t0.day, 12);
  final year = today.year;
  final daysSinceStart = math.max(0, today.difference(yearStartDay).inMilliseconds ~/ 86400000);
  int ago(int days) => -math.min(days, daysSinceStart);
  String dateStr(int offset) => isoDate(DateTime(today.year, today.month, today.day + offset));
  String dateTimeStr(int offset, [int hours = 8, int minutes = 0]) =>
      DateTime(today.year, today.month, today.day + offset, hours, minutes).toUtc().toIso8601String();
  final nowIso = DateTime.now().toUtc().toIso8601String();
  const seatFee = 50.0;

  // 1. الأعوام الدراسية
  final currentYearId = _uid();
  final previousYearId = _uid();
  final academicYears = <Map<String, dynamic>>[
    {
      'id': currentYearId,
      'label': '$y1 / ${y1 + 1}',
      'starts_on': '$y1-08-15',
      'ends_on': '${y1 + 1}-07-15',
      'term_1_start': '$y1-09-01',
      'term_1_end': '$y1-12-31',
      'term_2_start': '${y1 + 1}-01-15',
      'term_2_end': '${y1 + 1}-06-15',
      'status': 'open',
      'is_current': true,
      'created_at': dateTimeStr(ago(180)),
      'updated_at': nowIso,
    },
    {
      'id': previousYearId,
      'label': '${y1 - 1} / $y1',
      'starts_on': '${y1 - 1}-08-15',
      'ends_on': '$y1-07-15',
      'term_1_start': '${y1 - 1}-09-01',
      'term_1_end': '${y1 - 1}-12-31',
      'term_2_start': '$y1-01-15',
      'term_2_end': '$y1-06-15',
      'status': 'closed',
      'is_current': false,
      'created_at': '${y1 - 1}-08-01T08:00:00.000Z',
      'updated_at': '$y1-07-20T08:00:00.000Z',
    },
  ];

  // 2. الكادر الإداري
  final users = keptUsers.isNotEmpty
      ? [for (final u in keptUsers) {...u, 'updated_at': nowIso}]
      : <Map<String, dynamic>>[
          {
            'id': _uid(),
            'name': keptName ?? 'أحمد أبو شمالة (المدير العام)',
            'email': 'principal@alamal.edu',
            'role': 'admin',
            'is_active': true,
            'created_at': dateTimeStr(ago(180)),
            'updated_at': nowIso,
          },
          {
            'id': _uid(),
            'name': 'سارة أبو مصطفى (السكرتيرة)',
            'email': 'reception@alamal.edu',
            'role': 'receptionist',
            'is_active': true,
            'created_at': dateTimeStr(ago(180)),
            'updated_at': nowIso,
          },
          {
            'id': _uid(),
            'name': 'خالد أبو جراد (المحاسب المالي)',
            'email': 'finance@alamal.edu',
            'role': 'accountant',
            'is_active': true,
            'created_at': dateTimeStr(ago(150)),
            'updated_at': nowIso,
          },
          // حساب موظف بصلاحيات مخصصة مقيدة (شؤون طلاب فقط دون المالية)
          {
            'id': _uid(),
            'name': 'مروة أبو حصيرة (مشرفة شؤون الطلاب)',
            'email': 'affairs@alamal.edu',
            'role': 'receptionist',
            'capabilities': ['students', 'attendance', 'classes'],
            'is_active': true,
            'created_at': dateTimeStr(ago(100)),
            'updated_at': nowIso,
          },
        ];
  final principal = users.where((u) => u['id'] == keptUserId).firstOrNull ??
      users.where((u) => u['role'] == 'admin').firstOrNull ??
      users.first;
  final secretary = users.where((u) => u['role'] == 'receptionist' && u['id'] != principal['id']).firstOrNull ??
      users.where((u) => u['id'] != principal['id']).firstOrNull ??
      principal;
  final accountant = users.where((u) => u['role'] == 'accountant' && u['id'] != principal['id']).firstOrNull ?? secretary;

  // 3. المراحل والرسوم: أربعة أشهر تبدأ بالشهر الماضي، محصورة بين أيلول وحزيران
  final firstDueMonth = math.min(math.max(today.year * 12 + today.month - 2, y1 * 12 + 8), (y1 + 1) * 12 + 2);
  final dueMonthKeys = [
    for (var o = 0; o < 4; o++) '${(firstDueMonth + o) ~/ 12}-${_two((firstDueMonth + o) % 12 + 1)}',
  ];
  const gradeConfigs = <({String name, double fee, String tier, int order, List<double>? plan})>[
    (name: 'عاشر', fee: 200, tier: 'secondary', order: 1, plan: [70, 50, 50, 30]),
    (name: 'حادي عشر', fee: 220, tier: 'secondary', order: 2, plan: null),
    // خطة غير متساوية: دفعة أولى أكبر ثم أقساط وأخيرة أصغر
    (name: 'سابع', fee: 450, tier: 'middle', order: 3, plan: [600, 450, 450, 300]),
    (name: 'ثامن', fee: 180, tier: 'middle', order: 4, plan: null),
    (name: 'خامس', fee: 160, tier: 'middle', order: 5, plan: null),
    (name: 'رابع', fee: 140, tier: 'primary', order: 6, plan: null),
    (name: 'تمهيدي', fee: 120, tier: 'kindergarten', order: 7, plan: null),
  ];
  final planItemsByGrade = <String, List<Map<String, dynamic>>>{};
  final gradeFees = <Map<String, dynamic>>[];
  for (final g in gradeConfigs) {
    final items = [
      for (var i = 0; i < dueMonthKeys.length; i++)
        {
          'id': 'plan_${g.name}_term_${i + 1}',
          'title': feeMonthTitle('${dueMonthKeys[i]}-01', i + 1),
          'amount': g.plan?[i] ?? g.fee,
          'due_date': '${dueMonthKeys[i]}-01',
        },
    ];
    planItemsByGrade[g.name] = items;
    gradeFees.add({
      'id': _uid(),
      'grade_name': g.name,
      'monthly_fee': g.fee,
      'order_index': g.order,
      'stage_tier': g.tier,
      'is_custom': false,
      'term_1_start': '${dueMonthKeys[0]}-01',
      'term_1_end': '${dueMonthKeys[1]}-28',
      'term_2_start': '${dueMonthKeys[2]}-01',
      'term_2_end': '${dueMonthKeys[3]}-28',
      'plan_items': items,
      'academic_year_id': currentYearId,
      'created_at': dateTimeStr(ago(180)),
      'updated_at': nowIso,
    });
  }

  // 4. المواد الثمانية
  const subjectDefs = [
    ('الرياضيات', 'المنهاج المعتمد للرياضيات والجبر والهندسة'),
    ('اللغة العربية', 'قواعد اللغة والأدب والنصوص والتعبير'),
    ('اللغة الإنجليزية', 'اللغة الإنجليزية والمحادثة والقواعد'),
    ('العلوم العامة', 'منهاج العلوم والحياة'),
    ('الفيزياء والكيمياء', 'العلوم الفيزيائية والكيميائية للمرحلة الثانوية'),
    ('التربية الإسلامية', 'القرآن الكريم والحديث الشريف والفقه والسيرة'),
    ('تكنولوجيا المعلومات والحاسوب', 'الحاسوب والتطبيقات البرمجية'),
    ('التربية الفنية والأنشطة', 'الرسم والأنشطة الإبداعية والمهارات'),
  ];
  final subjects = [
    for (final s in subjectDefs)
      <String, dynamic>{
        'id': _uid(),
        'name': s.$1,
        'description': s.$2,
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(180)),
        'updated_at': nowIso,
      },
  ];
  final subjMath = subjects[0], subjArab = subjects[1], subjEng = subjects[2], subjSci = subjects[3];
  final subjPhy = subjects[4], subjIsl = subjects[5], subjTech = subjects[6], subjArt = subjects[7];

  final credentials = _Credentials();

  // 5. المعلمون السبعة
  final teacherDefs = [
    ('أ. محمود الزهار', '0599112233', 3400.0, 'معلم أول رياضيات للمرحلة الثانوية', [subjMath['id']]),
    ('أ. وفاء عاشور', '0568223344', 3200.0, 'معلمة لغة عربية متميزة', [subjArab['id']]),
    ('أ. طارق منصور', '0599334455', 3100.0, 'معلم اللغة الإنجليزية للمراحل المختلفة', [subjEng['id']]),
    ('أ. عيسى النمس', '0599445566', 3300.0, 'معلم الفيزياء والكيمياء والعلوم', [subjPhy['id'], subjSci['id']]),
    ('أ. هدى البنا', '0568556677', 2900.0, 'معلمة التربية الإسلامية والقرآن', [subjIsl['id']]),
    ('أ. مروان الحلو', '0599667788', 3000.0, 'معلم الحاسوب وتكنولوجيا المعلومات', [subjTech['id']]),
    ('أ. ريم الكرد', '0568778899', 2800.0, 'معلمة الصفوف الأساسية ورياض الأطفال', [subjSci['id'], subjArt['id'], subjArab['id']]),
  ];
  final teachers = <Map<String, dynamic>>[
    for (var i = 0; i < teacherDefs.length; i++)
      {
        'id': _uid(),
        'name': teacherDefs[i].$1,
        'national_id': credentials.nationalId(),
        'portal_code': credentials.code(),
        'phone': teacherDefs[i].$2,
        'email': 'teacher${i + 1}@alamal.edu',
        'subject_ids': teacherDefs[i].$5,
        'payment_rate': teacherDefs[i].$3,
        'notes': teacherDefs[i].$4,
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(180)),
        'updated_at': nowIso,
      },
  ];
  final tZahar = teachers[0], tWafaa = teachers[1], tTariq = teachers[2], tIsa = teachers[3];
  final tHuda = teachers[4], tMarwan = teachers[5], tReem = teachers[6];

  // 6. الشعب التسع
  final roomDefs = [
    ('عاشر', 'شعبة (أ)', tZahar, 28, 'طابق 2 - قاعة 101'),
    ('عاشر', 'شعبة (ب)', tIsa, 26, 'طابق 2 - قاعة 102'),
    ('حادي عشر', 'شعبة علمي', tZahar, 25, 'طابق 2 - مختبر العلوم'),
    ('ثامن', 'شعبة (أ)', tTariq, 30, 'طابق 1 - قاعة 201'),
    ('خامس', 'شعبة (أ)', tWafaa, 28, 'طابق 1 - قاعة 202'),
    ('رابع', 'شعبة (أ)', tReem, 25, 'طابق أرضي - قاعة 301'),
    ('رابع', 'شعبة (ب)', tHuda, 24, 'طابق أرضي - قاعة 302'),
    ('تمهيدي', 'قاعة الزهور', tReem, 20, 'قسم رياض الأطفال'),
    ('سابع', 'شعبة (أ)', tWafaa, 34, 'طابق 1 - قاعة 203'),
  ];
  final rooms = [
    for (final r in roomDefs)
      <String, dynamic>{
        'id': _uid(),
        'name': r.$2,
        'grade_level': r.$1,
        'homeroom_teacher_id': r.$3['id'],
        'capacity': r.$4,
        'notes': r.$5,
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(180)),
        'updated_at': nowIso,
      },
  ];

  // 7. إسناد المواد للشعب: المجموعة الواحدة تخدم شعب المرحلة نفسها
  final plans = <List<(Map<String, dynamic>, Map<String, dynamic>)>>[
    [(subjMath, tZahar), (subjArab, tWafaa), (subjEng, tTariq), (subjPhy, tIsa)],
    [(subjMath, tIsa), (subjArab, tWafaa), (subjEng, tTariq), (subjPhy, tIsa)],
    [(subjMath, tZahar), (subjPhy, tIsa), (subjArab, tWafaa), (subjEng, tTariq)],
    [(subjMath, tZahar), (subjArab, tWafaa), (subjSci, tIsa), (subjIsl, tHuda)],
    [(subjArab, tWafaa), (subjMath, tZahar), (subjSci, tIsa), (subjTech, tMarwan)],
    [(subjArab, tReem), (subjMath, tReem), (subjSci, tReem), (subjIsl, tHuda)],
    [(subjArab, tReem), (subjMath, tReem), (subjSci, tReem), (subjArt, tReem)],
    [(subjArab, tReem), (subjMath, tReem), (subjArt, tReem)],
    // السابع (أ): سبع مواد بمعلميها، فتمتلئ شهادة الطالب وكشف علاماته
    [(subjMath, tZahar), (subjArab, tWafaa), (subjEng, tTariq), (subjSci, tIsa), (subjIsl, tHuda), (subjTech, tMarwan), (subjArt, tReem)],
  ];
  final groups = <Map<String, dynamic>>[];
  final groupByKey = <String, Map<String, dynamic>>{};
  final roomGroups = <String, List<Map<String, dynamic>>>{};
  for (var ri = 0; ri < plans.length; ri++) {
    final room = rooms[ri];
    final mine = <Map<String, dynamic>>[];
    for (final (subject, teacher) in plans[ri]) {
      final key = '${subject['id']}|${teacher['id']}|${room['grade_level']}';
      var g = groupByKey[key];
      if (g != null) {
        final ids = g['room_ids'] as List<String>;
        if (!ids.contains(room['id'])) ids.add(room['id'] as String);
      } else {
        g = {
          'id': _uid(),
          'name': '${subject['name']} - ${teacher['name']}',
          'subject_id': subject['id'],
          'teacher_id': teacher['id'],
          'room_id': room['id'],
          'room_ids': <String>[room['id'] as String],
          'grade_level': room['grade_level'],
          'status': 'active',
          'academic_year_id': currentYearId,
          'created_at': dateTimeStr(ago(180)),
          'updated_at': nowIso,
        };
        groups.add(g);
        groupByKey[key] = g;
      }
      mine.add(g);
    }
    roomGroups[room['id'] as String] = mine;
  }

  // 8. الطلاب بكل السيناريوهات
  final seeds = <_Seed>[
    // عاشر (أ)
    _s('محمد', 'النجار', 'ذكر', 0, 'paid_full', notes: 'طالب متفوق أول الصف', attachment: true, previousYear: true, health: 'سليم', birthDate: '2010-04-12', parentJob: 'مهندس حاسوب'),
    _s('سارة', 'خضير', 'أنثى', 0, 'regular', notes: 'مستفيدة من خصم الأخوة 20%', parentName: 'إبراهيم خضير', parentPhone: '0598111222', family: '210001', attachment: true, previousYear: true, health: 'مريض', medical: 'حساسية قمح (السيلياك) - يرجى الانتباه للمقصف'),
    _s('عمر', 'الشوا', 'ذكر', 0, 'paid_partial', notes: 'سداد جزئي حسب إمكانيات ولي الأمر', previousYear: true, parentJob: 'تاجر أقمشة'),
    _s('نور', 'السوسي', 'أنثى', 0, 'overdue', notes: 'متأخر في سداد الرسوم الأولى والثانية', attachment: true, health: 'سليم'),
    _s('حمزة', 'الغول', 'ذكر', 0, 'scholarship', notes: 'منحة تفوق دراسي 50% من إدارة المدرسة - شقيقاه مريم ويوسف', parentName: 'محمود الغول', parentPhone: '0598333444', family: '220002'),
    _s('كريم', 'البرعي', 'ذكر', 0, 'custom_plan', status: 'archived', notes: 'طالب مؤرشف من العام السابق'),
    // عاشر (ب)
    _s('ياسر', 'عابد', 'ذكر', 1, 'paid_full', notes: 'مسدد كامل الرسوم نقداً', previousYear: true),
    _s('هديل', 'شاهين', 'أنثى', 1, 'regular', notes: 'سداد عبر حوالة بنكية بانتظام'),
    _s('أنس', 'مطر', 'ذكر', 1, 'paid_partial', notes: 'سدد نصف الرسوم الثانية'),
    _s('ريان', 'البطة', 'ذكر', 1, 'overdue', status: 'pending', notes: 'موقوف إدارياً بانتظار تأكيد التسجيل'),
    _s('شهد', 'عياش', 'أنثى', 1, 'scholarship', notes: 'كفالة طالب يتيم (منحة كاملة 100%)'),
    _s('محمود', 'المصري', 'ذكر', 1, 'regular', notes: 'منتظم في الحضور والأنشطة', previousYear: true),
    // حادي عشر علمي
    _s('طارق', 'حجازي', 'ذكر', 2, 'paid_full', notes: 'مسدد كامل مع رسوم حجز المقعد', previousYear: true),
    _s('دينا', 'الدلو', 'أنثى', 2, 'regular', notes: 'سداد عبر محفظة جوال باي'),
    _s('باسم', 'حمدونة', 'ذكر', 2, 'paid_partial', notes: 'متبقي من الرسوم الثانية 70 شيكل'),
    _s('وسيم', 'الريفي', 'ذكر', 2, 'overdue', status: 'withdrawn', notes: 'انسحب في منتصف الفصل وعليه متبقي'),
    _s('رغد', 'الجعبري', 'أنثى', 2, 'scholarship', notes: 'خصم أبناء المعلمين 30%'),
    _s('أمير', 'الطهراوي', 'ذكر', 2, 'paid_full', status: 'completed', notes: 'طالب أنهى المرحلة بنجاح'),
    // ثامن (أ)
    _s('ماجد', 'أبو ندى', 'ذكر', 3, 'paid_full', notes: 'مسدد بالكامل', previousYear: true),
    _s('لجين', 'كحيل', 'أنثى', 3, 'regular', notes: 'سداد منتظم بموجب شيك بنكي'),
    _s('بلال', 'الوادية', 'ذكر', 3, 'paid_partial', notes: 'سداد جزئي'),
    _s('فاطمة', 'الريس', 'أنثى', 3, 'overdue', notes: 'متأخرة عن سداد الرسوم'),
    _s('زيد', 'الوحيدي', 'ذكر', 3, 'custom_plan', notes: 'خطة رسوم خاصة ميسرة لولي الأمر'),
    _s('جنى', 'أبو شعبان', 'أنثى', 3, 'regular', notes: 'طالبة نشطة ومجتهدة', previousYear: true),
    // خامس (أ)
    _s('قصي', 'مشتهى', 'ذكر', 4, 'paid_full', notes: 'مسدد بالكامل', previousYear: true),
    _s('سيدرا', 'حلس', 'أنثى', 4, 'regular', notes: 'منتظمة في السداد والدراسة'),
    _s('رامي', 'البردويل', 'ذكر', 4, 'paid_partial', notes: 'سداد جزئي عبر البنك'),
    _s('حلا', 'الغمري', 'أنثى', 4, 'overdue', notes: 'متأخرة مع طلب إعفاء مقدم من ولي الأمر'),
    _s('مريم', 'الغول', 'أنثى', 4, 'scholarship', notes: 'شقيقة حمزة الغول - خصم إخوة 20%', parentName: 'محمود الغول', parentPhone: '0598333444', family: '220002'),
    _s('سعيد', 'عطالله', 'ذكر', 4, 'regular', status: 'pending', notes: 'بانتظار تأكيد استكمال أوراق التسجيل'),
    // رابع (أ)
    _s('أحمد', 'خضير', 'ذكر', 5, 'regular', notes: 'شقيق سارة خضير - خصم إخوة 20%', parentName: 'إبراهيم خضير', parentPhone: '0598111222', family: '210001', attachment: true),
    _s('تالا', 'الزعبوط', 'أنثى', 5, 'paid_full', notes: 'مسدد بالكامل مع المقعد'),
    _s('آدم', 'القرم', 'ذكر', 5, 'paid_partial', notes: 'سداد نصف الرسوم'),
    _s('ريماس', 'فلفل', 'أنثى', 5, 'overdue', notes: 'متأخرة عن رسوم الشهر الحالي'),
    _s('سامي', 'سكيك', 'ذكر', 5, 'regular', notes: 'سداد نقدي في الإدارة', previousYear: true),
    _s('لينا', 'الهسي', 'أنثى', 5, 'paid_full', notes: 'طالبة متفوقة ومنتظمة', previousYear: true),
    // رابع (ب) مع نقل طالب من رابع (أ)
    _s('جهاد', 'النعسان', 'ذكر', 6, 'paid_full', notes: 'مسدد بالكامل', previousYear: true),
    _s('غنى', 'المدلل', 'أنثى', 6, 'regular', notes: 'سداد بالتحويل البنكي'),
    _s('يامن', 'البورنو', 'ذكر', 6, 'paid_partial', notes: 'نُقل من شعبة (أ) إلى شعبة (ب) بطلب ولي الأمر', fromRoomIdx: 5),
    _s('ليان', 'عاشور', 'أنثى', 6, 'overdue', status: 'withdrawn', notes: 'منسحبة وانتقلت لمدرسة أخرى'),
    _s('فارس', 'الشوربجي', 'ذكر', 6, 'regular', notes: 'منتظم'),
    _s('بيسان', 'سعد', 'أنثى', 6, 'scholarship', status: 'archived', notes: 'طالبة مؤرشفة'),
    // تمهيدي
    _s('يوسف', 'الغول', 'ذكر', 7, 'regular', notes: 'شقيق حمزة ومريم - خصم إخوة 20%', parentName: 'محمود الغول', parentPhone: '0598333444', family: '220002'),
    _s('سوار', 'أبو رمضان', 'أنثى', 7, 'paid_full', notes: 'مسدد كامل الرسوم والنشاط والزي'),
    _s('جاد', 'حمدي', 'ذكر', 7, 'paid_partial', notes: 'سدد رسوم الروضة الأولى'),
    _s('ميرا', 'الدحدوح', 'أنثى', 7, 'overdue', notes: 'متأخر في سداد الرسوم'),
    _s('كنان', 'صباح', 'ذكر', 7, 'paid_full', notes: 'مسدد بالكامل'),
    _s('لانا', 'صالح', 'أنثى', 7, 'regular', notes: 'منتظمة في الحضور'),
    // السابع (أ): أوائلهم من لقطات الموقع التعريفي
    _s('ريم', 'سامي عودة', 'أنثى', 8, 'regular', notes: 'طالبة منتظمة ومتفوقة', attachment: true, previousYear: true, health: 'سليم', birthDate: '2013-03-18', parentName: 'سامي عودة', parentPhone: '0597111001', parentJob: 'مهندس مدني'),
    _s('يوسف', 'أحمد خليل', 'ذكر', 8, 'paid_partial', attachment: true, previousYear: true, birthDate: '2013-07-02'),
    _s('ليان', 'محمود ناصر', 'أنثى', 8, 'paid_full', attachment: true, previousYear: true, birthDate: '2013-01-25'),
    _s('آدم', 'خالد الريس', 'ذكر', 8, 'regular', attachment: true, birthDate: '2013-09-11'),
    _s('جنى', 'وليد حماد', 'أنثى', 8, 'regular', attachment: true, birthDate: '2013-05-30'),
    _s('سيف', 'نبيل عاشور', 'ذكر', 8, 'overdue', notes: 'متأخر عن القسط الثاني', attachment: true, birthDate: '2013-11-06'),
  ];
  const firstM = ['عمر', 'زيد', 'كنان', 'مازن', 'أنس', 'ليث', 'رائد', 'بشير', 'وائل', 'حازم', 'نادر', 'ثائر', 'عادل'];
  const firstF = ['سلمى', 'تيماء', 'روان', 'هبة', 'مي', 'دانة', 'لمى', 'رنا', 'أسيل', 'ميار', 'سندس', 'رزان', 'جوري', 'ملك'];
  const lastNames = ['الأغا', 'أبو سعدة', 'اللحام', 'شراب', 'القدوة', 'عبيد', 'النحال', 'الحداد', 'سلامة', 'أبو عيطة', 'الجرجاوي', 'دياب', 'المغربي', 'حسونة'];
  const showcaseScenarios = ['paid_full', 'regular', 'regular', 'paid_partial', 'regular', 'scholarship', 'paid_full', 'regular', 'overdue'];
  for (var i = 0; i < 27; i++) {
    seeds.add(_s(
      i.isEven ? firstM[(i >> 1) % firstM.length] : firstF[(i >> 1) % firstF.length],
      lastNames[(i * 3) % lastNames.length],
      i.isEven ? 'ذكر' : 'أنثى',
      8,
      showcaseScenarios[i % showcaseScenarios.length],
      attachment: i % 4 == 0,
      birthDate: '2013-${_two((i % 12) + 1)}-${_two((i % 27) + 1)}',
    ));
  }

  final students = <Map<String, dynamic>>[];
  final enrollments = <Map<String, dynamic>>[];
  final installments = <Map<String, dynamic>>[];
  final payments = <Map<String, dynamic>>[];
  final financeAttachments = <Map<String, dynamic>>[];
  final studentAttachments = <Map<String, dynamic>>[];
  final studentYears = <Map<String, dynamic>>[];
  final studentSections = <Map<String, dynamic>>[];
  var receiptNum = 1001;
  // الإخوة يتشاركون هوية ولي الأمر وكلمته
  final families = <String, ({String nationalId, String code})>{};
  ({String nationalId, String code}) parentLogin(String? family) {
    ({String nationalId, String code}) fresh() => (nationalId: credentials.nationalId(), code: credentials.code());
    if (family == null) return fresh();
    return families.putIfAbsent(family, fresh);
  }

  for (var idx = 0; idx < seeds.length; idx++) {
    final st = seeds[idx];
    final studentId = _uid();
    final room = rooms[st.roomIdx];
    final grade = room['grade_level'] as String;
    final myGroups = roomGroups[room['id']] ?? const [];
    final baseFee = (gradeFees.where((g) => g['grade_name'] == grade).firstOrNull?['monthly_fee'] as double?) ?? 160;
    final fullName = '${st.first} ${st.last}';

    var factor = 1.0;
    var discountRate = 0.0;
    var customPlan = false;
    if (st.scenario == 'scholarship') {
      discountRate = 50;
      factor = 0.5;
    } else if (st.scenario == 'custom_plan') {
      customPlan = true;
      factor = 0.8;
    }

    for (var p = 1; p <= 4; p++) {
      final monthKey = dueMonthKeys[p - 1];
      final planItem = planItemsByGrade[grade]?[p - 1];
      final instId = planInstallmentId('${planItem?['id'] ?? 'inst_${grade}_$p'}', studentId);
      final dueDate = '$monthKey-01';
      final planAmount = (planItem?['amount'] as double?) ?? baseFee;
      final amount = (planAmount * factor).roundToDouble();
      var paid = 0.0;
      switch (st.scenario) {
        case 'paid_full':
          paid = amount;
        case 'regular' || 'scholarship' || 'custom_plan':
          if (p <= 2) paid = amount;
        case 'paid_partial':
          if (p == 1) paid = amount;
          if (p == 2) paid = (amount / 2).roundToDouble();
        case 'overdue':
          if (p == 1) paid = (amount * 0.3).roundToDouble();
      }
      installments.add({
        'id': instId,
        'student_id': studentId,
        'title': feeMonthTitle(dueDate),
        'amount': amount,
        if (discountRate > 0) 'original_amount': planAmount,
        'paid_amount': paid,
        'due_date': dueDate,
        'status': paid >= amount ? 'paid' : (paid > 0 ? 'partially_paid' : 'unpaid'),
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
      if (paid <= 0) continue;
      final monthNote = '${monthKey.substring(5, 7)}/${monthKey.substring(0, 4)}';
      // تقسيم سداد القسط نفسه بين نقد وبنك
      if (st.scenario == 'paid_partial' && p == 2 && paid >= 40) {
        final cash = (paid / 2).floorToDouble();
        final bank = paid - cash;
        final id1 = _uid(), id2 = _uid();
        final d2 = dateStr(ago(49 - p * 12));
        payments.add({
          'id': id1,
          'receipt_number': '$year/${receiptNum++}',
          'student_id': studentId,
          'installment_id': instId,
          'amount': cash,
          'payment_method': 'cash',
          'payment_date': dateStr(ago(50 - p * 12)),
          'received_by_user_id': secretary['id'],
          'received_by_name': secretary['name'],
          'student_name': fullName,
          'notes': 'سداد دفعة أولى نقداً من رسوم $monthNote',
          'academic_year_id': currentYearId,
          'created_at': dateTimeStr(ago(50 - p * 12)),
          'updated_at': nowIso,
        });
        payments.add({
          'id': id2,
          'receipt_number': '$year/${receiptNum++}',
          'student_id': studentId,
          'installment_id': instId,
          'amount': bank,
          'payment_method': 'bop',
          'payment_date': d2,
          'received_by_user_id': accountant['id'],
          'received_by_name': accountant['name'],
          'student_name': fullName,
          'notes': 'سداد دفعة ثانية بحوالة بنك فلسطين من رسوم $monthNote',
          'transfer_channel': 'بنك فلسطين',
          'sender_name': st.parentName ?? 'ولي أمر الطالب ${st.first}',
          'reference_number': 'TRX-$year-${receiptNum + 500}',
          'academic_year_id': currentYearId,
          'created_at': dateTimeStr(ago(49 - p * 12)),
          'updated_at': nowIso,
        });
        financeAttachments.add({'id': id2, 'record_type': 'payment', '_png': images.transfer, 'created_at': d2, 'updated_at': nowIso});
      } else {
        final payDate = dateStr(ago(50 - p * 12));
        final receiver = p % 3 == 0 ? accountant : (p.isEven ? secretary : principal);
        // وسائل المدرسة نفسها: كل وسيلة حساب في الأرباح والإقفال
        final method = p % 4 == 0 || (p == 2 && idx % 3 == 0) ? 'bop' : (p % 3 == 0 ? 'jawwal_pay' : 'cash');
        final payId = _uid();
        payments.add({
          'id': payId,
          'receipt_number': '$year/${receiptNum++}',
          'student_id': studentId,
          'installment_id': instId,
          'amount': paid,
          'payment_method': method,
          'payment_date': payDate,
          'received_by_user_id': receiver['id'],
          'received_by_name': receiver['name'],
          'student_name': fullName,
          'notes': 'سداد رسوم $monthNote',
          if (method == 'bop') 'transfer_channel': 'بنك فلسطين',
          if (method == 'jawwal_pay') 'transfer_channel': 'محفظة جوال باي',
          if (method != 'cash') 'sender_name': st.parentName ?? 'ولي أمر الطالب ${st.first}',
          if (method != 'cash') 'reference_number': 'TRX-$year-${receiptNum + 500}',
          'academic_year_id': currentYearId,
          'created_at': dateTimeStr(ago(50 - p * 12)),
          'updated_at': nowIso,
        });
        if (method != 'cash') {
          financeAttachments.add({'id': payId, 'record_type': 'payment', '_png': images.transfer, 'created_at': payDate, 'updated_at': nowIso});
        }
      }
    }

    final seatPaid = idx.isEven || st.scenario == 'paid_full';
    if (seatPaid) {
      final seatInstId = _uid();
      installments.add({
        'id': seatInstId,
        'student_id': studentId,
        'title': seatTitle,
        'amount': seatFee,
        'paid_amount': seatFee,
        'due_date': dateStr(ago(120)),
        'status': 'paid',
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
      payments.add({
        'id': _uid(),
        'receipt_number': '$year/${receiptNum++}',
        'student_id': studentId,
        'installment_id': seatInstId,
        'amount': seatFee,
        'payment_method': 'cash',
        'payment_date': dateStr(ago(120)),
        'received_by_user_id': secretary['id'],
        'received_by_name': secretary['name'],
        'student_name': fullName,
        'payment_purpose': 'seat_reservation',
        'notes': 'تسديد رسوم حجز المقعد عند القبول والتسجيل',
        'academic_year_id': currentYearId,
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
    }

    final parent = parentLogin(st.family);
    students.add({
      'id': studentId,
      'first_name': st.first,
      'last_name': st.last,
      'national_id': credentials.nationalId(),
      'portal_code': credentials.code(),
      'parent_name': st.parentName,
      'parent_national_id': parent.nationalId,
      'parent_portal_code': parent.code,
      // ثلثهم على 056 وباقي رقمهم يبدأ بـ 20
      'phone': idx % 3 == 1 ? '05620${'${10000 + idx * 137}'.substring('${10000 + idx * 137}'.length - 5)}' : '0599${'${100000 + idx * 2222}'.substring(0, 6)}',
      'parent_phone': st.parentPhone ?? '0598${'${200000 + idx * 3333}'.substring(0, 6)}',
      'grade_level': grade,
      'section': room['name'],
      'gender': st.gender,
      'status': st.status ?? 'active',
      // يُشتق من السندات بعد بنائها كلها
      'balance': 0.0,
      'notes': st.notes ?? 'طالب مسجل في المدرسة',
      'seat_reservation_paid': seatPaid,
      'uses_custom_plan': customPlan,
      'academic_discount_applied': discountRate > 0,
      'academic_discount_rate': discountRate,
      'enrollment_date': dateStr(ago(120)),
      'health_status': st.health ?? 'سليم',
      'medical_condition': st.medical,
      'birth_date': st.birthDate ?? '2011-06-15',
      'birth_place': 'فلسطين',
      'nationality': 'فلسطينية',
      'parent_job': st.parentJob ?? 'موظف قطاع خاص',
      'academic_year_id': currentYearId,
      'created_at': dateTimeStr(ago(120)),
      'updated_at': nowIso,
    });

    for (final g in myGroups) {
      enrollments.add({
        'id': _uid(),
        'student_id': studentId,
        'group_id': g['id'],
        'room_id': room['id'],
        'enrolled_at': dateStr(ago(120)),
        'status': 'active',
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
    }

    final active = st.status == null || st.status == 'active';
    if (st.fromRoomIdx != null) {
      final oldRoom = rooms[st.fromRoomIdx!];
      for (final og in roomGroups[oldRoom['id']] ?? const <Map<String, dynamic>>[]) {
        // المجموعة الواحدة تخدم شعباً عدة: تسجيل الطالب فيها مرة واحدة فقط
        if (myGroups.any((g) => g['id'] == og['id'])) continue;
        enrollments.add({
          'id': _uid(),
          'student_id': studentId,
          'group_id': og['id'],
          'room_id': oldRoom['id'],
          'enrolled_at': dateStr(ago(120)),
          'status': 'withdrawn',
          'created_at': dateTimeStr(ago(120)),
          'updated_at': dateTimeStr(ago(60)),
        });
      }
      studentSections.add({
        'id': _uid(),
        'student_id': studentId,
        'academic_year_id': currentYearId,
        'grade_level': oldRoom['grade_level'],
        'section': oldRoom['name'],
        'from_date': dateStr(ago(120)),
        'to_date': dateStr(ago(60)),
        'created_at': dateTimeStr(ago(120)),
        'updated_at': dateTimeStr(ago(60)),
      });
      studentSections.add({
        'id': _uid(),
        'student_id': studentId,
        'academic_year_id': currentYearId,
        'grade_level': grade,
        'section': room['name'],
        'from_date': dateStr(ago(60)),
        'to_date': active ? null : dateStr(ago(10)),
        'created_at': dateTimeStr(ago(60)),
        'updated_at': nowIso,
      });
    } else {
      studentSections.add({
        'id': _uid(),
        'student_id': studentId,
        'academic_year_id': currentYearId,
        'grade_level': grade,
        'section': room['name'],
        'from_date': dateStr(ago(120)),
        'to_date': active ? null : dateStr(ago(10)),
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
    }

    if (st.attachment) {
      studentAttachments.add({
        'id': studentId,
        '_png_student_id_photo': images.avatars[st.gender]![idx % avatarVariants],
        '_png_birth_certificate': images.doc,
        'created_at': dateTimeStr(ago(120)),
        'updated_at': nowIso,
      });
    }

    if (st.previousYear) {
      studentYears.add({
        'id': studentYearRecordId(studentId, previousYearId),
        'student_id': studentId,
        'academic_year_id': previousYearId,
        'grade_level': grade == 'عاشر' ? 'تاسع' : (grade == 'رابع' ? 'ثالث' : (grade == 'سابع' ? 'سادس' : 'رابع')),
        'section': 'شعبة (أ)',
        'status': 'completed',
        'created_at': '${y1 - 1}-09-01T08:00:00.000Z',
        'updated_at': '$y1-06-20T08:00:00.000Z',
      });
    }
  }

  // 9. سندات خاصة: ملغى، وعكس، ورد، وشيك، وإيرادات عامة
  final first = students.first;
  final last = students.last;
  String nameOf(Map<String, dynamic> s) => '${s['first_name']} ${s['last_name']}';
  payments.add({
    'id': _uid(),
    'receipt_number': '$year/${receiptNum++}',
    'student_id': first['id'],
    'amount': 150.0,
    'payment_method': 'cash',
    'payment_date': dateStr(ago(15)),
    'received_by_user_id': secretary['id'],
    'received_by_name': secretary['name'],
    'student_name': nameOf(first),
    'payment_purpose': 'monthly_fee',
    'is_cancelled': true,
    'cancelled_reason': 'صدر السند مرتين بطريق الخطأ في المحاسبة',
    'notes': 'سند ملغى - نموذج لاختبار استبعاده من إجمالي الخزينة',
    'academic_year_id': currentYearId,
    'created_at': dateTimeStr(ago(15)),
    'updated_at': nowIso,
  });
  final origId = _uid(), reversalId = _uid();
  final origReceipt = '$year/${receiptNum++}';
  payments.add({
    'id': origId,
    'receipt_number': origReceipt,
    'student_id': first['id'],
    'amount': 120.0,
    'payment_method': 'cash',
    'payment_date': dateStr(ago(22)),
    'received_by_user_id': secretary['id'],
    'received_by_name': secretary['name'],
    'student_name': nameOf(first),
    'payment_purpose': 'monthly_fee',
    'reversed_by_payment_id': reversalId,
    'notes': 'سند قبض تم عكسه لاحقاً بسبب إيداع خاطئ',
    'academic_year_id': currentYearId,
    'created_at': dateTimeStr(ago(22)),
    'updated_at': nowIso,
  });
  payments.add({
    'id': reversalId,
    'receipt_number': '$year/${receiptNum++}',
    'student_id': first['id'],
    'amount': -120.0,
    'payment_method': 'cash',
    'payment_date': dateStr(ago(21)),
    'received_by_user_id': accountant['id'],
    'received_by_name': accountant['name'],
    'student_name': nameOf(first),
    'payment_purpose': 'reversal',
    'reverses_payment_id': origId,
    'notes': 'عكس السند $origReceipt — إيداع خاطئ',
    'academic_year_id': currentYearId,
    'created_at': dateTimeStr(ago(21)),
    'updated_at': nowIso,
  });
  final withdrawn = students.where((s) => s['status'] == 'withdrawn').firstOrNull ?? students[3];
  // لا يُرد أكثر مما دفعه الطالب
  final withdrawnPaid = payments
      .where((p) => p['student_id'] == withdrawn['id'] && p['is_cancelled'] != true)
      .fold<double>(0, (n, p) => n + (p['amount'] as num).toDouble());
  final refund = math.min(100.0, withdrawnPaid);
  if (refund > 0) {
    payments.add({
      'id': _uid(),
      'receipt_number': '$year/${receiptNum++}',
      'student_id': withdrawn['id'],
      'amount': -refund,
      'payment_method': 'cash',
      'payment_date': dateStr(ago(10)),
      'received_by_user_id': accountant['id'],
      'received_by_name': accountant['name'],
      'student_name': nameOf(withdrawn),
      'payment_purpose': 'refund',
      'notes': 'رد مبلغ نقدي لولي الأمر بعد تسوية حساب الانسحاب',
      'academic_year_id': currentYearId,
      'created_at': dateTimeStr(ago(10)),
      'updated_at': nowIso,
    });
  }
  payments.add({
    'id': _uid(),
    'receipt_number': '$year/${receiptNum++}',
    'student_id': last['id'],
    'amount': 300.0,
    'payment_method': 'arabbank',
    'payment_date': dateStr(ago(8)),
    'received_by_user_id': accountant['id'],
    'received_by_name': accountant['name'],
    'student_name': nameOf(last),
    'payment_purpose': 'monthly_fee',
    'reference_number': 'CHK-894102',
    'transfer_channel': 'البنك العربي',
    'sender_name': 'والد الطالب',
    'notes': 'شيك مؤجل الاستحقاق رقم 894102 مسحوب على البنك العربي',
    'academic_year_id': currentYearId,
    'created_at': dateTimeStr(ago(8)),
    'updated_at': nowIso,
  });
  const generalIncomes = [
    ('بيع الزي المدرسي والكتب المعتمدة', 1250.0, 'بيع', 'أولياء أمور الطلاب'),
    ('إيجار مقصف وكافتيريا المدرسة - الدفعة الثانية', 1800.0, 'إيجار', 'متعهد المقصف المدرسي'),
    ('اشتراك باص ونقل مدرسي - رسوم الأنشطة', 650.0, 'نشاطات', 'مشتركو الباص المدرسي'),
  ];
  for (var i = 0; i < generalIncomes.length; i++) {
    final gi = generalIncomes[i];
    payments.add({
      'id': _uid(),
      'receipt_number': '$year/${receiptNum++}',
      'amount': gi.$2,
      'payment_method': 'cash',
      'payment_date': dateStr(ago(20 - i * 5)),
      'received_by_user_id': accountant['id'],
      'received_by_name': accountant['name'],
      'payment_purpose': 'other_income',
      'payer_name': gi.$4,
      'income_category': gi.$3,
      'notes': gi.$1,
      'academic_year_id': currentYearId,
      'created_at': dateTimeStr(ago(20 - i * 5)),
      'updated_at': nowIso,
    });
  }

  // المسدَّد وحالة كل قسط ورصيد الطالب كما يشتقها التطبيق من السندات — `deriveLedger`
  for (final st in students) {
    final ownRows = installments.where((i) => i['student_id'] == st['id']).toList();
    final own = [for (final r in ownRows) Installment.fromCloud(r)];
    final ownPayments = [
      for (final p in payments)
        if (p['student_id'] == st['id']) Payment.fromCloud(p),
    ];
    final paid = allocatePaymentsToInstallments(own, ownPayments);
    for (var i = 0; i < own.length; i++) {
      final p = paid[own[i].id] ?? 0;
      ownRows[i]['paid_amount'] = p;
      ownRows[i]['status'] = installmentStatusFor(chargeableAmount(own[i]), p);
    }
    st['balance'] = balanceFrom(installments: own, payments: ownPayments);
  }

  // 10. الرقابة المالية: طلبات معلقة تُنفَّذ فعلاً عند الموافقة، وسجل الحركات
  double num0(Object? v) => v is num ? v.toDouble() : 0;
  final openInstallment = installments
          .where((i) => i['student_id'] == students[3]['id'] && i['status'] != 'paid' && num0(i['amount']) - num0(i['paid_amount']) > 50)
          .firstOrNull ??
      installments.where((i) => i['status'] != 'paid' && num0(i['amount']) - num0(i['paid_amount']) > 50).firstOrNull;
  final cancelTarget = payments
          .where((p) => p['student_id'] == students[2]['id'] && num0(p['amount']) > 0 && p['is_cancelled'] != true)
          .firstOrNull ??
      payments.where((p) => p['student_id'] != null && num0(p['amount']) > 0 && p['is_cancelled'] != true).firstOrNull ??
      payments.first;
  final cancelStudent = students.where((s) => s['id'] == cancelTarget['student_id']).firstOrNull ?? students[2];
  const discountReason = 'شقيقها أحمد مسجل في الصف الرابع';
  const hardshipReason = 'الأسرة تمر بظرف إنساني حرج ومستحقة للدعم';
  final financeRequests = <Map<String, dynamic>>[
    {
      'id': _uid(),
      'kind': 'student_discount',
      'status': 'pending',
      'summary': 'طلب خصم إخوة 20% للطالبة ${nameOf(students[1])}',
      'student_id': students[1]['id'],
      'student_name': nameOf(students[1]),
      'amount': 40.0,
      'reason': discountReason,
      'requested_by_id': secretary['id'],
      'requested_by_name': secretary['name'],
      'payload': {
        'discount': {'type': 'percentage', 'value': 20, 'reason': discountReason},
      },
      'created_at': dateTimeStr(ago(2)),
      'updated_at': nowIso,
    },
    {
      'id': _uid(),
      'kind': 'installment_discount',
      'status': 'pending',
      'summary': 'طلب إعفاء من غرامة تأخير ورسوم المقعد لظرف اجتماعي',
      'student_id': students[3]['id'],
      'student_name': nameOf(students[3]),
      'target_id': openInstallment?['id'],
      'amount': 50.0,
      'reason': hardshipReason,
      'requested_by_id': accountant['id'],
      'requested_by_name': accountant['name'],
      'payload': {
        'input': {'kind': 'amount', 'amount': 50, 'reason': hardshipReason},
      },
      'created_at': dateTimeStr(ago(1)),
      'updated_at': nowIso,
    },
    {
      'id': _uid(),
      'kind': 'payment_cancel',
      'status': 'pending',
      'summary': 'طلب إلغاء سند قبض صادر بمبلغ مكرر',
      'student_id': cancelStudent['id'],
      'student_name': nameOf(cancelStudent),
      'target_id': cancelTarget['id'],
      'amount': num0(cancelTarget['amount']),
      'reason': 'أدخل الموظف السند مرتين بنظام المحاسبة',
      'requested_by_id': secretary['id'],
      'requested_by_name': secretary['name'],
      'payload': <String, dynamic>{},
      'created_at': dateTimeStr(0, 10, 0),
      'updated_at': nowIso,
    },
  ];
  final auditLog = <Map<String, dynamic>>[
    {
      'id': _uid(),
      'action': 'request_submitted',
      'summary': 'إرسال طلب خصم إخوة للمدير',
      'student_id': students[1]['id'],
      'student_name': nameOf(students[1]),
      'user_id': secretary['id'],
      'user_name': secretary['name'],
      'created_at': dateTimeStr(ago(2)),
      'updated_at': nowIso,
    },
    {
      'id': _uid(),
      'action': 'request_submitted',
      'summary': 'إرسال طلب إعفاء مقعد للمدير',
      'student_id': students[3]['id'],
      'student_name': nameOf(students[3]),
      'user_id': accountant['id'],
      'user_name': accountant['name'],
      'created_at': dateTimeStr(ago(1)),
      'updated_at': nowIso,
    },
  ];

  // 11. الحضور: معلم بديل وحصة ملغاة. ما قبل بداية العام يُسقط
  final sessions = <Map<String, dynamic>>[];
  final attendance = <Map<String, dynamic>>[];
  final offsets = [-13, -12, -11, -10, -9, -8, -6, -5, -4, -3, -2, -1].where((d) => d >= -daysSinceStart);
  for (final d in offsets) {
    final day = dateStr(d);
    for (var ri = 0; ri < rooms.length; ri++) {
      final room = rooms[ri];
      final sessionId = 'ses_room_${room['id']}_$day';
      var status = 'completed';
      String? substitute;
      var notes = 'دوام مدرسي رسمي وحصص صباحية';
      if (ri == 0 && d == -3) {
        status = 'substituted';
        substitute = tIsa['id'] as String;
        notes = 'حصة رياضيات بإشراف أ. عيسى النمس كمعلم بديل لغياب أ. الزهار';
      }
      if (d == -8 && ri == 7) {
        status = 'cancelled';
        notes = 'تعليق دوام الروضة والتمهيدي بسبب الأحوال الجوية العاصفة';
      }
      sessions.add({
        'id': sessionId,
        'room_id': room['id'],
        'teacher_id': room['homeroom_teacher_id'] ?? teachers.first['id'],
        'substitute_teacher_id': substitute,
        'session_date': day,
        'start_time': '08:00',
        'end_time': '13:00',
        'status': status,
        'notes': notes,
        'created_at': dateTimeStr(d),
        'updated_at': nowIso,
      });
      if (status == 'cancelled') continue;
      // المنسحب والمؤرشف والمنهي يغادرون قبل عشرة أيام
      final roomStudents = students
          .where((s) =>
              s['section'] == room['name'] &&
              s['grade_level'] == room['grade_level'] &&
              (d < -10 || !const ['withdrawn', 'archived', 'completed'].contains(s['status'])))
          .toList();
      for (var si = 0; si < roomStudents.length; si++) {
        final s = roomStudents[si];
        var mark = 'present';
        String? note;
        if (ri == 8) {
          if (s['first_name'] == 'جنى' && const [-1, -4, -9].contains(d)) {
            mark = 'absent';
            note = 'غياب بلا عذر';
          } else if (s['first_name'] == 'سيف' && const [-1, -6].contains(d)) {
            mark = 'excused';
            note = 'إذن مراجعة طبيب';
          }
        } else if (si == 3 && (d == -3 || d == -10)) {
          mark = 'excused';
          note = 'تقرير طبي - مراجعة مستشفى';
        } else if (si == 3 && d == -2) {
          mark = 'absent';
          note = 'غياب غير مبرر';
        } else if (si == 2 && d == -5) {
          note = 'تأخر 20 دقيقة عن الطابور الصباحي';
        } else if (si == 5 && d == -1) {
          mark = 'excused';
          note = 'ظرف عائلي مع إشعار مسبق من ولي الأمر';
        }
        attendance.add({
          'id': _uid(),
          'session_id': sessionId,
          'student_id': s['id'],
          'status': mark,
          'notes': note,
          'marked_by_user_id': principal['id'],
          'created_at': dateTimeStr(d),
          'updated_at': nowIso,
        });
      }
    }
  }

  // 12. العلامات بأنواعها الخمسة
  final evaluations = <Map<String, dynamic>>[];
  Map<String, dynamic> evaluation(Map<String, dynamic> g, Object? studentId, String title, double score, double max, String date,
          String type, String? term, String? component, String? notes, String created) =>
      {
        'id': _uid(),
        'student_id': studentId,
        'group_id': g['id'],
        'subject_id': g['subject_id'],
        'teacher_id': g['teacher_id'],
        'title': title,
        'score': score,
        'max_score': max,
        'evaluation_date': date,
        'type': type,
        if (term != null) 'term': term,
        if (component != null) 'component_id': component,
        if (notes != null) 'notes': notes,
        'created_at': created,
        'updated_at': nowIso,
      };
  for (var gi = 0; gi < groups.length; gi++) {
    final g = groups[gi];
    final enrolled = enrollments.where((e) => e['group_id'] == g['id']).toList();
    for (var si = 0; si < enrolled.length; si++) {
      final score = math.min(20, 13 + ((si * 4 + gi * 3) % 8)).toDouble();
      evaluations.add(evaluation(g, enrolled[si]['student_id'], 'اختبار قصير (1)', score, 20, dateStr(ago(25)), 'quiz', 'term_1',
          'default_quizzes', score >= 18 ? 'ممتاز' : (score >= 14 ? 'جيد جداً' : 'يحتاج متابعة'), dateTimeStr(ago(25))));
    }
    for (var si = 0; si < enrolled.length; si++) {
      // الرابع في كل مجموعة ضعيف: «راسب» يُرى في الشهادة
      final score = (si == 3 ? 38 : math.min(100, 65 + ((si * 7 + gi * 5) % 34))).toDouble();
      evaluations.add(evaluation(g, enrolled[si]['student_id'], 'امتحان الشهر الأول الموحد', score, 100, dateStr(ago(12)), 'monthly',
          'term_1', 'default_monthly', score >= 90 ? 'أداء متفوق' : (score < 60 ? 'تنبيه أكاديمي لولي الأمر' : null), dateTimeStr(ago(12))));
    }
    for (var si = 0; si < enrolled.length; si++) {
      final score = (si == 3 ? 6 : (si == 0 ? 10 : 9)).toDouble();
      evaluations.add(evaluation(g, enrolled[si]['student_id'], 'الواجبات والمشاركة الصفية اليومية', score, 10, dateStr(ago(4)), 'activity',
          'term_1', 'default_participation', null, dateTimeStr(ago(4))));
    }
    for (var si = 0; si < enrolled.length; si++) {
      final score = (si == 3 ? 41 : math.min(100, 60 + ((si * 6 + gi * 4) % 38))).toDouble();
      evaluations.add(evaluation(g, enrolled[si]['student_id'], 'امتحان نهاية الفصل الأول', score, 100, dateStr(ago(1)), 'final', 'term_1',
          'default_final', score >= 90 ? 'أداء متفوق' : (score < 50 ? 'رسوب - يحتاج دوراً استدراكياً' : null), dateTimeStr(ago(1))));
    }
    for (var si = 0; si < enrolled.length; si++) {
      final score = (si == 3 ? 5 : (si % 5 == 0 ? 10 : 9)).toDouble();
      evaluations.add(evaluation(g, enrolled[si]['student_id'], 'تقييم السلوك والمواظبة الفصلي', score, 10, dateStr(ago(2)), 'behavior',
          'term_1', null, score <= 6 ? 'تنبيه سلوكي وتواصل مع ولي الأمر' : null, dateTimeStr(ago(2))));
    }
  }

  // الفصل الثاني للسابع إن بدأ فعلاً: لا علامة بتاريخ بعد اليوم
  final todayStr = dateStr(0);
  if (todayStr.compareTo('${y1 + 1}-01-15') >= 0) {
    String term2Date(int day) {
      final d = '${y1 + 1}-02-${_two(day)}';
      return d.compareTo(todayStr) < 0 ? d : todayStr;
    }

    final seventh = groups.where((g) => g['grade_level'] == 'سابع').toList();
    for (var gi = 0; gi < seventh.length; gi++) {
      final g = seventh[gi];
      final enrolled = enrollments.where((e) => e['group_id'] == g['id']).toList();
      for (var si = 0; si < enrolled.length; si++) {
        final weak = si == 3;
        final rows = <(String, String, String, double, double, int)>[
          ('default_participation', 'activity', 'الواجبات والمشاركة (الفصل الثاني)', 10, (weak ? 5 : 8 + ((si + gi) % 3)).toDouble(), 5),
          ('default_quizzes', 'quiz', 'اختبار قصير (الفصل الثاني)', 20, (weak ? 8 : 14 + ((si * 3 + gi) % 7)).toDouble(), 12),
          ('default_monthly', 'monthly', 'امتحان شهر شباط', 100, (weak ? 35 : 70 + ((si * 5 + gi * 3) % 29)).toDouble(), 24),
        ];
        for (final r in rows) {
          final date = term2Date(r.$6);
          evaluations.add(evaluation(g, enrolled[si]['student_id'], r.$3, r.$5, r.$4, date, r.$2, 'term_2', r.$1, null, '${date}T08:00:00.000Z'));
        }
      }
    }
  }

  // المعدل الشهري العام بلا مادة: العشرة الأوائل والسابع كله، وريم أعلاهم
  final averaged = [...students.take(10), ...students.where((s) => s['grade_level'] == 'سابع')];
  for (var i = 0; i < averaged.length; i++) {
    final s = averaged[i];
    evaluations.add({
      'id': _uid(),
      'student_id': s['id'],
      'title': 'المعدل العام للشهر الأول',
      'score': (s['first_name'] == 'ريم' && s['grade_level'] == 'سابع' ? 96 : 85 + (i % 12)).toDouble(),
      'max_score': 100.0,
      'evaluation_date': dateStr(ago(10)),
      'type': 'monthly',
      'notes': 'المعدل التراكمي الشامل للشهر الأول',
      'created_at': dateTimeStr(ago(10)),
      'updated_at': nowIso,
    });
  }

  // 13. المصروفات العشر
  const expenseDefs = [
    ('إيجار المبنى المدرسي - الدفعة الشهرية', 3500.0, 'إيجار وتشغيل', 'cash', 'دفعة نقدية لمالك العقار'),
    ('فاتورة الكهرباء والمياه للمرافق المدرسية', 1200.0, 'مرافق وخدمات', 'cash', 'سداد نقدي لشركة الكهرباء'),
    ('اشتراك الإنترنت والاتصالات والدعم الفني', 450.0, 'اتصالات وإنترنت', 'cash', 'اشتراك شهري خط حضارة فايبر'),
    ('قرطاسية وأوراق طباعة امتحانات ومستلزمات', 850.0, 'قرطاسية ومطبوعات', 'cash', 'أوراق A4 وأحبار طابعات'),
    ('صيانة دورية للمكيفات وتمديدات الكهرباء', 600.0, 'صيانة وترميم', 'cash', 'صيانة مكيفات الصفوف والمختبر'),
    ('أدوات نظافة وتعقيم للمرافق المدرسية', 350.0, 'نظافة ومستهلكات', 'cash', 'منظفات ومطهرات ومعقمات'),
    ('ضيافة لاجتماع أولياء الأمور الدوري', 280.0, 'ضيافة واستقبال', 'cash', 'قهوة وشاي ومخبوزات للاجتماع'),
    ('مستلزمات مختبر العلوم والمواد الكيميائية', 750.0, 'مستلزمات تعليمية', 'bop', 'حوالة من بنك فلسطين للمورّد'),
    ('صيانة أجهزة الحاسوب وشبكة المدرسة الداخلية', 500.0, 'صيانة وترميم', 'cash', 'صيانة سيرفر المدرسة وراوترات الواي فاي'),
    ('وقود وصيانة دورية لباص المدرسة', 900.0, 'نقل ومواصلات', 'cash', 'سولار وتغيير زيت للباص'),
  ];
  final expenses = [
    for (var i = 0; i < expenseDefs.length; i++)
      <String, dynamic>{
        'id': _uid(),
        'description': expenseDefs[i].$1,
        'amount': expenseDefs[i].$2,
        'expense_date': dateStr(ago(28 - i * 2)),
        'category': expenseDefs[i].$3,
        'payment_method': expenseDefs[i].$4,
        'recorded_by_user_id': accountant['id'],
        'recorded_by_name': accountant['name'],
        'notes': expenseDefs[i].$5,
        'created_at': dateTimeStr(ago(28 - i * 2)),
        'updated_at': nowIso,
      },
  ];

  // 14. الرواتب عن الشهر الماضي (لا قبل شهر بداية العام)، والسلفة في الشهر الحالي
  String monthKey(DateTime d) => '${d.year}-${_two(d.month)}';
  final currentMonth = monthKey(today);
  final previousMonth = monthKey(DateTime(today.year, today.month - 1, 1));
  final firstMonth = monthKey(yearStartDay);
  final salaryMonth = previousMonth.compareTo(firstMonth) > 0 ? previousMonth : firstMonth;
  final teacherPayouts = <Map<String, dynamic>>[
    for (var i = 0; i < teachers.length; i++)
      {
        'id': _uid(),
        'teacher_id': teachers[i]['id'],
        'teacher_name': teachers[i]['name'],
        'amount': teachers[i]['payment_rate'] ?? 3000.0,
        'payout_type': 'salary',
        'period_start': '$salaryMonth-01',
        'period_end': monthEnd(salaryMonth),
        'payment_date': dateStr(ago(3 - (i % 3))),
        'paid_by_user_id': accountant['id'],
        'paid_by_name': accountant['name'],
        'payment_method': i == 0 ? 'bop' : 'cash',
        'notes': 'راتب شهر ${monthLabel(salaryMonth)}',
        'created_at': dateTimeStr(ago(3)),
        'updated_at': nowIso,
      },
    {
      'id': _uid(),
      'teacher_id': tMarwan['id'],
      'teacher_name': tMarwan['name'],
      'amount': 500.0,
      'payout_type': 'advance',
      'period_start': '$currentMonth-01',
      'period_end': monthEnd(currentMonth),
      'payment_date': dateStr(0),
      'paid_by_user_id': accountant['id'],
      'paid_by_name': accountant['name'],
      'payment_method': 'cash',
      'notes': 'سلفة نقدية على حساب الراتب بناءً على طلب المعلم',
      'created_at': dateTimeStr(0, 11, 0),
      'updated_at': nowIso,
    },
    {
      'id': _uid(),
      'teacher_id': tReem['id'],
      'teacher_name': tReem['name'],
      'amount': 300.0,
      'payout_type': 'bonus',
      'period_start': '$salaryMonth-01',
      'period_end': monthEnd(salaryMonth),
      'payment_date': dateStr(ago(6)),
      'paid_by_user_id': principal['id'],
      'paid_by_name': principal['name'],
      'payment_method': 'cash',
      'notes': 'مكافأة تميز لمتابعتها الدؤوبة لطلاب رياض الأطفال',
      'created_at': dateTimeStr(ago(6)),
      'updated_at': nowIso,
    },
  ];

  // 14ب. دفعات أولياء الأمور: طلبان معلقان وآخر مرفوض
  final reem = students.where((s) => s['first_name'] == 'ريم' && s['grade_level'] == 'سابع').firstOrNull ?? students.first;
  final sayf = students.where((s) => s['first_name'] == 'سيف' && s['grade_level'] == 'سابع').firstOrNull ?? students[3];
  final requestDefs = [
    (reem, 450.0, 'سامي عودة', 'بنك فلسطين', 'bop', 'TRX-PAL-840213', 'pending', 0, 'القسط الثالث'),
    (sayf, 300.0, 'نبيل عاشور', 'محفظة جوال باي', 'jawwal_pay', 'JP-552917', 'pending', 1, 'دفعة من القسط الثاني'),
    (students[3], 200.0, 'والد الطالبة', 'البنك العربي', 'arabbank', 'AB-110274', 'rejected', 3, null),
  ];
  final paymentRequests = <Map<String, dynamic>>[];
  for (final r in requestDefs) {
    final id = _uid();
    final rejected = r.$7 == 'rejected';
    paymentRequests.add({
      'id': id,
      'student_id': r.$1['id'],
      'student_name': nameOf(r.$1),
      'amount': r.$2,
      'sender_name': r.$3,
      'payment_method': r.$5,
      'transfer_channel': r.$4,
      'transfer_date': dateStr(ago(r.$8)),
      'reference_number': r.$6,
      'notes': r.$9,
      'image_paths': tenantId == null ? <String>[] : ['$tenantId/${r.$1['id']}/$id-1.png'],
      'status': r.$7,
      if (rejected) 'rejection_reason': 'صورة الإشعار غير واضحة، أعد إرسالها بصورة أوضح',
      if (rejected) 'decided_by_id': accountant['id'],
      if (rejected) 'decided_by_name': accountant['name'],
      if (rejected) 'decided_at': dateTimeStr(ago(r.$8), 14, 0),
      'created_at': dateTimeStr(ago(r.$8), 9, 30),
      'updated_at': nowIso,
    });
  }

  // 17. محتوى المودل: وحدة ظاهرة (ملف ورابط) ووحدة مخفية (واجب وملاحظة) لكل مادة
  final moodleSections = <Map<String, dynamic>>[];
  final moodleItems = <Map<String, dynamic>>[];
  if (tenantId != null && groups.isNotEmpty) {
    const placeholders = [
      'https://images.unsplash.com/photo-1635070041078-e363dbe005cb?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1509228468518-180dd4864904?w=800&auto=format&fit=crop&q=80',
      'https://images.unsplash.com/photo-1532094349884-543bc11b234d?w=800&auto=format&fit=crop&q=80',
    ];
    final subjectPlans = <(Map<String, dynamic>, List<_Unit>)>[
      (subjMath, _mathUnits),
      (subjArab, _arabUnits),
      (subjEng, _engUnits),
      (subjSci, _sciUnits),
      (subjPhy, _phyUnits),
      (subjIsl, _islUnits),
      (subjTech, _techUnits),
      (subjArt, _artUnits),
    ];
    for (var si = 0; si < subjectPlans.length; si++) {
      final (subject, units) = subjectPlans[si];
      // مجموعة أولى للمادة، ومجموعتها في السابع (أ) إن وُجدت
      final reps = <Map<String, dynamic>>[];
      for (final g in [
        groups.where((g) => g['subject_id'] == subject['id']).firstOrNull,
        groups.where((g) => g['subject_id'] == subject['id'] && g['grade_level'] == 'سابع').firstOrNull,
      ]) {
        if (g != null && !reps.contains(g)) reps.add(g);
      }
      for (final rep in reps) {
        for (var ui = 0; ui < units.length; ui++) {
          final unit = units[ui];
          final sectionId = _uid();
          moodleSections.add({
            'id': sectionId,
            'tenant_id': tenantId,
            'group_id': rep['id'],
            'term': 'term_1',
            'title': unit.title,
            'sort_order': ui + 1,
            'is_visible': unit.visible,
            'created_at': dateTimeStr(ago(10 - si), 8 + ui, 0),
          });
          for (var ii = 0; ii < unit.items.length; ii++) {
            final item = unit.items[ii];
            moodleItems.add({
              'id': _uid(),
              'tenant_id': tenantId,
              'section_id': sectionId,
              'group_id': rep['id'],
              'title': item.title,
              'type': item.type,
              'description': item.description,
              'sort_order': ii + 1,
              'created_at': dateTimeStr(ago(10 - si), 8 + ui, 30 + ii * 15),
              if (item.type == 'file') 'content_url': placeholders[(si + ui + ii) % placeholders.length],
              if (item.type == 'file') 'file_name': item.extra,
              if (item.type == 'file') 'file_size': 380000 + ((si * 7 + ui * 3 + ii) % 6) * 25000,
              if (item.type == 'link') 'content_url': item.extra,
              if (item.type == 'assignment' && item.due != null) 'due_date': dateStr(item.due!),
            });
          }
        }
      }
    }
  }

  final top = students.first;
  final overdue = students[3];
  final siblings = students.firstWhere((s) => s['last_name'] == 'خضير');
  return DemoDataset(
    rows: {
      'academic_years': academicYears,
      'users': users,
      'grade_fees': gradeFees,
      'subjects': subjects,
      'teachers': teachers,
      'rooms': rooms,
      'groups': groups,
      'students': students,
      'enrollments': enrollments,
      'installments': installments,
      'payments': payments,
      'finance_attachments': financeAttachments,
      'student_attachments': studentAttachments,
      'student_years': studentYears,
      'student_sections': studentSections,
      'sessions': sessions,
      'attendance': attendance,
      'student_evaluations': evaluations,
      'expenses': expenses,
      'teacher_payouts': teacherPayouts,
      'finance_requests': financeRequests,
      'audit_log': auditLog,
      'payment_requests': paymentRequests,
    },
    currentAcademicYearId: currentYearId,
    principal: principal,
    seatFee: seatFee,
    transferImage: images.transfer,
    moodleSections: moodleSections,
    moodleItems: moodleItems,
    logins: DemoLogins(
      teacher: (name: tZahar['name'] as String, nationalId: tZahar['national_id'] as String, portalCode: tZahar['portal_code'] as String),
      student: (
        name: nameOf(top),
        nationalId: top['national_id'] as String,
        portalCode: top['portal_code'] as String,
        parentPortalCode: top['parent_portal_code'] as String,
      ),
      overdue: (name: nameOf(overdue), nationalId: overdue['national_id'] as String, portalCode: overdue['portal_code'] as String),
      parent: (
        name: 'إبراهيم خضير (ولي أمر لطالبين)',
        nationalId: siblings['parent_national_id'] as String,
        parentPortalCode: siblings['parent_portal_code'] as String,
        children: const ['سارة خضير (الصف العاشر)', 'أحمد خضير (الصف الرابع)'],
      ),
    ),
  );
}

/// عنصر مودل: `extra` اسم الملف للملف، والرابط للرابط.
class _Item {
  const _Item(this.title, this.type, this.description, {this.extra, this.due});

  final String title;
  final String type;
  final String description;
  final String? extra;
  final int? due;
}

class _Unit {
  const _Unit(this.title, this.visible, this.items);

  final String title;
  final bool visible;
  final List<_Item> items;
}

const _mathUnits = [
  _Unit('الوحدة الأولى: الجبر والمعادلات التربيعية', true, [
    _Item('ورقة عمل تدريبية - حل المعادلات بالتحليل والقانون العام', 'file', 'تمارين تطبيقية على حل المعادلات التربيعية بالتحليل', extra: 'ورقة_عمل_المعادلات.pdf'),
    _Item('شرح فيديو توضيحي: طريقة إكمال المربع', 'link', 'شرح مرئي مفصل على يوتيوب لطريقة إكمال المربع وحل المسائل', extra: 'https://www.youtube.com/watch?v=demo_math'),
  ]),
  _Unit('الوحدة الثانية: الهندسة التحليلية وحساب المثلثات', false, [
    _Item('واجب منزلي: حساب المسافة بين نقطتين وميل المستقيم', 'assignment', 'حل خمس مسائل من كتاب الهندسة التحليلية', due: 5),
    _Item('ملاحظات: جدول النسب المثلثية للزوايا الخاصة', 'note', 'مرجع سريع لحفظ جيب وجيب تمام الزوايا 30 و45 و60'),
  ]),
];

const _arabUnits = [
  _Unit('الوحدة الأولى: القواعد النحوية والإعراب', true, [
    _Item('ملخص قواعد النحو - المرفوعات والمنصوبات', 'file', 'جدول شامل بعلامات الإعراب الأصلية والفرعية', extra: 'ملخص_قواعد_النحو.pdf'),
    _Item('شرح فيديو: إعراب الجملة الاسمية والفعلية', 'link', 'شرح مبسط بالأمثلة لإعراب أركان الجملتين', extra: 'https://www.youtube.com/watch?v=demo_arabic'),
  ]),
  _Unit('الوحدة الثانية: التعبير الكتابي والنصوص الأدبية', false, [
    _Item('واجب: كتابة موضوع تعبير عن الانتماء الوطني', 'assignment', 'موضوع تعبير لا يقل عن 15 سطراً بمقدمة وعرض وخاتمة', due: 4),
    _Item('ملاحظات: تحليل الصورة الفنية في النص الأدبي', 'note', 'خطوات تحليل الاستعارة والتشبيه في النصوص المقررة'),
  ]),
];

const _engUnits = [
  _Unit('Unit 1: Welcome to Our School Community', true, [
    _Item('Grammar Worksheet: Present Simple & Present Continuous', 'file', 'Practice exercises comparing the two tenses', extra: 'grammar_worksheet.pdf'),
    _Item('English Vocabulary Worksheet & Listening Audio', 'link', 'Listening comprehension practice and new unit vocabulary', extra: 'https://www.youtube.com/watch?v=demo_english'),
  ]),
  _Unit('Unit 2: Reading and Writing Skills', false, [
    _Item('Homework: Write a short paragraph about your school day', 'assignment', 'At least 6 sentences using present simple verbs', due: 5),
    _Item('Notes: Common spelling mistakes to avoid', 'note', 'A quick reference list of frequently misspelled words'),
  ]),
];

const _sciUnits = [
  _Unit('الوحدة الأولى: الكائنات الحية والبيئة الطبيعية', true, [
    _Item('نشاط استكشافي: السلاسل والشبكات الغذائية في بيئة فلسطين', 'file', 'ورقة نشاط تفاعلية لرسم وتحديد الكائنات المنتجة والمستهلكة', extra: 'نشاط_العلوم_السلاسل_الغذائية.pdf'),
    _Item('فيديو توضيحي: دورة حياة النبات والتلقيح', 'link', 'شرح مرئي لمراحل نمو النبات وأنواع التلقيح', extra: 'https://www.youtube.com/watch?v=demo_science'),
  ]),
  _Unit('الوحدة الثانية: النظام الشمسي والفضاء', false, [
    _Item('واجب: رسم مخطط لكواكب المجموعة الشمسية بالترتيب', 'assignment', 'رسم وتلوين الكواكب الثمانية مرتبة حسب بعدها عن الشمس', due: 6),
    _Item('ملاحظات: الفرق بين الكواكب الداخلية والخارجية', 'note', 'جدول مقارنة بالتركيب والحجم والمسافة'),
  ]),
];

const _phyUnits = [
  _Unit('الوحدة الأولى: قوانين نيوتن للحركة', true, [
    _Item('ملخص قوانين نيوتن الثلاثة مع أمثلة محلولة', 'file', 'شرح مبسط للقوانين الثلاثة مع تطبيقات عملية', extra: 'ملخص_قوانين_نيوتن.pdf'),
    _Item('شرح فيديو: تجربة عملية على قانون نيوتن الثاني', 'link', 'تجربة مخبرية توضح العلاقة بين القوة والكتلة والتسارع', extra: 'https://www.youtube.com/watch?v=demo_physics'),
  ]),
  _Unit('الوحدة الثانية: التفاعلات الكيميائية الأساسية', false, [
    _Item('واجب: موازنة عشر معادلات كيميائية', 'assignment', 'موازنة المعادلات المرفقة بالطريقة التجريبية', due: 5),
    _Item('ملاحظات: الفرق بين التفاعل الطارد والماص للحرارة', 'note', 'أمثلة من الحياة اليومية على كل نوع'),
  ]),
];

const _islUnits = [
  _Unit('الوحدة الأولى: تفسير وحفظ سورة الكهف', true, [
    _Item('ملخص تفسير آيات أصحاب الكهف والعبر المستفادة', 'file', 'شرح مبسط لقصة أصحاب الكهف والدروس المستخلصة', extra: 'ملخص_تفسير_الكهف.pdf'),
    _Item('تلاوة مجودة لسورة الكهف مع الشرح', 'link', 'تسجيل صوتي بالتجويد مع وقفات تدبر', extra: 'https://www.youtube.com/watch?v=demo_islamic'),
  ]),
  _Unit('الوحدة الثانية: أحكام الطهارة والصلاة', false, [
    _Item('واجب: تلخيص شروط وأركان الصلاة', 'assignment', 'جدول بشروط الصلاة وأركانها وواجباتها', due: 4),
    _Item('ملاحظات: نواقض الوضوء بالترتيب', 'note', 'قائمة مرجعية سريعة لنواقض الوضوء'),
  ]),
];

const _techUnits = [
  _Unit('الوحدة الأولى: أساسيات البرمجة بلغة بايثون', true, [
    _Item('ورقة عمل: المتغيرات وأنواع البيانات في بايثون', 'file', 'تمارين على تعريف المتغيرات والتعامل مع الأنواع الأساسية', extra: 'ورقة_عمل_بايثون.pdf'),
    _Item('شرح فيديو: كتابة أول برنامج بلغة بايثون', 'link', 'خطوات عملية لتثبيت بايثون وكتابة أول برنامج', extra: 'https://www.youtube.com/watch?v=demo_tech'),
  ]),
  _Unit('الوحدة الثانية: أمن المعلومات وحماية البيانات', false, [
    _Item('واجب: إنشاء كلمة مرور قوية وتفسير معايير الأمان', 'assignment', 'اقتراح ثلاث كلمات مرور قوية مع شرح معايير القوة', due: 5),
    _Item('ملاحظات: أخطاء شائعة تعرّض الحساب للاختراق', 'note', 'قائمة بأكثر الأخطاء شيوعاً وطرق تجنبها'),
  ]),
];

const _artUnits = [
  _Unit('الوحدة الأولى: فن الرسم بالألوان المائية', true, [
    _Item('ورقة عمل: أساسيات مزج الألوان الأساسية والثانوية', 'file', 'دائرة الألوان وطريقة الحصول على الألوان الثانوية', extra: 'ورقة_عمل_الألوان.pdf'),
    _Item('شرح فيديو: تقنيات التظليل بالألوان المائية', 'link', 'خطوات عملية للتدرج والتظليل بالفرشاة', extra: 'https://www.youtube.com/watch?v=demo_art'),
  ]),
  _Unit('الوحدة الثانية: الأنشطة الابتكارية والمشغولات اليدوية', false, [
    _Item('واجب: تنفيذ مجسم بسيط من الخامات البيئية المتاحة', 'assignment', 'إحضار مجسم من خامات معاد تدويرها وعرضه في الحصة القادمة', due: 7),
    _Item('ملاحظات: نصائح للحفاظ على أدوات الرسم والألوان', 'note', 'إرشادات تنظيف الفرش وتخزين الألوان'),
  ]),
];

/// الصورة كرابط `data:` لمن يحتفظ بها في الصف بدل رفعها (الحقن على الجهاز).
String pngDataUrl(List<int> bytes) => 'data:image/png;base64,${base64Encode(bytes)}';
