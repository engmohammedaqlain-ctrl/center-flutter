import 'package:flutter/material.dart';

import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'expense_form_sheet.dart';
import 'payment_form_screen.dart';
import 'expense_voucher_screen.dart';
import 'general_income_sheet.dart';
import 'receipt_screen.dart';
import 'student_detail_screen.dart';

/// المالية والصندوق — بتبويبات `pages/Finance.tsx` وترتيبها: المستحقات ثم
/// المقبوضات ثم المصروفات وأجور المعلمين. المستحقات أولاً لأنها سبب فتح المالية.
///
/// بتنسيق ملف الطالب: بطاقات أرقام متجاورة أول كل تبويب، ثم سجل من بطاقات مرتبة —
/// سطر رئيسي مقابل مبلغه، وخط رفيع، ثم الحالة وأزرارها. البحث والتصفية سطر واحد
/// ثابت، والأرقام تُمرَّر مع السجل فلا تحجز من الشاشة شيئاً.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  int tab = 0;
  final search = TextEditingController();
  String method = '';
  String status = '';
  String dueStage = '';
  /// مصدر المقبوضات: '' الكل | students | other
  String sourceFilter = '';
  /// فلتر معلم في المصروفات (نسخه عبر الأعوام)
  String statementTeacherId = '';
  /// فلتر سنة المالية المستقل عن العام المعروض: `current` | `all` | yearId
  String financeYearFilter = 'current';
  String termFilter = 'all';
  bool showProcessedRequests = false;
  String auditUserFilter = '';
  String auditActionFilter = '';

  static const _statusOptions = {
    '': 'كل الحالات',
    'active': 'مقبوضة',
    'cancelled': 'ملغاة',
  };
  static const _stageOptions = {
    '': 'كل الحالات',
    'due': 'مستحق',
    'late': 'متأخر عن السداد',
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

  List<Payment> _periodPayments(AppStore store) {
    final source = financeYearFilter == 'all'
        ? store.payments
        : store.filterByYear(store.payments, yearId: _resolvedFinanceYearId(store));
    return source.where((p) {
      return _matchesFinancePeriod(
        store,
        yearId: p.academicYearId,
        paymentDate: isoDate(p.date),
      );
    }).toList();
  }

  ({double received, double spent, double net}) _periodNet(AppStore store) {
    final pays = _periodPayments(store).where((p) => !p.cancelled);
    final received = pays.fold<double>(0, (a, p) => a + p.amount);
    final year = _filterYear(store);
    var spent = 0.0;
    for (final e in store.expenses) {
      if (!_matchesFinancePeriod(store, paymentDate: e.expenseDate)) continue;
      if (financeYearFilter != 'all' && year != null) {
        final d = e.expenseDate.split('T').first;
        if (d.compareTo(year.startsOn) < 0 || d.compareTo(year.endsOn) > 0) continue;
      }
      spent += e.amount;
    }
    for (final p in store.teacherPayouts) {
      final d = p.periodStart.isNotEmpty ? p.periodStart : p.paymentDate;
      if (!_matchesFinancePeriod(store, paymentDate: d)) continue;
      if (financeYearFilter != 'all' && year != null) {
        final day = d.split('T').first;
        if (day.compareTo(year.startsOn) < 0 || day.compareTo(year.endsOn) > 0) continue;
      }
      spent += p.amount;
    }
    return (received: received, spent: spent, net: received - spent);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('finance')) {
          return NoAccess(section: 'finance', roleName: store.roleName);
        }

        // التبويب يتبع الميزة وحدها كما في Finance.tsx: من يفتح المالية يرى
        // المصروفات، وتسجيل سند الصرف وحده يتطلب صلاحيته
        final showExpenses = store.features.enableExpenses && store.can('finance.expenses');
        if (tab == 2 && !showExpenses) tab = 0;

        final q = search.text.trim().toLowerCase();
        final allDues = store.dueItems().where((d) {
          final inst = d.installmentId == null
              ? null
              : store.installments.where((i) => i.id == d.installmentId).firstOrNull;
          return _matchesFinancePeriod(
            store,
            yearId: inst?.academicYearId,
            dueDate: isoDate(d.dueDate),
          );
        }).toList();

        // الإجراء يتبع التبويب: قبض دفعة، أو سند صرف في تبويب المصروفات
        final ThumbAction? action;
        if (tab == 2) {
          action = store.can('finance.expenses')
              ? ThumbAction(
                  label: 'إضافة سند صرف',
                  icon: Icons.add,
                  color: AppColors.navy,
                  onPressed: () async {
                    final saved = await showExpenseSheet(context, store);
                    if (saved && context.mounted)
                      showAppSnack(context, 'تم حفظ سند الصرف');
                  },
                )
              : null;
        } else if (tab == 3) {
          action = store.can('finance.collect')
              ? ThumbAction(
                  label: 'إيراد جديد',
                  icon: Icons.add_card,
                  color: AppColors.navy,
                  onPressed: () async {
                    final saved = await showGeneralIncomeSheet(context, store);
                    if (saved && context.mounted) {
                      showAppSnack(context, 'تم حفظ الإيراد وإصدار السند');
                    }
                  },
                )
              : null;
        } else if (tab == 4) {
          action = null;
        } else {
          action = store.can('finance.collect')
              ? ThumbAction(
                  label: 'دفعة جديدة',
                  icon: Icons.add_card,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PaymentFormScreen(),
                      ),
                    );
                  },
                )
              : null;
        }

        final net = showExpenses ? _periodNet(store) : null;

        return ThumbActionLayer(
          action: action,
          child: Column(
            children: [
              _periodBar(store, showExpenses, net),
              _tabBar(store, allDues.length, showExpenses),
              Expanded(
                child: switch (tab) {
                  1 => _payments(context, store, q),
                  2 => _expenses(store),
                  3 => _generalIncome(context, store),
                  4 => _controls(context, store),
                  _ => _dues(context, store, allDues, q),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── التبويبات ─────────────────────────────────────────────────────────────

  Widget _periodBar(
    AppStore store,
    bool showExpenses,
    ({double received, double spent, double net})? net,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      color: Colors.white,
      child: Row(
        children: [
          FilterButton(
            value: financeYearFilter,
            options: {
              'current': 'عام التشغيل',
              'all': 'كل الأعوام',
              for (final y in store.academicYears) y.id: y.label,
            },
            onSelected: (v) => setState(() => financeYearFilter = v),
          ),
          const SizedBox(width: 6),
          FilterButton(
            value: termFilter,
            options: const {
              'all': 'كل الفصول',
              'term_1': 'الفصل الأول',
              'term_2': 'الفصل الثاني',
            },
            onSelected: (v) => setState(() => termFilter = v),
          ),
          if (showExpenses && net != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'صافي ${money(net.net)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: net.net >= 0 ? AppColors.heading : AppColors.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabBar(AppStore store, int dueCount, bool showExpenses) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tab(
              'المستحقات',
              0,
              dueCount,
              alert: dueCount > 0,
            ),
          ),
          Expanded(
            child: _tab(
              'المقبوضات',
              1,
              _periodPayments(store).length,
            ),
          ),
          if (showExpenses)
            Expanded(
              child: _tab(
                'المصروفات',
                2,
                store.expenses.length + store.teacherPayouts.length,
              ),
            ),
          Expanded(
            child: _tab(
              'إيرادات',
              3,
              store.generalIncomes.length,
            ),
          ),
          Expanded(
            child: _tab(
              'الرقابة',
              4,
              store.pendingFinanceRequests.length,
              alert: store.pendingFinanceRequests.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(
    String label,
    int index,
    int count, {
    bool alert = false,
  }) {
    final on = tab == index;
    final fg = on ? AppColors.heading : AppColors.muted;
    return InkWell(
      onTap: () {
        if (tab == index) return;
        setState(() {
          tab = index;
          // لكل تبويب بحثه: نص يبحث عن وصل لا معنى له في المستحقات
          search.clear();
        });
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: fg,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Container(
                constraints: const BoxConstraints(minWidth: 15),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: alert ? AppColors.dangerSoft : const Color(0xFFF1F5F9),
                  border: Border.all(
                    color: alert ? AppColors.dangerBorder : AppColors.line,
                  ),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: alert ? AppColors.danger : AppColors.muted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── عناصر مشتركة بين التبويبات ────────────────────────────────────────────

  /// البحث وعدد النتائج وزر التصفية في سطر واحد.
  Widget _toolbar({
    required String hint,
    required int shown,
    required int total,
    required Widget filter,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SearchField(
              controller: search,
              hint: hint,
              onChanged: (_) => setState(() {}),
              trailing: Text(
                shown == total ? '$total' : '$shown/$total',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          filter,
        ],
      ),
    );
  }

  /// سجل يبدأ ببطاقات الأرقام ثم عناصره، يُبنى منه ما يظهر فقط.
  Widget _list({
    required List<Widget> header,
    required int count,
    required Widget empty,
    required IndexedWidgetBuilder item,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, thumbActionClearance),
      itemCount: 1 + (count == 0 ? 1 : count),
      itemBuilder: (context, i) {
        if (i == 0) {
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
          child: item(context, i - 1),
        );
      },
    );
  }

  // ── المقبوضات ─────────────────────────────────────────────────────────────

  Widget _payments(BuildContext context, AppStore store, String q) {
    final yearPayments = _periodPayments(store);
    final pays = yearPayments.where((p) {
      final name = (store.studentById(p.studentId)?.fullName ?? '')
          .toLowerCase();
      // البحث يشمل البيان والمحوِّل وجهة التحويل، كما في Finance.tsx
      final matchQ =
          q.isEmpty ||
          p.receiptNumber.toLowerCase().contains(q) ||
          name.contains(q) ||
          p.reference.toLowerCase().contains(q) ||
          p.notes.toLowerCase().contains(q) ||
          p.senderName.toLowerCase().contains(q) ||
          p.channel.toLowerCase().contains(q);
      final matchM = method.isEmpty || p.method == method;
      final matchS =
          status.isEmpty ||
          (status == 'active' && !p.cancelled) ||
          (status == 'cancelled' && p.cancelled);
      final matchSource = sourceFilter.isEmpty ||
          (sourceFilter == 'students' && p.studentId.isNotEmpty) ||
          (sourceFilter == 'other' && p.studentId.isEmpty);
      return matchQ && matchM && matchS && matchSource;
    }).toList();
    sortPayments(pays);

    final active = pays.where((p) => !p.cancelled).toList();
    final collected = active.fold<double>(0, (a, p) => a + p.amount);
    final cancelled = pays.length - active.length;
    final refunded = active.where((p) => p.amount < 0).length;
    return Column(
      children: [
        _toolbar(
          hint: 'ابحث برقم الوصل، الطالب، المرجع...',
          shown: pays.length,
          total: yearPayments.length,
          filter: GroupedFilterButton(
            groups: [
              FilterGroup(
                title: 'المصدر',
                options: const {
                  '': 'الكل',
                  'students': 'الطلاب',
                  'other': 'إيرادات أخرى',
                },
                value: sourceFilter,
                onSelected: (v) => setState(() => sourceFilter = v),
              ),
              FilterGroup(
                title: 'طريقة الدفع',
                options: {
                  '': 'كل طرق الدفع',
                  for (final m in store.paymentMethods) m.id: m.name,
                },
                value: method,
                onSelected: (v) => setState(() => method = v),
              ),
              FilterGroup(
                title: 'الحالة',
                options: _statusOptions,
                value: status,
                onSelected: (v) => setState(() => status = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: _list(
            header: [
              if (store.pendingFinanceRequests.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => tab = 4),
                  child: InfoStrip(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${store.pendingFinanceRequests.length} طلب مالي بانتظار الموافقة',
                          style: TextStyle(
                            color: AppColors.amberDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        for (final request in store.pendingFinanceRequests.take(
                          3,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '• ${request.summary}${request.requestedByName.isEmpty ? '' : ' — ${request.requestedByName}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'اضغط لفتح تبويب الطلبات والرقابة',
                            style: TextStyle(
                              color: AppColors.heading,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              StatRow(
                children: [
                  StatCard(
                    label: 'إجمالي المقبوض',
                    value: money(collected),
                    color: AppColors.success,
                    caption: '${active.length} سند معتمد',
                    compact: true,
                  ),
                  StatCard(
                    label: 'مستردة',
                    value: '$refunded',
                    color: refunded > 0 ? AppColors.danger : AppColors.heading,
                    caption: 'ردود وعكوس',
                    compact: true,
                  ),
                  StatCard(
                    label: 'السندات الملغاة',
                    value: '$cancelled',
                    color: cancelled > 0 ? AppColors.danger : AppColors.heading,
                    caption: 'من ${pays.length} سند',
                    compact: true,
                  ),
                ],
              ),
            ],
            count: pays.length,
            empty: const EmptyState(
              message: 'لا توجد دفعات مسجلة مطابقة للبحث',
            ),
            item: (context, i) {
              final p = pays[i];
              return _PaymentCard(
                payment: p,
                student: store.studentById(p.studentId),
                onCancel: _canCancelPayment(p)
                    ? () => _cancel(context, store, p)
                    : null,
              );
            },
          ),
        ),
      ],
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
                fontWeight: FontWeight.w800,
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
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
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
  Widget _controls(BuildContext context, AppStore store) {
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
                  fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (pendingRow) ...[
                const SizedBox(height: 9),
                if (store.isFinanceAdmin)
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
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
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GhostButton(
                          label: 'رفض',
                          onPressed: () =>
                              _rejectFinanceRequest(context, store, request),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'بانتظار المدير',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: AppColors.amberDark,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      children: [
        Text(
          'طلبات بانتظار الموافقة (${pending.length})',
          style: TextStyle(
            color: AppColors.heading,
            fontWeight: FontWeight.w900,
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
                fontWeight: FontWeight.w800,
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
              fontWeight: FontWeight.w900,
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
                      setState(() => auditUserFilter = v ?? ''),
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
                      setState(() => auditActionFilter = v ?? ''),
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
          else
            for (final a in audit)
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
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: AppColors.heading,
                              ),
                            ),
                          ),
                          if (a.amount != null)
                            Text(
                              money(a.amount!),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
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
        ],
      ],
    );
  }

  // ── المستحقات ─────────────────────────────────────────────────────────────

  Widget _dues(
    BuildContext context,
    AppStore store,
    List<DueItem> all,
    String q,
  ) {
    final dues = all.where((d) {
      final matchQ =
          q.isEmpty ||
          d.student.fullName.toLowerCase().contains(q) ||
          d.student.phone.contains(q) ||
          d.title.toLowerCase().contains(q);
      final matchS =
          dueStage.isEmpty ||
          (dueStage == 'late' && d.late) ||
          (dueStage == 'due' && !d.late && !d.scheduled);
      return matchQ && matchS;
    }).toList();

    // المطلوب اليوم: القسط الذي لم يحن موعده ليس ديناً على الطالب
    final total = dues
        .where((d) => !d.scheduled)
        .fold<double>(0, (a, d) => a + d.amount);
    final debtors = dues
        .where((d) => !d.scheduled)
        .map((d) => d.student.id)
        .toSet()
        .length;
    final lateCount = all.where((d) => d.late).length;
    final dueCount = all.where((d) => !d.late && !d.scheduled).length;
    final scheduledCount = all.where((d) => d.scheduled).length;
    final canCollect = store.can('finance.collect');
    final canOpenStudent = store.can('students');

    return Column(
      children: [
        _toolbar(
          hint: 'ابحث باسم الطالب أو رقم الهاتف...',
          shown: dues.length,
          total: all.length,
          filter: FilterButton(
            options: _stageOptions,
            value: dueStage,
            onSelected: (v) => setState(() => dueStage = v),
          ),
        ),
        Expanded(
          child: _list(
            header: [
              StatRow(
                children: [
                  StatCard(
                    label: 'إجمالي المستحق',
                    value: money(total),
                    color: AppColors.danger,
                    caption: '${dues.length} بند',
                    compact: true,
                  ),
                  // للإدارة وحدها: متوقع لا يُطالَب به قبل موعده
                  StatCard(
                    label: 'باقي السنة',
                    value: money(store.projectRemainingYear()),
                    color: AppColors.heading,
                    caption: 'متوقع',
                    compact: true,
                  ),
                  StatCard(
                    label: 'طلاب عليهم مستحقات',
                    value: '$debtors',
                    color: AppColors.heading,
                    caption: 'من ${store.students.length} طالب',
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InfoStrip(
                child: Row(
                  children: [
                    Expanded(
                      child: _tally('متأخر', lateCount, AppColors.danger),
                    ),
                    const Text('•', style: TextStyle(color: AppColors.faint)),
                    Expanded(child: _tally('مستحق', dueCount, AppColors.amber)),
                    const Text('•', style: TextStyle(color: AppColors.faint)),
                    Expanded(
                      child: _tally('مجدول', scheduledCount, AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
            count: dues.length,
            empty: const EmptyState(message: 'لا مستحقات'),
            item: (context, i) {
              final d = dues[i];
              return _DueCard(
                item: d,
                onOpen: canOpenStudent
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              StudentDetailScreen(studentId: d.student.id),
                        ),
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
        ),
      ],
    );
  }

  Widget _tally(String label, int value, Color color) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: TallyText(label, value, color),
      ),
    );
  }

  // ── الإيرادات العامة ─────────────────────────────────────────────────────

  Widget _generalIncome(BuildContext context, AppStore store) {
    final rows = store.generalIncomes;
    final active = rows.where((e) => !e.cancelled).toList();
    final total = active.fold<double>(0, (sum, e) => sum + e.amount);
    return _list(
      header: [
        StatRow(
          children: [
            StatCard(
              label: 'الإيرادات العامة',
              value: money(total),
              color: AppColors.success,
              caption: '${active.length} سند معتمد',
              compact: true,
            ),
            StatCard(
              label: 'كل السندات',
              value: '${rows.length}',
              color: AppColors.heading,
              caption: store.viewedAcademicYear?.label ?? 'العام المعروض',
              compact: true,
            ),
          ],
        ),
      ],
      count: rows.length,
      empty: const EmptyState(message: 'لا توجد إيرادات عامة في هذا العام'),
      item: (context, i) => _IncomeCard(
        income: rows[i],
        methodLabel: store.paymentMethodLabel(rows[i].method),
        onEdit: !rows[i].cancelled && store.can('finance.collect')
            ? () => showGeneralIncomeSheet(context, store, income: rows[i])
            : null,
        onCancel: !rows[i].cancelled && store.can('finance.cancel')
            ? () async {
                final payment = store.payments
                    .where((p) => p.id == rows[i].id)
                    .firstOrNull;
                if (payment != null) await _cancel(context, store, payment);
              }
            : null,
      ),
    );
  }

  // ── المصروفات وأجور المعلمين ──────────────────────────────────────────────

  /// سجل موحّد للمصروفات وأجور المعلمين مرتّب بالتاريخ تنازلياً —
  /// نفس دمج القائمتين في جدول واحد في Finance.tsx.
  Widget _expenses(AppStore store) {
    final linked = statementTeacherId.isEmpty
        ? null
        : store.linkedTeacherIds(statementTeacherId);
    final expenses = store.expenses;
    final payouts = [
      for (final p in store.teacherPayouts)
        if (linked == null || linked.contains(p.teacherId)) p,
    ];
    final rows = <_SpendRow>[
      for (final e in expenses)
        if (linked == null)
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
          description: payoutDescription(
            p,
            fallbackName: store.teacherById(p.teacherId)?.name ?? '',
          ),
          amount: p.amount,
          method: p.method,
          voucher: ExpenseVoucher.fromPayout(
            p,
            fallbackName: store.teacherById(p.teacherId)?.name ?? '',
          ),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final payoutTotal = payouts.fold<double>(0, (a, p) => a + p.amount);
    final expenseTotal = linked == null
        ? store.totalExpenses
        : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: AppDropdown<String>(
            value: statementTeacherId.isEmpty ? null : statementTeacherId,
            hint: 'كل المعلمين',
            items: [
              const DropdownMenuItem(value: '', child: Text('كل المعلمين')),
              for (final t in store.teachersInViewedYear)
                DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => statementTeacherId = v ?? ''),
          ),
        ),
        Expanded(
          child: _list(
            header: [
              _SalariesDueCard(store: store),
              const SizedBox(height: 8),
              StatRow(
                children: [
                  StatCard(
                    label: linked == null ? 'المصروفات' : 'سندات المعلم',
                    value: money(expenseTotal + payoutTotal),
                    color: AppColors.danger,
                    caption: '${rows.length} سند',
                    compact: true,
                  ),
                  if (linked == null)
                    StatCard(
                      label: 'تشغيلية',
                      value: money(store.totalExpenses),
                      color: AppColors.heading,
                      caption: '${expenses.length} سند',
                      compact: true,
                    ),
                  StatCard(
                    label: 'أجور معلمين',
                    value: money(payoutTotal),
                    color: AppColors.amber,
                    caption: '${payouts.length} دفعة',
                    compact: true,
                  ),
                ],
              ),
            ],
            count: rows.length,
            empty: const EmptyState(message: 'لا سندات صرف'),
            item: (context, i) => _SpendCard(row: rows[i]),
          ),
        ),
      ],
    );
  }
}

// ═══ بطاقات السجل ════════════════════════════════════════════════════════════

TextStyle get _titleStyle => TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 13,
  color: AppColors.heading,
);

const _metaStyle = TextStyle(color: AppColors.muted, fontSize: 11);

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

/// حالة البند بألوان Finance.tsx: متأخر أحمر، ومستحق بلون العمليات.
StatusChip _stageChip(DueItem d) {
  if (d.late) return StatusChip.danger(d.stageLabel);
  // المجدول ليس مطلوباً بعد، فلا يُلوَّن بلون المطالبة
  return d.scheduled
      ? StatusChip.muted(d.stageLabel)
      : StatusChip.amber(d.stageLabel);
}

/// سند قبض: الطالب مقابل المبلغ، ثم رقم الوصل وتاريخه مقابل طريقة الدفع، ثم خط
/// رفيع، ثم الحالة مقابل أزرار الوصل والواتساب والإلغاء.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.student,
    this.onCancel,
  });

  final Payment payment;
  final Student? student;
  final VoidCallback? onCancel;

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
    ].join('  ');
    final reversed = p.reversedByPaymentId != null;
    final sameDay = dateOnly(p.date) == dateOnly(DateTime.now());
    final amountColor = p.cancelled
        ? AppColors.faint
        : (p.amount < 0 ? AppColors.danger : AppColors.success);

    return AppCard(
      onTap: () => ReceiptScreen.open(context, p),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(p.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: amountColor,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          if (p.discountAmount.abs() > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '(خصم: -${money(p.discountAmount.abs())})',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          Icons.receipt_long_outlined,
                          size: 13,
                          color: AppColors.amber,
                        ),
                      ),
                      TextSpan(
                        text: ' ${p.receiptNumber}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.heading,
                        ),
                      ),
                      TextSpan(text: '  ·  ${formatDate(p.date)}'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
              ),
              const SizedBox(width: 8),
              // طريقة الدفع في طرف السطر تحت المبلغ، لا في منتصف البطاقة
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  method,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: _metaStyle,
                ),
              ),
            ],
          ),
          const _Rule(),
          Row(
            children: [
              if (p.cancelled)
                StatusChip.danger('ملغى')
              else if (reversed)
                StatusChip.muted('معكوس')
              else
                StatusChip.success('معتمد'),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    alignment: WrapAlignment.end,
                    children: [
                      TileButton(
                        label: 'الوصل',
                        icon: const Icon(Icons.print_outlined, size: 13),
                        color: AppColors.heading,
                        background: Colors.white,
                        border: AppColors.lineStrong,
                        onTap: () => ReceiptScreen.open(context, p),
                      ),
                      if (!p.cancelled && !reversed && student != null)
                        TileButton(
                          label: 'واتساب',
                          icon: const MessageCircleIcon(
                            color: AppColors.success,
                            size: 12,
                          ),
                          color: AppColors.success,
                          background: AppColors.successSoft,
                          border: const Color(0xFF86EFAC),
                          onTap: () =>
                              ReceiptScreen.sendWhatsApp(context, p, student!),
                        ),
                      if (onCancel != null)
                        TileButton(
                          label: sameDay ? 'إلغاء' : 'عكس',
                          icon: const Icon(Icons.block, size: 13),
                          color: AppColors.danger,
                          background: Colors.white,
                          border: AppColors.dangerBorder,
                          onTap: onCancel!,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بند مستحق: الطالب ومرحلته مقابل حالة البند، ثم خط رفيع، ثم البيان وتاريخ
/// الاستحقاق مقابل المبلغ وزر التسديد. البطاقة تفتح ملف الطالب.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.item, this.onOpen, this.onPay});

  final DueItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final d = item;
    final meta = [
      if (d.student.gradeLevel.trim().isNotEmpty) d.student.gradeLevel.trim(),
      if (d.student.phone.trim().isNotEmpty) d.student.phone.trim(),
    ].join('  ·  ');

    return AppCard(
      onTap: onOpen,
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
                    Text(
                      d.student.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _metaStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _stageChip(d),
            ],
          ),
          const _Rule(),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'استحقاق: ${formatDate(d.dueDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _metaStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(d.amount),
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              if (onPay != null) ...[
                const SizedBox(width: 8),
                TileButton(
                  label: 'تسديد',
                  icon: const Icon(Icons.credit_card, size: 13),
                  color: Colors.white,
                  background: AppColors.amber,
                  border: AppColors.amber,
                  onTap: onPay!,
                ),
              ],
            ],
          ),
        ],
      ),
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

/// سند صرف: البيان مقابل المبلغ، ثم التاريخ وطريقة الصرف مقابل التصنيف.
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.row});
  final _SpendRow row;

  @override
  Widget build(BuildContext context) {
    // التاريخ يصل أحياناً بطابع زمني كامل من السحابة — يُعرض يوماً فقط
    final day = parseIsoDate(
      row.date.length >= 10 ? row.date.substring(0, 10) : row.date,
    );
    final details = [
      day == null ? row.date : formatDate(day),
      StoreScope.of(context).paymentMethodLabel(row.method),
    ].join('  ·  ');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      // السند المطبوع يُسلَّم لمن قبض المبلغ، فيُفتح بلمس بطاقته
      onTap: () => ExpenseVoucher.open(context, row.voucher),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.description.trim().isEmpty
                      ? row.category
                      : row.description.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(row.amount),
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // التاريخ وطريقة الصرف تحت البيان، والتصنيف في الطرف تحت المبلغ
          Row(
            children: [
              Expanded(
                child: Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: row.isPayout
                    ? StatusChip.amber(row.category)
                    : StatusChip.muted(row.category),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// سند إيراد عام: الجهة والبيان دون إيهام بأنه مرتبط بملف طالب.
class _IncomeCard extends StatelessWidget {
  const _IncomeCard({
    required this.income,
    required this.methodLabel,
    this.onEdit,
    this.onCancel,
  });

  final GeneralIncome income;
  final String methodLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  income.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
              Text(
                money(income.amount),
                style: TextStyle(
                  color: income.cancelled ? AppColors.faint : AppColors.success,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  decoration: income.cancelled
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              income.category,
              formatDate(income.date),
              methodLabel,
              if (income.note.isNotEmpty) income.note,
            ].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _metaStyle,
          ),
          if (onEdit != null || onCancel != null) ...[
            const _Rule(),
            Row(
              children: [
                income.cancelled
                    ? StatusChip.danger('ملغى')
                    : StatusChip.success('معتمد'),
                const Spacer(),
                if (onEdit != null)
                  TileButton(
                    label: 'تعديل',
                    icon: const Icon(Icons.edit_outlined, size: 13),
                    color: AppColors.heading,
                    background: Colors.white,
                    border: AppColors.lineStrong,
                    onTap: onEdit!,
                  ),
                if (onEdit != null && onCancel != null)
                  const SizedBox(width: 5),
                if (onCancel != null)
                  TileButton(
                    label: 'إبطال',
                    icon: const Icon(Icons.block, size: 13),
                    color: AppColors.danger,
                    background: Colors.white,
                    border: AppColors.dangerBorder,
                    onTap: onCancel!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// رواتب الشهر الجاري: ما صُرف لكل معلم، وزر صرفها دفعةً واحدة.
///
/// لا «مستحق» ولا «متبقٍّ»: المدرسة عمل خاص لا وظيفة حكومية، فشهر بلا راتب وشهر
/// بأكثر منه وشهر إجازة. الصرف يُنسب لشهر الراتب لا ليوم صرفه، فراتب أيلول
/// المصروف في تشرين يبقى لأيلول.
class _SalariesDueCard extends StatelessWidget {
  const _SalariesDueCard({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (store.teachersInViewedYear.isEmpty) return const SizedBox.shrink();
    final month = monthKeyOf(DateTime.now());
    final rows = [
      for (final t in store.teachersInViewedYear)
        (teacher: t, paid: paidInMonth(store.teacherPayouts, store.linkedTeacherIds(t.id), month)),
    ];
    final total = rows.fold<double>(0, (sum, r) => sum + r.paid.total);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'رواتب ${monthLabel(month)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: AppColors.heading,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final count = await showPayrollSheet(
                    context,
                    store,
                    month: month,
                  );
                  if (count > 0 && context.mounted) {
                    showAppSnack(context, 'صُرفت رواتب $count معلماً');
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.amber,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('صرف الرواتب'),
              ),
            ],
          ),
          Text(
            total > 0
                ? 'صُرف هذا الشهر ${money(total)}'
                : 'لم يُصرف شيء هذا الشهر',
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
          for (final row in rows.where((r) => r.paid.total > 0))
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
                          row.teacher.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          [
                            if (row.paid.salary > 0)
                              'راتب ${money(row.paid.salary)}',
                            if (row.paid.advance > 0)
                              'سلفة ${money(row.paid.advance)}',
                            if (row.paid.bonus > 0)
                              'مكافأة ${money(row.paid.bonus)}',
                          ].join('  ·  '),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    money(row.paid.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: AppColors.success,
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
                    fontWeight: FontWeight.w800,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'الشهر السابق',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_right, size: 18),
                            onPressed: () => setSt(
                              () => payrollMonth = shiftMonth(payrollMonth, -1),
                            ),
                          ),
                          Text(
                            monthLabel(payrollMonth),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: AppColors.heading,
                            ),
                          ),
                          IconButton(
                            tooltip: 'الشهر التالي',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.chevron_left, size: 18),
                            onPressed: () => setSt(
                              () => payrollMonth = shiftMonth(payrollMonth, 1),
                            ),
                          ),
                        ],
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
                        fontWeight: FontWeight.w800,
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
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'إلغاء',
                        onPressed: () => Navigator.pop(ctx, 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
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

  for (final c in amounts.values) {
    c.dispose();
  }
  return saved ?? 0;
}
