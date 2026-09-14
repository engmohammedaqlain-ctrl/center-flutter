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
                      options: {'': 'كل المراحل', for (final g in store.gradeOptions) g: g},
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
/// الاسم والمرحلة ووليّ الأمر، ثم الرصيد وتحته زرّا التواصل. نسخة
/// Center بصفّين كانت تُفرد سطراً كاملاً لثلاثة أزرار صغيرة وتترك جانبه فارغاً،
/// فتطول البطاقة إلى ضعف ما يلزم. البطاقة كلها تفتح ملف الطالب، وسهم خافت في طرفها يدلّ على ذلك.
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
      padding: const EdgeInsets.fromLTRB(6, 11, 12, 11),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: student.id)));
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        student.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle.copyWith(fontSize: 14),
                      ),
                    ),
                    // المنسحب والمؤرشف يُعرفان من القائمة بلا فتح الملف
                    if (!student.isActiveStudent) ...[
                      const SizedBox(width: 6),
                      StudentStatusChip(status: student.status, compact: true),
                    ],
                  ],
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
              if (StoreScope.of(context).can('finance.view')) _BalanceText(balance: student.balance),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContactIconButton(
                      tooltip: 'اتصال هاتفي',
                      onTap: () => launchTel(phone),
                      child: const Icon(Icons.phone_outlined, size: 18, color: AppColors.muted),
                    ),
                    ContactIconButton(
                      tooltip: 'مراسلة واتساب',
                      onTap: () => launchWa(phone),
                      child: const MessageCircleIcon(color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(width: 2),
          // إشارة هادئة بأن البطاقة تفتح صفحة الطالب — «<» باتجاه التقدّم في العربية.
          // أيقونات الأسهم تنعكس مع اتجاه النص: «التالي» (chevron_right) يُرسم يساراً
          const Icon(Icons.chevron_right, size: 20, color: AppColors.faint),
        ],
      ),
    );
  }
}

/// الرصيد نصاً هادئاً بلونه — بلا شارة ولا خلفية تنافس الاسم.
class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    // من لا دين عليه «مسدد»: رصيدٌ لصالحه تفصيلٌ يخصّ ملفه لا قائمة الطلاب
    final (text, color) = balance < 0
        ? ('عليه ${money(balance)}', AppColors.danger)
        : ('مسدد', AppColors.success);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
