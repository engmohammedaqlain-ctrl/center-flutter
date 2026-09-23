import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/form_layout.dart';
import '../widgets/list_paging.dart';
import '../widgets/table_gate.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'expense_form_sheet.dart';
import 'payment_form_screen.dart';
import 'expense_voucher_screen.dart';
import 'general_income_sheet.dart';
import 'receipt_screen.dart';
import 'student_detail_screen.dart';

/// المالية والصندوق — بترتيب `pages/Finance.tsx` ومنطقه.
///
/// الملخص هو التبويبات كما في الويب: أربع بطاقات — المستحقات والمقبوضات
/// والمصروفات والطلبات — كلٌّ منها رقم الفترة وبابُ سجلّه. تحتها سطر ثابت:
/// البحث وزرّ تصفية واحد يجمع العام والفصل وفلاتر التبويب، ثم السجل في بطاقة
/// واحدة. الإجراء الأساسي زر الإبهام، والثانوي في رأس السجل.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

/// التبويبات بترتيب الويب.
enum _Tab { dues, payments, expenses, controls }

class _FinanceScreenState extends State<FinanceScreen> {
  _Tab tab = _Tab.dues;
  /// التنقّل بين الأقسام سحباً بالإصبع، لا بالضغط على المفتاح وحده
  final _pages = PageController();
  final search = TextEditingController();
  String method = '';
  String status = '';

  /// مصدر المقبوضات: '' الكل | students | other
  String sourceFilter = '';

  /// المقبوضات حسب سنة الدفع (متى قُبض) أو حسب سنة القسط (رسوم أي سنة سُدّدت).
  String paymentsBasis = 'payment';

  int visibleCount = kListPageSize;
  int auditVisible = kListPageSize;

  /// فلتر معلم في المصروفات (نسخه عبر الأعوام)
  String statementTeacherId = '';
  bool showProcessedRequests = false;
  String auditUserFilter = '';
  String auditActionFilter = '';

  /// فلتر سنة المالية المستقل عن العام المعروض: `current` | `all` | yearId
  String financeYearFilter = 'current';
  String termFilter = 'all';

  static const _statusOptions = {
    '': 'كل الحالات',
    'active': 'مقبوضة',
    'cancelled': 'ملغاة',
  };

  String _resolvedFinanceYearId(AppStore store) {
    if (financeYearFilter == 'all') return '';
    if (financeYearFilter == 'current') {
      return store.operationalAcademicYear?.id ?? store.viewedAcademicYearId;
    }
    return financeYearFilter;
  }

  AcademicYear? _filterYear(AppStore store) {
    final id = _resolvedFinanceYearId(store);
    if (id.isEmpty) return null;
    return store.academicYears.where((y) => y.id == id).firstOrNull;
  }

  bool _matchesFinancePeriod(
    AppStore store, {
    String? yearId,
    String? dueDate,
    String? paymentDate,
  }) {
    final resolved = _resolvedFinanceYearId(store);
    final year = _filterYear(store);
    if (financeYearFilter != 'all' && resolved.isNotEmpty) {
      if (yearId != null && yearId.isNotEmpty) {
        if (yearId != resolved) return false;
      } else {
        final d = (dueDate ?? paymentDate ?? '').split('T').first;
        if (year != null && d.isNotEmpty) {
          if (d.compareTo(year.startsOn) < 0 || d.compareTo(year.endsOn) > 0) {
            return false;
          }
        }
      }
    }
    if (termFilter != 'all' && year != null) {
      final d = (dueDate ?? paymentDate ?? '').split('T').first;
      if (!_dueDateInTerm(d, year, termFilter)) return false;
    }
    return true;
  }

  bool _dueDateInTerm(String date, AcademicYear year, String term) {
    if (date.isEmpty) return true;
    if (term == 'term_1') {
      final start = year.term1Start.isNotEmpty ? year.term1Start : year.startsOn;
      final end = year.term1End.isNotEmpty ? year.term1End : year.endsOn;
      return date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
    }
    if (term == 'term_2') {
      final start = year.term2Start.isNotEmpty ? year.term2Start : year.startsOn;
      final end = year.term2End.isNotEmpty ? year.term2End : year.endsOn;
      return date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
    }
    return true;
  }

  /// سندات الفترة بسنة دفعها — أساس «المقبوضات» في البطاقة والصافي.
  List<Payment> _periodPayments(AppStore store) {
    return store.payments
        .where((p) => _matchesFinancePeriod(store, yearId: p.academicYearId, paymentDate: isoDate(p.date)))
        .toList();
  }

  /// المصروفات التشغيلية بتاريخها ضمن السنة والفصل — كما في الويب.
  List<Expense> _periodExpenses(AppStore store) =>
      store.expenses.where((e) => _matchesFinancePeriod(store, paymentDate: e.expenseDate)).toList();

  /// الرواتب بشهرها لا بيوم صرفها.
  List<TeacherPayout> _periodPayouts(AppStore store) => store.teacherPayouts
      .where((p) => _matchesFinancePeriod(
            store,
            paymentDate: p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate,
          ))
      .toList();

  /// صافي الفترة: المقبوض فعلاً (بتاريخ قبضه) ناقص المصروفات والرواتب.
  ({double received, double spent, double net}) _periodNet(AppStore store) {
    final received = _periodPayments(store).where((p) => !p.cancelled).fold<double>(0, (a, p) => a + p.amount);
    final spent = _periodExpenses(store).fold<double>(0, (a, e) => a + e.amount) +
        _periodPayouts(store).fold<double>(0, (a, p) => a + p.amount);
    return (received: received, spent: spent, net: received - spent);
  }

  @override
  void dispose() {
    _pages.dispose();
    search.dispose();
    super.dispose();
  }

  /// الأقسام بترتيبها — فهرس القسم هو رقم صفحته في السحب.
  List<_Tab> _visibleTabs(bool showExpenses) => [
        _Tab.dues,
        _Tab.payments,
        if (showExpenses) _Tab.expenses,
        _Tab.controls,
      ];

  void _openTab(_Tab next) {
    if (tab == next) return;
    setState(() {
      tab = next;
      // لكل تبويب بحثه: نص يبحث عن وصل لا معنى له في المستحقات
      search.clear();
      visibleCount = kListPageSize;
      auditVisible = kListPageSize;
    });
  }

  ({Widget? toolbar, List<Widget> slivers}) _bodyOf(
    _Tab which,
    BuildContext context,
    AppStore store,
    List<DueItem> allDues,
    String q,
  ) =>
      switch (which) {
        _Tab.payments => _payments(context, store, q),
        _Tab.expenses => _expenses(store, q),
        _Tab.controls => (toolbar: null, slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              sliver: SliverList(delegate: SliverChildListDelegate(_controls(context, store))),
            ),
          ]),
        _Tab.dues => _dues(context, store, allDues, q),
      };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return TableGate(
      tables: const ['payments', 'installments', 'expenses', 'teacher_payouts'],
      message: 'جارٍ تحميل المالية...',
      child: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('finance')) {
          return NoAccess(section: 'finance', roleName: store.roleName);
        }

        // التبويب يتبع الميزة والصلاحية كما في Finance.tsx
        final showExpenses = store.features.enableExpenses && store.can('finance.expenses');
        if (tab == _Tab.expenses && !showExpenses) tab = _Tab.dues;

        final q = search.text.trim().toLowerCase();
        // المستحقات تُحسب لتبويب المستحقات فقط — لا في كل تبديل
        final List<DueItem> allDues;
        if (tab == _Tab.dues) {
          final byId = <String, Installment>{
            for (final i in store.installments) i.id: i,
          };
          allDues = store.dueItems().where((d) {
            final inst = d.installmentId == null ? null : byId[d.installmentId!];
            return _matchesFinancePeriod(
              store,
              yearId: inst?.academicYearId,
              dueDate: isoDate(d.dueDate),
            );
          }).toList();
        } else {
          allDues = const [];
        }

        // صافي الفترة للتبويبات التي تعرضه فقط
        final net = (tab == _Tab.payments || tab == _Tab.expenses)
            ? _periodNet(store)
            : (received: 0.0, spent: 0.0, net: 0.0);

        // زر «+» واحد يفتح ورقة تختار منها العملية، بدل أزرار ثانوية متفرقة
        final ThumbAction? action = switch (tab) {
          _Tab.expenses => store.can('finance.expenses')
              ? ThumbAction(
                  label: 'صرف جديد',
                  icon: Icons.add,
                  color: AppColors.navy,
                  onPressed: () => _showActions(context, 'صرف جديد', [
                    (
                      icon: Icons.receipt_long_outlined,
                      label: 'إضافة سند صرف',
                      color: AppColors.heading,
                      onTap: () async {
                        final saved = await showExpenseSheet(context, store);
                        if (saved && context.mounted) showAppSnack(context, 'تم حفظ سند الصرف');
                      },
                    ),
                    (
                      icon: Icons.payments_outlined,
                      label: 'صرف رواتب',
                      color: AppColors.heading,
                      onTap: () async {
                        final count = await showPayrollSheet(context, store, month: monthKeyOf(DateTime.now()));
                        if (count > 0 && context.mounted) showAppSnack(context, 'صُرفت رواتب $count معلماً');
                      },
                    ),
                  ]),
                )
              : null,
          // المستحقات: التسديد وحده هو المقصود منها
          _Tab.dues => store.can('finance.collect')
              ? ThumbAction(
                  label: 'تسديد دفعة',
                  icon: Icons.add_card,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PaymentFormScreen()),
                  ),
                )
              : null,
          _Tab.controls => null,
          _ => store.can('finance.collect')
              ? ThumbAction(
                  label: 'قبض جديد',
                  icon: Icons.add,
                  onPressed: () => _showActions(context, 'قبض جديد', [
                    (
                      icon: Icons.add_card,
                      label: 'تسديد دفعة',
                      color: AppColors.heading,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PaymentFormScreen()),
                      ),
                    ),
                    (
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'قبض من غير طالب',
                      color: AppColors.heading,
                      onTap: () async {
                        final saved = await showGeneralIncomeSheet(context, store);
                        if (saved && context.mounted) showAppSnack(context, 'تم حفظ الإيراد وإصدار السند');
                      },
                    ),
                  ]),
                )
              : null,
        };

        final tabs = _visibleTabs(showExpenses);
        final index = tabs.indexOf(tab).clamp(0, tabs.length - 1);
        // تبديل فوري بلا أنيميشن صفحي يبني صفحتين معاً
        if (_pages.hasClients && (_pages.page ?? index).round() != index) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pages.hasClients) return;
            _pages.jumpToPage(index);
          });
        }
        final hero = _hero(store, allDues, net, showExpenses);

        return ThumbActionLayer(
          action: action,
          child: Column(
            children: [
              _segments(store, showExpenses),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: tabs.length,
                  onPageChanged: (i) => _openTab(tabs[i]),
                  itemBuilder: (context, i) {
                    if (tabs[i] != tab) {
                      return const SizedBox.shrink();
                    }
                    final body = _bodyOf(tabs[i], context, store, allDues, q);
                    return CustomScrollView(
                      slivers: [
                        // الكارد الكبيرة تمرّ مع السجل؛ البحث والفلترة وحدهما مثبتان
                        if (hero != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
                              child: hero,
                            ),
                          ),
                        if (body.toolbar != null)
                          SliverPersistentHeader(pinned: true, delegate: _PinnedBar(child: body.toolbar!)),
                        ...body.slivers,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  // ── الأقسام والملخص ──────────────────────────────────────────────────────

  Widget _segments(AppStore store, bool showExpenses) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: _Segmented(
        selected: tab,
        onSelect: _openTab,
        items: [
          (_Tab.dues, 'المستحقات', 0),
          (_Tab.payments, 'المقبوضات', 0),
          if (showExpenses) (_Tab.expenses, 'المصروفات', 0),
          (_Tab.controls, 'الرقابة', store.pendingFinanceRequests.length),
        ],
      ),
    );
  }

  /// بطاقة القسم المفتوح: رقمه الرئيسي كبيراً وتفاصيله شرائح. الرقابة سجلّ
  /// طلبات لا رقم فيه، فلا بطاقة لها.
  Widget? _hero(
    AppStore store,
    List<DueItem> dues,
    ({double received, double spent, double net}) net,
    bool showExpenses,
  ) {
    final period = _periodLabel(store);
    switch (tab) {
      case _Tab.dues:
        final owed = dues.where((d) => !d.scheduled).toList();
        final debtors = owed.map((d) => d.student.id).toSet().length;
        return _Hero(
          tab: tab,
          label: 'إجمالي المستحق',
          value: money(owed.fold<double>(0, (a, d) => a + d.amount)),
          period: period,
          onPeriod: () => _openFilters(store),
          chips: ['$debtors طالب', 'قادم ${money(store.projectRemainingYear())}'],
        );
      case _Tab.payments:
        return _Hero(
          tab: tab,
          label: 'المقبوض في الفترة',
          value: money(net.received),
          period: period,
          onPeriod: () => _openFilters(store),
          chips: [
            '${_periodPayments(store).length} سند',
            if (showExpenses) 'الصافي ${net.net < 0 ? '-' : ''}${money(net.net)}',
          ],
        );
      case _Tab.controls:
        return null;
      case _Tab.expenses:
        return _Hero(
          tab: tab,
          label: 'المصروف في الفترة',
          value: money(net.spent),
          period: period,
          onPeriod: () => _openFilters(store),
          chips: ['${_periodExpenses(store).length} تشغيلية', '${_periodPayouts(store).length} رواتب'],
        );
    }
  }

  String _periodLabel(AppStore store) {
    final year = switch (financeYearFilter) {
      'current' => 'عام التشغيل',
      'all' => 'كل الأعوام',
      _ => store.academicYears.where((y) => y.id == financeYearFilter).firstOrNull?.label ?? 'عام',
    };
    final term = switch (termFilter) {
      'term_1' => 'الفصل الأول',
      'term_2' => 'الفصل الثاني',
      _ => null,
    };
    return term == null ? year : '$year · $term';
  }

  // ── البحث والتصفية ───────────────────────────────────────────────────────

  /// عدد الفلاتر المختلفة عن الافتراضي في التبويب الحالي.
  int get _activeFilters {
    var n = 0;
    if (financeYearFilter != 'current') n++;
    if (termFilter != 'all') n++;
    switch (tab) {
      case _Tab.dues:
        break;
      case _Tab.payments:
        n += [method, status, sourceFilter].where((v) => v.isNotEmpty).length;
        if (paymentsBasis != 'payment') n++;
      case _Tab.expenses:
        if (statementTeacherId.isNotEmpty) n++;
      case _Tab.controls:
        break;
    }
    return n;
  }

  Widget _toolbar({required String hint, required int shown, required int total, required AppStore store}) {
    return Row(
      children: [
        Expanded(
          child: SearchField(
            controller: search,
            hint: hint,
            onChanged: (_) => setState(() => visibleCount = kListPageSize),
            trailing: Text(
              shown == total ? '$total' : '$shown/$total',
              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _FiltersButton(count: _activeFilters, onTap: () => _openFilters(store)),
      ],
    );
  }

  /// ورقة التصفية: العام والفصل لكل التبويبات، ثم فلاتر التبويب نفسه.
  Future<void> _openFilters(AppStore store) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void pick(VoidCallback change) {
            setState(change);
            setSheet(() {});
          }

          // ثلاثة خيارات فأقل: مفتاح مقسّم بسطر واحد؛ وأكثر: شرائح تتمرّر أفقياً
          Widget group(String title, Map<String, String> options, String value, ValueChanged<String> onPick) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (options.length <= 3)
                    _FilterSegment(options: options, value: value, onPick: (v) => pick(() => onPick(v)))
                  else
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final e in options.entries)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: _Pill(
                                label: e.value,
                                selected: e.key == value,
                                onTap: () => pick(() => onPick(e.key)),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // مقبض السحب — الورقة تُغلق بالسحب لأسفل
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 12, 10),
                    child: Row(
                      children: [
                        Expanded(child: Text('تصفية', style: AppText.cardTitle.copyWith(fontSize: 16))),
                        if (_activeFilters > 0)
                          TextButton(
                            onPressed: () => pick(_clearFilters),
                            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                            child: const Text('إعادة الضبط', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      children: [
                        group(
                          'العام الدراسي',
                          {
                            'current': 'عام التشغيل',
                            'all': 'كل الأعوام',
                            for (final y in store.academicYears) y.id: y.label,
                          },
                          financeYearFilter,
                          (v) => financeYearFilter = v,
                        ),
                        group(
                          'الفصل',
                          const {'all': 'كل الفصول', 'term_1': 'الفصل الأول', 'term_2': 'الفصل الثاني'},
                          termFilter,
                          (v) => termFilter = v,
                        ),
                        if (tab == _Tab.payments) ...[
                          group('الحالة', _statusOptions, status, (v) => status = v),
                          group(
                            'طريقة الدفع',
                            {'': 'الكل', for (final m in store.paymentMethods) m.id: m.name},
                            method,
                            (v) => method = v,
                          ),
                          group(
                            'المصدر',
                            const {'': 'الكل', 'students': 'الطلاب', 'other': 'إيرادات أخرى'},
                            sourceFilter,
                            (v) => sourceFilter = v,
                          ),
                          group(
                            'السنة المحتسبة',
                            const {'payment': 'حسب سنة الدفع', 'installment': 'حسب سنة الرسوم'},
                            paymentsBasis,
                            (v) => paymentsBasis = v,
                          ),
                        ],
                        if (tab == _Tab.expenses)
                          group(
                            'المعلم',
                            {'': 'كل المعلمين', for (final t in store.teachersInViewedYear) t.id: t.name},
                            statementTeacherId,
                            (v) => statementTeacherId = v,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: PrimaryButton(label: 'تم', expand: true, height: 46, onPressed: () => Navigator.pop(ctx)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _clearFilters() {
    financeYearFilter = 'current';
    termFilter = 'all';
    method = '';
    status = '';
    sourceFilter = '';
    paymentsBasis = 'payment';
    statementTeacherId = '';
    visibleCount = kListPageSize;
    auditVisible = kListPageSize;
  }

  /// سجل مجمّع بالتاريخ كتطبيقات البنوك: عنوان لكل مجموعة بمجموعها، وتحته
  /// بطاقتها. العناصر مرتّبة سلفاً فتتجاور عناصر المجموعة الواحدة.
  /// تُعرض أول [visibleCount] بنداً فقط مع زر المزيد تحتها.
  List<Widget> _listSlivers<T>({
    Widget? header,
    required List<T> items,
    required String emptyMessage,
    required String Function(T) groupOf,
    required double Function(T) amountOf,
    required Widget Function(BuildContext, T) row,
  }) {
    final page = listPage(items, visibleCount);
    // مدخلات القائمة: عنوان مجموعة أو صف بموضعه فيها
    final entries = <({String? title, double total, T? item, bool first, bool last})>[];
    for (var i = 0; i < page.length; i++) {
      final g = groupOf(page[i]);
      final first = i == 0 || groupOf(page[i - 1]) != g;
      final last = i == page.length - 1 || groupOf(page[i + 1]) != g;
      if (first) {
        var total = 0.0;
        for (var j = i; j < page.length && groupOf(page[j]) == g; j++) {
          total += amountOf(page[j]);
        }
        entries.add((title: g, total: total, item: null, first: false, last: false));
      }
      entries.add((title: null, total: 0, item: page[i], first: first, last: last));
    }

    return [
      if (header != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          sliver: SliverToBoxAdapter(child: header),
        ),
      if (items.isEmpty)
        SliverToBoxAdapter(child: SizedBox(height: 200, child: EmptyState(message: emptyMessage)))
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          sliver: SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              if (e.title != null) return _GroupHeader(title: e.title!, total: e.total);
              const r = Radius.circular(14);
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: e.first ? r : Radius.zero,
                    bottom: e.last ? r : Radius.zero,
                  ),
                  boxShadow: const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 3))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!e.first) const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: AppColors.hover),
                    row(context, e.item as T),
                  ],
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, thumbActionClearance),
            child: LoadMoreButton(
              shown: page.length,
              total: items.length,
              onMore: () => setState(() => visibleCount += kListPageSize),
            ),
          ),
        ),
      ],
    ];
  }

  // ── المستحقات ─────────────────────────────────────────────────────────────

  ({Widget? toolbar, List<Widget> slivers}) _dues(
    BuildContext context,
    AppStore store,
    List<DueItem> all,
    String q,
  ) {
    final dues = all.where((d) {
      final matchQ = q.isEmpty ||
          d.student.fullName.toLowerCase().contains(q) ||
          d.student.phone.contains(q) ||
          d.title.toLowerCase().contains(q);
      return matchQ;
    }).toList();

    // بتاريخ الاستحقاق كما في الويب، فتتجاور بنود الشهر الواحد
    dues.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final canCollect = store.can('finance.collect');
    final canOpenStudent = store.can('students');

    return (
      toolbar: _toolbar(hint: 'اسم الطالب أو الهاتف', shown: dues.length, total: all.length, store: store),
      slivers: _listSlivers(
        items: dues,
        emptyMessage: 'لا مستحقات',
        groupOf: (d) => _monthLabel(d.dueDate),
        amountOf: (d) => d.amount,
        row: (context, d) {
          return _DueCard(
            item: d,
            onOpen: canOpenStudent
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: d.student.id)),
                    )
                : null,
            onPay: canCollect
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PaymentFormScreen(
                          studentId: d.student.id,
                          installmentId: d.installmentId,
                          amount: d.amount,
                        ),
                      ),
                    )
                : null,
          );
        },
      ),
    );
  }

  // ── المقبوضات ─────────────────────────────────────────────────────────────

  ({Widget? toolbar, List<Widget> slivers}) _payments(BuildContext context, AppStore store, String q) {
    // «حسب سنة الرسوم»: السند المربوط بقسط يُنسب لسنة قسطه (دين العام الماضي
    // المدفوع اليوم يُحسب على العام الماضي)، والدفعة غير المربوطة بسنة دفعها
    final installmentById = paymentsBasis == 'installment' ? {for (final i in store.installments) i.id: i} : null;
    bool inPeriod(Payment p) {
      final inst = installmentById?[p.installmentId];
      if (inst != null) {
        return _matchesFinancePeriod(store, yearId: inst.academicYearId, dueDate: isoDate(inst.dueDate));
      }
      return _matchesFinancePeriod(store, yearId: p.academicYearId, paymentDate: isoDate(p.date));
    }

    final periodPays = store.payments.where(inPeriod).toList();
    final pays = periodPays.where((p) {
      final name = (store.studentById(p.studentId)?.fullName ?? '${p.payerName} ${p.incomeCategory}').toLowerCase();
      // البحث يشمل البيان والمحوِّل وجهة التحويل، كما في Finance.tsx
      final matchQ = q.isEmpty ||
          p.receiptNumber.toLowerCase().contains(q) ||
          name.contains(q) ||
          p.reference.toLowerCase().contains(q) ||
          p.notes.toLowerCase().contains(q) ||
          p.senderName.toLowerCase().contains(q) ||
          p.channel.toLowerCase().contains(q);
      final matchM = method.isEmpty || p.method == method;
      final matchS = status.isEmpty || (status == 'active' && !p.cancelled) || (status == 'cancelled' && p.cancelled);
      final matchSource = sourceFilter.isEmpty ||
          (sourceFilter == 'students' && p.studentId.isNotEmpty) ||
          (sourceFilter == 'other' && p.studentId.isEmpty);
      return matchQ && matchM && matchS && matchSource;
    }).toList();
    sortPayments(pays);

    // رسوم الفترة بحسب سنة الرسوم: المطلوب منها وما سُدّد وما بقي
    Widget? feesLine;
    if (paymentsBasis == 'installment' && financeYearFilter != 'all') {
      final insts = store.installments.where(
        (i) => _matchesFinancePeriod(store, yearId: i.academicYearId, dueDate: isoDate(i.dueDate)),
      );
      final required = insts.fold<double>(0, (a, i) => a + i.chargeable);
      final paid = insts.fold<double>(0, (a, i) => a + i.paidAmount);
      feesLine = _ListHeader(
        parts: [
          ('رسوم الفترة: مطلوب ${money(required)}', AppColors.muted),
          ('مسدَّد ${money(paid)}', AppColors.success),
          ('باقٍ ${money(math.max(0, required - paid))}', AppColors.danger),
        ],
      );
    }

    return (
      toolbar: _toolbar(hint: 'اسم أو رقم وصل', shown: pays.length, total: periodPays.length, store: store),
      slivers: _listSlivers(
        // سطر «رسوم الفترة» وحده يبقى، حين يُحتسب المقبوض بسنة الرسوم
        header: feesLine,
        items: pays,
        emptyMessage: 'لا نتائج',
        groupOf: (p) => _dayLabel(p.date),
        amountOf: (p) => p.cancelled ? 0 : p.amount,
        row: (context, p) {
          final income = p.studentId.isEmpty ? store.generalIncomes.where((g) => g.id == p.id).firstOrNull : null;
          return _PaymentCard(
            payment: p,
            student: store.studentById(p.studentId),
            onCancel: _canCancelPayment(p) ? () => _cancel(context, store, p) : null,
            onEdit: income != null && !p.cancelled && store.can('finance.collect')
                ? () => showGeneralIncomeSheet(context, store, income: income)
                : null,
          );
        },
      ),
    );
  }

  // ── المصروفات وأجور المعلمين ──────────────────────────────────────────────

  /// سجل موحّد للمصروفات وأجور المعلمين في الفترة، مرتّب بالتاريخ تنازلياً —
  /// نفس دمج القائمتين في جدول واحد في Finance.tsx. اختيار معلم يقصره على ما صُرف له.
  ({Widget? toolbar, List<Widget> slivers}) _expenses(AppStore store, String q) {
    final linked = statementTeacherId.isEmpty ? null : store.linkedTeacherIds(statementTeacherId);
    final expenses = linked == null ? _periodExpenses(store) : <Expense>[];
    final payouts = [
      for (final p in _periodPayouts(store))
        if (linked == null || linked.contains(p.teacherId)) p,
    ];
    final all = <_SpendRow>[
      for (final e in expenses)
        _SpendRow(
          date: e.expenseDate,
          isPayout: false,
          category: expenseCategoryLabel(e.category),
          description: e.description,
          amount: e.amount,
          method: e.method,
          voucher: ExpenseVoucher.fromExpense(e),
        ),
      for (final p in payouts)
        _SpendRow(
          date: p.paymentDate,
          isPayout: true,
          category: payoutExpenseCategory,
          description: payoutDescription(p, fallbackName: store.teacherById(p.teacherId)?.name ?? ''),
          amount: p.amount,
          method: p.method,
          voucher: ExpenseVoucher.fromPayout(p, fallbackName: store.teacherById(p.teacherId)?.name ?? ''),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final rows = q.isEmpty
        ? all
        : all.where((r) => r.description.toLowerCase().contains(q) || r.category.toLowerCase().contains(q)).toList();

    return (
      toolbar: _toolbar(hint: 'ابحث في البيان', shown: rows.length, total: all.length, store: store),
      slivers: _listSlivers(
        items: rows,
        emptyMessage: 'لا مصروفات',
        groupOf: (r) {
          final d = parseIsoDate(r.date.length >= 10 ? r.date.substring(0, 10) : r.date);
          return d == null ? r.date : _dayLabel(d);
        },
        amountOf: (r) => r.amount,
        row: (context, r) => _SpendCard(row: r),
      ),
    );
  }

  /// هل يظهر زر الإلغاء/العكس — مطابق لمنطق Finance.tsx.
  bool _canCancelPayment(Payment p) {
    if (p.cancelled || p.reversedByPaymentId != null) return false;
    final sameDay = dateOnly(p.date) == dateOnly(DateTime.now());
    // سند سالب (رد/عكس) من يوم سابق لا يُبطَل من الواجهة
    if (p.amount < 0 && !sameDay) return false;
    return true;
  }

  Future<void> _cancel(BuildContext context, AppStore store, Payment p) async {
    final sameDay = dateOnly(p.date) == dateOnly(DateTime.now());
    final reason = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sameDay ? 'إلغاء السند' : 'عكس السند',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sameDay
                  ? 'سند اليوم يُلغى ولا يدخل تقرير اليوم.'
                  : 'السند من يوم سابق: سيصدر سند عكس سالب بتاريخ اليوم، ولن يتغير تقرير يومه.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'السبب (إجباري)'),
            ),
            const SizedBox(height: 12),
            if (!store.can('finance.cancel')) ...[
              Text(
                'لا تملك صلاحية الإلغاء: سيُرسل طلباً للمدير ولا يتغير السند حتى يوافق.',
                style: TextStyle(color: AppColors.amberDark, fontSize: 10.5),
              ),
              const SizedBox(height: 8),
            ],
            PrimaryButton(
              label: !store.can('finance.cancel')
                  ? 'إرسال للمدير'
                  : sameDay
                  ? 'تأكيد الإلغاء'
                  : 'إصدار سند العكس',
              color: AppColors.danger,
              onPressed: () {
                if (reason.text.trim().isEmpty) {
                  showAppSnack(ctx, 'اكتب سبب الإلغاء أو العكس', error: true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) {
      reason.dispose();
      return;
    }
    try {
      if (store.can('finance.cancel')) {
        store.voidPayment(p, reason.text);
      } else {
        store.submitFinanceRequest(
          kind: 'payment_cancel',
          summary:
              '${sameDay ? 'إلغاء' : 'عكس'} السند ${p.receiptNumber} (${money(p.amount)})',
          studentId: p.studentId,
          targetId: p.id,
          payload: const {},
          amount: p.amount,
          reason: reason.text,
        );
      }
      showAppSnack(
        context,
        store.can('finance.cancel')
            ? (sameDay ? 'تم إلغاء السند' : 'تم إصدار سند العكس بتاريخ اليوم')
            : 'أُرسل الطلب للمدير',
      );
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    } finally {
      reason.dispose();
    }
  }


  Future<void> _rejectFinanceRequest(
    BuildContext context,
    AppStore store,
    FinanceRequest request,
  ) async {
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'رفض الطلب',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'سبب الرفض (يراه الموظف)',
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'تأكيد الرفض',
              color: AppColors.danger,
              onPressed: () {
                if (note.text.trim().isEmpty) {
                  showAppSnack(ctx, 'اكتب سبب الرفض', error: true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      store.rejectFinanceRequest(request.id, note.text);
    }
    note.dispose();
  }

  /// تبويب الطلبات والرقابة — المقابل لـ `FinanceControlPanel.tsx`.
  List<Widget> _controls(BuildContext context, AppStore store) {
    final pending = store.pendingFinanceRequests;
    final done = store.financeRequests
        .where((r) => r.status != 'pending')
        .toList()
      ..sort((a, b) => (b.updatedAt ?? b.createdAt ?? '')
          .compareTo(a.updatedAt ?? a.createdAt ?? ''));
    final auditUsers = {
      for (final a in store.financeAudit)
        if (a.userName.trim().isNotEmpty) a.userName,
    }.toList()
      ..sort();
    final audit = store.financeAudit.where((a) {
      if (auditUserFilter.isNotEmpty && a.userName != auditUserFilter) {
        return false;
      }
      if (auditActionFilter.isNotEmpty && a.action != auditActionFilter) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final auditPage = listPage(audit, auditVisible);

    Widget requestCard(FinanceRequest request) {
      final pendingRow = request.status == 'pending';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [
                  financeRequestLabel(request.kind),
                  if (request.studentName.isNotEmpty) request.studentName,
                ].join(' — '),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                request.summary,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  'السبب: ${request.reason}',
                  if (request.requestedByName.isNotEmpty)
                    'من ${request.requestedByName}',
                  if ((request.createdAt ?? '').isNotEmpty)
                    (request.createdAt ?? '').split('T').first,
                ].join('  ·  '),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
              if (!pendingRow) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    request.status == 'approved' ? 'وافق' : 'رفض',
                    if (request.decidedByName.isNotEmpty) request.decidedByName,
                    if ((request.decidedAt ?? '').isNotEmpty)
                      (request.decidedAt ?? '').split('T').first,
                    if (request.decisionNote.isNotEmpty)
                      '— ${request.decisionNote}',
                  ].join(' '),
                  style: TextStyle(
                    color: request.status == 'approved'
                        ? AppColors.success
                        : AppColors.danger,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (pendingRow) ...[
                const SizedBox(height: 9),
                if (store.isFinanceAdmin)
                  ActionButtons(
                    primaryFlex: 1,
                    gap: 8,
                    primary: PrimaryButton(
                      label: 'موافقة وتنفيذ',
                      color: AppColors.success,
                      onPressed: () {
                        try {
                          store.approveFinanceRequest(request.id);
                        } on StoreException catch (e) {
                          showAppSnack(context, e.message, error: true);
                        }
                      },
                    ),
                    secondary: GhostButton(
                      label: 'رفض',
                      onPressed: () =>
                          _rejectFinanceRequest(context, store, request),
                    ),
                  )
                else
                  Text(
                    'بانتظار المدير',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: AppColors.amberDark,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return [
        Text(
          'طلبات بانتظار الموافقة (${pending.length})',
          style: TextStyle(
            color: AppColors.heading,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'لا طلبات معلّقة',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          )
        else
          for (final r in pending) requestCard(r),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () =>
                setState(() => showProcessedRequests = !showProcessedRequests),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: AlignmentDirectional.centerStart,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
            child: Text(
              showProcessedRequests
                  ? 'إخفاء الطلبات المُعالجة (${done.length})'
                  : 'عرض الطلبات المُعالجة (${done.length})',
            ),
          ),
          if (showProcessedRequests)
            for (final r in done) requestCard(r),
        ],
        if (store.isFinanceAdmin) ...[
          const SizedBox(height: 16),
          Text(
            'سجل الحركات الحساسة',
            style: TextStyle(
              color: AppColors.heading,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppDropdown<String>(
                  value: auditUserFilter.isEmpty ? null : auditUserFilter,
                  hint: 'كل الموظفين',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('كل الموظفين')),
                    for (final u in auditUsers)
                      DropdownMenuItem(value: u, child: Text(u)),
                  ],
                  onChanged: (v) =>
                      setState(() {
                        auditUserFilter = v ?? '';
                        auditVisible = kListPageSize;
                      }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppDropdown<String>(
                  value: auditActionFilter.isEmpty ? null : auditActionFilter,
                  hint: 'كل الحركات',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('كل الحركات')),
                    for (final e in financeAuditActionLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) =>
                      setState(() {
                        auditActionFilter = v ?? '';
                        auditVisible = kListPageSize;
                      }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (audit.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'لا حركات',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            )
          else ...[
            for (final a in auditPage)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.all(11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              financeAuditActionLabel(a.action),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: AppColors.heading,
                              ),
                            ),
                          ),
                          if (a.amount != null)
                            Text(
                              money(a.amount!),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (a.userName.isNotEmpty) a.userName,
                          if ((a.createdAt ?? '').isNotEmpty)
                            (a.createdAt ?? '').replaceFirst('T', ' ').split('.').first,
                        ].join('  ·  '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10.5,
                        ),
                      ),
                      if (a.studentName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          a.studentName,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        a.summary,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                      if (a.reason.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'السبب: ${a.reason}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            LoadMoreButton(
              shown: auditPage.length,
              total: audit.length,
              onMore: () => setState(() => auditVisible += kListPageSize),
            ),
          ],
        ],
    ];
  }
}

// ═══ عناصر الشاشة ═══════════════════════════════════════════════════════════

/// بطاقة ملخص هي تبويب في الوقت نفسه: اسم القسم ورقمه وسطر تحته. المختارة
/// بيضاء بإطار داكن، والبقية على خلفية هادئة — كبطاقات الويب.
/// مفتاح الأقسام المقسّم: مسار هادئ والقسم المفتوح بطاقة بيضاء تنزلق إليه.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.items, required this.selected, required this.onSelect});

  final List<(_Tab, String, int)> items;
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((e) => e.$1 == selected).clamp(0, items.length - 1);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                width: w,
                left: rtl ? box.maxWidth - w * (index + 1) : w * index,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (value, label, badge) in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(value),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    style: TextStyle(
                                      fontFamily: AppText.family,
                                      fontSize: 12.5,
                                      fontWeight: value == selected ? FontWeight.w600 : FontWeight.w600,
                                      color: value == selected ? AppColors.heading : AppColors.muted,
                                    ),
                                    child: Text(label, maxLines: 1),
                                  ),
                                  if (badge > 0) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      constraints: const BoxConstraints(minWidth: 16),
                                      height: 16,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.warn,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$badge',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// لون كل قسم في بطاقة الملخص — درجات عميقة هادئة لا فاقعة، ليُعرف القسم
/// من لونه قبل قراءة عنوانه.
({List<Color> colors, IconData icon}) _toneOf(_Tab tab) => switch (tab) {
      _Tab.dues => (
          colors: const [Color(0xFF5B1A24), Color(0xFF8C3441)],
          icon: Icons.pending_actions_rounded,
        ),
      _Tab.payments => (
          colors: const [Color(0xFF0F4A34), Color(0xFF1E7651)],
          icon: Icons.south_west_rounded,
        ),
      _Tab.expenses || _Tab.controls => (
          colors: const [Color(0xFF1E2A44), Color(0xFF3A4C72)],
          icon: Icons.north_east_rounded,
        ),
    };

/// ملخّص القسم: بطاقة بلون قسمها، الرقم الرئيسي بالأبيض وتفاصيله شرائح شفافة.
/// الانتقال بين الأقسام يمزج اللون ويحرّك الزخرفة ويبدّل الرقم بسلاسة.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.tab,
    required this.label,
    required this.value,
    required this.chips,
    this.period,
    this.onPeriod,
  });

  final _Tab tab;
  final String label;
  final String value;
  final List<String> chips;
  final String? period;
  final VoidCallback? onPeriod;

  @override
  Widget build(BuildContext context) {
    final tone = _toneOf(tab);
    final i = tab.index;
    return Container(
      key: const ValueKey('finance-hero'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadiusDirectional.only(
          topStart: Radius.circular(i.isEven ? 20 : 12),
          topEnd: Radius.circular(i.isEven ? 12 : 20),
          bottomStart: Radius.circular(i.isEven ? 12 : 20),
          bottomEnd: Radius.circular(i.isEven ? 20 : 12),
        ),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: tone.colors,
        ),
        boxShadow: [
          BoxShadow(color: tone.colors.first.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -40.0 + i * 30,
            top: -60.0 + i * 12,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          PositionedDirectional(
            end: 70.0 - i * 18,
            bottom: -70.0 + i * 8,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          PositionedDirectional(
            end: 14,
            bottom: 10,
            child: Icon(tone.icon, key: ValueKey(tab), size: 46, color: Colors.white.withValues(alpha: 0.14)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (period != null) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: PressableScale(
                          onTap: onPeriod,
                          child: Container(
                            height: 26,
                            padding: const EdgeInsetsDirectional.fromSTEB(9, 0, 5, 0),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    period!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: AppText.family,
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.expand_more_rounded, size: 16, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  key: ValueKey('$tab|$value'),
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: AppText.family,
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in chips)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(
                            fontFamily: AppText.family,
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// سطر البحث والتصفية مثبّتاً أعلى السجل عند التمرير.
class _PinnedBar extends SliverPersistentHeaderDelegate {
  const _PinnedBar({required this.child});

  final Widget child;
  static const _height = 60.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_PinnedBar old) => true;
}

/// زرّ التصفية الموحّد: أيقونة، وعدد الفلاتر المفعّلة عليها.
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return Tooltip(
      message: 'تصفية',
      child: PressableScale(
        key: const ValueKey('finance-filters'),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: controlHeight,
              height: controlHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.amberSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(Corner.field),
                border: Border.all(color: on ? AppColors.amberBorder : AppColors.line),
              ),
              child: Icon(Icons.tune_rounded, size: 20, color: on ? AppColors.amberDark : AppColors.muted),
            ),
            if (on)
              PositionedDirectional(
                top: -5,
                end: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  height: 17,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600, height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// سطر أرقام فوق السجل — «رسوم الفترة» حين يُحتسب المقبوض بسنة الرسوم.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.parts});

  final List<(String, Color)> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < parts.length; i++) ...[
                  if (i > 0) const TextSpan(text: '  ·  ', style: TextStyle(color: AppColors.faint)),
                  TextSpan(
                    text: parts[i].$1,
                    style: TextStyle(
                      color: parts[i].$2,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppText.family, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? AppColors.amber : AppColors.lineStrong),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.family,
            color: selected ? Colors.white : AppColors.heading,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// إجراء في ورقة الإجراءات.
typedef _SheetAction = ({IconData icon, String label, Color color, VoidCallback onTap});

Future<void> _showActions(BuildContext context, String title, List<_SheetAction> actions) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
          ),
          const Divider(height: 1, color: AppColors.line),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon, color: a.color, size: 20),
              title: Text(
                a.label,
                style: TextStyle(
                  color: a.color == AppColors.danger ? AppColors.danger : AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                a.onTap();
              },
            ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

// ═══ صفوف السجل ═════════════════════════════════════════════════════════════
//
// كل صف بنمط واحد: دائرة بالحرف الأول أو أيقونة، ثم العنوان وتحته التفاصيل،
// والمبلغ بلون داكن هادئ في الطرف وتحته حالته شارةً ناعمة. الأحمر للحالة لا
// للرقم: عمود أرقام حمراء صارخ يُتعب العين ولا يضيف معنى.

TextStyle get _titleStyle => TextStyle(
  fontFamily: AppText.family,
  fontWeight: FontWeight.w700,
  fontSize: 14,
  color: AppColors.heading,
);

const _metaStyle = TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.3);

/// تاريخ قصير مقروء: «1 أكتوبر»، والسنة إن لم تكن الحالية.
String _shortDate(DateTime d) {
  final base = '${d.day} ${gregorianMonths[d.month - 1]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// عنوان مجموعة يومية: «اليوم» و«أمس»، وإلا التاريخ.
String _dayLabel(DateTime d) {
  final today = dateOnly(DateTime.now());
  final day = dateOnly(d);
  if (day == today) return 'اليوم';
  if (day == today.subtract(const Duration(days: 1))) return 'أمس';
  return _shortDate(d);
}

/// عنوان مجموعة شهرية للمستحقات.
String _monthLabel(DateTime d) => '${gregorianMonths[d.month - 1]} ${d.year}';

/// عنوان مجموعة في السجل: اسمها ومجموعها.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.total});

  final String title;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: AppText.family,
                color: AppColors.heading,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${total < 0 ? '-' : ''}${money(total)}',
            style: const TextStyle(
              fontFamily: AppText.family,
              color: AppColors.faint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// مفتاح مقسّم لمجموعة تصفية قصيرة: الخيارات متجاورة بعرض متساوٍ.
class _FilterSegment extends StatelessWidget {
  const _FilterSegment({required this.options, required this.value, required this.onPick});

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.hover, borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: e.key == value
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 5, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        e.value,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: e.key == value ? AppColors.heading : AppColors.muted,
                          fontSize: 12.5,
                          fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// شارة حالة ناعمة: خلفية باهتة ونص بلونها.
class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(fontFamily: AppText.family, color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// ألوان الشارات: أعمق وأهدأ من ألوان الأزرار.
/// المبلغ المستحق بأحمر هادئ مطفي: يُقرأ ديناً بلا صراخ.
const _owedColor = Color(0xFFA5484A);
const _lateColor = Color(0xFFB42318);
const _dueColor = Color(0xFF9A6700);
const _okColor = Color(0xFF1F7A4D);

/// المبلغ في طرف الصف وتحته شارة حالته.
class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.amount, this.color, this.badge, this.struck = false});

  final String amount;
  final Color? color;
  final Widget? badge;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          amount,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
            color: color ?? AppColors.heading,
            decoration: struck ? TextDecoration.lineThrough : null,
          ),
        ),
        if (badge != null) ...[const SizedBox(height: 4), badge!],
      ],
    );
  }
}

/// هيكل الصف: [العنوان/التفاصيل] [المبلغ]. لمسه يفتح إجراءاته.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.meta,
    required this.amount,
    this.onTap,
  });

  final String title;
  final String meta;
  final Widget amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              amount,
            ],
          ),
        ),
      ),
    );
  }
}

/// سند قبض: الطالب ورقم الوصل وتاريخه وطريقة الدفع، والمبلغ بحالته. لمس الصف
/// يفتح الوصل، والتعديل والواتساب والإلغاء في «المزيد».
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.student,
    this.onCancel,
    this.onEdit,
  });

  final Payment payment;
  final Student? student;
  final VoidCallback? onCancel;

  /// تعديل سند قبض من غير طالب — الإيراد العام.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final payer = p.payerName.trim();
    final category = p.incomeCategory.trim();
    final name = student?.fullName ??
        (payer.isNotEmpty
            ? (category.isNotEmpty ? '$payer · $category' : payer)
            : (p.notes.trim().isEmpty ? 'سند عام' : p.notes.trim()));
    final method = [
      StoreScope.of(context).paymentMethodLabel(p.method),
      if (p.reference.trim().isNotEmpty) '(${p.reference.trim()})',
    ].join(' ');
    final reversed = p.reversedByPaymentId != null;
    final sameDay = dateOnly(p.date) == dateOnly(DateTime.now());

    final Widget? badge = p.cancelled
        ? const _Badge('ملغى', _lateColor)
        : reversed
            ? _Badge('معكوس', AppColors.muted)
            : p.amount < 0
                ? const _Badge('مسترد', _lateColor)
                : p.discountAmount.abs() > 0
                    ? _Badge('خصم ${money(p.discountAmount.abs())}', _dueColor)
                    : null;

    final canWhatsApp = !p.cancelled && !reversed && student != null;

    return _Row(
      title: name,
      meta: ['#${p.receiptNumber}', method].join('  ·  '),
      amount: _AmountColumn(
        amount: '${p.amount < 0 ? '-' : '+'}${money(p.amount)}',
        color: p.cancelled ? AppColors.faint : (p.amount < 0 ? _lateColor : _okColor),
        badge: badge,
        struck: p.cancelled,
      ),
      // الإجراءات في ورقة بلمس الصف، أولها الوصل — لا نقاط ثلاث في كل صف
      onTap: () => _showActions(context, 'سند ${p.receiptNumber}', [
        (
          icon: Icons.receipt_long_outlined,
          label: 'عرض الوصل',
          color: AppColors.heading,
          onTap: () => ReceiptScreen.open(context, p),
        ),
        if (onEdit != null)
          (icon: Icons.edit_outlined, label: 'تعديل', color: AppColors.heading, onTap: onEdit!),
        if (canWhatsApp)
          (
            icon: Icons.chat_outlined,
            label: 'إرسال عبر واتساب',
            color: AppColors.success,
            onTap: () => ReceiptScreen.sendWhatsApp(context, p, student!),
          ),
        if (onCancel != null)
          (
            icon: Icons.block,
            label: sameDay ? 'إلغاء السند' : 'عكس السند',
            color: AppColors.danger,
            onTap: onCancel!,
          ),
      ]),
    );
  }
}

/// بند مستحق: الطالب والبيان وتاريخ الاستحقاق، والمبلغ وتحته حالته، وزر التسديد.
/// لمسه يفتح التسديد وملف الطالب.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.item, this.onOpen, this.onPay});

  final DueItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final d = item;

    return _Row(
      title: d.student.fullName,
      meta: [d.title, _shortDate(d.dueDate)].where((s) => s.trim().isNotEmpty).join('  ·  '),
      amount: _AmountColumn(amount: money(d.amount), color: _owedColor),
      // لمسة واحدة: التسديد وملف الطالب في ورقة، أو مباشرةً إن كان متاحاً وحده
      onTap: () {
        final actions = <_SheetAction>[
          if (onPay != null) (icon: Icons.add_card, label: 'تسديد', color: AppColors.heading, onTap: onPay!),
          if (onOpen != null)
            (icon: Icons.person_outline, label: 'ملف الطالب', color: AppColors.heading, onTap: onOpen!),
        ];
        if (actions.length == 1) return actions.first.onTap();
        if (actions.isNotEmpty) _showActions(context, d.student.fullName, actions);
      },
    );
  }
}

/// صف موحّد يمثّل سند صرف أو دفعة أجر معلم في سجل واحد.
class _SpendRow {
  const _SpendRow({
    required this.date,
    required this.isPayout,
    required this.category,
    required this.description,
    required this.amount,
    required this.method,
    required this.voucher,
  });

  final String date;
  final bool isPayout;
  final String category;
  final String description;
  final double amount;
  final String method;

  /// السند المطبوع الذي يُفتح بلمس البطاقة.
  final ExpenseVoucher voucher;
}

/// سند صرف: البيان وتحته التاريخ وطريقة الصرف، والمبلغ وتحته التصنيف.
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.row});
  final _SpendRow row;

  @override
  Widget build(BuildContext context) {
    // التاريخ يصل أحياناً بطابع زمني كامل من السحابة — يُعرض يوماً فقط
    final details = StoreScope.of(context).paymentMethodLabel(row.method);

    return _Row(
      title: row.description.trim().isEmpty ? row.category : row.description.trim(),
      meta: details,
      amount: _AmountColumn(
        amount: '-${money(row.amount)}',
        color: _owedColor,
        badge: _Badge(row.category, row.isPayout ? const Color(0xFF6E5DC6) : AppColors.muted),
      ),
      // السند المطبوع يُسلَّم لمن قبض المبلغ، فيُفتح بلمس صفّه
      onTap: () => ExpenseVoucher.open(context, row.voucher),
    );
  }
}

/// صرف رواتب الشهر دفعةً واحدة — المقابل لـ `PayrollModal.tsx`.
///
/// العملية الشهرية المتكررة في أجور المعلمين: المدير يعطي عشرة معلمين رواتبهم في
/// يوم، وكتابة عشرة سندات يدوياً غير عملية. الراتب المسجّل يُملأ مقترحاً ويُعدَّل في
/// مكانه، ومن لا يأخذ هذا الشهر يُترك بلا تأشير. يعيد عدد من صُرف لهم.
Future<int> showPayrollSheet(
  BuildContext context,
  AppStore store, {
  required String month,
}) async {
  final amounts = <String, TextEditingController>{
    for (final t in store.teachersInViewedYear)
      t.id: TextEditingController(text: t.rate > 0 ? trimNum(t.rate) : ''),
  };
  final chosen = <String>{};
  var payrollMonth = month;
  var date = DateTime.now();
  var method = store.activePaymentMethods
          .where((m) => m.isDefault)
          .firstOrNull
          ?.id ??
      store.activePaymentMethods.firstOrNull?.id ??
      'cash';
  var payoutType = 'salary';

  double amountOf(String id) =>
      double.tryParse(amounts[id]?.text.trim() ?? '') ?? 0;

  String shiftMonth(String key, int delta) {
    final parts = key.split('-');
    final y = int.tryParse(parts.first) ?? DateTime.now().year;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
    final d = DateTime(y, m + delta, 1);
    return monthKeyOf(d);
  }

  void refillAmounts() {
    for (final t in store.teachersInViewedYear) {
      final ctl = amounts[t.id];
      if (ctl == null) continue;
      ctl.text = payoutType == 'salary' && t.rate > 0 ? trimNum(t.rate) : '';
    }
  }

  final saved = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final selected = chosen.where((id) => amountOf(id) > 0).toList();
        final total = selected.fold<double>(0, (sum, id) => sum + amountOf(id));
        final title = payoutType == 'advance'
            ? 'صرف سلف'
            : payoutType == 'bonus'
                ? 'صرف مكافآت'
                : 'صرف رواتب';

        void toggleAll() {
          setSt(() {
            if (selected.isNotEmpty) {
              chosen.clear();
              return;
            }
            for (final t in store.teachersInViewedYear) {
              final paid = paidInMonth(
                store.teacherPayouts,
                store.linkedTeacherIds(t.id),
                payrollMonth,
              );
              // الراتب لا يُصرف مرتين في الشهر؛ السلفة والمكافأة بلا قيد
              if (payoutType == 'salary' && paid.salary > 0) continue;
              chosen.add(t.id);
            }
          });
        }

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
                  '$title ${monthLabel(payrollMonth)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppDropdown<String>(
                        value: payoutType,
                        items: [
                          for (final e in payoutTypeNames.entries)
                            DropdownMenuItem(value: e.key, child: Text('صرف ${e.value}')),
                        ],
                        onChanged: (v) => setSt(() {
                          payoutType = v ?? payoutType;
                          chosen.clear();
                          refillAmounts();
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(Corner.box),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'الشهر السابق',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.chevron_left, size: 18),
                              onPressed: () => setSt(
                                () => payrollMonth = shiftMonth(payrollMonth, -1),
                              ),
                            ),
                            Text(
                              monthLabel(payrollMonth),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: AppColors.heading,
                              ),
                            ),
                            IconButton(
                              tooltip: 'الشهر التالي',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.chevron_right, size: 18),
                              onPressed: () => setSt(
                                () => payrollMonth = shiftMonth(payrollMonth, 1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SelectField(
                        text: isoDate(date),
                        icon: Icons.calendar_today_outlined,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (picked != null) setSt(() => date = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdown<String>(
                        value: method,
                        items: [
                          for (final m in store.activePaymentMethods)
                            DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                m.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setSt(() => method = v ?? method),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: toggleAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                    ),
                    child: Text(selected.isEmpty ? 'تحديد الكل' : 'إلغاء الكل'),
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.38,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: store.teachersInViewedYear.length,
                    itemBuilder: (_, i) {
                      final t = store.teachersInViewedYear[i];
                      final paid = paidInMonth(
                        store.teacherPayouts,
                        store.linkedTeacherIds(t.id),
                        payrollMonth,
                      );
                      return Row(
                        children: [
                          Checkbox(
                            value: chosen.contains(t.id),
                            activeColor: AppColors.amber,
                            onChanged: (_) => setSt(
                              () => chosen.contains(t.id)
                                  ? chosen.remove(t.id)
                                  : chosen.add(t.id),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                if (paid.total > 0)
                                  Text(
                                    [
                                      if (paid.salary > 0)
                                        'صُرف ${money(paid.salary)}',
                                      if (paid.advance > 0)
                                        'سلفة ${money(paid.advance)}',
                                      if (paid.bonus > 0)
                                        'مكافأة ${money(paid.bonus)}',
                                    ].join('  ·  '),
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 92,
                            child: TextField(
                              controller: amounts[t.id],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              onChanged: (_) => setSt(() => chosen.add(t.id)),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${selected.length} معلماً  ·  ${money(total)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 8),
                ActionButtons(
                  primary: PrimaryButton(
                    label: 'صرف',
                    color: AppColors.navy,
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                            try {
                              for (final id in selected) {
                                store.addTeacherPayout(
                                  teacherId: id,
                                  amount: amountOf(id),
                                  paymentDate: isoDate(date),
                                  payoutType: payoutType,
                                  periodStart: '$payrollMonth-01',
                                  periodEnd: monthEnd(payrollMonth),
                                  method: method,
                                );
                              }
                              Navigator.pop(ctx, selected.length);
                            } on StoreException catch (e) {
                              showAppSnack(ctx, e.message, error: true);
                            }
                          },
                  ),
                  secondary: GhostButton(
                    label: 'إلغاء',
                    onPressed: () => Navigator.pop(ctx, 0),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  for (final c in amounts.values) {
    c.dispose();
  }
  return saved ?? 0;
}
