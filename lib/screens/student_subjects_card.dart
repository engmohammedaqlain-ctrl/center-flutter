import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';

/// «المواد والمعلمون» في ملف الطالب — سطر لكل مادة: اسمها ومعلمها، كالويب.
///
/// مرآةٌ لشعبته: موادها ومعلموها يُسندون من صفحة الصفوف، فلا تسجيل ولا إلغاء
/// ولا سعر هنا — رسوم المدرسة كلها في أقساط الطالب.
class StudentSubjectsCard extends StatelessWidget {
  const StudentSubjectsCard({super.key, required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mine = store.enrollmentsOf(student.id).where((e) => e.status != 'withdrawn').toList();
    if (mine.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NoonFoldCard(
        title: 'المواد والمعلمون (${mine.length})',
        gap: 0,
        children: [
          for (var i = 0; i < mine.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: AdminNoon.line))) : null,
              child: _row(store, mine[i]),
            ),
        ],
      ),
    );
  }

  Widget _row(AppStore store, StudentEnrollment e) {
    final group = store.groupById(e.groupId);
    final subjectRaw = group == null ? '' : store.subjectName(group.subjectId);
    final subjectName = subjectRaw.isNotEmpty ? subjectRaw : (group?.name ?? 'مادة');
    final teacher = group == null ? null : store.teacherById(group.teacherId);

    return Row(
      children: [
        Flexible(
          child: Text(
            subjectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NoonText.style(11, weight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        const Spacer(),
        Flexible(
          child: Text(
            teacher?.name ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NoonText.style(11, color: AdminNoon.muted),
          ),
        ),
      ],
    );
  }
}
