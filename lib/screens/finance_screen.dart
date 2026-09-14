import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'expense_form_sheet.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'student_detail_screen.dart';

/// المالية والصندوق — بتبويبات `pages/Finance.tsx`: المقبوضات، والمستحقات،
/// والمصروفات وأجور المعلمين.
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

  static const _statusOptions = {'': 'كل الحالات', 'active': 'مقبوضة', 'cancelled': 'ملغاة'};
  static const _stageOptions = {
    '': 'كل الحالات',
    'due': 'مستحق',
    'late': 'متأخر عن السداد',
    'scheduled': 'مجدول',
    'exception': 'استثناء',
  };

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
        final showExpenses = store.features.enableExpenses;
        if (tab == 2 && !showExpenses) tab = 0;

        final q = search.text.trim().toLowerCase();
        final allDues = store.dueItems();

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
                    if (saved && context.mounted) showAppSnack(context, 'تم حفظ سند الصرف');
                  },
                )
              : null;
        } else {
          action = store.can('finance')
              ? ThumbAction(
                  label: 'دفعة جديدة',
                  icon: Icons.add_card,
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentFormScreen()));
                  },
                )
              : null;
        }

        return ThumbActionLayer(
          action: action,
          child: Column(
            children: [
              _tabBar(store, allDues.length, showExpenses),
              Expanded(
                child: switch (tab) {
                  1 => _dues(context, store, allDues, q),
                  2 => _expenses(store),
                  _ => _payments(context, store, q),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ── التبويبات ─────────────────────────────────────────────────────────────

  Widget _tabBar(AppStore store, int dueCount, bool showExpenses) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(child: _tab('المقبوضات', Icons.receipt_long_outlined, 0, store.payments.length)),
          Expanded(child: _tab('المستحقات', Icons.schedule, 1, dueCount, alert: dueCount > 0)),
          if (showExpenses)
            Expanded(
              child: _tab('المصروفات', Icons.payments_outlined, 2, store.expenses.length + store.teacherPayouts.length),
            ),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, int index, int count, {bool alert = false}) {
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
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: on ? AppColors.accent : Colors.transparent, width: 2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.chip),
                color: alert ? AppColors.dangerSoft : const Color(0xFFF1F5F9),
                border: Border.all(color: alert ? AppColors.dangerBorder : AppColors.line),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: alert ? AppColors.danger : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── عناصر مشتركة بين التبويبات ────────────────────────────────────────────

  /// البحث وعدد النتائج وزر التصفية في سطر واحد.
  Widget _toolbar({required String hint, required int shown, required int total, required Widget filter}) {
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
                style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header),
          );
        }
        if (count == 0) return SizedBox(height: 220, child: empty);
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: item(context, i - 1));
      },
    );
  }

  // ── المقبوضات ─────────────────────────────────────────────────────────────

  Widget _payments(BuildContext context, AppStore store, String q) {
    final pays = store.payments.where((p) {
      final name = (store.studentById(p.studentId)?.fullName ?? '').toLowerCase();
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
      return matchQ && matchM && matchS;
    }).toList();
    sortPayments(pays);

    final active = pays.where((p) => !p.cancelled).toList();
    final collected = active.fold<double>(0, (a, p) => a + p.amount);
    final cancelled = pays.length - active.length;
    final canCancel = store.can('finance');

    return Column(
      children: [
        _toolbar(
          hint: 'ابحث برقم الوصل، الطالب، المرجع...',
          shown: pays.length,
          total: store.payments.length,
          filter: GroupedFilterButton(
            groups: [
              FilterGroup(
                title: 'طريقة الدفع',
                options: {'': 'كل طرق الدفع', for (final m in store.paymentMethods) m.id: m.name},
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
              StatRow(
                children: [
                  StatCard(
                    label: 'إجمالي المقبوض',
                    value: money(collected),
                    color: AppColors.success,
                    caption: '${active.length} سند معتمد',
                  ),
                  StatCard(
                    label: 'السندات الملغاة',
                    value: '$cancelled',
                    color: cancelled > 0 ? AppColors.danger : AppColors.heading,
                    caption: 'من ${pays.length} سند',
                  ),
                ],
              ),
            ],
            count: pays.length,
            empty: const EmptyState(message: 'لا توجد دفعات مسجلة مطابقة للبحث'),
            item: (context, i) => _PaymentCard(
              payment: pays[i],
              student: store.studentById(pays[i].studentId),
              onCancel: !pays[i].cancelled && canCancel ? () => _cancel(context, store, pays[i]) : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cancel(BuildContext context, AppStore store, Payment p) async {
    final ok = await confirmSheet(
      context,
      title: 'تأكيد إلغاء الدفعة',
      message: 'هل أنت متأكد من إلغاء الدفعة رقم ${p.receiptNumber} بمبلغ ${money(p.amount)}؟ '
          'سيُعكس رصيد الطالب تلقائياً.',
      confirmLabel: 'إلغاء السند',
    );
    if (!ok || !context.mounted) return;
    try {
      store.cancelPayment(p);
      showAppSnack(context, 'تم إلغاء السند وعكس الرصيد');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  // ── المستحقات ─────────────────────────────────────────────────────────────

  Widget _dues(BuildContext context, AppStore store, List<DueItem> all, String q) {
    final dues = all.where((d) {
      final matchQ = q.isEmpty ||
          d.student.fullName.toLowerCase().contains(q) ||
          d.student.phone.contains(q) ||
          d.title.toLowerCase().contains(q);
      final matchS = dueStage.isEmpty ||
          (dueStage == 'late' && d.late) ||
          (dueStage == 'due' && !d.late && !d.scheduled) ||
          (dueStage == 'scheduled' && d.scheduled);
      return matchQ && matchS;
    }).toList();

    // المطلوب اليوم: القسط الذي لم يحن موعده ليس ديناً على الطالب
    final total = dues.where((d) => !d.scheduled).fold<double>(0, (a, d) => a + d.amount);
    final debtors = dues.where((d) => !d.scheduled).map((d) => d.student.id).toSet().length;
    final lateCount = all.where((d) => d.late).length;
    final dueCount = all.where((d) => !d.late && !d.scheduled).length;
    final scheduledCount = all.where((d) => d.scheduled).length;
    final canCollect = store.can('finance');
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
                  ),
                  StatCard(
                    label: 'طلاب عليهم مستحقات',
                    value: '$debtors',
                    color: AppColors.heading,
                    caption: 'من ${store.students.length} طالب',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InfoStrip(
                child: Row(
                  children: [
                    Expanded(child: _tally('متأخر', lateCount, AppColors.danger)),
                    const Text('•', style: TextStyle(color: AppColors.faint)),
                    Expanded(child: _tally('مستحق', dueCount, AppColors.amber)),
                    const Text('•', style: TextStyle(color: AppColors.faint)),
                    Expanded(child: _tally('مجدول', scheduledCount, AppColors.muted)),
                  ],
                ),
              ),
            ],
            count: dues.length,
            empty: const EmptyState(message: 'لا توجد دفعات أو أقساط مستحقة مطابقة للبحث. الحسابات منتظمة ومسددة.'),
            item: (context, i) {
              final d = dues[i];
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
        ),
      ],
    );
  }

  Widget _tally(String label, int value, Color color) {
    return Center(child: FittedBox(fit: BoxFit.scaleDown, child: TallyText(label, value, color)));
  }

  // ── المصروفات وأجور المعلمين ──────────────────────────────────────────────

  /// سجل موحّد للمصروفات وأجور المعلمين مرتّب بالتاريخ تنازلياً —
  /// نفس دمج القائمتين في جدول واحد في Finance.tsx.
  Widget _expenses(AppStore store) {
    final expenses = store.expenses;
    final payouts = store.teacherPayouts;
    final rows = <_SpendRow>[
      for (final e in expenses)
        _SpendRow(
          date: e.expenseDate,
          isPayout: false,
          category: expenseCategoryLabel(e.category),
          description: e.description,
          amount: e.amount,
          method: e.method,
        ),
      for (final p in payouts)
        _SpendRow(
          date: p.paymentDate,
          isPayout: true,
          category: 'أجور تدريس',
          // الاسم المجمَّد وقت الصرف أولاً: سند سابق لا يتغيّر نصّه إذا عُدّل اسم
          // المعلم أو حُذف بعد صرفه — مطابق لـ `p.teacher_name || t?.name`
          description: switch (p.teacherName.trim().isNotEmpty
              ? p.teacherName.trim()
              : (store.teacherById(p.teacherId)?.name ?? '')) {
            '' => 'صرف مستحقات معلم',
            final name => 'صرف مستحقات المعلم: $name',
          },
          amount: p.amount,
          method: p.method,
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return _list(
      header: [
        StatRow(
          children: [
            StatCard(
              label: 'المصروفات',
              value: money(store.totalExpenses + store.totalPayouts),
              color: AppColors.danger,
              caption: '${rows.length} سند',
            ),
            StatCard(
              label: 'تشغيلية',
              value: money(store.totalExpenses),
              color: AppColors.heading,
              caption: '${expenses.length} سند',
            ),
            StatCard(
              label: 'أجور معلمين',
              value: money(store.totalPayouts),
              color: AppColors.amber,
              caption: '${payouts.length} دفعة',
            ),
          ],
        ),
      ],
      count: rows.length,
      empty: const EmptyState(message: 'لا توجد سندات صرف أو دفعات أجور مسجلة حتى الآن.'),
      item: (context, i) => _SpendCard(row: rows[i]),
    );
  }
}

// ═══ بطاقات السجل ════════════════════════════════════════════════════════════

TextStyle get _titleStyle => TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading);

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
  return d.scheduled ? StatusChip.muted(d.stageLabel) : StatusChip.amber(d.stageLabel);
}

/// سند قبض: الطالب مقابل المبلغ، ثم رقم الوصل وتاريخه مقابل طريقة الدفع، ثم خط
/// رفيع، ثم الحالة مقابل أزرار الوصل والواتساب والإلغاء.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.student, this.onCancel});

  final Payment payment;
  final Student? student;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final name = student?.fullName ?? (p.notes.trim().isEmpty ? 'سند عام' : p.notes.trim());
    final method = [
      StoreScope.of(context).paymentMethodLabel(p.method),
      if (p.reference.trim().isNotEmpty) '#${p.reference.trim()}',
    ].join('  ');

    return AppCard(
      onTap: () => ReceiptScreen.open(context, p),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle)),
              const SizedBox(width: 8),
              Text(
                money(p.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: p.cancelled ? AppColors.faint : AppColors.success,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
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
                        child: Icon(Icons.receipt_long_outlined, size: 13, color: AppColors.amber),
                      ),
                      TextSpan(
                        text: ' ${p.receiptNumber}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading),
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
                child: Text(method, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: _metaStyle),
              ),
            ],
          ),
          const _Rule(),
          Row(
            children: [
              p.cancelled ? StatusChip.danger('ملغى') : StatusChip.success('معتمد'),
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
                      if (!p.cancelled && student != null)
                        TileButton(
                          label: 'واتساب',
                          icon: const MessageCircleIcon(color: AppColors.success, size: 12),
                          color: AppColors.success,
                          background: AppColors.successSoft,
                          border: const Color(0xFF86EFAC),
                          onTap: () => ReceiptScreen.sendWhatsApp(context, p, student!),
                        ),
                      if (onCancel != null)
                        TileButton(
                          label: 'إلغاء',
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
                    Text(d.student.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
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
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text('استحقاق: ${formatDate(d.dueDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(money(d.amount), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900, fontSize: 15)),
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
  });

  final String date;
  final bool isPayout;
  final String category;
  final String description;
  final double amount;
  final String method;
}

/// سند صرف: البيان مقابل المبلغ، ثم التاريخ وطريقة الصرف مقابل التصنيف.
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.row});
  final _SpendRow row;

  @override
  Widget build(BuildContext context) {
    // التاريخ يصل أحياناً بطابع زمني كامل من السحابة — يُعرض يوماً فقط
    final day = parseIsoDate(row.date.length >= 10 ? row.date.substring(0, 10) : row.date);
    final details = [
      day == null ? row.date : formatDate(day),
      expenseMethodNames[row.method] ?? row.method,
    ].join('  ·  ');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  row.description.trim().isEmpty ? row.category : row.description.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(money(row.amount), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          // التاريخ وطريقة الصرف تحت البيان، والتصنيف في الطرف تحت المبلغ
          Row(
            children: [
              Expanded(child: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: _metaStyle)),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: row.isPayout ? StatusChip.amber(row.category) : StatusChip.muted(row.category),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
