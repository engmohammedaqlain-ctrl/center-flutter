class CapabilityItem {
  const CapabilityItem(this.id, this.label, [this.hint]);
  final String id;
  final String label;
  final String? hint;
}

class CapabilityGroup {
  const CapabilityGroup(this.label, this.items);
  final String label;
  final List<CapabilityItem> items;
}

const capabilityGroups = [
  CapabilityGroup('الطلاب', [
    CapabilityItem('students.view', 'عرض الطلاب وملفاتهم'),
    CapabilityItem('students.edit', 'إضافة وتعديل بيانات الطلاب'),
    CapabilityItem('students.delete', 'حذف الطلاب', 'إجراء لا رجعة فيه'),
  ]),
  CapabilityGroup('الجداول والمجموعات', [
    CapabilityItem('schedule.view', 'عرض الجداول والمجموعات'),
    CapabilityItem('schedule.edit', 'إنشاء وتعديل المجموعات والتسجيل فيها'),
  ]),
  CapabilityGroup('الحضور', [
    CapabilityItem('attendance.view', 'عرض كشوف الحضور'),
    CapabilityItem('attendance.edit', 'رصد الحضور والغياب'),
  ]),
  CapabilityGroup('المالية', [
    CapabilityItem('finance.view', 'عرض المالية والذمم'),
    CapabilityItem('finance.collect', 'قبض الدفعات وإصدار السندات'),
    CapabilityItem('finance.cancel', 'إلغاء سند قبض', 'يعكس رصيد الطالب'),
    CapabilityItem('finance.expenses', 'إدارة المصروفات وصرف الأجور'),
  ]),
  CapabilityGroup('الإعدادات', [
    CapabilityItem('settings.view', 'المواد والمعلمين والقاعات'),
    CapabilityItem('settings.fees', 'الرسوم الدراسية'),
    CapabilityItem('settings.branding', 'الشعار والألوان واسم المنشأة'),
    CapabilityItem('settings.users', 'إدارة المستخدمين والصلاحيات', 'صلاحية إدارية'),
    CapabilityItem('settings.backup', 'النسخ الاحتياطي واستيراد البيانات', 'صلاحية إدارية'),
  ]),
  CapabilityGroup('المزامنة', [
    CapabilityItem('sync.pull', 'سحب البيانات من السحابة'),
    CapabilityItem('sync.push', 'رفع التعديلات إلى السحابة'),
  ]),
];

const allCapabilities = [
  'students.view', 'students.edit', 'students.delete',
  'schedule.view', 'schedule.edit',
  'attendance.view', 'attendance.edit',
  'finance.view', 'finance.collect', 'finance.cancel', 'finance.expenses',
  'settings.view', 'settings.fees', 'settings.users', 'settings.backup', 'settings.branding',
  'sync.push', 'sync.pull',
];

const receptionistCapabilities = [
  'students.view', 'students.edit',
  'schedule.view',
  'attendance.view', 'attendance.edit',
  'finance.view', 'finance.collect',
  'sync.push', 'sync.pull',
];

/// أسماء صلاحيات قديمة استُبدلت. الحساب المحفوظ بالاسم القديم لا يفقد حقه:
/// يُترجم إلى الاسم الجديد عند القراءة، ويُعاد كتابته مرة واحدة في المتجر.
const legacyCapabilityAliases = <String, String>{
  // «ورديات الصندوق» أُلغيت وحلّت محلّها «المصروفات وصرف الأجور»
  'finance.cashbox': 'finance.expenses',
};

/// ترقية قائمة صلاحيات من الأسماء القديمة إلى الحالية بلا تكرار.
List<String> upgradeCapabilities(List<String> caps) {
  final out = <String>[];
  for (final c in caps) {
    final next = legacyCapabilityAliases[c] ?? c;
    if (!out.contains(next)) out.add(next);
  }
  return out;
}

/// اسم الصلاحية كما يُعرض في شاشة المستخدمين — لرسائل الرفض.
String capabilityLabel(String cap) {
  for (final g in capabilityGroups) {
    for (final item in g.items) {
      if (item.id == cap) return item.label;
    }
  }
  return cap;
}

String normalizeRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  if (r == 'admin' || r == 'مدير' || r.contains('مدير')) return 'admin';
  return 'receptionist';
}

String roleLabel(String? role) => normalizeRole(role) == 'admin' ? 'مدير النظام' : 'سكرتير';

String roleDescription(String? role) => normalizeRole(role) == 'admin'
    ? 'صلاحية كاملة: المالية وإدارة المستخدمين والنسخ الاحتياطي.'
    : 'تسجيل الطلاب وقبض الدفعات ورصد الحضور والعمليات اليومية.';

List<String> defaultCapsFor(String role) {
  return normalizeRole(role) == 'admin' ? [...allCapabilities] : [...receptionistCapabilities];
}

/// الصلاحيات الفعلية للحساب: قائمته الخاصة، أو قالب دوره إن لم تُحدَّد بعد.
/// الحساب الذي لا يحمل قائمة (أُنشئ قبل الميزة) لا يفقد صلاحياته فجأة.
List<String> effectiveCapabilities(List<String> caps, String role) {
  if (caps.isNotEmpty) {
    return upgradeCapabilities(caps).where(allCapabilities.contains).toList();
  }
  return defaultCapsFor(role);
}

/// أقسام النظام وما تتطلبه من قدرات.
/// تُستعمل لإخفاء ما لا يخص المستخدم من التنقّل ولحماية الشاشات.
const sectionCapability = <String, String>{
  'students': 'students.view',
  'classes': 'schedule.view',
  'schedule': 'schedule.view',
  'attendance': 'attendance.view',
  'finance': 'finance.view',
  'settings': 'settings.view',
};

const sectionLabels = <String, String>{
  'students': 'الطلاب',
  'classes': 'الصفوف',
  'schedule': 'الجداول',
  'attendance': 'الحضور',
  'finance': 'المالية',
  'settings': 'الإعدادات',
};

/// علاقات الاعتماد بين الصلاحيات.
/// منح صلاحية تعديل بلا صلاحية عرض حالة متناقضة لا يستطيع المستخدم استعمالها.
const capabilityRequires = <String, List<String>>{
  'students.edit': ['students.view'],
  'students.delete': ['students.view'],
  'schedule.edit': ['schedule.view'],
  'attendance.edit': ['attendance.view'],
  'finance.collect': ['finance.view'],
  'finance.cancel': ['finance.view'],
  'finance.expenses': ['finance.view'],
  'settings.fees': ['settings.view'],
  'settings.users': ['settings.view'],
  'settings.backup': ['settings.view'],
  'settings.branding': ['settings.view'],
};

/// المعكوس: سحب صلاحية العرض يسحب ما يقوم عليها.
final capabilityDependents = () {
  final map = <String, List<String>>{};
  for (final entry in capabilityRequires.entries) {
    for (final required in entry.value) {
      map.putIfAbsent(required, () => []).add(entry.key);
    }
  }
  return Map<String, List<String>>.unmodifiable(map);
}();

/// تبديل صلاحية واحدة مع احترام الاعتماديات. دالة صرفة قابلة للاختبار.
List<String> toggleCapability(List<String> current, String cap) {
  final next = {...current};
  if (next.contains(cap)) {
    next.remove(cap);
    for (final d in capabilityDependents[cap] ?? const <String>[]) {
      next.remove(d);
    }
  } else {
    next.add(cap);
    for (final r in capabilityRequires[cap] ?? const <String>[]) {
      next.add(r);
    }
  }
  return next.toList();
}

/// تحديد أو إلغاء مجموعة صلاحيات دفعةً واحدة.
List<String> toggleCapabilityGroup(List<String> current, List<String> caps, bool turnOff) {
  final next = {...current};
  for (final cap in caps) {
    if (turnOff) {
      next.remove(cap);
      for (final d in capabilityDependents[cap] ?? const <String>[]) {
        next.remove(d);
      }
    } else {
      next.add(cap);
      for (final r in capabilityRequires[cap] ?? const <String>[]) {
        next.add(r);
      }
    }
  }
  return next.toList();
}
