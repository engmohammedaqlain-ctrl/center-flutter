import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// «المواد والمعلمون» في ملف الطالب — صفوف مسطحة كقائمة الطلاب.
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
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final mine = store.enrollmentsOf(widget.student.id).where((e) => e.status != 'withdrawn').toList();
    if (mine.isEmpty && store.groupsInViewedYear.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
        boxShadow: cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'المواد والمعلمون (${mine.length})',
                      style: AppText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, size: 22, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.line,
              indent: 18,
              endIndent: 18,
            ),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                child: Text('لا مواد', style: AppText.muted),
              )
            else
              for (var i = 0; i < mine.length; i++) ...[
                _row(store, mine[i]),
                if (i < mine.length - 1)
                  const Divider(height: 1, thickness: 1, color: AppColors.line, indent: 18, endIndent: 18),
              ],
          ],
        ],
      ),
    );
  }

  /// بنمط «بيانات إضافية» في الملف: اسم المادة عنواناً في أول السطر، ومعلمها
  /// قيمةً في آخره، فلا يبقى نصف السطر فارغاً.
  Widget _row(AppStore store, StudentEnrollment e) {
    final group = store.groupById(e.groupId);
    final subjectRaw = group == null ? '' : store.subjectName(group.subjectId);
    final subjectName = subjectRaw.isNotEmpty ? subjectRaw : (group?.name ?? 'مادة دراسية');
    final teacher = group == null ? null : store.teacherById(group.teacherId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Text(subjectName, style: AppText.label),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              teacher?.name ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: AppText.family,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.35,
                color: teacher == null ? AppColors.faint : AppColors.text,
              ),
            ),
          ),
          if (e.discountReason.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              'خصم',
              style: TextStyle(
                fontFamily: AppText.family,
                color: AppColors.amberDark,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
