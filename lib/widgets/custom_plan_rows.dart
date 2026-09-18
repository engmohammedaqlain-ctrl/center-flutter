import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fee_plan.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// صف قسط مخصص — المقابل لـ `CustomPlanRow` في الويب.
class CustomPlanRow {
  CustomPlanRow({this.title = '', this.amount = '', this.dueDate = ''});

  String title;

  /// نص المبلغ كما في الويب (فارغ مسموح أثناء الكتابة).
  String amount;
  String dueDate;

  double get amountValue => double.tryParse(amount.trim()) ?? 0;
}

/// أول الشهر التالي لتاريخ: اقتراح موعد القسط التالي — `nextMonthDate`.
String nextMonthDate(String date) => addMonths(
      date.isNotEmpty ? date : isoDate(DateTime.now()),
      1,
    );

/// صف جديد بعنوان متسلسل، وآخر مبلغ، وموعد الشهر التالي — `makeCustomRow`.
CustomPlanRow makeCustomRow(List<CustomPlanRow> rows, [String? fallbackDue]) {
  final last = rows.isEmpty ? null : rows.last;
  return CustomPlanRow(
    title: 'قسط ${rows.length + 1}',
    amount: last?.amount ?? '',
    dueDate: last != null && last.dueDate.isNotEmpty
        ? nextMonthDate(last.dueDate)
        : (fallbackDue?.isNotEmpty == true ? fallbackDue! : isoDate(DateTime.now())),
  );
}

/// محرّر أقساط خطة مخصصة: لكل قسط عنوانه ومبلغه وموعده — `CustomPlanRowsEditor`.
class CustomPlanRowsEditor extends StatelessWidget {
  const CustomPlanRowsEditor({
    super.key,
    required this.rows,
    required this.onChanged,
    this.fallbackDue,
  });

  final List<CustomPlanRow> rows;
  final ValueChanged<List<CustomPlanRow>> onChanged;

  /// موعد أول قسط حين لا صفوف بعد (تاريخ الالتحاق مثلاً).
  final String? fallbackDue;

  double get _total => rows.fold<double>(0, (sum, r) => sum + r.amountValue);

  void _notify() => onChanged(List<CustomPlanRow>.of(rows));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'لا أقساط بعد — أضف أول قسط',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          )
        else
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 8),
              child: _CustomPlanRowTile(
                key: ObjectKey(rows[i]),
                index: i,
                row: rows[i],
                onEdited: _notify,
                onRemove: () {
                  rows.removeAt(i);
                  _notify();
                },
              ),
            ),
        const SizedBox(height: 8),
        Container(height: 1, color: AppColors.line),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: () {
                rows.add(makeCustomRow(rows, fallbackDue));
                _notify();
              },
              borderRadius: BorderRadius.circular(Corner.box),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.amber),
                    const SizedBox(width: 4),
                    Text(
                      'قسط',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.amber),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Text(
              '${rows.length} قسط · الإجمالي ',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
            Text(
              money(_total),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                color: AppColors.heading,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomPlanRowTile extends StatefulWidget {
  const _CustomPlanRowTile({
    super.key,
    required this.index,
    required this.row,
    required this.onEdited,
    required this.onRemove,
  });

  final int index;
  final CustomPlanRow row;
  final VoidCallback onEdited;
  final VoidCallback onRemove;

  @override
  State<_CustomPlanRowTile> createState() => _CustomPlanRowTileState();
}

class _CustomPlanRowTileState extends State<_CustomPlanRowTile> {
  late final TextEditingController titleCtl;
  late final TextEditingController amountCtl;

  @override
  void initState() {
    super.initState();
    titleCtl = TextEditingController(text: widget.row.title);
    amountCtl = TextEditingController(text: widget.row.amount);
  }

  @override
  void dispose() {
    titleCtl.dispose();
    amountCtl.dispose();
    super.dispose();
  }

  void _syncFields() {
    widget.row.title = titleCtl.text;
    widget.row.amount = amountCtl.text;
    widget.onEdited();
  }

  Future<void> _pickDue() async {
    final initial = parseIsoDate(widget.row.dueDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => widget.row.dueDate = isoDate(picked));
    widget.onEdited();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '${widget.index + 1}',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.faint),
          ),
        ),
        Expanded(
          child: TextField(
            controller: titleCtl,
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'اسم القسط',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (_) => _syncFields(),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 72,
          child: TextField(
            controller: amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'المبلغ',
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
            onChanged: (_) => _syncFields(),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 108,
          child: InkWell(
            onTap: _pickDue,
            borderRadius: BorderRadius.circular(Corner.field),
            child: InputDecorator(
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              child: Text(
                widget.row.dueDate.isEmpty ? 'التاريخ' : widget.row.dueDate,
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: widget.row.dueDate.isEmpty ? AppColors.faint : AppColors.heading,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'حذف القسط',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
          onPressed: widget.onRemove,
        ),
      ],
    );
  }
}
