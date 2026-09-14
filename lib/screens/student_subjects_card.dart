import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// «المواد والمعلمون» في ملف الطالب.
///
/// مرآةٌ لشعبته: موادها ومعلموها يُسندون من صفحة الصفوف، فلا تسجيل ولا إلغاء
/// ولا سعر هنا — رسوم المدرسة كلها في أقساط الطالب.
class StudentSubjectsCard extends StatefulWidget {
  const StudentSubjectsCard({super.key, required this.student});
  final Student student;

  @override
  State<StudentSubjectsCard> createState() => _StudentSubjectsCardState();
}

class _StudentSubjectsCardState extends State<StudentSubjectsCard> {
  /// مطوية كبقية أقسام ملف الطالب حتى تُطلب.
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    // التسجيل المنتهي (شعبة سابقة أو مادة أُلغيت) يبقى لأجل درجاته، لكنه ليس
    // من مواد الطالب الحالية — كما في `StudentDetail.tsx`
    final mine = store.enrollmentsOf(widget.student.id).where((e) => e.status != 'withdrawn').toList();
    if (mine.isEmpty && store.groups.isEmpty) return const SizedBox.shrink();

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            onTap: () => setState(() => open = !open),
            leading: AnimatedRotation(
              turns: open ? 0 : 0.5,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more, size: 18, color: AppColors.faint),
            ),
            'المواد والمعلمون (${mine.length})',
          ),
          if (open && mine.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('لا مواد', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else if (open)
            for (final e in mine) _row(store, e),
        ],
      ),
    );
  }

  Widget _row(AppStore store, StudentEnrollment e) {
    final group = store.groupById(e.groupId);
    final subject = group == null ? '' : store.subjectName(group.subjectId);
    final teacher = group == null ? null : store.teacherById(group.teacherId);
    final line = [
      if (teacher != null) teacher.name,
      if (e.discountReason.isNotEmpty) 'خصم: ${e.discountReason}',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject.isNotEmpty ? subject : group?.name ?? 'مادة دراسية',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          if (line.isNotEmpty)
            Text(
              line.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
        ],
      ),
    );
  }
}
