import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'student_detail_screen.dart';
import 'student_form_screen.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final search = TextEditingController();
  String grade = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('students')) {
          return NoAccess(section: 'students', roleName: store.roleName);
        }
        final q = search.text.trim().toLowerCase();
        final list = store.students.where((s) {
          if (grade.isNotEmpty && s.gradeLevel.trim() != grade) return false;
          if (q.isEmpty) return true;
          return s.fullName.toLowerCase().contains(q) ||
              s.phone.contains(q) ||
              s.parentName.toLowerCase().contains(q) ||
              s.parentPhone.contains(q) ||
              s.nationalId.contains(q);
        }).toList()
          // الأحدث تسجيلاً أولاً — مطابق لفرز Students.tsx
          ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

        return ThumbActionLayer(
          action: store.can('students.edit')
              ? ThumbAction(
                  label: 'طالب جديد',
                  icon: Icons.person_add_alt_1,
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudentFormScreen()));
                  },
                )
              : null,
          child: Column(
            children: [
              // البحث والتصفية والعدد في سطر واحد: البحث يأخذ ما يتبقّى، والعدد
              // في طرف حقله، والمرحلة زر مدمج بدل قائمة بعرض الشاشة.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchField(
                        controller: search,
                        hint: 'بحث بالاسم أو الهاتف...',
                        onChanged: (_) => setState(() {}),
                        trailing: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${list.length}',
                                style: TextStyle(color: AppColors.heading, fontWeight: FontWeight.w800),
                              ),
                              if (list.length != store.students.length)
                                TextSpan(text: '/${store.students.length}', style: const TextStyle(color: AppColors.faint)),
                            ],
                          ),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterButton(
                      value: grade,
                      options: {'': 'كل المراحل', for (final g in gradeLevelsFilter) g: g},
                      onSelected: (v) => setState(() => grade = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: EmptyState(message: 'لا توجد بيانات طلاب مطابقة للبحث'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, thumbActionClearance),
                        itemCount: list.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _StudentCard(student: list[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// بطاقة الطالب — بعناصر `StudentMobileCard.tsx` في صفّ واحد.
///
/// الصورة، ثم الاسم والمرحلة ووليّ الأمر، ثم الرصيد وتحته زرّا التواصل. نسخة
/// Center بصفّين كانت تُفرد سطراً كاملاً لثلاثة أزرار صغيرة وتترك جانبه فارغاً،
/// فتطول البطاقة إلى ضعف ما يلزم. البطاقة كلها تفتح ملف الطالب، فلا حاجة لسهم.
class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    // هاتف الطالب أو وليّ أمره — مطابق لـ `rawPhone` في StudentMobileCard
    final phone = student.phone.trim().isNotEmpty ? student.phone.trim() : student.parentPhone.trim();
    final grade = student.gradeLevel.trim().isEmpty ? 'غير محدد' : student.gradeLevel.trim();
    final meta = student.section.trim().isEmpty ? grade : '$grade  ·  شعبة ${student.section.trim()}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: student.id)));
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.amberSoft,
              border: Border.all(color: AppColors.amberBorder),
            ),
            child: Text(
              student.initial,
              style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  student.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
                if (student.parentName.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'ولي الأمر: ${student.parentName.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.faint, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // الرصيد أعلى الطرف، وتحته التواصل — عمود واحد بارتفاع الاسم
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (StoreScope.of(context).can('finance.view')) MoneyChip(balance: student.balance),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ContactButton(
                      tooltip: 'اتصال هاتفي',
                      background: const Color(0xFFF1F5F9),
                      border: AppColors.lineStrong,
                      onTap: () => launchTel(phone),
                      child: Icon(Icons.phone_outlined, size: 15, color: AppColors.navy),
                    ),
                    const SizedBox(width: 6),
                    _ContactButton(
                      tooltip: 'مراسلة واتساب',
                      background: AppColors.successSoft,
                      border: const Color(0xFF86EFAC),
                      onTap: () => launchWa(phone),
                      child: const _MessageCircleIcon(color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// زر تواصل مربّع صغير — مطابق لأزرار `w-7 h-7` في StudentMobileCard.
class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.background = Colors.transparent,
    this.border = Colors.transparent,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, border: Border.all(color: border)),
          child: child,
        ),
      ),
    );
  }
}

/// فقاعة محادثة دائرية بذيل — مطابقة لأيقونة `MessageCircle` من lucide التي
/// يستعملها Center لزر واتساب، ولا مقابل لها في مكتبة Material.
class _MessageCircleIcon extends StatelessWidget {
  const _MessageCircleIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 16, height: 16, child: CustomPaint(painter: _MessageCirclePainter(color)));
  }
}

class _MessageCirclePainter extends CustomPainter {
  const _MessageCirclePainter(this.color);
  final Color color;

  static const _pi = 3.141592653589793;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // الذيل في أسفل اليسار كما في الأيقونة الأصلية، ولا ينعكس مع الاتجاه
    const tail = 3 * _pi / 4;
    const gap = 0.36;
    final rect = Rect.fromCircle(center: Offset(w * 0.54, h * 0.46), radius: w * 0.40);
    final path = Path()
      ..arcTo(rect, tail + gap, 2 * _pi - 2 * gap, true)
      ..lineTo(w * 0.08, h * 0.92)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MessageCirclePainter old) => old.color != color;
}
