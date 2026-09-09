import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key, this.student});
  final Student? student;

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  late final name = TextEditingController(text: widget.student?.fullName ?? '');
  late final nationalId = TextEditingController(text: widget.student?.nationalId ?? '');
  late final phone = TextEditingController(text: widget.student?.phone ?? '');
  late final parentName = TextEditingController(text: widget.student?.parentName ?? '');
  late final parentPhone = TextEditingController(text: widget.student?.parentPhone ?? '');
  late final notes = TextEditingController(text: widget.student?.notes ?? '');
  late String grade = widget.student?.gradeLevel ?? gradeLevels.first;
  late String section = widget.student?.section ?? '';
  late String relation = widget.student?.relation ?? 'أب';
  late String neighborhood =
      (widget.student?.neighborhood ?? '').isNotEmpty ? widget.student!.neighborhood : neighborhoods.first;
  late String gender = widget.student?.gender ?? 'ذكر';
  bool extra = false;

  @override
  void dispose() {
    name.dispose();
    nationalId.dispose();
    phone.dispose();
    parentName.dispose();
    parentPhone.dispose();
    notes.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    final sections = store.rooms.map((r) => r.name).toList();
    try {
      store.upsertStudent(
        Student(
          id: widget.student?.id ?? store.newId(),
          fullName: name.text.trim(),
          gradeLevel: grade,
          section: section.isEmpty && sections.isNotEmpty ? sections.first : section,
          phone: phone.text.trim(),
          parentName: parentName.text.trim(),
          parentPhone: parentPhone.text.trim(),
          nationalId: nationalId.text.trim(),
          neighborhood: neighborhood,
          relation: relation,
          gender: gender,
          notes: notes.text.trim(),
          balance: widget.student?.balance ?? 0,
          enrolledAt: widget.student?.enrolledAt,
        ),
        isNew: widget.student == null,
      );
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sections = store.rooms.map((r) => r.name).toList();
    final currentSection = sections.contains(section)
        ? section
        : (sections.isNotEmpty ? sections.first : '');
    final editing = widget.student != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(editing ? 'تعديل بيانات الطالب' : 'تسجيل طالب جديد'),
        backgroundColor: AppColors.amberSoft,
        foregroundColor: AppColors.heading,
        titleTextStyle: const TextStyle(color: AppColors.heading, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('الاسم الرباعي'),
                TextField(controller: name, decoration: const InputDecoration(hintText: 'مثال: محمد أحمد النجار')),
                const SizedBox(height: 10),
                const FieldLabel('رقم الهوية'),
                TextField(
                  controller: nationalId,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  decoration: const InputDecoration(hintText: '9 أرقام', counterText: ''),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('المرحلة'),
                          AppDropdown<String>(
                            value: grade,
                            items: gradeLevels.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setState(() => grade = v ?? grade),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('الشعبة'),
                          AppDropdown<String>(
                            value: currentSection.isEmpty ? null : currentSection,
                            items: sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (v) => setState(() => section = v ?? section),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('هاتف الطالب'),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '059xxxxxxx')),
                const SizedBox(height: 10),
                const FieldLabel('اسم ولي الأمر'),
                TextField(controller: parentName),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('صلة القرابة'),
                          AppDropdown<String>(
                            value: relation,
                            items: guardianRelations.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                            onChanged: (v) => setState(() => relation = v ?? relation),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FieldLabel('هاتف ولي الأمر'),
                          TextField(controller: parentPhone, keyboardType: TextInputType.phone),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const FieldLabel('الحي'),
                AppDropdown<String>(
                  value: neighborhood,
                  items: neighborhoods.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                  onChanged: (v) => setState(() => neighborhood = v ?? neighborhood),
                ),
                const SizedBox(height: 10),
                const FieldLabel('ملاحظات'),
                TextField(controller: notes, maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AppCard(
            onTap: () => setState(() => extra = !extra),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('بيانات إضافية', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading, fontSize: 13))),
                    Icon(extra ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.muted),
                  ],
                ),
                if (extra) ...[
                  const SizedBox(height: 12),
                  const FieldLabel('الجنس'),
                  AppDropdown<String>(
                    value: gender,
                    items: const [
                      DropdownMenuItem(value: 'ذكر', child: Text('ذكر')),
                      DropdownMenuItem(value: 'أنثى', child: Text('أنثى')),
                    ],
                    onChanged: (v) => setState(() => gender = v ?? gender),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(child: PrimaryButton(label: editing ? 'حفظ التعديل' : 'تسجيل الطالب', onPressed: _save)),
            ],
          ),
        ],
      ),
    );
  }
}
