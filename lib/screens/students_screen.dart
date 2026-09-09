import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
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
        final q = search.text.trim();
        final list = store.students.where((s) {
          if (grade.isNotEmpty && s.gradeLevel != grade) return false;
          if (q.isEmpty) return true;
          return s.fullName.contains(q) ||
              s.phone.contains(q) ||
              s.parentName.contains(q) ||
              s.parentPhone.contains(q) ||
              s.nationalId.contains(q);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: search,
                      hint: 'بحث سريع بالاسم أو الهاتف...',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PrimaryButton(
                    label: 'طالب جديد',
                    icon: Icons.add,
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudentFormScreen()));
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      value: grade,
                      onChanged: (v) => setState(() => grade = v ?? ''),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('جميع المراحل الدراسية')),
                        ...gradeLevelsFilter.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      text: 'العدد: ',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      children: [
                        TextSpan(
                          text: '${list.length}',
                          style: const TextStyle(color: AppColors.heading, fontWeight: FontWeight.w800),
                        ),
                        if (list.length != store.students.length)
                          TextSpan(text: ' / ${store.students.length}', style: const TextStyle(color: AppColors.faint)),
                      ],
                    ),
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
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: list.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _StudentCard(student: list[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: student.id)));
      },
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.amberSoft,
                  border: Border.all(color: AppColors.amberBorder),
                ),
                child: Text(student.initial, style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.heading),
                    ),
                    const SizedBox(height: 3),
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
              MoneyChip(balance: student.balance),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  student.parentName.isNotEmpty ? 'ولي الأمر: ${student.parentName}' : student.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              SquareIconButton(icon: Icons.call, onTap: () => launchTel(student.phone)),
              const SizedBox(width: 6),
              SquareIconButton(
                icon: Icons.chat,
                onTap: () => launchWa(student.parentPhone.isNotEmpty ? student.parentPhone : student.phone),
                bg: AppColors.successSoft,
                border: const Color(0xFF86EFAC),
                color: AppColors.success,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left, color: AppColors.muted, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
