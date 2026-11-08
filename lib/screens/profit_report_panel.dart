import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/profit_report.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../data/year_closing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/finance_documents.dart';
import '../widgets/ledger_row.dart';
import '../widgets/widgets.dart';
import 'year_close_sheet.dart';

/// تبويب الأرباح في المالية — `ProfitReportPanel.tsx`: ربح الفترة شهراً شهراً،
/// بتاريخ الدفع أو بموعد القسط، والمسحوب منه والباقي.
class ProfitReportPanel extends StatefulWidget {
  const ProfitReportPanel({super.key, required this.store, this.year});

  final AppStore store;

  /// عام شاشة المالية المختار.
  final AcademicYear? year;

  @override
  State<ProfitReportPanel> createState() => _ProfitReportPanelState();
}

const _periods = <String, String>{
  'month': 'شهر',
  'term_1': 'الفصل الأول',
  'term_2': 'الفصل الثاني',
  'year': 'السنة',
  'custom': 'من – إلى',
};

/// الأعمدة كالويب؛ المقبوض صافٍ بعد الرد والعكس.
final _columns = <(String, double Function(ProfitRow))>[
  ('المقبوض', (r) => r.received),
  ('المصاريف', (r) => r.expenses),
  ('الرواتب', (r) => r.salaries),
  ('الربح', (r) => r.net),
  ('المسحوب', (r) => r.draws),
  ('الباقي', (r) => r.remaining),
];

class _ProfitReportPanelState extends State<ProfitReportPanel> {
  final today = isoDate(DateTime.now());
  String period = 'year';
  late String month = today.substring(0, 7);
  late String from = widget.year?.startsOn ?? today;
  late String to = today;
  ProfitBasis basis = ProfitBasis.paid;

  /// حساب مختار من مربعات الباقي: التقرير يعرض حركته وحده.
  String spendMethod = '';

  ({String from, String to}) get range {
    if (period == 'month') {
      final y = int.parse(month.substring(0, 4));
      final m = int.parse(month.substring(5, 7));
      final last = DateTime(y, m + 1, 0).day;
      return (from: '$month-01', to: '$month-${last.toString().padLeft(2, '0')}');
    }
    if (period == 'custom') return from.compareTo(to) <= 0 ? (from: from, to: to) : (from: to, to: from);
    final year = widget.year;
    if (year == null) return (from: '${today.substring(0, 4)}-01-01', to: '${today.substring(0, 4)}-12-31');
    return academicRange(year, period == 'year' ? 'all' : period);
  }

  ProfitReport get report => computeProfitReport(
        payments: spendMethod.isEmpty
            ? widget.store.payments
            : widget.store.payments.where((p) => p.method == spendMethod).toList(),
        installments: widget.store.installments,
        expenses: spendMethod.isEmpty
            ? widget.store.expenses
            : widget.store.expenses.where((e) => e.method == spendMethod).toList(),
        payouts: spendMethod.isEmpty
            ? widget.store.teacherPayouts
            : widget.store.teacherPayouts.where((p) => p.method == spendMethod).toList(),
        range: range,
        basis: basis,
      );

  String get _basisLabel => basis == ProfitBasis.paid ? 'حسب تاريخ الدفع' : 'حسب موعد القسط';

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('$month-01'),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: 'أي يوم من الشهر',
    );
    if (picked != null) setState(() => month = isoDate(picked).substring(0, 7));
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    setState(() => start ? from = isoDate(picked) : to = isoDate(picked));
  }

  Future<void> _print(ProfitReport r) => runBusyOp(context, () async {
        final store = widget.store;
        final period = '${formatDate(DateTime.parse(range.from))} – ${formatDate(DateTime.parse(range.to))}';
        String cell(double v) => '${v < 0 ? '-' : ''}${money(v)}';
        final bytes = await PdfKit.buildSafe(
          title: 'تقرير الأرباح',
          institutionName: store.institutionName,
          logoBase64: store.institutionLogo,
          subtitle: '$period · $_basisLabel',
          body: (_) => [
            PdfKit.table(
              headers: ['الشهر', for (final c in _columns) c.$1],
              rows: [
                for (final row in r.rows) [monthLabel(row.month), for (final c in _columns) cell(c.$2(row))],
                ['المجموع', for (final c in _columns) cell(c.$2(r.total))],
              ],
              flex: const [3, 3, 3, 3, 3, 3, 3],
            ),
          ],
          endMatter: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                'الخصومات: ${money(r.total.discounts)}'
                '${r.total.refunds != 0 ? ' · المردود: ${money(-r.total.refunds)}' : ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        );
        if (!mounted) return;
        if (bytes == null) {
          showAppSnack(context, 'تعذّر تجهيز التقرير', error: true);
          return;
        }
        DocExport.showActions(context, bytes, PdfKit.fileName('تقرير الأرباح'));
      }, message: 'جارٍ تجهيز التقرير...');

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Choice(
                    value: period,
                    options: _periods,
                    onPick: (v) => setState(() => period = v),
                  ),
                  if (period == 'month') _DateChip(label: monthLabel(month), onTap: _pickMonth),
                  if (period == 'custom') ...[
                    _DateChip(label: from, onTap: () => _pickDate(true)),
                    _DateChip(label: to, onTap: () => _pickDate(false)),
                  ],
                  Tooltip(
                    message: basis == ProfitBasis.paid
                        ? 'كل دفعة في شهر قبضها'
                        : 'كل دفعة في شهر موعد قسطها؛ الإيراد العام والزائد على يوم القبض',
                    child: _Choice(
                      value: basis.name,
                      options: const {'paid': 'تاريخ الدفع', 'due': 'موعد القسط'},
                      onPick: (v) => setState(() => basis = ProfitBasis.values.byName(v)),
                    ),
                  ),
                ],
              ),
            ),
            _toolsMenu(r),
          ],
        ),
        ..._wallets(),
        const SizedBox(height: 10),
        _monthsList(r),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
            children: [
              const TextSpan(text: 'الخصومات: '),
              TextSpan(text: money(r.total.discounts), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (r.total.refunds != 0) ...[
                const TextSpan(text: '  ·  المردود: '),
                TextSpan(text: money(-r.total.refunds), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// قائمة الأدوات: التنزيل وكشف الحسابات وإقفال السنة في قائمة واحدة بدل أزرار تتجاوز عرض الشاشة.
  Widget _toolsMenu(ProfitReport r) {
    final store = widget.store;
    final year = widget.year;
    final wallets = year == null ? null : store.yearBook[year.id];
    final canClose = year != null && wallets != null && store.isAdminUser;
    final closeLabel = wallets == null ? '' : (wallets.stale ? 'أعد الإقفال' : (wallets.closed != null ? 'السنة مقفلة' : 'إقفال السنة'));
    return PopupMenuButton<String>(
      tooltip: 'المزيد',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        if (v == 'pdf') {
          await _print(r);
        } else if (v == 'close' && canClose) {
          await showYearCloseSheet(context, store, year: year, wallets: wallets);
          if (mounted) setState(() {});
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'pdf', child: Text('تنزيل التقرير PDF')),
        if (canClose) PopupMenuItem(value: 'close', child: Text(closeLabel)),
      ],
    );
  }

  /// الباقي في كل حساب: لوحة بسطر لكل حساب (يفلتر التقرير بلمسه) ومجموع ختامي.
  List<Widget> _wallets() {
    final store = widget.store;
    final year = widget.year;
    final wallets = year == null ? null : store.yearBook[year.id];
    final rows = balanceRows(
      wallets?.closing ??
          walletFlows(
            payments: store.payments,
            expenses: store.expenses,
            payouts: store.teacherPayouts,
            from: '',
            until: '9999-12-31',
          ),
    );
    final opening = wallets?.opening.values.fold<double>(0, (a, v) => a + v) ?? 0;
    final groups = <({String owner, List<({String method, double amount})> items})>[];
    final ungrouped = rows;
    final total = rows.fold<double>(0, (a, r) => a + r.amount);

    Widget accountRow(({String method, double amount}) row) {
      final active = spendMethod == row.method;
      return InkWell(
        onTap: () => setState(() => spendMethod = active ? '' : row.method),
        child: Container(
          color: active ? AppColors.navy.withValues(alpha: 0.06) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              if (active) ...[Icon(Icons.check_circle, size: 16, color: AppColors.navy), const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  row.method.isEmpty ? 'بلا طريقة' : store.paymentMethodLabel(row.method),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.heading),
                ),
              ),
              Text(
                webMoney(row.amount),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: row.amount < 0 ? AppColors.danger : AppColors.success),
              ),
            ],
          ),
        ),
      );
    }

    final items = <Widget>[
      for (final g in groups) ...[
        Container(
          color: AppColors.sunken,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(children: [
            Expanded(child: Text(g.owner, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted))),
            Text(webMoney(g.items.fold<double>(0, (a, i) => a + i.amount)),
                textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ),
        for (final i in g.items) accountRow(i),
      ],
      for (final i in ungrouped) accountRow(i),
    ];

    return [
      const SizedBox(height: 12),
      if (opening.abs() >= 0.01)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('افتتاحي من السنة السابقة ${webMoney(opening)}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
        ),
      if (rows.isNotEmpty)
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('أرصدة الحسابات', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.heading))),
                    if (rows.length > 1)
                      Text(webMoney(total), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: total < 0 ? AppColors.danger : AppColors.success)),
                  ],
                ),
              ),
              for (final w in items) ...[Divider(height: 1, thickness: 1, color: AppColors.line), w],
            ],
          ),
        ),
    ];
  }

  /// أشهر بلا حركة تُطوى في سطر واحد بدل صفوف أصفار.
  bool _showIdle = false;

  String _num(double v) => '${v < 0 ? '-' : ''}${trimNum(v.abs())}';

  Color _signed(double v) => v < 0 ? AppColors.danger : AppColors.success;

  /// شهر: ربحه عند الطرف، وتحت اسمه ما دخل وخرج بسطر واحد (الأصفار تُحذف).
  Widget _monthRow(ProfitRow row) {
    final parts = [
      if (row.received.abs() >= 0.005) 'مقبوض ${_num(row.received)}',
      if (row.expenses.abs() >= 0.005) 'مصاريف ${_num(row.expenses)}',
      if (row.salaries.abs() >= 0.005) 'رواتب ${_num(row.salaries)}',
      if (row.draws.abs() >= 0.005) 'مسحوب ${_num(row.draws)}',
    ];
    final up = row.net >= 0;
    return LedgerRow(
      icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      tone: up ? LedgerTone.paid : LedgerTone.due,
      title: Text(monthLabel(row.month)),
      subtitle: Text(parts.isEmpty ? 'لا حركة' : parts.join('  ·  ')),
      amount: Text(_num(row.net), textDirection: TextDirection.ltr, style: TextStyle(color: _signed(row.net))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  Widget _monthsList(ProfitReport r) {
    bool idle(ProfitRow x) => _columns.every((c) => c.$2(x).abs() < 0.005);
    final busy = [for (final row in r.rows) if (!idle(row)) row];
    final quiet = [for (final row in r.rows) if (idle(row)) row];
    final rows = <Widget>[
      for (final row in busy) _monthRow(row),
      if (quiet.isNotEmpty)
        InkWell(
          onTap: () => setState(() => _showIdle = !_showIdle),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _showIdle ? 'إخفاء الأشهر بلا حركة' : '${quiet.length} أشهر بلا حركة',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Icon(_showIdle ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
              ],
            ),
          ),
        ),
      if (_showIdle)
        for (final row in quiet)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(children: [
              Text(monthLabel(row.month), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const Spacer(),
              const Text('لا حركة', style: TextStyle(color: AppColors.faint, fontSize: 12)),
            ]),
          ),
    ];
    final t = r.total;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
            rows[i],
          ],
          Divider(height: 1, thickness: 1, color: AppColors.lineStrong),
          Container(
            color: AppColors.sunken,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('المجموع', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.heading))),
                    Text(_num(t.net), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _signed(t.net))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'مقبوض ${_num(t.received)}  ·  مصاريف ${_num(t.expenses)}  ·  رواتب ${_num(t.salaries)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// قائمة منسدلة صغيرة بخياراتها.
class _Choice extends StatelessWidget {
  const _Choice({required this.value, required this.options, required this.onPick});

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onPick,
      itemBuilder: (_) => [for (final e in options.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: _ChipBody(label: options[value] ?? value, icon: Icons.expand_more),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: _ChipBody(label: label, icon: Icons.event));
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.heading)),
          const SizedBox(width: 4),
          Icon(icon, size: 16, color: AppColors.muted),
        ],
      ),
    );
  }
}
