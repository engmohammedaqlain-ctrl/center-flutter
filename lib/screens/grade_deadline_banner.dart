import 'package:flutter/material.dart';
import '../data/grade_deadlines.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/noon_ui.dart';

/// شريط فوق بوابة المعلم: أقرب رصد مطلوب، والنقر يفتح الرصد على مادته وشعبته.
/// بشكل شريط الملاحظات، وبلون الخطر حين يفوت الموعد.
class GradeDeadlineBanner extends StatelessWidget {
  const GradeDeadlineBanner({super.key, required this.due, required this.onOpen});

  final List<DueGrade> due;
  final ValueChanged<DueGrade> onOpen;

  static String _dm(String d) => '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}';

  @override
  Widget build(BuildContext context) {
    if (due.isEmpty) return const SizedBox.shrink();
    final first = due.first;
    final more = due.length - 1;
    final tone = first.late ? AppColors.danger : Noon.action;
    final title = first.late ? 'رصد ${first.component} متأخر' : 'ارصد ${first.component} قبل ${_dm(first.due)}';
    final text = [
      first.subject,
      [first.gradeLevel, first.section].where((s) => s.trim().isNotEmpty).join(' '),
      if (more > 0) 'و$more غيره',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return Container(
      decoration: nPanelDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NoonRadius.panel),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onOpen(first),
            highlightColor: Noon.mist2,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: tone),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
                      child: Row(
                        children: [
                          Icon(Icons.assignment_turned_in_outlined, size: 20, color: first.late ? AppColors.danger : Noon.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700)),
                                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('ارصد', style: nText(12, weight: FontWeight.w700, color: Noon.tealD)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
