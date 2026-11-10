import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/arabic_search.dart';
import '../data/method_owners.dart';
import '../data/profit_report.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_tokens.dart' show AdminNoon;
import '../widgets/admin_ui.dart' show NoonEmpty, NoonSegment, NoonText, noonPanel;
import '../widgets/ledger_row.dart';
import '../widgets/animated_count.dart';
import '../widgets/list_paging.dart';
import '../widgets/table_gate.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'expense_form_sheet.dart';
import 'payment_form_screen.dart';
import 'payroll_screen.dart';
import 'payment_requests_panel.dart';
import 'profit_report_panel.dart';
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
/// فتح المستحقات بفلتر أعمار الديون من خارج المالية — «متأخرون +60 يوم» في الرئيسية
/// (`/finance?tab=dues&aging=60`).
final financeAgingRequest = ValueNotifier<String?>(null);

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

/// التبويبات بترتيب الويب.
enum _Tab { dues, payments, expenses, profits, controls }

class _FinanceScreenState extends State<FinanceScreen> {
  _Tab tab = _Tab.dues;
  /// التنقّل بين الأقسام سحباً بالإصبع، لا بالضغط على المفتاح وحده
  final _pages = PageController();
  final search = TextEditingController();

  /// نص البحث المطبَّق: يتأخر 250ms عن آخر حرف، فلا يُعاد فلترة آلاف البنود مع كل حرف.
  String _query = '';
  Timer? _searchTimer;
  String method = '';
  String status = '';

  /// مصدر المقبوضات: '' الكل | students | other
  String sourceFilter = '';

  /// أعمار الديون — `AGING_FILTERS`: الكل، أو ما تأخر أكثر من 30 أو 60 يوماً.
  String agingFilter = 'all';

  /// المقبوضات حسب سنة الدفع (متى قُبض) أو حسب سنة القسط (رسوم أي سنة سُدّدت).
  String paymentsBasis = 'payment';

  /// مستحقات محسوبة خارج إطار البناء — حتى لا يتجمّد مؤشر التحميل.
  List<DueItem> _duesSnapshot = const [];
  var _duesBusy = false;
  int _duesStamp = 0;
  var _duesReady = false;

  int visibleCount = kListPageSize;
  int auditVisible = kListPageSize;

  /// فلتر معلم في المصروفات (نسخه عبر الأعوام)
  String statementTeacherId = '';
  bool showProcessedRequests = false;

  /// الرقابة: `requests` الطلبات، أو `audit` سجل الحركات الحساسة.
  String controlsView = 'requests';
  String auditUserFilter = '';
  String auditActionFilter = '';

  /// فلتر سنة المالية المستقل عن العام المعروض: `current` | `all` | yearId
  String financeYearFilter = 'current';
  String termFilter = 'all';

  /// فترة مخصصة «من – إلى» (yyyy-mm-dd): تتقدّم على العام والفصل في كل تبويبات المالية.
  /// طرفٌ فارغ مفتوح.
  String customFrom = '';
  String customTo = '';
  bool get _customPeriod => customFrom.isNotEmpty || customTo.isNotEmpty;

  static const _statusOptions = {
    '': 'كل الحالات',
    'active': 'مقبوضة',
    'cancelled': 'ملغى',
  };

  String _resolvedFinanceYearId(AppStore store) {
    if (financeYearFilter == 'all') return '';
    // سنة المالية هي العام المعروض في النظام كله، و«كل الأعوام» خيار إضافي — كالويب
    // (`useFinanceYearFilter`). فلتر مستقل كان يعرض مستحقات عام بطلاب عام آخر
    return store.viewedAcademicYearId;
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
    if (_customPeriod) {
      final d = (dueDate ?? paymentDate ?? '').split('T').first;
      if (d.isEmpty) return true;
      if (customFrom.isNotEmpty && d.compareTo(customFrom) < 0) return false;
      if (customTo.isNotEmpty && d.compareTo(customTo) > 0) return false;
      return true;
    }
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

  /// هل السند من الفترة المختارة؟ بسنة السند لا بيوم قبضه: رسوم تسجيل قُبضت قبل بدء
  /// العام تُحسب على عامها. «حسب سنة الرسوم»: المربوط بقسط يُنسب لسنة قسطه.
  bool _paymentInPeriod(AppStore store, Payment p, Map<String, Installment>? installmentById) {
    final inst = installmentById?[p.installmentId];
    if (inst != null) {
      return _matchesFinancePeriod(store, yearId: inst.academicYearId, dueDate: isoDate(inst.dueDate));
    }
    return _matchesFinancePeriod(store, yearId: p.academicYearId, paymentDate: isoDate(p.date));
  }

  Map<String, Installment>? _installmentIndex(AppStore store) =>
      paymentsBasis == 'installment' ? {for (final i in store.installments) i.id: i} : null;

  /// سندات الفترة — أساس «المقبوضات» في البطاقة والصافي، وسجل المقبوضات قبل البحث والفلاتر.
  /// محفوظة حتى تتغير السندات أو الأقساط أو الفترة: تُطلب في البطاقة والعدّ والسجل لكل رسم.
  Object? _periodPaymentsKey;
  List<Payment> _periodPaymentsValue = const [];

  List<Payment> _periodPayments(AppStore store) {
    final key = Object.hash(
      store.netInputStamp,
      store.duesInputStamp,
      paymentsBasis,
      financeYearFilter,
      termFilter,
      customFrom,
      customTo,
    );
    if (key != _periodPaymentsKey) {
      final index = _installmentIndex(store);
      _periodPaymentsValue = store.payments.where((p) => _paymentInPeriod(store, p, index)).toList();
      _periodPaymentsKey = key;
    }
    return _periodPaymentsValue;
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

  /// مدى الفترة المختارة؛ «كل الأعوام» من أول عام إلى آخره — `periodRange`.
  ({String from, String to}) _periodRange(AppStore store) {
    if (_customPeriod) {
      final today = isoDate(DateTime.now());
      final starts = [for (final y in store.academicYears) if (y.startsOn.isNotEmpty) y.startsOn]..sort();
      return (
        from: customFrom.isNotEmpty ? customFrom : (starts.isEmpty ? today : starts.first),
        to: customTo.isNotEmpty ? customTo : today,
      );
    }
    final year = financeYearFilter == 'all' ? null : _filterYear(store);
    if (year != null) return academicRange(year, termFilter);
    final starts = [for (final y in store.academicYears) if (y.startsOn.isNotEmpty) y.startsOn]..sort();
    final ends = [for (final y in store.academicYears) if (y.endsOn.isNotEmpty) y.endsOn]..sort();
    final today = isoDate(DateTime.now());
    return starts.isEmpty ? (from: today, to: today) : (from: starts.first, to: ends.last);
  }

  /// ربح الفترة بتاريخ القبض: المقبوض ناقص المصروفات والرواتب (المسحوبات والتحويل خارجه).
  ({double received, double spent, double net, double draws}) _periodNet(AppStore store) {
    // يُحسب مرة لكل تغيّر في السندات أو المصروفات أو الرواتب أو الفلتر، لا مع كل رسم
    final stamp = Object.hash(store.netInputStamp, financeYearFilter, termFilter, paymentsBasis, customFrom, customTo);
    final cached = _netCache;
    if (cached != null && stamp == _netStamp) return cached;
    _netStamp = stamp;
    return _netCache = _computePeriodNet(store);
  }

  int _netStamp = 0;
  ({double received, double spent, double net, double draws})? _netCache;

  /// المقبوض بسنة السند كسجل المقبوضات فيتطابق الرقمان؛ المصروفات والرواتب بتاريخها.
  ({double received, double spent, double net, double draws}) _computePeriodNet(AppStore store) {
    final total = computeProfitReport(
      payments: const [],
      installments: const [],
      expenses: store.expenses,
      payouts: store.teacherPayouts,
      range: _periodRange(store),
      basis: ProfitBasis.paid,
    ).total;
    // الصافي بعد الرد والعكس، والملغى خارجه — كمجموع سجل المقبوضات
    final received = _periodPayments(store).fold<double>(0, (a, p) => a + (p.cancelled ? 0 : p.amount));
    final spent = total.expenses + total.salaries;
    return (received: received, spent: spent, net: received - spent, draws: total.draws);
  }

  @override
  void dispose() {
    financeAgingRequest.removeListener(_takeAging);
    _pages.dispose();
    _searchTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final v = financeAgingRequest.value;
    if (v != null) {
      financeAgingRequest.value = null;
      tab = _Tab.dues;
      agingFilter = v;
    }
    financeAgingRequest.addListener(_takeAging);
  }

  void _takeAging() {
    final v = financeAgingRequest.value;
    if (v == null || !mounted) return;
    financeAgingRequest.value = null;
    setState(() {
      tab = _Tab.dues;
      agingFilter = v;
    });
  }

  /// الأقسام بترتيبها — فهرس القسم هو رقم صفحته في السحب.
  List<_Tab> _visibleTabs(bool showExpenses) => [
        _Tab.dues,
        _Tab.payments,
        if (showExpenses) _Tab.expenses,
        if (showExpenses) _Tab.profits,
        _Tab.controls,
      ];

  void _openTab(_Tab next) {
    if (tab == next) return;
    setState(() {
      tab = next;
      // لكل تبويب بحثه: نص يبحث عن وصل لا معنى له في المستحقات
      search.clear();
      _searchTimer?.cancel();
      _query = '';
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
        _Tab.profits => (toolbar: null, slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              sliver: SliverToBoxAdapter(
                child: ProfitReportPanel(
                  store: store,
                  year: _filterYear(store) ?? store.viewedAcademicYear,
                  customRange: _customPeriod ? _periodRange(store) : null,
                ),
              ),
            ),
          ]),
        _Tab.controls => (toolbar: null, slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              sliver: SliverList(delegate: SliverChildListDelegate(_controls(context, store))),
            ),
          ]),
        _Tab.dues => _dues(context, store, allDues, q),
      };

  /// يحسب المستحقات بعد إفساح الواجهة — لا داخل `build`.
  void _scheduleDues(AppStore store) {
    // ختم القوائم نفسها لا عدّاد التعديل وحده: التحميل من القرص يستبدل القائمة بلا
    // عدّاد، فكانت المستحقات تبقى على نسخة قديمة
    final stamp = Object.hash(store.duesInputStamp, financeYearFilter, termFilter, customFrom, customTo);
    if (stamp == _duesStamp || _duesBusy) return;
    _duesBusy = true;
    unawaited(() async {
      await yieldUi(2);
      if (!mounted) return;
      final byId = <String, Installment>{
        for (final i in store.installments) i.id: i,
      };
      final list = store.dueItems().where((d) {
        final inst = d.installmentId == null ? null : byId[d.installmentId!];
        return _matchesFinancePeriod(
          store,
          yearId: inst?.academicYearId,
          dueDate: isoDate(d.dueDate),
        );
      }).toList();
      if (!mounted) return;
      setState(() {
        _duesSnapshot = list;
        _duesStamp = stamp;
        _duesBusy = false;
        _duesReady = true;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return TableGate(
      tables: const ['payments', 'installments', 'expenses', 'teacher_payouts'],
      message: 'جارٍ التحميل...',
      spinner: false,
      child: Builder(
      builder: (context) {
        if (!store.canOpenSection('finance')) {
          return NoAccess(section: 'finance', roleName: store.roleName);
        }

        // التبويب يتبع الميزة والصلاحية كما في Finance.tsx
        final showExpenses = store.features.enableExpenses && store.can('finance.expenses');
        if ((tab == _Tab.expenses || tab == _Tab.profits) && !showExpenses) tab = _Tab.dues;

        final q = _query;
        final List<DueItem> allDues;
        if (tab == _Tab.dues) {
          _scheduleDues(store);
          if (!_duesReady) {
            return const AppLoader(message: 'جارٍ التحميل...', spinner: false);
          }
          allDues = _duesSnapshot;
        } else {
          allDues = const [];
        }

        // صافي الفترة للتبويبات التي تعرضه فقط
        final net = (tab == _Tab.payments || tab == _Tab.expenses || tab == _Tab.profits)
            ? _periodNet(store)
            : (received: 0.0, spent: 0.0, net: 0.0, draws: 0.0);

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
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PayrollScreen()));
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
          _Tab.controls || _Tab.profits => null,
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
      child: NoonSegment<_Tab>(
        value: tab,
        onChanged: _openTab,
        options: [
          (_Tab.dues, 'المستحقات'),
          (_Tab.payments, 'المقبوضات'),
          if (showExpenses) (_Tab.expenses, 'المصروفات'),
          if (showExpenses) (_Tab.profits, 'الأرباح'),
          (_Tab.controls, 'الرقابة'),
        ],
        // طلبات الموظفين ودفعات أولياء الأمور معاً: كلاهما ينتظر قراراً
        badges: {_Tab.controls: store.pendingFinanceRequests.length + store.pendingPaymentRequests.length},
      ),
    );
  }

  /// بطاقة القسم المفتوح: رقمه الرئيسي كبيراً وتفاصيله شرائح. الرقابة سجلّ
  /// طلبات لا رقم فيه، فلا بطاقة لها.
  Widget? _hero(
    AppStore store,
    List<DueItem> dues,
    ({double received, double spent, double net, double draws}) net,
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
          chips: ['$debtors طالب', 'القسط الجاي ${money(store.projectRemainingYear())}'],
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
      case _Tab.profits:
        return _Hero(
          tab: tab,
          label: 'الربح في الفترة',
          value: '${net.net < 0 ? '-' : ''}${money(net.net)}',
          period: period,
          onPeriod: () => _openFilters(store),
          chips: ['المسحوب ${money(net.draws)}', 'الباقي ${net.net - net.draws < 0 ? '-' : ''}${money(net.net - net.draws)}'],
        );
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
    if (_customPeriod) {
      String d(String iso) => iso.isEmpty ? '…' : iso.split('-').reversed.join('/');
      return '${d(customFrom)} – ${d(customTo)}';
    }
    final year = financeYearFilter == 'all' ? 'كل الأعوام' : (store.viewedAcademicYear?.label ?? 'عام');
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
    if (_customPeriod) {
      n++;
    } else {
      if (financeYearFilter != 'current') n++;
      if (termFilter != 'all') n++;
    }
    switch (tab) {
      case _Tab.dues:
        break;
      case _Tab.payments:
        n += [method, status, sourceFilter].where((v) => v.isNotEmpty).length;
        if (paymentsBasis != 'payment') n++;
      case _Tab.expenses:
        if (statementTeacherId.isNotEmpty) n++;
      case _Tab.controls:
      case _Tab.profits:
        break;
    }
    return n;
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    final next = value.trim().toLowerCase();
    // المسح فوري، وظهور زر المسح مع أول حرف كذلك؛ الفلترة نفسها بعد توقف الكتابة
    if (next.isEmpty || _query.isEmpty && search.text.length == 1) {
      if (next.isEmpty) {
        setState(() {
          _query = '';
          visibleCount = kListPageSize;
        });
        return;
      }
      setState(() {});
    }
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = search.text.trim().toLowerCase();
        visibleCount = kListPageSize;
      });
    });
  }

  Widget _toolbar({required String hint, required int shown, required int total, required AppStore store, String? unit}) {
    return Row(
      children: [
        Expanded(
          child: SearchField(
            controller: search,
            hint: hint,
            onChanged: _onSearch,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AdminNoon.mist, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '${shown == total ? '$total' : '$shown/$total'}${unit == null ? '' : ' $unit'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
              ),
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

          // ثلاثة خيارات فأقل: مفتاح مقسّم بسطر واحد؛ وأكثر: شرائح تلتف بلا تمرير أفقي
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
                    NoonSegment<String>(value: value, options: [for (final e in options.entries) (e.key, e.value)], onChanged: (v) => pick(() => onPick(v)))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in options.entries)
                          _Pill(
                            label: e.value,
                            selected: e.key == value,
                            onTap: () => pick(() => onPick(e.key)),
                          ),
                      ],
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
                        _CustomRange(
                          from: customFrom,
                          to: customTo,
                          onFrom: (v) => pick(() => customFrom = v),
                          onTo: (v) => pick(() => customTo = v),
                          onClear: () => pick(() {
                            customFrom = '';
                            customTo = '';
                          }),
                        ),
                        if (!_customPeriod) ...[
                        group(
                          'العام الدراسي',
                          {
                            for (final y in store.academicYears) y.id: y.label,
                            'all': 'كل الأعوام',
                          },
                          financeYearFilter == 'all' ? 'all' : store.viewedAcademicYearId,
                          (v) {
                            // اختيار عام يبدّل العام المعروض في النظام كله، كالويب
                            if (v == 'all') {
                              financeYearFilter = 'all';
                            } else {
                              financeYearFilter = 'current';
                              store.viewedAcademicYearId = v;
                            }
                          },
                        ),
                        group(
                          'الفصل',
                          const {'all': 'كل الفصول', 'term_1': 'الفصل الأول', 'term_2': 'الفصل الثاني'},
                          termFilter,
                          (v) => termFilter = v,
                        ),
                        ],
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
    customFrom = '';
    customTo = '';
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
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, thumbActionClearance), child: NoonEmpty(emptyMessage)))
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
          matchArabicName(d.student.fullName, q) ||
          d.student.phone.contains(q) ||
          d.title.toLowerCase().contains(q);
      return matchQ && (agingFilter == 'all' || _daysLate(d.dueDate) > int.parse(agingFilter));
    }).toList();

    // الأحدث أولاً كبقية السجلات، فتتجاور بنود الشهر الواحد، وطلابه أبجدياً
    dues.sort((a, b) {
      final byDate = b.dueDate.compareTo(a.dueDate);
      return byDate != 0 ? byDate : compareArabicNames(a.student.fullName, b.student.fullName);
    });

    final canCollect = store.can('finance.collect');
    final canOpenStudent = store.can('students');

    return (
      toolbar: _toolbar(hint: 'اسم الطالب أو الجوال', shown: dues.length, total: all.length, store: store, unit: 'قسط'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: NoonSegment<String>(
              value: agingFilter,
              options: const [('all', 'الكل'), ('30', '+30 يوم'), ('60', '+60 يوم')],
              onChanged: (v) => setState(() => agingFilter = v),
            ),
          ),
        ),
        ..._listSlivers(
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
      ],
    );
  }

  // ── المقبوضات ─────────────────────────────────────────────────────────────

  /// سجل المقبوضات بعد البحث والفلاتر مرتباً — محفوظ في [_paysValue] حتى يتغير
  /// مفتاحه، فلا تُفلتر ولا تُرتب ستون ألف سند مع كل إعادة رسم.
  Object? _paysKey;
  List<Payment> _paysValue = const [];

  List<Payment> _filterPayments(AppStore store, List<Payment> periodPays, String q) {
    final pays = periodPays.where((p) {
      final studentName = store.studentById(p.studentId)?.fullName ?? '${p.payerName} ${p.incomeCategory}';
      // البحث يشمل البيان والمحوِّل وجهة التحويل، كما في Finance.tsx
      final matchQ = q.isEmpty ||
          p.receiptNumber.toLowerCase().contains(q) ||
          matchArabicName(studentName, q) ||
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
    return pays;
  }

  ({Widget? toolbar, List<Widget> slivers}) _payments(BuildContext context, AppStore store, String q) {
    // «حسب سنة الرسوم»: السند المربوط بقسط يُنسب لسنة قسطه (دين العام الماضي
    // المدفوع اليوم يُحسب على العام الماضي)، والدفعة غير المربوطة بسنة دفعها
    final periodPays = _periodPayments(store);
    final paysKey = Object.hash(
      identityHashCode(periodPays),
      periodPays.length,
      store.tableRev('payments'),
      store.tableRev('students'),
      q,
      method,
      status,
      sourceFilter,
    );
    if (paysKey != _paysKey) {
      _paysKey = paysKey;
      _paysValue = _filterPayments(store, periodPays, q);
    }
    final pays = _paysValue;

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

    // المقبوض لكل طريقة دفع (كل حساب أو محفظة باسمه) — كبطاقات Finance.tsx
    final byMethod = <String, ({double amount, int count})>{};
    for (final p in pays) {
      if (p.cancelled) continue;
      final prev = byMethod[p.method] ?? (amount: 0.0, count: 0);
      byMethod[p.method] = (amount: prev.amount + p.amount, count: prev.count + 1);
    }
    final methodRows = byMethod.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final methodsStrip = methodRows.isEmpty
        ? null
        : _MethodTotals(
            rows: [
              for (final m in methodRows)
                (
                  id: m.key,
                  label: m.key.isEmpty ? 'بلا طريقة' : store.paymentMethodLabel(m.key),
                  amount: m.value.amount,
                  count: m.value.count,
                ),
            ],
            selected: method,
            onTap: (id) => setState(() => method = method == id ? '' : id),
          );
    final header = methodsStrip == null && feesLine == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?methodsStrip,
              if (methodsStrip != null && feesLine != null) const SizedBox(height: 8),
              ?feesLine,
            ],
          );

    return (
      toolbar: _toolbar(hint: 'اسم أو رقم وصل', shown: pays.length, total: periodPays.length, store: store, unit: 'سند'),
      slivers: _listSlivers(
        // بطاقات طرق الدفع، وسطر «رسوم الفترة» حين يُحتسب المقبوض بسنة الرسوم
        header: header,
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

  /// حساب مختار من مربعات المصروفات: السجل يعرض حركته وحده.
  String spendMethod = '';

  /// سجل موحّد للمصروفات وأجور المعلمين في الفترة، مرتّب بالتاريخ تنازلياً —
  /// نفس دمج القائمتين في جدول واحد في Finance.tsx. اختيار معلم يقصره على ما صُرف له.
  ({Widget? toolbar, List<Widget> slivers}) _expenses(AppStore store, String q) {
    final linked = statementTeacherId.isEmpty ? null : store.linkedTeacherIds(statementTeacherId);
    // الملغى في السجل مشطوباً بسببه، خارج المجموع
    final expenses = linked == null
        ? [
            ..._periodExpenses(store),
            ...store.cancelledExpenses.where((e) => _matchesFinancePeriod(store, paymentDate: e.expenseDate)),
          ]
        : <Expense>[];
    final payouts = [
      for (final p in _periodPayouts(store))
        if (linked == null || linked.contains(p.teacherId)) p,
      for (final p in store.cancelledPayouts)
        if ((linked == null || linked.contains(p.teacherId)) &&
            _matchesFinancePeriod(store, paymentDate: p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate))
          p,
    ];
    final all = <_SpendRow>[
      for (final e in expenses)
        _SpendRow(
          date: e.expenseDate,
          isPayout: false,
          // المسحوبات والتحويل تُعرف من بندها: لا تنقص الربح
          category: expenseKindOf(e) == 'expense'
              ? expenseCategoryLabel(e.category)
              : '${expenseKindNames[expenseKindOf(e)]} · ${expenseCategoryLabel(e.category)}',
          // التحويل يظهر في مصروفات الحسابين: «من ← إلى»
          description: e.isTransferIn
              ? '${store.paymentMethodLabel(e.method)} ← ${store.paymentMethodLabel(e.toMethod)}'
              : e.description,
          amount: e.amount,
          method: e.method,
          toMethod: e.isTransferIn ? e.toMethod : '',
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
    // المصروف من كل حساب أو محفظة — `MethodTotals`
    final spentBy = <String, ({double amount, int count})>{};
    for (final r in all) {
      if (r.voucher.isCancelled) continue;
      final prev = spentBy[r.method] ?? (amount: 0.0, count: 0);
      spentBy[r.method] = (amount: prev.amount + r.amount, count: prev.count + 1);
    }
    final methodRows = spentBy.entries.toList()..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final byAccount = spendMethod.isEmpty
        ? all
        : all.where((r) => r.method == spendMethod || r.toMethod == spendMethod).toList();
    final rows = q.isEmpty
        ? byAccount
        : byAccount.where((r) => r.description.toLowerCase().contains(q) || r.category.toLowerCase().contains(q)).toList();

    return (
      toolbar: _toolbar(hint: 'ابحث في البيان', shown: rows.length, total: all.length, store: store, unit: 'حركة'),
      slivers: _listSlivers(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الرواتب قسم من المصروفات: بابها ظاهر هنا لا مخفياً خلف «+»
            if (store.can('finance.expenses')) ...[
              Material(
          color: Colors.transparent,
          child: Ink(
            decoration: noonPanel(),
            child: InkWell(
              borderRadius: BorderRadius.circular(AdminNoon.rPanel),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PayrollScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 20, color: AdminNoon.ink),
                    const SizedBox(width: 10),
                    Expanded(child: Text('كشف الرواتب وصرفها', style: NoonText.style(13.5, weight: FontWeight.w700))),
                    Icon(Icons.chevron_right_rounded, size: 20, color: AdminNoon.faint),
                  ],
                ),
              ),
            ),
          ),
        ),
              const SizedBox(height: 8),
            ],
            if (methodRows.isNotEmpty)
              _MethodTotals(
                rows: [
                  for (final m in methodRows)
                    (
                      id: m.key,
                      label: m.key.isEmpty ? 'بلا طريقة' : store.paymentMethodLabel(m.key),
                      amount: m.value.amount,
                      count: m.value.count,
                    ),
                ],
                selected: spendMethod,
                onTap: (id) => setState(() => spendMethod = spendMethod == id ? '' : id),
              ),
          ],
        ),
        items: rows,
        emptyMessage: 'لا مصروفات',
        groupOf: (r) {
          final d = parseIsoDate(r.date.length >= 10 ? r.date.substring(0, 10) : r.date);
          return d == null ? r.date : _dayLabel(d);
        },
        amountOf: (r) => r.voucher.isCancelled ? 0 : r.amount,
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
      try {
        await runBusyOp(context, () => store.rejectFinanceRequest(request.id, note.text), message: 'جارٍ الحسم...');
      } on StoreException catch (e) {
        if (context.mounted) showAppSnack(context, e.message, error: true);
      }
    }
    note.dispose();
  }

  /// تبويب الطلبات والرقابة — المقابل لـ `FinanceControlPanel.tsx`.
  List<Widget> _controls(BuildContext context, AppStore store) {
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

    /// السند الذي تخصه الحركة، إن وُجد: مباشرة، أو عبر الطلب الذي أصدره — `paymentIdOf`.
    String? paymentIdOf(FinanceAuditEntry a) {
      if (a.entityId.isEmpty) return null;
      if (const ['payment_discount', 'payment_reverse', 'refund', 'payment_cancel'].contains(a.action)) return a.entityId;
      if (a.action.startsWith('payment_request_')) {
        final id = store.paymentRequests.where((r) => r.id == a.entityId).firstOrNull?.paymentId ?? '';
        return id.isEmpty ? null : id;
      }
      final req = store.financeRequests.where((r) => r.id == a.entityId).firstOrNull;
      return req?.kind == 'payment_cancel' && req!.targetId.isNotEmpty ? req.targetId : null;
    }

    Future<void> openReceipt(String paymentId) async {
      final p = store.payments.where((x) => x.id == paymentId).firstOrNull;
      if (p == null) {
        showAppSnack(context, 'السند غير موجود', error: true);
        return;
      }
      await ReceiptScreen.open(context, p);
    }

    IconData kindIcon(String key) {
      if (key.contains('cancel')) return Icons.block_outlined;
      if (key.contains('discount')) return Icons.percent_rounded;
      if (key.contains('refund')) return Icons.undo_rounded;
      if (key.contains('reverse')) return Icons.swap_horiz_rounded;
      if (key.contains('expense') || key.contains('spend')) return Icons.receipt_long_outlined;
      return Icons.rule_folder_outlined;
    }

    Widget statusChip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: NoonText.style(10.5, weight: FontWeight.w700, color: color)),
        );

    Widget kv(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 74, child: Text(label, style: NoonText.style(12, color: AdminNoon.muted))),
                Expanded(child: Text(value, style: NoonText.style(12.5, height: 1.35))),
              ],
            ),
          );

    Widget requestCard(FinanceRequest request) {
      final pendingRow = request.status == 'pending';
      final approved = request.status == 'approved';
      final day = (request.createdAt ?? '').split('T').first;
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(financeRequestLabel(request.kind), style: NoonText.style(15, weight: FontWeight.w700)),
                      if (request.studentName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(request.studentName, style: NoonText.style(12.5, color: AdminNoon.muted)),
                      ],
                    ],
                  ),
                ),
                statusChip(
                  pendingRow ? 'بانتظار القرار' : (approved ? 'اعتُمد' : 'مرفوض'),
                  pendingRow ? AppColors.amberDark : (approved ? AppColors.success : AppColors.danger),
                ),
              ],
            ),
            if (request.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(request.summary, style: NoonText.style(13, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: AdminNoon.line),
            const SizedBox(height: 6),
            kv('السبب', request.reason),
            kv('من', request.requestedByName),
            kv('التاريخ', day),
            if (!pendingRow && request.decisionNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('— ${request.decisionNote}', style: NoonText.style(12, weight: FontWeight.w600, color: approved ? AppColors.success : AppColors.danger)),
              ),
            if (pendingRow) ...[
              const SizedBox(height: 12),
              if (store.isFinanceAdmin)
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'قبول',
                        color: AppColors.success,
                        expand: true,
                        height: 46,
                        onPressed: () async {
                          try {
                            await runBusyOp(context, () => store.approveFinanceRequest(request.id), message: 'جارٍ الحسم...');
                          } on StoreException catch (e) {
                            if (context.mounted) showAppSnack(context, e.message, error: true);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: GhostButton(label: 'رفض', height: 46, onPressed: () => _rejectFinanceRequest(context, store, request))),
                  ],
                )
              else
                Text('بانتظار المدير', style: NoonText.style(12, weight: FontWeight.w600, color: AppColors.amberDark)),
            ],
          ],
        ),
      );
    }

    // طلبات الموظفين ودفعات أولياء الأمور في قائمة واحدة، الأحدث أولاً
    final items = <({String at, bool pending, Widget node})>[
      for (final r in store.financeRequests)
        (at: r.createdAt ?? '', pending: r.status == 'pending', node: requestCard(r)),
      for (final r in store.paymentRequests)
        (at: r.createdAt ?? '', pending: r.status == 'pending', node: ParentRequestCard(key: ValueKey(r.id), store: store, request: r)),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final pending = [for (final i in items) if (i.pending) i.node];
    // المدير يرى القرارات في السجل؛ الموظف لا سجل له فتبقى له قائمة السابقة
    final done = store.isFinanceAdmin ? const <Widget>[] : [for (final i in items) if (!i.pending) i.node];

    Widget panel(List<Widget> rows) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: noonPanel(),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: AdminNoon.line),
                rows[i],
              ],
            ],
          ),
        );

    final showAudit = store.isFinanceAdmin && controlsView == 'audit';
    return [
        if (store.isFinanceAdmin) ...[
          NoonSegment<String>(
            value: controlsView,
            options: [('requests', 'الطلبات${pending.isEmpty ? '' : ' (${pending.length})'}'), ('audit', 'سجل الحركات')],
            onChanged: (v) => setState(() => controlsView = v),
          ),
          const SizedBox(height: 12),
        ],
        if (!showAudit) ...[
          if (pending.isEmpty && done.isEmpty)
            const NoonEmpty('لا طلبات بانتظار الموافقة', icon: Icons.task_alt_outlined)
          else ...[
            if (pending.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('بانتظار الموافقة (${pending.length})', style: NoonText.style(13, weight: FontWeight.w700)),
              ),
              panel(pending),
            ] else if (store.isFinanceAdmin)
              const NoonEmpty('لا طلبات بانتظار الموافقة', icon: Icons.task_alt_outlined),
          ],
          if (done.isNotEmpty) ...[
            TextButton(
              onPressed: () => setState(() => showProcessedRequests = !showProcessedRequests),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: AlignmentDirectional.centerStart,
                textStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w600, fontSize: 12),
              ),
              child: Text(showProcessedRequests ? 'إخفاء السابقة (${done.length})' : 'عرض السابقة (${done.length})'),
            ),
            if (showProcessedRequests) panel(done),
          ],
        ],
        if (showAudit) ...[
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
            const NoonEmpty('لا حركات', icon: Icons.history_outlined)
          else ...[
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: noonPanel(),
              child: Column(
                children: [
                  for (var i = 0; i < auditPage.length; i++) ...[
                    if (i > 0) Divider(height: 1, thickness: 1, color: AdminNoon.line),
                    () {
                      final a = auditPage[i];
                      final pid = paymentIdOf(a);
                      return LedgerRow(
                        icon: kindIcon(a.action),
                        tone: LedgerTone.neutral,
                        title: Text(financeAuditActionLabel(a.action)),
                        subtitle: Text([
                          if (a.userName.isNotEmpty) a.userName,
                          if ((a.createdAt ?? '').isNotEmpty) (a.createdAt ?? '').replaceFirst('T', ' ').split('.').first,
                        ].join('  ·  ')),
                        amount: a.amount != null ? Text(money(a.amount!), textDirection: TextDirection.ltr) : const SizedBox.shrink(),
                        onTap: pid != null ? () => openReceipt(pid) : null,
                        notes: [
                          if (a.studentName.isNotEmpty)
                            GestureDetector(
                              onTap: a.studentId.isEmpty
                                  ? null
                                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: a.studentId))),
                              child: Text(
                                a.studentName,
                                style: NoonText.style(11.5, weight: FontWeight.w700, color: a.studentId.isEmpty ? AdminNoon.text : AdminNoon.ink),
                              ),
                            ),
                          if (a.summary.isNotEmpty) Text(a.summary, style: NoonText.style(11.5, color: AdminNoon.text, height: 1.35)),
                          if (a.reason.isNotEmpty) Text('السبب: ${a.reason}', style: NoonText.style(11, color: AdminNoon.muted)),
                        ],
                      );
                    }(),
                  ],
                ],
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
      _Tab.expenses || _Tab.profits || _Tab.controls => (
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
/// المقبوض لكل طريقة دفع: لمس بطاقة يعرض سندات ذلك الحساب وحده، ولمسة ثانية تلغي.
class _MethodTotals extends StatelessWidget {
  const _MethodTotals({required this.rows, required this.selected, required this.onTap});

  final List<({String id, String label, double amount, int count})> rows;
  final String selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(0, (a, r) => a + r.amount);
    final ownerOf = {for (final m in StoreScope.of(context).paymentMethods) m.id: m.owner};
    final grouping = groupMethodsByOwner<({String id, String label, double amount, int count})>(rows, (r) => ownerOf[r.id]);
    final groups = grouping.groups;
    final ungrouped = grouping.ungrouped;

    Widget methodRow(({String id, String label, double amount, int count}) r) {
      final active = selected == r.id;
      final share = total > 0 ? (r.amount / total).clamp(0.0, 1.0) : 0.0;
      return InkWell(
        onTap: () => onTap(r.id),
        child: Container(
          color: active ? AppColors.navy.withValues(alpha: 0.06) : Colors.transparent,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (active) ...[Icon(Icons.check_circle, size: 16, color: AppColors.navy), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppText.family, fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.heading)),
                  ),
                  Text('${r.count} سند', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  const SizedBox(width: 12),
                  Text(money(r.amount),
                      style: TextStyle(fontFamily: AppText.family, fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.heading)),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 3,
                  backgroundColor: AppColors.line,
                  valueColor: AlwaysStoppedAnimation(AppColors.navy),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[
      for (final g in groups) ...[
        Container(
          color: AppColors.sunken,
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
          child: Row(
            children: [
              Expanded(child: Text(g.owner, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted))),
              Text(money(g.items.fold<double>(0, (a, i) => a + i.amount)),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
        ),
        for (final i in g.items) methodRow(i),
      ],
      for (final i in ungrouped) methodRow(i),
    ];
    final divided = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
        children[i],
      ],
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.field + 2),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...divided,
          if (rows.length > 1 && selected.isEmpty) ...[
            Divider(height: 1, thickness: 1, color: AppColors.line),
            Container(
              color: AppColors.sunken,
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                children: [
                  Expanded(child: Text('المجموع', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.heading))),
                  Text(money(total), style: TextStyle(fontFamily: AppText.family, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.success)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
/// أيام التأخير بين موعد القسط واليوم، وصفر لما لم يحن — `daysLate`.
int _daysLate(DateTime due) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(due.year, due.month, due.day)).inDays;
  return days < 0 ? 0 : days;
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.item, this.onOpen, this.onPay});

  final DueItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final d = item;

    // أيام التأخير بلون من ثلاث درجات: رمادي، ثم عنبري بعد 30، ثم أحمر بعد 60
    final late = _daysLate(d.dueDate);
    return _Row(
      title: d.student.fullName,
      meta: [d.title, _shortDate(d.dueDate)].where((s) => s.trim().isNotEmpty).join('  ·  '),
      amount: _AmountColumn(
        amount: money(d.amount),
        color: _owedColor,
        badge: late > 0 ? _Badge('متأخر $late يوم', late > 60 ? AppColors.danger : (late >= 30 ? AppColors.warn : AppColors.muted)) : null,
      ),
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
    this.toMethod = '',
  });

  /// المستلِم في التحويل بين حسابين.
  final String toMethod;
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
      meta: row.voucher.isCancelled ? 'ملغى: ${row.voucher.cancelledReason}' : details,
      amount: _AmountColumn(
        amount: '-${money(row.amount)}',
        color: row.voucher.isCancelled ? AppColors.muted : _owedColor,
        struck: row.voucher.isCancelled,
        badge: _Badge(row.category, row.isPayout ? const Color(0xFF6E5DC6) : AppColors.muted),
      ),
      // السند المطبوع يُسلَّم لمن قبض المبلغ، فيُفتح بلمس صفّه
      onTap: () => ExpenseVoucher.open(context, row.voucher),
    );
  }
}
/// «فترة مخصصة» في ورقة تصفية المالية: من تاريخ وإلى تاريخ، تتقدّم على العام والفصل.
class _CustomRange extends StatelessWidget {
  const _CustomRange({required this.from, required this.to, required this.onFrom, required this.onTo, required this.onClear});

  final String from;
  final String to;
  final ValueChanged<String> onFrom;
  final ValueChanged<String> onTo;
  final VoidCallback onClear;

  Future<void> _pick(BuildContext context, String current, ValueChanged<String> done) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2, 12, 31),
      locale: const Locale('ar'),
    );
    if (picked != null) done(isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    Widget box(String label, String value, ValueChanged<String> done) => Expanded(
          child: InkWell(
            onTap: () => _pick(context, value, done),
            borderRadius: BorderRadius.circular(Corner.box),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: value.isEmpty ? AppColors.line : AppColors.navy),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 17, color: value.isEmpty ? AppColors.muted : AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.isEmpty ? label : '$label ${value.split('-').reversed.join('/')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: value.isEmpty ? FontWeight.w500 : FontWeight.w700,
                        color: value.isEmpty ? AppColors.muted : AppColors.heading,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('فترة مخصصة', style: TextStyle(color: AppColors.faint, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
              if (from.isNotEmpty || to.isNotEmpty)
                GestureDetector(
                  onTap: onClear,
                  child: const Text('مسح', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [box('من', from, onFrom), const SizedBox(width: 8), box('إلى', to, onTo)]),
          if (from.isNotEmpty || to.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('تتقدّم على العام والفصل في كل تبويبات المالية', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}
