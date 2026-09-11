import 'package:flutter/material.dart';

import '../data/class_tiers.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

/// إضافة صف / شعبة أو تعديله — المقابل لنافذة النموذج في SchoolClasses.tsx.
///
/// بتخطيط نموذج تسجيل الطالب: أقسام بعنوان وخط، والحقول القصيرة متجاورة، والحفظ
/// ثابت أسفل الشاشة. المربي اختياري كما في Center، واختيار المرحلة الدراسية
/// يضبط المرحلة الكبرى تلقائياً.
class RoomFormScreen extends StatefulWidget {
  const RoomFormScreen({super.key, this.room});

  final Classroom? room;

  @override
  State<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends State<RoomFormScreen> {
  late final name = TextEditingController(text: widget.room?.name ?? '');
  late final capacity = TextEditingController(text: '${widget.room?.capacity ?? 30}');
  late final notes = TextEditingController(text: widget.room?.notes ?? '');
  late String grade = widget.room?.gradeLevel.trim() ?? '';
  late String teacherId = widget.room?.teacherId ?? '';
  String tier = 'secondary';
  final errors = FieldErrors();
  bool _seeded = false;

  static const _gap = SizedBox(height: 12);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final room = widget.room;
    if (room != null) {
      // «أخرى» تعود للثانوية كما في `handleOpenEdit`
      final detected = classTier(StoreScope.of(context), room);
      tier = detected == 'other' ? 'secondary' : detected;
    }
  }

  @override
  void dispose() {
    name.dispose();
    capacity.dispose();
    notes.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    final trimmed = name.text.trim();
    setState(() {
      errors
        ..reset()
        ..check('name', trimmed.isEmpty, 'يرجى إدخال اسم الصف / الشعبة')
        ..check('grade', grade.trim().isEmpty, 'يرجى تحديد المرحلة الدراسية التابعة لها هذه الشعبة');
    });
    if (errors.report(context)) return;

    final seats = int.tryParse(capacity.text.trim()) ?? 0;
    try {
      store.upsertRoom(
        Classroom(
          id: widget.room?.id ?? store.newId(),
          name: trimmed,
          gradeLevel: grade.trim(),
          teacherId: teacherId,
          capacity: seats > 0 ? seats : 30,
          notes: notes.text.trim(),
          tier: tier,
        ),
      );
      showAppSnack(context, widget.room == null ? 'تم إضافة "$trimmed"' : 'تم تعديل "$trimmed"');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.room != null;
    final title = editing ? 'تعديل: ${widget.room!.name}' : 'إضافة صف / شعبة جديدة';

    if (!store.can('schedule.edit')) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(title)),
        body: NoAccess(section: 'classes', roleName: store.roleName),
      );
    }

    final grades = <String>[
      ...(store.gradeFees.isEmpty ? gradeLevelsFilter : store.gradeFees.map((g) => g.gradeName.trim())),
    ];
    // مرحلة محفوظة لم تعد في جدول الرسوم تبقى ظاهرة ولا تُمحى بصمت عند الحفظ
    if (grade.isNotEmpty && !grades.contains(grade)) grades.add(grade);
    final teachers = store.teachers;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
      bottomNavigationBar: FormActionBar(label: editing ? 'حفظ التعديلات' : 'إضافة الصف', onSave: _save),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // ── ١. بيانات الصف ──────────────────────────────────────────────
            const FormSection(icon: Icons.apartment_outlined, title: 'بيانات الصف', note: 'الحقول ذات * مطلوبة'),
            FieldLabel('اسم الصف / الشعبة', key: errors.key('name'), requiredField: true),
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (errors.clear('name')) setState(() {});
              },
              decoration: InputDecoration(hintText: 'مثال: الشعبة (أ)...', errorText: errors['name']),
            ),
            _gap,
            FieldPair(
              start: [
                FieldLabel('المرحلة الدراسية', key: errors.key('grade'), requiredField: true),
                AppDropdown<String>(
                  value: grade.isEmpty ? null : grade,
                  hint: 'اختر المرحلة',
                  errorText: errors['grade'],
                  items: [
                    for (final g in grades) DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    grade = v ?? grade;
                    errors.clear('grade');
                    final detected = gradeTier(store, grade);
                    if (detected != 'other') tier = detected;
                  }),
                ),
              ],
              end: [
                const FieldLabel('المرحلة الكبرى', requiredField: true),
                AppDropdown<String>(
                  value: tier,
                  items: [
                    for (final e in educationalStageTiers.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => tier = v ?? tier),
                ),
              ],
            ),

            // ── ٢. الإشراف والسعة ───────────────────────────────────────────
            const FormSection(icon: Icons.groups_outlined, title: 'الإشراف والسعة'),
            FieldPair(
              startFlex: 3,
              endFlex: 2,
              start: [
                const FieldLabel('مربي الصف'),
                AppDropdown<String>(
                  value: teachers.any((t) => t.id == teacherId) ? teacherId : '',
                  items: [
                    const DropdownMenuItem(value: '', child: Text('بدون تعيين حالياً')),
                    for (final t in teachers)
                      DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => teacherId = v ?? ''),
                ),
              ],
              end: [
                const FieldLabel('السعة (مقعد)'),
                TextField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(hintText: '30'),
                ),
              ],
            ),
            _gap,
            const FieldLabel('ملاحظات إضافية'),
            TextField(
              controller: notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'ملاحظات وتفاصيل التجهيزات...'),
            ),
          ],
        ),
      ),
    );
  }
}
