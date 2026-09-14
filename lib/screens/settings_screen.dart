import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/backup.dart';
import '../data/permissions.dart';
import '../data/phone.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'developer_settings_screen.dart';
import 'payment_methods_tab.dart';
import 'settings_forms.dart';
import 'grading_scheme_tab.dart';
import 'student_promotion_sheet.dart';

/// الإعدادات — المقابل لـ `pages/Settings.tsx`.
///
/// بتنسيق بقية الأقسام: شريط تبويبات بعرض الشاشة، ثم لكل تبويب بحث وعدد في سطر
/// واحد، وبطاقات مرتبة تُفتح للتعديل. زر الإضافة ثابت في متناول الإبهام ويتبع
/// التبويب، والنماذج صفحات كاملة بتخطيط نموذج الطالب. تسجيل الخروج في القائمة
/// السريعة (⋮) وحدها — لا يتكرر أسفل الإعدادات.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// تبويب في الإعدادات مع صلاحيته.
class _Tab {
  const _Tab(this.id, this.icon, this.label, {this.capability});

  final String id;
  final IconData icon;
  final String label;
  final String? capability;
}

class _SettingsScreenState extends State<SettingsScreen> {
  String current = 'teachers';

  /// التبويبات بترتيب Settings.tsx — تُخفى بحسب الصلاحية.
  static const _allTabs = [
    _Tab('grade_fees', Icons.payments_outlined, 'المراحل والرسوم', capability: 'settings.fees'),
    _Tab('payment_methods', Icons.credit_card_outlined, 'وسائل الدفع'),
    _Tab('teachers', Icons.school_outlined, 'المعلمون'),
    _Tab('subjects', Icons.menu_book_outlined, 'المواد'),
    _Tab('grading', Icons.workspace_premium_outlined, 'مخطط العلامات'),
    _Tab('users', Icons.manage_accounts_outlined, 'المستخدمون', capability: 'settings.users'),
    _Tab('backup', Icons.storage_outlined, 'البيانات والنسخ', capability: 'settings.backup'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('settings')) {
          return NoAccess(section: 'settings', roleName: store.roleName);
        }
        final tabs = _allTabs.where((t) {
          if (t.capability != null && !store.can(t.capability!)) return false;
          return true;
        }).toList();
        if (tabs.isEmpty) return NoAccess(section: 'settings', roleName: store.roleName);
        // من فقد صلاحية التبويب المفتوح يعود إلى أول تبويب مسموح
        final active = tabs.firstWhere((t) => t.id == current, orElse: () => tabs.first);

        return ThumbActionLayer(
          action: _actionFor(context, active.id),
          child: Column(
            children: [
              _tabBar(tabs, active.id),
              Expanded(
                child: switch (active.id) {
                  'grade_fees' => const _FeesTab(),
                  'payment_methods' => const PaymentMethodsTab(),
                  'subjects' => const _SubjectsTab(),
                  'grading' => const GradingSchemeTab(),
                  'users' => const _UsersTab(),
                  'backup' => const _DataTab(),
                  _ => const _TeachersTab(),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// زر الإضافة يتبع التبويب — تبويب البيانات بلا إضافة.
  ThumbAction? _actionFor(BuildContext context, String tab) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return switch (tab) {
      'grade_fees' => ThumbAction(label: 'مرحلة جديدة', icon: Icons.add, onPressed: () => open(const GradeFeeFormScreen())),
      'teachers' => ThumbAction(
          label: 'إضافة مدرس',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: () => open(const TeacherFormScreen()),
        ),
      'payment_methods' => ThumbAction(
          label: 'وسيلة دفع',
          icon: Icons.add,
          onPressed: () => addPaymentMethod(context),
        ),
      'subjects' => ThumbAction(label: 'إضافة مادة', icon: Icons.add, onPressed: () => open(const SubjectFormScreen())),
      'users' => ThumbAction(
          label: 'مستخدم جديد',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: () => open(const UserFormScreen()),
        ),
      _ => null,
    };
  }

  Widget _tabBar(List<_Tab> tabs, String active) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      // تمرير التبويبات أفقياً لا يُخفي زر الإضافة
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          children: [
            for (final t in tabs)
              InkWell(
                onTap: () => setState(() => current = t.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.id == active ? AppColors.accent : Colors.transparent, width: 2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 15, color: t.id == active ? AppColors.heading : AppColors.muted),
                      const SizedBox(width: 5),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: t.id == active ? AppColors.heading : AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══ عناصر مشتركة ═══════════════════════════════════════════════════════════

TextStyle get _titleStyle => TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading);

const _metaStyle = TextStyle(color: AppColors.muted, fontSize: 11);

void _open(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// خط رفيع يفصل رأس البطاقة عن تفاصيلها.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
    );
  }
}

/// البحث وعدد النتائج في سطر واحد أعلى القائمة.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.hint,
    required this.shown,
    required this.total,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final int shown;
  final int total;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SearchField(
        controller: controller,
        hint: hint,
        onChanged: onChanged,
        trailing: Text(
          shown == total ? '$total' : '$shown/$total',
          style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// قائمة بطاقات تُبنى على قدر ما يظهر، بأرقام اختيارية في رأسها.
Widget _cardList({
  List<Widget> header = const [],
  required int count,
  required Widget empty,
  required IndexedWidgetBuilder item,
}) {
  final offset = header.isEmpty ? 0 : 1;
  return ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, thumbActionClearance),
    itemCount: offset + (count == 0 ? 1 : count),
    itemBuilder: (context, i) {
      if (offset == 1 && i == 0) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header),
        );
      }
      if (count == 0) return SizedBox(height: 220, child: empty);
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: item(context, i - offset));
    },
  );
}

/// سهم «فتح» في طرف البطاقة — «التالي» ينعكس مع الاتجاه فيُرسم «<».
const _chevron = Icon(Icons.chevron_right, size: 18, color: AppColors.faint);

// ═══ الرسوم والمراحل (للمدارس) ══════════════════════════════════════════════

class _FeesTab extends StatelessWidget {
  const _FeesTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final fees = store.gradeFees;
    final missing = store.studentsMissingFee;
    return _cardList(
      header: [
        StatRow(
          children: [
            StatCard(label: 'المراحل الدراسية', value: '${fees.length}', color: AppColors.heading),
            StatCard(label: 'الشعب', value: '${store.rooms.length}', color: AppColors.heading),
          ],
        ),
        const SizedBox(height: 10),
        _SeatFeeCard(store: store),
        const SizedBox(height: 8),
        _StudyMonthsCard(store: store),
        if (missing > 0) ...[
          const SizedBox(height: 8),
          // من لا رسم لمرحلته لا يُولَّد له مستحق، فيبقى بلا مطالبة بصمت
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(Corner.box),
              border: Border.all(color: AppColors.dangerBorder),
            ),
            child: Text(
              'طلاب نشطون بلا رسم شهري معرّف: $missing',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.danger),
            ),
          ),
        ],
        const SizedBox(height: 8),
        GhostButton(
          label: 'ترقية الطلاب',
          icon: Icons.moving_outlined,
          onPressed: () => showStudentPromotionSheet(context, store),
        ),
      ],
      count: fees.length,
      empty: const EmptyState(message: 'لا توجد مراحل دراسية مسجلة.'),
      item: (context, i) => _GradeFeeCard(fee: fees[i]),
    );
  }
}

/// رسم حجز المقعد — المقابل لبطاقته في GradeFeesSettings.tsx.
///
/// يُدفع مرة واحدة ويُخصم من أول مستحق. صفرٌ يعني ألّا رسم حجز أصلاً.
class _SeatFeeCard extends StatefulWidget {
  const _SeatFeeCard({required this.store});

  final AppStore store;

  @override
  State<_SeatFeeCard> createState() => _SeatFeeCardState();
}

class _SeatFeeCardState extends State<_SeatFeeCard> {
  late final TextEditingController amount;
  late bool enabled;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    final fee = widget.store.seatReservationFee;
    enabled = fee > 0;
    amount = TextEditingController(text: fee > 0 ? trimNum(fee) : '');
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = widget.store;
    final value = enabled ? (double.tryParse(amount.text.trim()) ?? 0) : 0.0;
    await store.setSeatReservationFee(value < 0 ? 0 : value);
    if (!mounted) return;
    setState(() {
      saved = true;
      amount.text = value > 0 ? trimNum(value) : '';
    });
    showAppSnack(context, 'تم حفظ رسم حجز المقعد');
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'رسم حجز المقعد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
              ),
              if (saved)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Text('حُفظ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success)),
                ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: AppColors.amber,
                onChanged: (v) => setState(() {
                  enabled = v;
                  saved = false;
                }),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onChanged: (_) => setState(() => saved = false),
                    decoration: InputDecoration(hintText: '0 $currency'),
                  ),
                ),
                const SizedBox(width: 8),
                PrimaryButton(label: 'حفظ', color: AppColors.navy, onPressed: _save),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'بلا رسم حجز',
                      style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GhostButton(label: 'حفظ', onPressed: _save),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'يُدفع مرة واحدة ويُخصم من أول مستحق',
            style: TextStyle(fontSize: 10.5, color: AppColors.faint, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// أشهر الدراسة: الرسم الشهري يُستحق فيها وحدها.
class _StudyMonthsCard extends StatefulWidget {
  const _StudyMonthsCard({required this.store});

  final AppStore store;

  @override
  State<_StudyMonthsCard> createState() => _StudyMonthsCardState();
}

class _StudyMonthsCardState extends State<_StudyMonthsCard> {
  late Set<int> selected = {...?widget.store.studyMonths};

  Future<void> _save() async {
    final store = widget.store;
    await store.saveStudyMonths(selected.toList());
    // المستحق يُولَّد فور اعتماد الأشهر، كما تفعل النسخة المكتبية عند الحفظ
    final result = store.generateMonthlyDues();
    if (!mounted) return;
    showAppSnack(
      context,
      result.created > 0 ? 'حُفظت الأشهر، وأُنشئ ${result.created} مستحقاً' : 'حُفظت أشهر الدراسة',
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'أشهر الدراسة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                ),
              ),
              if (store.studyMonths == null)
                const Text(
                  'الرسوم الشهرية متوقفة',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.danger),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var m = 1; m <= 12; m++)
                _MonthChip(
                  label: gregorianMonths[m - 1],
                  on: selected.contains(m),
                  onTap: () => setState(() => selected.contains(m) ? selected.remove(m) : selected.add(m)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          PrimaryButton(label: 'حفظ أشهر الدراسة', color: AppColors.navy, onPressed: _save),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.heading : Colors.white,
          borderRadius: BorderRadius.circular(Corner.chip),
          border: Border.all(color: on ? AppColors.heading : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// مرحلة دراسية: الاسم ومرحلتها الكبرى وعدد طلابها مقابل الرسم الشهري، ثم خط
/// رفيع، ثم شعبها وزر إضافة شعبة، ثم التعديل والحذف.
class _GradeFeeCard extends StatelessWidget {
  const _GradeFeeCard({required this.fee});

  final GradeFee fee;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final f = fee;
    final sections = store.rooms.where((r) => r.gradeLevel == f.gradeName).toList();
    final students = store.students.where((s) => isSameGrade(s.gradeLevel, f.gradeName)).length;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f.gradeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                    const SizedBox(height: 2),
                    Text(
                      '${stageTierLabel(f.tier)}  ·  $students طالب',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(money(f.monthlyFee), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.heading)),
                  const Text('شهرياً', style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
                ],
              ),
            ],
          ),
          const _Rule(),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final r in sections) StatusChip.muted(r.name),
              TileButton(
                label: 'شعبة',
                icon: const Icon(Icons.add, size: 13),
                color: AppColors.amber,
                background: AppColors.amberSoft,
                border: AppColors.amberBorder,
                onTap: () => _addSection(context, f),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TileButton(
                label: 'تعديل',
                icon: const Icon(Icons.edit_outlined, size: 13),
                color: AppColors.heading,
                background: Colors.white,
                border: AppColors.lineStrong,
                onTap: () => _open(context, GradeFeeFormScreen(fee: f)),
              ),
              const SizedBox(width: 6),
              TileButton(
                label: 'حذف',
                icon: const Icon(Icons.delete_outline, size: 13),
                color: AppColors.danger,
                background: Colors.white,
                border: AppColors.dangerBorder,
                onTap: () => _deleteFee(context, f),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _deleteFee(BuildContext context, GradeFee f) async {
  final store = StoreScope.of(context);
  final ok = await confirmSheet(
    context,
    title: 'حذف المرحلة',
    message: 'هل أنت متأكد من حذف مرحلة «${f.gradeName}»؟',
    confirmLabel: 'حذف',
  );
  if (!ok || !context.mounted) return;
  try {
    store.deleteGradeFee(f);
    showAppSnack(context, 'تم حذف المرحلة');
  } on StoreException catch (e) {
    showAppSnack(context, e.message, error: true);
  }
}

/// إضافة شعبة لمرحلة — حقل واحد، فورقة قصيرة لا صفحة.
Future<void> _addSection(BuildContext context, GradeFee f) async {
  final store = StoreScope.of(context);
  final ctl = TextEditingController();
  final errors = FieldErrors();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إضافة شعبة لمرحلة: ${f.gradeName}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
              ),
              const SizedBox(height: 12),
              FieldLabel('اسم الشعبة', key: errors.key('name'), requiredField: true),
              TextField(
                controller: ctl,
                autofocus: true,
                onChanged: (_) {
                  if (errors.clear('name')) setSt(() {});
                },
                decoration: InputDecoration(hintText: 'مثال: الشعبة (ب)', errorText: errors['name']),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: 'حفظ الشعبة',
                      icon: Icons.check,
                      height: 44,
                      onPressed: () {
                        setSt(() {
                          errors
                            ..reset()
                            ..check('name', ctl.text.trim().isEmpty, 'يرجى إدخال اسم الشعبة');
                        });
                        if (errors.report(ctx)) return;
                        try {
                          store.upsertRoom(
                            Classroom(
                              id: store.newId(),
                              name: ctl.text.trim(),
                              gradeLevel: f.gradeName,
                              teacherId: '',
                              capacity: 25,
                              tier: f.tier,
                            ),
                          );
                          Navigator.pop(ctx);
                          showAppSnack(context, 'تمت إضافة الشعبة «${ctl.text.trim()}» إلى ${f.gradeName}');
                        } on StoreException catch (e) {
                          showAppSnack(ctx, e.message, error: true);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ═══ المدرسون ═══════════════════════════════════════════════════════════════

class _TeachersTab extends StatefulWidget {
  const _TeachersTab();

  @override
  State<_TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<_TeachersTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = search.text.trim();
    final list = store.teachers.where((t) {
      if (q.isEmpty) return true;
      return t.name.contains(q) || t.phone.contains(q) || t.email.toLowerCase().contains(q.toLowerCase());
    }).toList();

    return Column(
      children: [
        _Toolbar(
          controller: search,
          hint: 'ابحث باسم المدرس أو رقم الهاتف...',
          shown: list.length,
          total: store.teachers.length,
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: _cardList(
            count: list.length,
            empty: EmptyState(message: q.isEmpty ? 'لا يوجد مدرسون مسجلون.' : 'لا يوجد مدرسون مطابقون للبحث.'),
            item: (context, i) => _TeacherCard(teacher: list[i]),
          ),
        ),
      ],
    );
  }
}

/// مدرس: الاسم ورقمه مقابل أيقونتي التواصل وسهم الفتح، ثم خط رفيع، ثم موادّه.
class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = teacher;
    final phone = t.phone.trim();
    final subjects = store.subjects.where((s) => t.subjectIds.contains(s.id) || s.name == t.subject).toList();
    final groups = store.groups.where((g) => g.teacherId == t.id && g.isActive).length;
    final meta = [
      phone.isEmpty ? 'بلا رقم هاتف' : formatPhoneDisplay(phone),
      if (groups > 0) '$groups مجموعة',
    ];

    return AppCard(
      onTap: () => _open(context, TeacherFormScreen(teacher: t)),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                    const SizedBox(height: 2),
                    Text(
                      meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              if (phone.isNotEmpty) ...[
                ContactIconButton(
                  tooltip: 'اتصال',
                  onTap: () => launchTel(phone),
                  child: const Icon(Icons.phone_outlined, size: 18, color: AppColors.muted),
                ),
                ContactIconButton(
                  tooltip: 'واتساب',
                  onTap: () => launchWa(phone),
                  child: const MessageCircleIcon(color: AppColors.success),
                ),
              ],
              _chevron,
            ],
          ),
          if (subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Rule(),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [for (final s in subjects) StatusChip.muted(s.name)],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══ المواد ═════════════════════════════════════════════════════════════════

class _SubjectsTab extends StatefulWidget {
  const _SubjectsTab();

  @override
  State<_SubjectsTab> createState() => _SubjectsTabState();
}

class _SubjectsTabState extends State<_SubjectsTab> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = search.text.trim();
    final list = store.subjects.where((s) {
      if (q.isEmpty) return true;
      return s.name.contains(q) || s.code.toLowerCase().contains(q.toLowerCase()) || s.gradeLevel.contains(q);
    }).toList();

    return Column(
      children: [
        _Toolbar(
          controller: search,
          hint: 'ابحث باسم المادة، الرمز، أو المرحلة...',
          shown: list.length,
          total: store.subjects.length,
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: _cardList(
            count: list.length,
            empty: EmptyState(message: q.isEmpty ? 'لا توجد مواد دراسية مسجلة.' : 'لا توجد مواد مطابقة للبحث.'),
            item: (context, i) => _SubjectCard(subject: list[i]),
          ),
        ),
      ],
    );
  }
}

/// مادة: رمزها في صندوق صغير، ثم اسمها ومرحلتها ووصفها، مقابل عدد مدرّسيها وسهم الفتح.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final SubjectItem subject;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = subject;
    final teachers = store.teachers.where((t) => t.subjectIds.contains(s.id) || t.subject == s.name).length;

    return AppCard(
      onTap: () => _open(context, SubjectFormScreen(subject: s)),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 34,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: tileDecoration(),
            child: Text(
              s.code.isEmpty ? '—' : s.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, fontFamily: 'monospace', color: AppColors.heading),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                const SizedBox(height: 2),
                Text(
                  s.gradeLevel.isEmpty ? 'عام / كل المراحل' : s.gradeLevel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
                if (s.description.trim().isNotEmpty)
                  Text(
                    s.description.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (teachers > 0) ...[
            const SizedBox(width: 6),
            Text('$teachers مدرس', style: _metaStyle),
          ],
          const SizedBox(width: 2),
          _chevron,
        ],
      ),
    );
  }
}

// ═══ المستخدمون والصلاحيات ══════════════════════════════════════════════════

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final users = store.users;
    return _cardList(
      header: const [_DeviceCard()],
      count: users.length,
      empty: const EmptyState(message: 'لا يوجد مستخدمون.'),
      item: (context, i) => _UserCard(
        user: users[i],
        isThisDevice: users[i].id == store.deviceUserId,
        canDelete: users.length > 1,
      ),
    );
  }
}

/// المستخدم المثبَّت على هذا الجهاز — من تُطبَّق صلاحياته ويظهر اسمه على السندات.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final me = store.deviceUser;
    final label = store.receiptReceiverLabel.trim();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Corner.box),
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: Icon(Icons.phonelink_lock_outlined, size: 19, color: AppColors.amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('المستخدم المثبَّت على هذا الجهاز', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  me == null ? 'لم يُثبَّت مستخدم بعد' : me.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
                if (me != null)
                  Text(
                    [roleLabel(me.role), if (label.isNotEmpty) 'المستلم على السند: $label'].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _metaStyle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// مستخدم: الاسم وشارة «هذا الجهاز» مقابل حالته، ودوره وعدد صلاحياته، ثم خط رفيع
/// وأزرار التثبيت والصلاحيات والحذف.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.isThisDevice, required this.canDelete});

  final AppUser user;
  final bool isThisDevice;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final caps = effectiveCapabilities(u.capabilities, u.role).length;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle)),
                        if (isThisDevice) ...[
                          const SizedBox(width: 6),
                          StatusChip.success('هذا الجهاز'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${roleLabel(u.role)}  ·  $caps من ${allCapabilities.length} صلاحية',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              if (!u.isActive) StatusChip.danger('موقوف'),
            ],
          ),
          const _Rule(),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (!isThisDevice)
                  TileButton(
                    label: 'تثبيت على الجهاز',
                    icon: const Icon(Icons.phonelink_lock_outlined, size: 13),
                    color: AppColors.amber,
                    background: AppColors.amberSoft,
                    border: AppColors.amberBorder,
                    onTap: () => _pinUser(context, u),
                  ),
                TileButton(
                  label: 'الصلاحيات',
                  icon: const Icon(Icons.tune, size: 13),
                  color: AppColors.heading,
                  background: Colors.white,
                  border: AppColors.lineStrong,
                  onTap: () => _open(context, CapabilitiesScreen(user: u)),
                ),
                if (canDelete && !isThisDevice)
                  TileButton(
                    label: 'حذف',
                    icon: const Icon(Icons.delete_outline, size: 13),
                    color: AppColors.danger,
                    background: Colors.white,
                    border: AppColors.dangerBorder,
                    onTap: () => _deleteUser(context, u),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// تثبيت مستخدم على الجهاز — بكلمة مرور المدير لكل الأدوار، كما في تهيئة الجهاز:
/// تثبيت سكرتير بلا كلمة مرور كان يغيّر صلاحيات الجهاز لأي حامل له.
Future<void> _pinUser(BuildContext context, AppUser u) async {
  final store = StoreScope.of(context);
  final label = TextEditingController(text: u.name);
  final pass = TextEditingController();
  String? passError;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        Future<void> submit() async {
          final entered = pass.text.trim();
          if (entered.isEmpty) {
            setSt(() => passError = 'يرجى إدخال كلمة مرور المدير');
            return;
          }
          // القاعدة هي التي تتحقق من كلمة مرور المدير الآن
          if (!await store.verifyAdminSetupPassword(entered)) {
            if (ctx.mounted) setSt(() => passError = 'كلمة المرور غير صحيحة');
            return;
          }
          store.setDeviceIdentity(u, label.text);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          showAppSnack(context, 'تم تثبيت «${u.name}» على هذا الجهاز');
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.phonelink_lock_outlined, size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تثبيت «${u.name}» على هذا الجهاز',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.heading),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'تُطبَّق صلاحياته على هذا الجهاز، ويظهر الاسم التالي مستلماً على سندات القبض.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
                ),
                const SizedBox(height: 14),
                const FieldLabel('اسم المستلم على سند القبض'),
                TextField(controller: label),
                const SizedBox(height: 12),
                const FieldLabel('كلمة مرور المدير الرئيسية', requiredField: true),
                TextField(
                  controller: pass,
                  obscureText: true,
                  onChanged: (_) {
                    if (passError != null) setSt(() => passError = null);
                  },
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(hintText: 'مطلوبة لتثبيت أي مستخدم', errorText: passError),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(label: 'تثبيت على الجهاز', icon: Icons.check, height: 44, onPressed: submit),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _deleteUser(BuildContext context, AppUser u) async {
  final store = StoreScope.of(context);
  final ok = await confirmSheet(
    context,
    title: 'حذف المستخدم',
    message: 'هل تريد حذف «${u.name}» نهائياً؟',
    confirmLabel: 'حذف',
  );
  if (!ok || !context.mounted) return;
  try {
    store.deleteUser(u.id);
    showAppSnack(context, 'تم حذف المستخدم');
  } on StoreException catch (e) {
    showAppSnack(context, e.message, error: true);
  }
}

// ═══ البيانات والمطور ═══════════════════════════════════════════════════════

class _DataTab extends StatelessWidget {
  const _DataTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final failed = store.sync.getFailedActions();
    final tenant = store.currentTenant;
    final counts = <(String, int)>[
      ('الطلاب', store.students.length),
      ('الصفوف', store.rooms.length),
      ('المدرسون', store.teachers.length),
      ('المواد', store.subjects.length),
      ('المقبوضات', store.payments.length),
      ('الأقساط', store.installments.length),
      ('الحضور', store.attendance.length),
      ('المراحل', store.gradeFees.length),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        const FormSection(icon: Icons.cloud_sync_outlined, title: 'المزامنة مع السحابة'),
        StatRow(
          children: [
            StatCard(
              label: 'بانتظار الرفع',
              value: '${store.pendingPush}',
              color: store.pendingPush > 0 ? AppColors.amber : AppColors.success,
            ),
            StatCard(
              label: 'عمليات متعثرة',
              value: '${failed.length}',
              color: failed.isEmpty ? AppColors.success : AppColors.danger,
            ),
          ],
        ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          _FailedActions(failed: failed),
        ],

        const FormSection(icon: Icons.storage_outlined, title: 'البيانات المحلية على هذا الجهاز'),
        _CountGrid(counts: counts),

        const FormSection(icon: Icons.backup_outlined, title: 'النسخ الاحتياطي'),
        _NavTile(
          icon: Icons.download_outlined,
          title: 'تصدير نسخة احتياطية',
          subtitle: 'حفظ بيانات هذا الجهاز كاملة في ملف',
          onTap: () => _export(context, store),
        ),
        const SizedBox(height: 8),
        _NavTile(
          icon: Icons.upload_file_outlined,
          title: 'استرجاع نسخة احتياطية',
          subtitle: 'استبدال بيانات الجهاز بمحتوى ملف سابق',
          onTap: () => _restore(context, store),
        ),

        const FormSection(icon: Icons.apartment_outlined, title: 'المنشأة'),
        InfoStrip(
          child: Column(
            children: [
              _infoRow('المنشأة', tenant?.name ?? (store.institutionName.isEmpty ? '—' : store.institutionName)),
              _infoRow('رمز المنشأة', tenant?.code.isNotEmpty == true ? tenant!.code : '—'),
              _infoRow('المستخدم على الجهاز', store.deviceUser?.name ?? '—'),
            ],
          ),
        ),
        if (store.can('settings.branding')) ...[
          const SizedBox(height: 8),
          _NavTile(
            icon: Icons.tune,
            title: 'تخصيص المنشأة وأدوات المطور',
            subtitle: 'الاسم والشعار والألوان والميزات',
            onTap: () => _open(context, const DeveloperSettingsScreen()),
          ),
        ],
      ],
    );
  }
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
          ),
        ),
      ],
    ),
  );
}

/// أعداد السجلات المحلية في شبكة من أربعة أعمدة متساوية.
class _CountGrid extends StatelessWidget {
  const _CountGrid({required this.counts});

  final List<(String, int)> counts;

  static const _columns = 4;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < counts.length; i += _columns) {
      final slice = counts.sublist(i, (i + _columns).clamp(0, counts.length));
      rows.add(
        Row(
          children: [
            for (var j = 0; j < _columns; j++) ...[
              if (j > 0) const SizedBox(width: 6),
              Expanded(child: j < slice.length ? _cell(slice[j]) : const SizedBox.shrink()),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          rows[i],
        ],
      ],
    );
  }

  Widget _cell((String, int) c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      decoration: tileDecoration(),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${c.$2}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.heading)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(c.$1, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}

/// سطر يُفتح بلمسة: أيقونة في صندوق، وعنوان وشرح، وسهم الفتح.
class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: tileDecoration(),
            child: Icon(icon, size: 18, color: AppColors.amber),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _titleStyle),
                const SizedBox(height: 1),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: _metaStyle),
              ],
            ),
          ),
          _chevron,
        ],
      ),
    );
  }
}

/// العمليات التي تعذّر رفعها بعد كل المحاولات، مع إعادة المحاولة أو التجاهل.
class _FailedActions extends StatelessWidget {
  const _FailedActions({required this.failed});

  final List<PendingSync> failed;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'تعذّر رفع ${failed.length} عملية بعد $maxSyncRetries محاولات',
            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          for (final a in failed.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${tableLabelsAr[a.tableName] ?? a.tableName}: ${a.lastError ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _metaStyle,
              ),
            ),
          const _Rule(),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'إعادة المحاولة',
                  icon: Icons.refresh,
                  onPressed: () async {
                    final count = store.sync.retryFailedActions();
                    final result = await store.sync.push();
                    if (!context.mounted) return;
                    showAppSnack(
                      context,
                      count == 0 ? 'لا توجد عمليات متعثرة' : result.message,
                      error: !result.success,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GhostButton(
                  label: 'تجاهل المتعثرة',
                  icon: Icons.delete_outline,
                  onPressed: () async {
                    final ok = await confirmSheet(
                      context,
                      title: 'تجاهل العمليات المتعثرة',
                      message: 'سيتم إسقاط ${failed.length} عملية من طابور الرفع نهائياً. '
                          'التعديلات تبقى على هذا الجهاز لكنها لن تصل السحابة.',
                      confirmLabel: 'تجاهل',
                    );
                    if (!ok) return;
                    for (final a in failed) {
                      store.sync.discardAction(a);
                    }
                    store.markAllDirty();
                    if (!context.mounted) return;
                    showAppSnack(context, 'تم إسقاط ${failed.length} عملية متعثرة');
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _export(BuildContext context, AppStore store) async {
  try {
    final path = await const BackupService().export(store);
    if (!context.mounted) return;
    showAppSnack(context, 'تم حفظ النسخة الاحتياطية في: $path');
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, 'تعذّر تصدير النسخة: $e', error: true);
  }
}

Future<void> _restore(BuildContext context, AppStore store) async {
  const service = BackupService();
  String? json;
  try {
    json = await service.pickFile();
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, 'تعذّر فتح الملف: $e', error: true);
    return;
  }
  if (json == null || !context.mounted) return;

  Map<String, int> summary;
  try {
    summary = service.summarize(json);
  } catch (_) {
    if (!context.mounted) return;
    showAppSnack(context, 'الملف ليس نسخة احتياطية صالحة', error: true);
    return;
  }

  final lines = summary.entries.map((e) => '${tableLabelsAr[e.key] ?? e.key}: ${e.value}').join('\n');
  final ok = await confirmSheet(
    context,
    title: 'استرجاع نسخة احتياطية',
    message: 'سيتم استبدال كل البيانات المحلية بمحتوى الملف:\n\n$lines\n\n'
        'لا يمكن التراجع عن هذه العملية. هل تريد المتابعة؟',
    confirmLabel: 'استرجاع',
  );
  if (!ok || !context.mounted) return;

  try {
    final count = await service.restore(store, json);
    if (!context.mounted) return;
    showAppSnack(context, 'تم استرجاع $count سجلاً بنجاح');
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, 'فشل الاسترجاع: $e', error: true);
  }
}
