import 'package:flutter/material.dart';
import '../data/supabase.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';

// «الراتب» للمعلم — المقابل لتبويب «الراتب» في `features/staff/TeacherSelfModal.tsx`.

/// قسيمة راتب مصروفة: الشهر والمصروف وسطور الحساب كما ثُبّتت عند الصرف.
class Payslip {
  const Payslip({required this.id, required this.month, required this.paid, required this.lines});

  final String id;
  final String month;
  final double paid;
  final List<({String label, double amount})> lines;

  static Payslip? fromRow(Map<String, dynamic> r) {
    final snap = r['snapshot'];
    if (snap is! Map) return null;
    return Payslip(
      id: '${r['id']}',
      month: '${r['month'] ?? ''}',
      paid: (snap['paid'] as num?)?.toDouble() ?? 0,
      lines: [
        for (final l in (snap['lines'] as List? ?? const []))
          if (l is Map) (label: '${l['label'] ?? ''}', amount: (l['amount'] as num?)?.toDouble() ?? 0),
      ],
    );
  }
}

/// قسائمه المصروفة، إن فعّلتها المدرسة (السياسة `teacher_own_payslips`). فارغة بلا شبكة.
Future<List<Payslip>> loadMyPayslips(String teacherId) async {
  final rows = await supabaseSelect(
    'payroll_entries',
    columns: 'id,month,snapshot',
    filters: {'teacher_id': 'eq.$teacherId', 'snapshot': 'not.is.null'},
    order: 'month.desc',
    limit: 24,
  );
  return [
    for (final r in rows ?? const <Map<String, dynamic>>[])
      if (Payslip.fromRow(r) case final slip?) slip,
  ];
}

/// قائمة القسائم: داخل «ملفي» أو نافذتها.
Widget payslipListView(List<Payslip> slips) => _PayslipList(slips: slips);

/// زر الشريط العلوي: يظهر لمن صُرف له راتب، ويفتح قسائمه.
class PayslipsButton extends StatelessWidget {
  const PayslipsButton({super.key, required this.slips});

  final List<Payslip> slips;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'الراتب',
      child: InkWell(
        onTap: () => showNoonSheet<void>(context, title: 'الراتب', body: (_, __) => [_PayslipList(slips: slips)]),
        borderRadius: BorderRadius.circular(NoonRadius.btn),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.payments_outlined, size: 18, color: Noon.onInkSoft),
        ),
      ),
    );
  }
}

/// الشهر وصافيه، وتفصيله بالضغط؛ الأحدث مفتوح.
class _PayslipList extends StatefulWidget {
  const _PayslipList({required this.slips});

  final List<Payslip> slips;

  @override
  State<_PayslipList> createState() => _PayslipListState();
}

class _PayslipListState extends State<_PayslipList> {
  late String? open = widget.slips.firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in widget.slips) ...[
          InkWell(
            onTap: () => setState(() => open = open == s.id ? null : s.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(monthLabel(s.month), style: nText(14, weight: FontWeight.w700))),
                  Text(money(s.paid), style: nText(14, weight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          if (open == s.id && s.lines.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(NoonRadius.btn),
              ),
              child: Column(
                children: [
                  for (final l in s.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(12))),
                          Text(
                            l.amount < 0 ? '− ${money(-l.amount)}' : money(l.amount),
                            style: nText(12, color: l.amount < 0 ? AppColors.danger : AppColors.text),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Divider(height: 1, color: AppColors.line),
        ],
      ],
    );
  }
}
