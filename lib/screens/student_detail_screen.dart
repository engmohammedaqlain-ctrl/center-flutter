import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'schedule_screen.dart';
import 'receipt_screen.dart';
import 'student_form_screen.dart';

class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({super.key, required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final student = store.studentById(studentId);
        if (student == null) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(title: const Text('ملف الطالب')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('لم يتم العثور على ملف الطالب', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  GhostButton(label: 'العودة لقائمة الطلاب', onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          );
        }

        final pays = store.payments.where((p) => p.studentId == student.id).toList();
        final insts = store.installments.where((i) => i.studentId == student.id).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final marks = store.attendance.where((a) => a.studentId == student.id).toList();
        final totalPaid = pays.where((p) => !p.cancelled).fold<double>(0, (a, p) => a + p.amount);
        final present = marks.where((m) => m.status == 'present').length;
        final absent = marks.where((m) => m.status == 'absent').length;
        final late = marks.where((m) => m.status == 'late').length;
        final excused = marks.where((m) => m.status == 'excused').length;
        // الالتزام يحتسب الحاضر والمتأخر — مطابق لـ attendanceStats في StudentDetail.tsx
        final rate = marks.isEmpty ? 100 : (((present + late) / marks.length) * 100).round();
        final settled = !student.isDebtor && insts.every((i) => i.isPaid);

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Column(
            children: [
              _bar(context, student),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('الرصيد المالي الحالي:', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                                    const SizedBox(height: 4),
                                    if (student.isDebtor)
                                      Text('عليه ${money(student.balance)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 16))
                                    else if (student.balance > 0)
                                      Text('له ${money(student.balance)}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 16))
                                    else
                                      const Text('مسدد بالكامل (0 ₪)', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                              PrimaryButton(
                                label: 'تسديد دفعة',
                                icon: Icons.credit_card,
                                onPressed: settled
                                    ? null
                                    : () {
                                        final next = insts.where((i) => !i.isPaid).firstOrNull;
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => PaymentFormScreen(
                                              studentId: student.id,
                                              installmentId: next?.id,
                                              amount: next?.remaining,
                                            ),
                                          ),
                                        );
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('إجمالي المقبوضات:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              const Spacer(),
                              Text(money(totalPaid), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 12.5)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle('بيانات الطالب والتواصل'),
                          _line('هاتف الطالب:', student.phone, phone: student.phone),
                          const SizedBox(height: 8),
                          _line('ولي الأمر:', '${student.parentName} · ${student.parentPhone}', phone: student.parentPhone),
                          if (student.nationalId.isNotEmpty || student.neighborhood.isNotEmpty || student.detailedAddress.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            const SizedBox(height: 8),
                            Text(
                              [
                                if (student.nationalId.isNotEmpty) 'هوية: ${student.nationalId}',
                                if (student.neighborhood.isNotEmpty) student.neighborhood,
                                if (student.detailedAddress.isNotEmpty) student.detailedAddress,
                              ].join('  ·  '),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                            ),
                          ],
                          if (student.birthPlace.isNotEmpty || student.nationality.isNotEmpty || student.healthStatus.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              [
                                if (student.gender.isNotEmpty) student.gender,
                                if (student.birthPlace.isNotEmpty) 'مكان الولادة: ${student.birthPlace}',
                                if (student.nationality.isNotEmpty) student.nationality,
                                if (student.healthStatus.isNotEmpty) 'الصحة: ${student.healthStatus}',
                              ].join('  ·  '),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                            ),
                          ],
                          if (student.referralSource.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('مصدر التعرف: ${student.referralSource}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                            ),
                          if (student.initialRating > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  for (var i = 1; i <= 5; i++)
                                    Icon(i <= student.initialRating ? Icons.star : Icons.star_border, size: 14, color: const Color(0xFFF59E0B)),
                                  const SizedBox(width: 6),
                                  Text('${student.initialRating} / 5', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          if (student.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
                              child: Text(student.notes, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (insts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            SectionTitle('الأقساط المجدولة (${insts.length})'),
                            for (final inst in insts) _inst(context, student, inst),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          SectionTitle('سجل الدفعات (${pays.length})', trailing: Text('المقبوض: ${money(totalPaid)}', style: const TextStyle(color: AppColors.muted, fontSize: 11))),
                          if (pays.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('لا توجد دفعات مسجلة حتى الآن', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            )
                          else
                            for (final p in pays) _pay(context, p),
                        ],
                      ),
                    ),
                    if (!store.isSchool) ...[
                      const SizedBox(height: 8),
                      StudentGroupsCard(student: student),
                    ],
                    if (marks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _AttendanceCard(marks: marks, rate: rate, present: present, absent: absent, late: late, excused: excused),
                    ],
                    const SizedBox(height: 8),
                    _AttachmentsCard(studentId: student.id),
                    const SizedBox(height: 12),
                    if (store.can('students.delete'))
                      GhostButton(
                        label: 'حذف الطالب',
                        icon: Icons.delete_outline,
                        onPressed: () async {
                          final ok = await confirmSheet(
                            context,
                            title: 'تأكيد حذف الطالب',
                            message: 'هل تريد حذف هذا الطالب نهائياً من النظام؟',
                            confirmLabel: 'حذف',
                          );
                          if (!ok || !context.mounted) return;
                          try {
                            store.deleteStudent(student.id);
                            Navigator.pop(context);
                          } on StoreException catch (e) {
                            showAppSnack(context, e.message, error: true);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, Student student) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, top + 8, 12, 0),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            SquareIconButton(icon: Icons.arrow_forward, onTap: () => Navigator.pop(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(student.gradeLevel, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      const SizedBox(width: 6),
                      StatusChip.muted('شعبة ${student.section}'),
                    ],
                  ),
                ],
              ),
            ),
            GhostButton(
              label: 'تعديل',
              icon: Icons.edit_outlined,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentFormScreen(student: student)));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String k, String v, {String phone = ''}) {
    return Row(
      children: [
        Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(width: 6),
        Expanded(child: Text(v, textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
        if (phone.isNotEmpty) ...[
          SquareIconButton(icon: Icons.call, onTap: () => launchTel(phone)),
          const SizedBox(width: 6),
          SquareIconButton(
            icon: Icons.chat,
            onTap: () => launchWa(phone),
            bg: AppColors.successSoft,
            border: const Color(0xFF86EFAC),
            color: AppColors.success,
          ),
        ],
      ],
    );
  }

  Widget _inst(BuildContext context, Student student, Installment inst) {
    final future = dateOnly(inst.dueDate).isAfter(dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: inst.isPaid
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentFormScreen(studentId: student.id, installmentId: inst.id, amount: inst.remaining),
                  ),
                );
              },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: inst.isPaid ? AppColors.bg : Colors.white, border: Border.all(color: AppColors.line)),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text(inst.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
                  if (inst.isPaid)
                    StatusChip.success('مسدد')
                  else if (future)
                    StatusChip.muted('مجدول')
                  else
                    StatusChip.danger('مستحق'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('استحقاق: ${formatDate(inst.dueDate)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  const Spacer(),
                  Text('المطلوب: ${money(inst.amount)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  if (!inst.isPaid) ...[
                    const SizedBox(width: 8),
                    Text('المتبقي: ${money(inst.remaining)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pay(BuildContext context, Payment p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(p.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                const SizedBox(width: 8),
                Text(formatDate(p.date), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                const Spacer(),
                Text(
                  money(p.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: p.cancelled ? AppColors.faint : AppColors.success,
                    decoration: p.cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(paymentMethodNames[p.method] ?? p.method, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                const Spacer(),
                GhostButton(label: 'الوصل', icon: Icons.print_outlined, onPressed: () => ReceiptScreen.open(context, p)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// سجل الحضور التفصيلي — المقابل لقسم «سجل الحضور والالتزام» في StudentDetail.tsx.
class _AttendanceCard extends StatefulWidget {
  const _AttendanceCard({
    required this.marks,
    required this.rate,
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
  });

  final List<AttendanceMark> marks;
  final int rate;
  final int present;
  final int absent;
  final int late;
  final int excused;

  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard> {
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.marks]..sort((a, b) => b.date.compareTo(a.date));
    final shown = showAll ? sorted : sorted.take(4).toList();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'سجل الحضور والالتزام',
            trailing: Text('الالتزام: ${widget.rate}%',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('حضور', widget.present, AppColors.success),
                _stat('غياب', widget.absent, AppColors.danger),
                _stat('تأخير', widget.late, AppColors.amber),
                _stat('معذور', widget.excused, AppColors.info),
                _stat('الرصد', widget.marks.length, AppColors.navy),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final m in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(width: 8, height: 8, color: _color(m.status)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatDate(parseIsoDate(m.date) ?? DateTime.now()),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    attendanceStatusNames[m.status] ?? m.status,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _color(m.status)),
                  ),
                ],
              ),
            ),
          if (sorted.length > 4)
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: showAll ? 'عرض أقل' : 'عرض الكل (${sorted.length})',
                onPressed: () => setState(() => showAll = !showAll),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, Color color) => Column(
        children: [
          Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
      );

  Color _color(String status) => switch (status) {
        'present' => AppColors.success,
        'absent' => AppColors.danger,
        'late' => AppColors.amber,
        'excused' => AppColors.info,
        _ => AppColors.faint,
      };
}

/// المرفقات الرسمية — المقابل لقسم «المرفقات» في StudentDetail.tsx مع التكبير.
class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final att = store.attachmentsOf(studentId);
    if (att == null || att.isEmpty) return const SizedBox.shrink();

    final items = <(String, String)>[
      if (att.studentIdPhoto.isNotEmpty) ('صورة هوية الطالب', att.studentIdPhoto),
      if (att.parentIdPhoto.isNotEmpty) ('صورة هوية ولي الأمر', att.parentIdPhoto),
      if (att.birthCertificate.isNotEmpty) ('شهادة الميلاد', att.birthCertificate),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('المرفقات والوثائق الرسمية (${items.length})'),
          Row(
            children: [
              for (final item in items)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _Thumb(label: item.$1, data: item.$2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.label, required this.data});
  final String label;
  final String data;

  Uint8List? get _bytes {
    try {
      final comma = data.indexOf(',');
      return base64Decode(comma >= 0 ? data.substring(comma + 1) : data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
              ),
              Flexible(child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes))),
              Padding(
                padding: const EdgeInsets.all(10),
                child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 78,
            decoration: BoxDecoration(border: Border.all(color: AppColors.line), color: AppColors.bg),
            child: Image.memory(bytes, fit: BoxFit.cover, width: double.infinity),
          ),
          const SizedBox(height: 4),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
        ],
      ),
    );
  }
}
