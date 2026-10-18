import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/profit_report.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

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
        payments: widget.store.payments,
        installments: widget.store.installments,
        expenses: widget.store.expenses,
        payouts: widget.store.teacherPayouts,
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
        Wrap(
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
            IconButton(
              tooltip: 'طباعة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.print_outlined, size: 20),
              onPressed: () => _print(r),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.sunken),
                  children: [
                    _cell('الشهر', head: true),
                    for (final c in _columns) _cell(c.$1, head: true),
                  ],
                ),
                for (final row in r.rows)
                  TableRow(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                    children: [
                      _cell(monthLabel(row.month), muted: true),
                      for (final c in _columns) _amount(c.$1, c.$2(row)),
                    ],
                  ),
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.sunken),
                  children: [
                    _cell('المجموع', head: true),
                    for (final c in _columns) _amount(c.$1, c.$2(r.total), bold: true),
                  ],
                ),
              ],
            ),
          ),
        ),
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

  Widget _cell(String text, {bool head = false, bool muted = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: head ? FontWeight.w700 : FontWeight.w500,
            color: muted ? AppColors.muted : AppColors.heading,
          ),
        ),
      );

  Widget _amount(String column, double v, {bool bold = false}) {
    final signed = column == 'الربح' || column == 'الباقي';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        '${v < 0 ? '-' : ''}${money(v)}',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontSize: 11.5,
          fontFamily: 'monospace',
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: signed ? (v < 0 ? AppColors.danger : AppColors.success) : AppColors.heading,
        ),
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
