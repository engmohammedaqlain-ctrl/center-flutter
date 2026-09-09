import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String type = 'center_summary';
  String period = 'month';
  String? studentId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    DateTime start;
    if (period == 'today') {
      start = dateOnly(now);
    } else {
      start = DateTime(now.year, now.month, 1);
    }
    final pays = store.payments.where((p) => !p.cancelled && !p.date.isBefore(start)).toList();
    final total = pays.fold<double>(0, (a, p) => a + p.amount);
    final student = studentId == null ? null : store.studentById(studentId!);
    final stuPays = student == null ? <Payment>[] : store.payments.where((p) => p.studentId == student.id && !p.cancelled).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('التقارير'),
        backgroundColor: AppColors.navy,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'center_summary', child: Text('تقرير المركز')),
                      DropdownMenuItem(value: 'student_statement', child: Text('كشف حساب طالب')),
                    ],
                    onChanged: (v) => setState(() => type = v ?? type),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (type == 'center_summary') ...[
            AppCard(
              child: AppDropdown<String>(
                value: period,
                items: const [
                  DropdownMenuItem(value: 'today', child: Text('اليوم')),
                  DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                ],
                onChanged: (v) => setState(() => period = v ?? period),
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.institutionName, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                  const SizedBox(height: 8),
                  _kv('عدد الطلاب', '${store.students.length}'),
                  _kv('المقبوضات', money(total)),
                  _kv('عدد السندات', '${pays.length}'),
                  _kv('المستحقات الحالية', money(store.dueItems().fold<double>(0, (a, d) => a + d.amount))),
                  _kv('الغياب اليوم', '${store.attendance.where((a) => a.date == isoDate(now) && a.status == 'absent').length}'),
                ],
              ),
            ),
          ] else ...[
            AppCard(
              child: AppDropdown<String>(
                value: studentId,
                hint: 'اختر الطالب',
                items: store.students.map((s) => DropdownMenuItem(value: s.id, child: Text(s.fullName))).toList(),
                onChanged: (v) => setState(() => studentId = v),
              ),
            ),
            if (student != null) ...[
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('كشف حساب: ${student.fullName}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                    const SizedBox(height: 8),
                    _kv('الرصيد', student.isDebtor ? 'عليه ${money(student.balance)}' : 'خالص'),
                    _kv('إجمالي المقبوض', money(stuPays.fold<double>(0, (a, p) => a + p.amount))),
                    const Divider(),
                    for (final p in stuPays)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Text(formatDate(p.date), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(p.receiptNumber, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                            Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const Spacer(),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.heading)),
        ],
      ),
    );
  }
}
