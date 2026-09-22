import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/backup.dart';
import '../data/permissions.dart';
import '../data/phone.dart';
import '../data/payment_methods.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/list_paging.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'developer_settings_screen.dart';
import 'grade_plan_screen.dart';
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
  const SettingsScreen({super.key, this.initialTab});

  /// تبويب يُفتح مباشرة — من القائمة الجانبية مثلاً.
  final String? initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// تبويب في الإعدادات مع التبويب الفرعي الذي يحرسه.
class _Tab {
  const _Tab(this.id, this.icon, this.label, {this.section});

  final String id;
  final IconData icon;
  final String label;
  final String? section;
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String current = widget.initialTab ?? 'teachers';

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != null && widget.initialTab != oldWidget.initialTab) {
      current = widget.initialTab!;
    }
  }

  /// التبويبات بترتيب Settings.tsx — تُخفى بحسب الصلاحية.
  static const _allTabs = [
    _Tab('academic_years', Icons.calendar_month_outlined, 'الأعوام الدراسية'),
    _Tab('grade_fees', Icons.payments_outlined, 'المراحل والرسوم'),
    _Tab('payment_methods', Icons.credit_card_outlined, 'وسائل الدفع'),
    _Tab('teachers', Icons.school_outlined, 'المعلمون'),
    _Tab('subjects', Icons.menu_book_outlined, 'المواد'),
    _Tab('grading', Icons.workspace_premium_outlined, 'نظام العلامات'),
    _Tab(
      'users',
      Icons.manage_accounts_outlined,
      'المستخدمون',
      section: 'settings.users',
    ),
    _Tab(
      'backup',
      Icons.storage_outlined,
      'البيانات والنسخ',
      section: 'settings.backup',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('settings')) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(title: const Text('الإعدادات')),
            body: Material(
              color: AppColors.bg,
              child: NoAccess(section: 'settings', roleName: store.roleName),
            ),
          );
        }
        final tabs = _allTabs.where((t) {
          if (t.id == 'grading' && !store.features.enableEvaluations) {
            return false;
          }
          if (t.section != null && !store.can(t.section!)) return false;
          return true;
        }).toList();
        if (tabs.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(title: const Text('الإعدادات')),
            body: Material(
              color: AppColors.bg,
              child: NoAccess(section: 'settings', roleName: store.roleName),
            ),
          );
        }
        // من فقد صلاحية التبويب المفتوح يعود إلى أول تبويب مسموح
        final active = tabs.firstWhere(
          (t) => t.id == current,
          orElse: () => tabs.first,
        );

        // صفحة مستقلة من القائمة الجانبية: Scaffold لا يغلّف body بـ Material،
        // وLookupBoundary في الـ route يمنع الاعتماد على Material خارج الصفحة.
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            titleSpacing: 0,
            title: Text(active.label),
          ),
          body: Material(
            type: MaterialType.canvas,
            color: AppColors.bg,
            child: ThumbActionLayer(
              action: _actionFor(context, active.id),
              child: switch (active.id) {
                'academic_years' => const _AcademicYearsTab(),
                'grade_fees' => const _FeesTab(),
                'payment_methods' => const PaymentMethodsTab(),
                'subjects' => const _SubjectsTab(),
                'grading' => const GradingSchemeTab(),
                'users' => const _UsersTab(),
                'backup' => const _DataTab(),
                _ => const _TeachersTab(),
              },
            ),
          ),
        );
      },
    );
  }

  /// زر الإضافة يتبع التبويب — تبويب البيانات بلا إضافة.
  ThumbAction? _actionFor(BuildContext context, String tab) {
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return switch (tab) {
      'grade_fees' => ThumbAction(
        label: 'مرحلة جديدة',
        icon: Icons.add,
        onPressed: () => open(const GradeFeeFormScreen()),
      ),
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
      'subjects' => ThumbAction(
        label: 'إضافة مادة',
        icon: Icons.add,
        onPressed: () => open(const SubjectFormScreen()),
      ),
      'users' => ThumbAction(
        label: 'مستخدم جديد',
        icon: Icons.person_add_alt_1_outlined,
        onPressed: () => open(const UserFormScreen()),
      ),
      _ => null,
    };
  }
}

// ═══ الأعوام الدراسية ═══════════════════════════════════════════════════════

class _AcademicYearsTab extends StatefulWidget {
  const _AcademicYearsTab();

  @override
  State<_AcademicYearsTab> createState() => _AcademicYearsTabState();
}

class _AcademicYearsTabState extends State<_AcademicYearsTab> {
  bool openDates = false;
  String startsOn = '';
  String endsOn = '';
  String term1Start = '';
  String term1End = '';
  String term2Start = '';
  String term2End = '';
  bool busy = false;

  void _loadDraft(AcademicYear? current) {
    if (current == null) return;
    startsOn = current.startsOn;
    endsOn = current.endsOn;
    term1Start = current.term1Start;
    term1End = current.term1End;
    term2Start = current.term2Start;
    term2End = current.term2End;
  }

  Future<void> _pick(String current, ValueChanged<String> onPicked) async {
    final initial = parseIsoDate(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (picked != null) onPicked(isoDate(picked));
  }

  Future<void> _saveDates(AppStore store, AcademicYear current) async {
    setState(() => busy = true);
    await yieldUi(2);
    try {
      await store.updateAcademicYear(
        current.id,
        startsOn: startsOn,
        endsOn: endsOn,
        term1Start: term1Start,
        term1End: term1End,
        term2Start: term2Start,
        term2End: term2End,
      );
      if (!mounted) return;
      setState(() => openDates = false);
      showAppSnack(context, 'تم حفظ تواريخ ${current.label}');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final years = [...store.academicYears]
      ..sort((a, b) => b.startsOn.compareTo(a.startsOn));
    final current = store.operationalAcademicYear;
    if (!openDates && current != null && startsOn.isEmpty) {
      _loadDraft(current);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, thumbActionClearance),
      children: [
        for (final year in years)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(year.label, style: _titleStyle),
                        const SizedBox(height: 2),
                        Text(
                          '${year.startsOn} — ${year.endsOn}',
                          style: _metaStyle,
                        ),
                      ],
                    ),
                  ),
                  if (year.isCurrent)
                    StatusChip.success('الحالي')
                  else if (year.status == 'closed')
                    StatusChip.muted('مغلق')
                  else
                    GhostButton(
                      label: 'جعله الحالي',
                      onPressed: () async {
                        await store.setCurrentAcademicYear(year.id);
                        if (context.mounted) {
                          showAppSnack(
                            context,
                            'تم تعيين ${year.label} عاماً حالياً',
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        if (current != null) ...[
          const SizedBox(height: 8),
          GhostButton(
            label: openDates ? 'إخفاء التواريخ' : 'تعديل تواريخ العام الحالي',
            icon: Icons.edit_calendar_outlined,
            onPressed: () => setState(() {
              openDates = !openDates;
              if (openDates) _loadDraft(current);
            }),
          ),
          if (openDates) ...[
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('العام', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  FieldPair(
                    start: [
                      const FieldLabel('من'),
                      SelectField(
                        text: startsOn.isEmpty ? 'اختر' : startsOn,
                        icon: Icons.calendar_today_outlined,
                        placeholder: startsOn.isEmpty,
                        onTap: () => _pick(startsOn, (v) => setState(() => startsOn = v)),
                      ),
                    ],
                    end: [
                      const FieldLabel('إلى'),
                      SelectField(
                        text: endsOn.isEmpty ? 'اختر' : endsOn,
                        icon: Icons.calendar_today_outlined,
                        placeholder: endsOn.isEmpty,
                        onTap: () => _pick(endsOn, (v) => setState(() => endsOn = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('الفصل الأول', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  FieldPair(
                    start: [
                      const FieldLabel('من'),
                      SelectField(
                        text: term1Start.isEmpty ? 'اختر' : term1Start,
                        icon: Icons.calendar_today_outlined,
                        placeholder: term1Start.isEmpty,
                        onTap: () => _pick(term1Start, (v) => setState(() => term1Start = v)),
                      ),
                    ],
                    end: [
                      const FieldLabel('إلى'),
                      SelectField(
                        text: term1End.isEmpty ? 'اختر' : term1End,
                        icon: Icons.calendar_today_outlined,
                        placeholder: term1End.isEmpty,
                        onTap: () => _pick(term1End, (v) => setState(() => term1End = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('الفصل الثاني', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  FieldPair(
                    start: [
                      const FieldLabel('من'),
                      SelectField(
                        text: term2Start.isEmpty ? 'اختر' : term2Start,
                        icon: Icons.calendar_today_outlined,
                        placeholder: term2Start.isEmpty,
                        onTap: () => _pick(term2Start, (v) => setState(() => term2Start = v)),
                      ),
                    ],
                    end: [
                      const FieldLabel('إلى'),
                      SelectField(
                        text: term2End.isEmpty ? 'اختر' : term2End,
                        icon: Icons.calendar_today_outlined,
                        placeholder: term2End.isEmpty,
                        onTap: () => _pick(term2End, (v) => setState(() => term2End = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: busy ? 'جارِ الحفظ...' : 'حفظ التواريخ',
                    onPressed: busy ? null : () => _saveDates(store, current),
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'إغلاق العام وفتح التالي',
          icon: Icons.next_plan_outlined,
          color: AppColors.navy,
          onPressed: () async {
            final cur = store.operationalAcademicYear;
            if (cur == null) return;
            final ok = await confirmSheet(
              context,
              title: 'إغلاق ${cur.label}',
              message:
                  'سيُغلق العام الحالي ويُفتح التالي مع نسخ الصفوف والمواد والخطط.',
              confirmLabel: 'إغلاق وفتح التالي',
            );
            if (!ok || !context.mounted) return;
            final result = await store.closeCurrentAndOpenNext();
            if (context.mounted) {
              showAppSnack(context, 'تم فتح ${result.opened.label}');
            }
          },
        ),
      ],
    );
  }
}

// ═══ عناصر مشتركة ═══════════════════════════════════════════════════════════

TextStyle get _titleStyle => TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 13,
  color: AppColors.heading,
);

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
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: header,
          ),
        );
      }
      if (count == 0) return SizedBox(height: 220, child: empty);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: item(context, i - offset),
      );
    },
  );
}

/// سهم «فتح» في طرف البطاقة — ينعكس تلقائياً في العربية.
const _chevron = AppChevron(size: 22);

// ═══ الرسوم والمراحل (للمدارس) ══════════════════════════════════════════════

class _FeesTab extends StatelessWidget {
  const _FeesTab();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final fees = store.gradeFeesInViewedYear;
    final missing = store.studentsMissingPlan;
    final withoutPlan = fees.where((f) => f.planItems.isEmpty).length;

    return _cardList(
      header: [
        // الأرقام سطر واحد بدل بطاقتين
        Row(
          children: [
            Expanded(
              child: Text(
                '${fees.length} مرحلة  ·  ${store.roomsInViewedYear.length} شعبة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle,
              ),
            ),
            TextButton.icon(
              onPressed: () => showStudentPromotionSheet(context, store),
              icon: const Icon(Icons.moving_outlined, size: 16),
              label: const Text('ترقية الطلاب'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amberDark,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
        if (missing > 0) ...[
          const SizedBox(height: 8),
          // مرحلةٌ بلا خطة لا تولّد أقساطاً لمن يُسجَّل فيها، فيبقى بلا مطالبة بصمت
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(Corner.card),
              border: Border.all(color: AppColors.dangerBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 17, color: AppColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$missing طالباً نشطاً بلا خطة أقساط لمرحلته',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        // كالويب: رسم الحجز وخصم المتفوقين في قسم واحد تحت المراحل
        _FeeSection(
          icon: Icons.local_offer_outlined,
          title: 'الرسوم المحددة والخصومات',
          summary: 'رسم الحجز وخصم المتفوقين',
          children: [
            _SeatFeeCard(store: store),
            const SizedBox(height: 8),
            _ExcellenceDiscountCard(store: store),
          ],
        ),
        const SizedBox(height: 8),
        _FeeSection(
          icon: Icons.playlist_add_outlined,
          title: 'رسوم إضافية',
          summary: store.feeItems.isEmpty ? 'لا بنود' : '${store.feeItems.length} بند',
          children: [_FeeItemsCard(store: store)],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('المراحل', style: _titleStyle),
            const Spacer(),
            if (withoutPlan > 0)
              Text(
                '$withoutPlan بلا خطة',
                style: const TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      count: fees.length,
      empty: const EmptyState(message: 'لا توجد مراحل دراسية مسجلة.'),
      item: (context, i) => _GradeFeeCard(fee: fees[i]),
    );
  }
}

/// قسم في الرسوم يُطوى بملخّص يُقرأ وهو مغلق.
class _FeeSection extends StatefulWidget {
  const _FeeSection({
    required this.icon,
    required this.title,
    required this.summary,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String summary;
  final List<Widget> children;

  @override
  State<_FeeSection> createState() => _FeeSectionState();
}

class _FeeSectionState extends State<_FeeSection> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 8, 11),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(Corner.field),
                      border: Border.all(color: AppColors.amberBorder),
                    ),
                    child: Icon(widget.icon, size: 17, color: AppColors.amberDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            color: AppColors.heading,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: const BoxDecoration(
                      color: AppColors.sunken,
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
                  ),
          ),
        ],
      ),
    );
  }
}

/// رسوم إضافية تحددها الإدارة — المقابل لـ `FeeItemsSettings.tsx`.
///
/// زيّ أو كتب أو رحلة: تُقيَّد أقساطاً على طلاب مرحلة، أو على الجميع، أو على طلاب
/// بأسمائهم — فالرحلة لا يشترك فيها كل الصف. تظهر في بند الدفعة وبيان السند
/// وتدخل في المستحق، و«تطبيق» تجعلها مقيّدة على المستهدفين بها بالضبط.
class _FeeItemsCard extends StatefulWidget {
  const _FeeItemsCard({required this.store});

  final AppStore store;

  @override
  State<_FeeItemsCard> createState() => _FeeItemsCardState();
}

/// قيمة «طلاب بعينهم» في قائمة الاستهداف — لا مرحلة تحمل هذا الاسم.
const _pickStudents = '__pick__';

class _FeeItemsCardState extends State<_FeeItemsCard> {
  final name = TextEditingController();
  final amount = TextEditingController();
  String grade = '';
  DateTime due = DateTime.now();
  bool adding = false;

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final store = widget.store;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (name.text.trim().isEmpty || value <= 0) {
      showAppSnack(context, 'اكتب البند والمبلغ', error: true);
      return;
    }
    // «طلاب بعينهم» يبدأ بقائمة فارغة، ثم تُختار أسماؤهم من زر «الطلاب»
    final picking = grade == _pickStudents;
    final item = FeeItem(
      id: store.newId(),
      name: name.text.trim(),
      amount: value,
      dueDate: isoDate(due),
      gradeLevel: picking ? '' : grade,
      studentIds: picking ? const [] : null,
    );
    try {
      await store.saveFeeItems([...store.feeItems, item]);
      final result = store.applyFeeItem(item);
      if (!mounted) return;
      setState(() {
        name.clear();
        amount.clear();
        adding = false;
      });
      showAppSnack(
        context,
        picking ? 'أُضيف — اختر طلابه' : 'قُيّد على ${result.added} طالباً',
      );
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  String _describe(({int added, int removed}) result) {
    if (result.added == 0 && result.removed == 0) return 'لا تغيير';
    if (result.removed == 0) return 'قُيّد على ${result.added} طالباً';
    if (result.added == 0) return 'رُفع عن ${result.removed} طالباً';
    return 'قُيّد على ${result.added} ورُفع عن ${result.removed}';
  }

  Future<void> _apply(FeeItem item) async {
    try {
      final result = widget.store.applyFeeItem(item);
      if (!mounted) return;
      showAppSnack(context, _describe(result));
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  /// اختيار طلاب الرسم بأسمائهم، ثم تقييده عليهم بالضبط.
  Future<void> _pick(FeeItem item) async {
    final store = widget.store;
    final chosen = await showFeeStudentsSheet(
      context,
      store,
      selected: item.studentIds ?? const [],
    );
    if (chosen == null || !mounted) return;
    final updated = item.copyWith(studentIds: chosen, gradeLevel: '');
    try {
      await store.saveFeeItems([
        for (final i in store.feeItems) i.id == item.id ? updated : i,
      ]);
      final result = store.applyFeeItem(updated);
      if (!mounted) return;
      showAppSnack(context, _describe(result));
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _remove(FeeItem item) async {
    final store = widget.store;
    final ok = await confirmSheet(
      context,
      title: 'حذف «${item.name}»',
      message: 'يُزال عن الطلاب، ويبقى على من له سند مربوط به.',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      final kept = store.removeFeeItem(item.id);
      await store.saveFeeItems(
        store.feeItems.where((i) => i.id != item.id).toList(),
      );
      if (!mounted) return;
      showAppSnack(
        context,
        kept == 0 ? 'حُذف' : 'حُذف، وبقي على $kept طالباً لهم سندات',
      );
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final items = store.feeItems;
    final grades = store.gradeOptions;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'رسوم إضافية',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.heading,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => adding = !adding),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.amber,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                icon: Icon(adding ? Icons.close : Icons.add, size: 16),
                label: Text(adding ? 'إلغاء' : 'رسم جديد'),
              ),
            ],
          ),
          if (adding) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: name,
                    decoration: const InputDecoration(hintText: 'الزي المدرسي'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(hintText: '0 $currency'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    value: grade.isEmpty ? '' : grade,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('كل الطلاب'),
                      ),
                      const DropdownMenuItem(
                        value: _pickStudents,
                        child: Text('طلاب بعينهم'),
                      ),
                      for (final g in grades)
                        DropdownMenuItem(
                          value: g,
                          child: Text(g, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => grade = v ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectField(
                    text: isoDate(due),
                    icon: Icons.calendar_today_outlined,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) setState(() => due = picked);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'إضافة وتقييد',
              color: AppColors.navy,
              onPressed: _add,
            ),
          ],
          if (items.isEmpty && !adding)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'لا رسوم إضافية',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          '${money(item.amount)}  ·  ${_targetLabel(item)}  ·  ${item.dueDate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        item.studentIds == null ? _apply(item) : _pick(item),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.amber,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                    child: Text(item.studentIds == null ? 'تطبيق' : 'الطلاب'),
                  ),
                  IconButton(
                    onPressed: () => _remove(item),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _targetLabel(FeeItem item) {
  final ids = item.studentIds;
  if (ids != null) return '${ids.length} طالباً';
  return item.gradeLevel.isEmpty ? 'كل الطلاب' : item.gradeLevel;
}

/// اختيار طلاب الرسم بأسمائهم — المقابل لـ `FeeStudentsModal.tsx`.
///
/// يعيد المعرّفات المختارة، أو `null` إن أُغلقت بلا حفظ.
Future<List<String>?> showFeeStudentsSheet(
  BuildContext context,
  AppStore store, {
  required List<String> selected,
}) {
  final chosen = {...selected};
  final search = TextEditingController();
  var visibleCount = kListPageSize;

  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final q = search.text.trim().toLowerCase();
        final all = store.students.where((s) => s.status == 'active').toList();
        // بالاسم أو الهوية كما تفلتر شاشة الطلاب
        final shown = q.isEmpty
            ? all
            : all
                  .where(
                    (s) =>
                        s.fullName.toLowerCase().contains(q) ||
                        s.nationalId.contains(q),
                  )
                  .toList();
        final page = listPage(shown, visibleCount);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            12 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'طلاب الرسم',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${chosen.length} من ${all.length} طالباً نشطاً',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                SearchField(
                  controller: search,
                  hint: 'ابحث بالاسم أو الهوية',
                  onChanged: (_) {
                    visibleCount = kListPageSize;
                    setSt(() {});
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.4,
                  ),
                  child: shown.isEmpty
                      ? const EmptyState(message: 'لا طلاب مطابقون للبحث')
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: page.length + (page.length < shown.length ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= page.length) {
                              return LoadMoreButton(
                                shown: page.length,
                                total: shown.length,
                                onMore: () {
                                  visibleCount += kListPageSize;
                                  setSt(() {});
                                },
                              );
                            }
                            final s = page[i];
                            final on = chosen.contains(s.id);
                            return CheckboxListTile(
                              dense: true,
                              value: on,
                              activeColor: AppColors.amber,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                s.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${s.gradeLevel}${s.section.isEmpty ? '' : ' · ${s.section}'}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.muted,
                                ),
                              ),
                              onChanged: (_) => setSt(
                                () =>
                                    on ? chosen.remove(s.id) : chosen.add(s.id),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                ActionButtons(
                  gap: 8,
                  primary: PrimaryButton(
                    label: 'حفظ',
                    color: AppColors.navy,
                    onPressed: () => Navigator.pop(ctx, chosen.toList()),
                  ),
                  secondary: GhostButton(
                    label: 'إلغاء',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  ).whenComplete(search.dispose);
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
  late bool deduct;
  bool saved = false;

  /// المستخدم بدأ يعدّل: ما يصل من جهاز آخر لا يُبدّل ما تحت يده.
  bool editing = false;

  @override
  void initState() {
    super.initState();
    _readStore();
    amount = TextEditingController(
      text: widget.store.seatReservationFee > 0
          ? trimNum(widget.store.seatReservationFee)
          : '',
    );
  }

  void _readStore() {
    enabled = widget.store.seatReservationFee > 0;
    deduct = widget.store.deductsSeatFee;
  }

  @override
  void didUpdateWidget(covariant _SeatFeeCard old) {
    super.didUpdateWidget(old);
    // ضبطٌ غُيّر على جهاز آخر يصل بالسحب: كان لا يظهر حتى تُغلق الصفحة وتُفتح
    if (editing) return;
    final fee = widget.store.seatReservationFee;
    final shown = fee > 0 ? trimNum(fee) : '';
    if (amount.text != shown) amount.text = shown;
    _readStore();
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = widget.store;
    final value = enabled ? (double.tryParse(amount.text.trim()) ?? 0) : 0.0;
    await store.setSeatReservationFee(value < 0 ? 0 : value, deduct: deduct);
    if (!mounted) return;
    setState(() {
      saved = true;
      editing = false;
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
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.heading,
                  ),
                ),
              ),
              if (saved)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Text(
                    'حُفظ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: AppColors.amber,
                onChanged: (v) => setState(() {
                  enabled = v;
                  editing = true;
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onChanged: (_) => setState(() {
                      editing = true;
                      saved = false;
                    }),
                    decoration: InputDecoration(hintText: '0 $currency'),
                  ),
                ),
                const SizedBox(width: 8),
                PrimaryButton(
                  label: 'حفظ',
                  color: AppColors.navy,
                  onPressed: _save,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // الاقتطاع يجعله سلفةً على الخطة، والاستقلال يجعله رسماً فوقها
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in const [
                  (true, 'يُخصم من الأقساط'),
                  (false, 'رسم مستقل فوقها'),
                ])
                  _MonthChip(
                    label: option.$2,
                    on: deduct == option.$1,
                    onTap: () => setState(() {
                      deduct = option.$1;
                      editing = true;
                      saved = false;
                    }),
                  ),
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
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GhostButton(label: 'حفظ', onPressed: _save),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            enabled && !deduct
                ? 'يُدفع مرة واحدة، ويبقى مطالبةً مستقلة فوق أقساط الطالب'
                : 'يُدفع مرة واحدة ويُخصم من أول الأقساط',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.faint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// خصم المتفوقين — المقابل لخياره في GradeFeesSettings.tsx.
///
/// اقتراح عند التسجيل لمن بلغ المعدل؛ القرار يبقى للإدارة. منفصل عن قواعد
/// خصم التفوق في نظام العلامات (نمط المعدل الشهري).
class _ExcellenceDiscountCard extends StatefulWidget {
  const _ExcellenceDiscountCard({required this.store});

  final AppStore store;

  @override
  State<_ExcellenceDiscountCard> createState() => _ExcellenceDiscountCardState();
}

class _ExcellenceDiscountCardState extends State<_ExcellenceDiscountCard> {
  late bool enabled;
  late final TextEditingController minGpa;
  late final TextEditingController rate;
  bool saved = false;
  bool editing = false;

  @override
  void initState() {
    super.initState();
    final rules = widget.store.discountRules;
    enabled = rules.autoSuggestExcellence;
    minGpa = TextEditingController(text: _num(rules.excellenceMinGpa));
    rate = TextEditingController(text: _num(rules.excellenceDiscountRate));
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void didUpdateWidget(covariant _ExcellenceDiscountCard old) {
    super.didUpdateWidget(old);
    if (editing) return;
    final rules = widget.store.discountRules;
    enabled = rules.autoSuggestExcellence;
    final g = _num(rules.excellenceMinGpa);
    final r = _num(rules.excellenceDiscountRate);
    if (minGpa.text != g) minGpa.text = g;
    if (rate.text != r) rate.text = r;
  }

  @override
  void dispose() {
    minGpa.dispose();
    rate.dispose();
    super.dispose();
  }

  Future<void> _save({bool? turnOn}) async {
    final on = turnOn ?? enabled;
    final gpa = double.tryParse(minGpa.text.trim()) ?? 90;
    final pct = double.tryParse(rate.text.trim()) ?? 10;
    final cleanGpa = gpa <= 0 || gpa > 100 ? 90.0 : gpa;
    final cleanPct = pct <= 0 || pct > 100 ? 10.0 : pct;
    try {
      await widget.store.saveDiscountRules(
        SchoolDiscountRules(
          autoSuggestExcellence: on,
          excellenceMinGpa: cleanGpa,
          excellenceDiscountRate: cleanPct,
        ),
      );
      if (!mounted) return;
      setState(() {
        enabled = on;
        saved = true;
        editing = false;
        minGpa.text = _num(cleanGpa);
        rate.text = _num(cleanPct);
      });
      showAppSnack(context, on ? 'تم حفظ خصم المتفوقين' : 'تم إيقاف خصم المتفوقين');
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
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
                  'خصم المتفوقين',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: AppColors.heading,
                  ),
                ),
              ),
              if (saved)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Text(
                    'حُفظ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: AppColors.amber,
                onChanged: (v) {
                  setState(() {
                    enabled = v;
                    editing = true;
                    saved = false;
                  });
                  if (!v) _save(turnOn: false);
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'أدنى معدل (%)',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: minGpa,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {
                          editing = true;
                          saved = false;
                        }),
                        decoration: const InputDecoration(hintText: '90'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'نسبة الخصم (%)',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: rate,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {
                          editing = true;
                          saved = false;
                        }),
                        decoration: const InputDecoration(hintText: '10'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PrimaryButton(
                  label: 'حفظ',
                  color: AppColors.navy,
                  onPressed: () => _save(turnOn: true),
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'معطّل — لا يُقترح خصم تلقائي عند التسجيل',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'اقتراح لا إلزام: عند التسجيل يُنبَّه لمن بلغ الحد الأدنى، والقرار للإدارة.',
            style: TextStyle(fontSize: 10.5, color: AppColors.faint, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

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
    final sections = store.roomsInViewedYear.where((r) => r.gradeLevel == f.gradeName).toList();
    final students = store.students.where((s) => isSameGrade(s.gradeLevel, f.gradeName)).length;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الرأس: المرحلة وقسطها، والتعديل والحذف في ورقة «المزيد»
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.gradeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                      const SizedBox(height: 3),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money(f.monthlyFee),
                      style: TextStyle(
                        fontFamily: AppText.family,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: AppColors.heading,
                      ),
                    ),
                    const Text('قيمة القسط', style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
                  ],
                ),
                IconButton(
                  tooltip: 'إجراءات',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_vert, size: 20, color: AppColors.faint),
                  onPressed: () => _gradeActions(context, f),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.hover),
          // الخطة سطر يُلمس فيفتح محرّرها
          _GradePlanRow(fee: f),
          const Divider(height: 1, color: AppColors.hover),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final r in sections)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.sunken,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r.name,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                TileButton(
                  label: 'شعبة',
                  icon: const Icon(Icons.add, size: 13),
                  color: AppColors.amberDark,
                  background: AppColors.amberSoft,
                  border: AppColors.amberBorder,
                  onTap: () => _addSection(context, f),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// تعديل المرحلة أو حذفها — ورقة بدل زرّين في كل بطاقة.
Future<void> _gradeActions(BuildContext context, GradeFee f) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(f.gradeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
          ),
          const Divider(height: 1, color: AppColors.line),
          ListTile(
            leading: Icon(Icons.edit_outlined, size: 20, color: AppColors.heading),
            title: const Text('تعديل المرحلة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
            title: const Text(
              'حذف المرحلة',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.danger),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'edit') {
    _open(context, GradeFeeFormScreen(fee: f));
  } else {
    await _deleteFee(context, f);
  }
}

/// خطة أقساط المرحلة: ملخّصها، ولمس السطر يفتح محرّرها.
class _GradePlanRow extends StatelessWidget {
  const _GradePlanRow({required this.fee});

  final GradeFee fee;

  @override
  Widget build(BuildContext context) {
    final items = fee.planItems;
    final missing = items.isEmpty;
    final total = items.fold<double>(0, (a, i) => a + i.amount);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GradePlanScreen(fee: fee)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11),
        child: Row(
          children: [
            Icon(
              missing ? Icons.event_busy_outlined : Icons.edit_calendar_outlined,
              size: 17,
              color: missing ? AppColors.danger : AppColors.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                missing
                    ? 'لا خطة أقساط — من يُسجَّل في المرحلة لا تُقيَّد عليه أقساط'
                    : '${items.length} قسطاً  ·  ${money(total)}',
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: missing ? AppColors.danger : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.faint),
          ],
        ),
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
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          12 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إضافة شعبة لمرحلة: ${f.gradeName}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 12),
              FieldLabel(
                'اسم الشعبة',
                key: errors.key('name'),
                requiredField: true,
              ),
              TextField(
                controller: ctl,
                autofocus: true,
                onChanged: (_) {
                  if (errors.clear('name')) setSt(() {});
                },
                decoration: InputDecoration(
                  hintText: 'مثال: الشعبة (ب)',
                  errorText: errors['name'],
                ),
              ),
              const SizedBox(height: 16),
              ActionButtons(
                primary: PrimaryButton(
                  label: 'حفظ الشعبة',
                  icon: Icons.check,
                  height: 40,
                  onPressed: () {
                    setSt(() {
                      errors
                        ..reset()
                        ..check(
                          'name',
                          ctl.text.trim().isEmpty,
                          'يرجى إدخال اسم الشعبة',
                        );
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
                      showAppSnack(
                        context,
                        'تمت إضافة الشعبة «${ctl.text.trim()}» إلى ${f.gradeName}',
                      );
                    } on StoreException catch (e) {
                      showAppSnack(ctx, e.message, error: true);
                    }
                  },
                ),
                secondary: GhostButton(
                  label: 'إلغاء',
                  onPressed: () => Navigator.pop(ctx),
                ),
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
    final list = store.teachersInViewedYear.where((t) {
      if (q.isEmpty) return true;
      return t.name.contains(q) ||
          t.phone.contains(q) ||
          t.email.toLowerCase().contains(q.toLowerCase());
    }).toList();

    return Column(
      children: [
        _Toolbar(
          controller: search,
          hint: 'ابحث باسم المدرس أو رقم الهاتف...',
          shown: list.length,
          total: store.teachersInViewedYear.length,
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: _cardList(
            count: list.length,
            empty: EmptyState(
              message: q.isEmpty
                  ? 'لا يوجد مدرسون مسجلون.'
                  : 'لا يوجد مدرسون مطابقون للبحث.',
            ),
            item: (context, i) => _TeacherCard(teacher: list[i]),
          ),
        ),
      ],
    );
  }
}

/// مدرس: اسمه، ثم رقمه وعدد شعبه، ثم موادّه سطراً واحداً. لمس البطاقة يفتح
/// ملفه، ولمس الرقم يتصل به، والواتساب أيقونة واحدة في الطرف.
class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher});

  final Teacher teacher;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = teacher;
    final phone = t.phone.trim();
    final subjects = store.subjectsInViewedYear
        .where((s) => t.subjectIds.contains(s.id) || s.name == t.subject)
        .map((s) => s.name)
        .toList();
    final groups = store.groupsInViewedYear.where((g) => g.teacherId == t.id && g.isActive).length;

    return AppCard(
      onTap: () => _open(context, TeacherFormScreen(teacher: t)),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                const SizedBox(height: 3),
                Text(
                  [
                    phone.isEmpty ? 'بلا رقم هاتف' : formatPhoneDisplay(phone),
                    if (groups > 0) '$groups شعبة',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subjects.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11),
                  ),
                ],
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
    final list = store.subjectsInViewedYear.where((s) {
      if (q.isEmpty) return true;
      return s.name.contains(q) ||
          s.code.toLowerCase().contains(q.toLowerCase()) ||
          subjectGradesLabel(s).contains(q) ||
          s.gradeLevels.any((g) => g.contains(q));
    }).toList();

    return Column(
      children: [
        _Toolbar(
          controller: search,
          hint: 'ابحث باسم المادة، الرمز، أو المرحلة...',
          shown: list.length,
          total: store.subjectsInViewedYear.length,
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: _cardList(
            count: list.length,
            empty: EmptyState(
              message: q.isEmpty
                  ? 'لا توجد مواد دراسية مسجلة.'
                  : 'لا توجد مواد مطابقة للبحث.',
            ),
            item: (context, i) => _SubjectCard(subject: list[i]),
          ),
        ),
      ],
    );
  }
}

/// مادة: اسمها، وتحته رمزها ومراحلها ووصفها، وعدد مدرّسيها في الطرف.
class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject});

  final SubjectItem subject;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = subject;
    final teachers = store.teachersInViewedYear
        .where((t) => t.subjectIds.contains(s.id) || t.subject == s.name)
        .length;

    return AppCard(
      onTap: () => _open(context, SubjectFormScreen(subject: s)),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                const SizedBox(height: 3),
                Text(
                  [
                    if (s.code.trim().isNotEmpty) s.code.trim(),
                    subjectGradesLabel(s),
                    if (s.description.trim().isNotEmpty) s.description.trim(),
                  ].where((x) => x.trim().isNotEmpty).join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
              ],
            ),
          ),
          if (teachers > 0) ...[
            const SizedBox(width: 10),
            Text(
              '$teachers مدرس',
              style: const TextStyle(color: AppColors.faint, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
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
            child: Icon(
              Icons.phonelink_lock_outlined,
              size: 19,
              color: AppColors.amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'المستخدم المثبَّت على هذا الجهاز',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  me == null ? 'لم يُثبَّت مستخدم بعد' : me.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
                if (me != null)
                  Text(
                    [
                      roleLabel(me.role),
                      if (label.isNotEmpty) 'المستلم على السند: $label',
                    ].join('  ·  '),
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
  const _UserCard({
    required this.user,
    required this.isThisDevice,
    required this.canDelete,
  });

  final AppUser user;
  final bool isThisDevice;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final tabs = effectiveSections(u.capabilities, u.role).length;

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
                        Flexible(
                          child: Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle,
                          ),
                        ),
                        if (isThisDevice) ...[
                          const SizedBox(width: 6),
                          StatusChip.success('هذا الجهاز'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${roleLabel(u.role)}  ·  $tabs تبويب',
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
                  onTap: () => _open(context, UserAccessScreen(user: u)),
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
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            12 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.phonelink_lock_outlined,
                      size: 18,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تثبيت «${u.name}» على هذا الجهاز',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.heading,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'اسمه يظهر مستلماً على السندات.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                const FieldLabel('اسم المستلم على سند القبض'),
                TextField(controller: label),
                const SizedBox(height: 12),
                const FieldLabel(
                  'كلمة مرور المدير الرئيسية',
                  requiredField: true,
                ),
                TextField(
                  controller: pass,
                  obscureText: true,
                  onChanged: (_) {
                    if (passError != null) setSt(() => passError = null);
                  },
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: 'مطلوبة لتثبيت أي مستخدم',
                    errorText: passError,
                  ),
                ),
                const SizedBox(height: 16),
                ActionButtons(
                  primary: PrimaryButton(
                    label: 'تثبيت على الجهاز',
                    icon: Icons.check,
                    height: 40,
                    onPressed: submit,
                  ),
                  secondary: GhostButton(
                    label: 'إلغاء',
                    onPressed: () => Navigator.pop(ctx),
                  ),
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
      ('الصفوف', store.roomsInViewedYear.length),
      ('المدرسون', store.teachersInViewedYear.length),
      ('المواد', store.subjectsInViewedYear.length),
      ('المقبوضات', store.payments.length),
      ('الأقساط', store.installments.length),
      ('الحضور', store.attendance.length),
      ('المراحل', store.gradeFeesInViewedYear.length),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        const FormSection(
          icon: Icons.cloud_sync_outlined,
          title: 'المزامنة مع السحابة',
        ),
        StatRow(
          children: [
            StatCard(
              label: 'بانتظار الرفع',
              value: '${store.pendingPush}',
              color: store.pendingPush > 0
                  ? AppColors.amber
                  : AppColors.success,
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

        const FormSection(
          icon: Icons.storage_outlined,
          title: 'البيانات المحلية على هذا الجهاز',
        ),
        _CountGrid(counts: counts),

        const FormSection(
          icon: Icons.backup_outlined,
          title: 'النسخ الاحتياطي',
        ),
        _NavTile(
          icon: Icons.download_outlined,
          title: 'تصدير نسخة احتياطية',
          subtitle: 'اختر أين تحفظ الملف على جهازك',
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
              _infoRow(
                'المنشأة',
                tenant?.name ??
                    (store.institutionName.isEmpty
                        ? '—'
                        : store.institutionName),
              ),
              _infoRow(
                'المعرّف',
                tenant?.code.isNotEmpty == true ? tenant!.code : '—',
              ),
              _infoRow('المستخدم على الجهاز', store.deviceUser?.name ?? '—'),
            ],
          ),
        ),
        if (store.can('settings')) ...[
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
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.heading,
            ),
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
              Expanded(
                child: j < slice.length
                    ? _cell(slice[j])
                    : const SizedBox.shrink(),
              ),
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
            child: Text(
              '${c.$2}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.heading,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              c.$1,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر يُفتح بلمسة: أيقونة في صندوق، وعنوان وشرح، وسهم الفتح.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
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
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
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
          ActionButtons(
            primaryFlex: 1,
            gap: 8,
            primary: PrimaryButton(
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
            secondary: GhostButton(
              label: 'تجاهل المتعثرة',
              icon: Icons.delete_outline,
              onPressed: () async {
                final ok = await confirmSheet(
                  context,
                  title: 'تجاهل العمليات المتعثرة',
                  message:
                      'سيتم إسقاط ${failed.length} عملية من طابور الرفع نهائياً. '
                      'التعديلات تبقى على هذا الجهاز لكنها لن تصل السحابة.',
                  confirmLabel: 'تجاهل',
                );
                if (!ok) return;
                for (final a in failed) {
                  store.sync.discardAction(a);
                }
                store.markAllDirty();
                if (!context.mounted) return;
                showAppSnack(
                  context,
                  'تم إسقاط ${failed.length} عملية متعثرة',
                );
              },
            ),
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
    final mobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    showAppSnack(
      context,
      mobile ? 'افتح ورقة المشاركة واختر مكان الحفظ' : 'تم حفظ النسخة: $path',
    );
  } catch (e) {
    if (!context.mounted) return;
    final msg = userMessage(e, 'تعذّر تصدير النسخة');
    if (msg.contains('أُلغي')) return;
    showAppSnack(context, msg, error: true);
  }
}

Future<void> _restore(BuildContext context, AppStore store) async {
  const service = BackupService();
  String? json;
  try {
    json = await service.pickFile();
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, userMessage(e, 'تعذّر فتح الملف'), error: true);
    return;
  }
  if (json == null || !context.mounted) return;

  Map decoded;
  Map<String, int> summary;
  try {
    decoded = jsonDecode(json) as Map;
    service.validateTenant(store, decoded);
    summary = service.summarize(json);
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, userMessage(e, 'ملف النسخة غير صالح'), error: true);
    return;
  }

  final total = summary.values.fold<int>(0, (a, b) => a + b);
  final lines = summary.entries
      .map((e) => '${tableLabelsAr[e.key] ?? e.key}: ${e.value}')
      .join('\n');
  final ok = await confirmSheet(
    context,
    title: 'استرجاع نسخة احتياطية',
    message:
        'سيتم دمج $total سجلاً في البيانات الحالية، وتسجيلها للرفع إلى السحابة.\n'
        'السجل الأحدث على الجهاز لا يُستبدل.\n\n$lines\n\nهل تريد المتابعة؟',
    confirmLabel: 'تنفيذ',
  );
  if (!ok || !context.mounted) return;

  try {
    final result = await service.restore(store, json);
    if (!context.mounted) return;
    final skipped = result.skipped > 0 ? '، وتُرك ${result.skipped} أحدث محلياً' : '';
    showAppSnack(context, 'تم استرجاع ${result.restored} سجلاً$skipped');
  } catch (e) {
    if (!context.mounted) return;
    showAppSnack(context, userMessage(e, 'فشل الاسترجاع'), error: true);
  }
}

/// قسم يُطوى بعنوانه — لتبويبٍ تكدّست بطاقاته فوق قائمته.
class _Collapsible extends StatefulWidget {
  const _Collapsible({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.faint,
                ),
              ],
            ),
          ),
        ),
        if (open) ...widget.children,
        Container(height: 1, color: AppColors.line),
      ],
    );
  }
}
