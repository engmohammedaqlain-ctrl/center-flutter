/// نظام الصلاحيات = أي تبويبات النظام يراها هذا الحساب — مطابق لـ
/// `lib/permissions.ts`.
///
/// الوحدة تبويب لا «قدرة» مجرّدة: القائمة الطويلة السابقة كانت تعد بتفريق لا
/// تنفّذه النسخة المكتبية، فصار المعروض على المدير هو ما يطبَّق بالضبط.
/// الأدوار قوالب بداية، وللمدير تعديلها لكل حساب. والحساب الذي لا يحمل قائمة
/// خاصة (أُنشئ قبل الميزة) يرجع إلى قالب دوره.
library;

class SectionDef {
  const SectionDef(this.id, this.label, {this.hint, this.parent});

  final String id;
  final String label;
  final String? hint;

  /// تبويب داخل قسم آخر: لا يُتاح إلا بإتاحة أصله.
  final String? parent;
}

const accessSections = <SectionDef>[
  SectionDef('students', 'الطلاب'),
  SectionDef('classes', 'الصفوف والجداول'),
  SectionDef('attendance', 'الحضور والغياب'),
  SectionDef('evaluations', 'الدرجات والتقييمات'),
  SectionDef('moodle', 'المودل'),
  SectionDef('finance', 'المالية'),
  SectionDef('finance.expenses', 'المصروفات وصرف الأجور', hint: 'يكشف رواتب الموظفين', parent: 'finance'),
  SectionDef('settings', 'الإعدادات'),
  SectionDef('settings.users', 'المستخدمون والصلاحيات', hint: 'يمكّنه من منح الصلاحيات لغيره', parent: 'settings'),
  SectionDef('settings.backup', 'البيانات والنسخ الاحتياطي', hint: 'يشمل استيراد البيانات واستبدالها', parent: 'settings'),
];

final allSections = [for (final s in accessSections) s.id];

SectionDef? sectionDef(String id) {
  for (final s in accessSections) {
    if (s.id == id) return s;
  }
  return null;
}

/// اسم التبويب المعروض — لرسائل الرفض وشاشة «غير متاح».
String sectionLabel(String id) => sectionDef(resolveSection(id) ?? id)?.label ?? id;

/// مسار «الجداول» القديم يقابل تبويب «الصفوف»، وغير المعروف لا يُحرس.
String? resolveSection(String? id) {
  if (id == null || id.isEmpty) return null;
  if (id == 'schedule') return 'classes';
  return sectionDef(id) == null ? null : id;
}

class RoleDefinition {
  const RoleDefinition(this.id, this.label, this.description, this.sections);

  final String id;
  final String label;
  final String description;

  /// قالب البداية: ما يُعلَّم تلقائياً عند اختيار هذا الدور، وللمدير تعديله.
  final List<String> sections;
}

final roles = <String, RoleDefinition>{
  'admin': RoleDefinition('admin', 'مدير', 'كل التبويبات، وإدارة المستخدمين والنسخ الاحتياطي.', allSections),
  'accountant': const RoleDefinition(
    'accountant',
    'محاسب',
    'المالية بما فيها المصروفات، والطلاب والصفوف.',
    ['students', 'classes', 'finance', 'finance.expenses'],
  ),
  'receptionist': const RoleDefinition(
    'receptionist',
    'سكرتير',
    'المالية والطلاب والصفوف والحضور والغياب، دون المصروفات.',
    ['students', 'classes', 'attendance', 'finance'],
  ),
};

final roleList = [roles['admin']!, roles['accountant']!, roles['receptionist']!];

/// توحيد أي قيمة دور قديمة أو غير معروفة إلى دور معتمد. المجهول سكرتير لا مدير.
String normalizeRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  if (r == 'admin' || r.contains('مدير')) return 'admin';
  if (r == 'accountant' || r.contains('محاسب')) return 'accountant';
  return 'receptionist';
}

RoleDefinition roleDefinition(String? role) => roles[normalizeRole(role)]!;

String roleLabel(String? role) => roleDefinition(role).label;

/// ترجمة القوائم المحفوظة بصيغة القدرات القديمة إلى تبويبات.
///
/// عند القراءة لا بترحيل لمرة واحدة: أجهزة أخرى قد تُزامن حسابات ما زالت
/// بالصيغة القديمة، وبلا ترجمة يفقد الحساب كل تبويباته دفعةً واحدة.
const _legacyCapabilitySections = <String, List<String>>{
  'students.view': ['students'],
  'students.edit': ['students'],
  'students.delete': ['students'],
  // المودل كان محكوماً بصلاحية الجداول، والتقييمات بصلاحية الحضور
  'schedule.view': ['classes', 'moodle'],
  'schedule.edit': ['classes', 'moodle'],
  'attendance.view': ['attendance', 'evaluations'],
  'attendance.edit': ['attendance', 'evaluations'],
  'finance.view': ['finance'],
  'finance.collect': ['finance'],
  'finance.cancel': ['finance'],
  // «ورديات الصندوق» على الجوال أُلغيت قبل ذلك وحلّت محلها المصروفات
  'finance.cashbox': ['finance.expenses'],
  'settings.view': ['settings'],
  'settings.fees': ['settings'],
  'settings.branding': ['settings'],
};

/// تحويل قائمة محفوظة (قديمة أو جديدة) إلى تبويبات معروفة، بلا تكرار وبترتيب ثابت.
List<String> normalizeSections(Iterable<String> stored) {
  final out = <String>{};
  for (final entry in stored) {
    if (sectionDef(entry) != null) {
      out.add(entry);
      continue;
    }
    out.addAll(_legacyCapabilitySections[entry] ?? const []);
  }
  // تبويب فرعي لا يُوصل إليه إلا عبر أصله، فوجوده يستلزمه
  for (final s in accessSections) {
    if (s.parent != null && out.contains(s.id)) out.add(s.parent!);
  }
  return allSections.where(out.contains).toList();
}

/// التبويبات الفعلية للحساب: قائمته الخاصة، أو قالب دوره إن لم تُحدَّد بعد.
/// القائمة الفارغة الصريحة تعني لا شيء، لا رجوعاً إلى القالب.
List<String> effectiveSections(List<String>? stored, String? role) {
  if (stored != null) return normalizeSections(stored);
  return [...roleDefinition(role).sections];
}

bool roleCanAccess(String? role, String section) => roleDefinition(role).sections.contains(section);

/// تبديل تبويب واحد مع احترام علاقة الأصل بالفرع. دالة صرفة قابلة للاختبار.
List<String> toggleSection(List<String> current, String id) {
  final next = {...current};
  if (next.contains(id)) {
    next.remove(id);
    // إخفاء الأصل يخفي فروعه
    for (final child in accessSections) {
      if (child.parent == id) next.remove(child.id);
    }
  } else {
    next.add(id);
    final parent = sectionDef(id)?.parent;
    if (parent != null) next.add(parent);
  }
  return allSections.where(next.contains).toList();
}
