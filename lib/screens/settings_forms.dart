import 'package:flutter/material.dart';

import '../data/permissions.dart';
import '../data/teacher_salary.dart';
import '../data/phone.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';

// نماذج الإعدادات — صفحات كاملة بتخطيط نموذج تسجيل الطالب: أقسام بعنوان وخط،
// والحقول القصيرة متجاورة، والحفظ ثابت أسفل الشاشة، والنواقص تحت حقولها.

const _gap = SizedBox(height: 12);

AppBar _formBar(String title) => AppBar(
      title: Text(title),
      titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
    );

Widget _denied(AppStore store, String title) => Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: NoAccess(section: 'settings', roleName: store.roleName),
    );

/// زر الحذف في آخر النموذج: كامل العرض بلون التحذير، بعيداً عن زر الحفظ.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.dangerBorder),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.field))),
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// اختيار متعدد بشكل شارة: إطار بلون العمليات وعلامة صح حين يُختار.
Widget _choiceChip(String label, bool on, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(Corner.box),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.box),
        color: on ? AppColors.amberSoft : Colors.white,
        border: Border.all(color: on ? AppColors.amber : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (on) ...[
            Icon(Icons.check, size: 14, color: AppColors.amber),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.amber : AppColors.text),
          ),
        ],
      ),
    ),
  );
}

// ═══ المدرس ═════════════════════════════════════════════════════════════════

class TeacherFormScreen extends StatefulWidget {
  const TeacherFormScreen({super.key, this.teacher});

  final Teacher? teacher;

  @override
  State<TeacherFormScreen> createState() => _TeacherFormScreenState();
}

class _TeacherFormScreenState extends State<TeacherFormScreen> {
  late final _parsed = parsePhoneAndPrefix(widget.teacher?.phone);
  late final name = TextEditingController(text: widget.teacher?.name ?? '');
  late final phone = TextEditingController(text: _parsed.number);
  late String prefix = _parsed.prefix;
  late final email = TextEditingController(text: widget.teacher?.email ?? '');
  late final nationalId = TextEditingController(text: widget.teacher?.nationalId ?? '');
  late final portalCode = TextEditingController(
    text: (widget.teacher?.portalCode.isNotEmpty ?? false) ? widget.teacher!.portalCode : AppStore.instance.newPortalCode(),
  );
  late final rate = TextEditingController(text: trimNum(widget.teacher?.rate ?? 70));
  late final notes = TextEditingController(text: widget.teacher?.notes ?? '');
  /// الراتب شهري فقط؛ أنواع الأجر الأخرى أُلغيت.
  final String paymentType = 'fixed_monthly';

  /// الشهر الذي يسري منه الراتب المُدخل — الأشهر السابقة تبقى براتبها.
  late String salaryFrom = monthKeyOf(DateTime.now());
  late final List<String> subjectIds = [...?widget.teacher?.subjectIds];
  final errors = FieldErrors();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    // حساب قديم يحمل اسم مادة واحدة بلا معرّفات — تُختار مادته
    final t = widget.teacher;
    if (subjectIds.isEmpty && (t?.subject ?? '').isNotEmpty) {
      subjectIds.addAll(StoreScope.of(context).subjects.where((s) => s.name == t!.subject).map((s) => s.id));
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    nationalId.dispose();
    portalCode.dispose();
    rate.dispose();
    notes.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    final rateValue = double.tryParse(rate.text.trim());
    final idDigits = digitsOnly(nationalId.text);
    final number = digitsOnly(phone.text);
    setState(() {
      errors
        ..reset()
        ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المدرس')
        ..check('phone', number.isEmpty, 'يرجى إدخال رقم هاتف المدرس')
        ..check('nationalId', idDigits.isNotEmpty && idDigits.length != 9, 'رقم الهوية يجب أن يتكون من 9 أرقام')
        ..check('rate', rateValue == null || rateValue < 0, 'يرجى إدخال راتب صحيح');
    });
    if (errors.report(context)) return;

    try {
      final names = store.subjects.where((s) => subjectIds.contains(s.id)).map((s) => s.name).toList();
      store.upsertTeacher(
        Teacher(
          id: widget.teacher?.id ?? store.newId(),
          name: name.text.trim(),
          phone: combinePhoneAndPrefix(number, prefix),
          subject: names.isEmpty ? '' : names.first,
          rate: rateValue ?? 0,
          email: email.text.trim(),
          paymentType: paymentType,
          // الراتب الجديد يسري من شهره: راتب شهر مضى يبقى كما كان وقته
          salaryHistory: applySalaryChange(widget.teacher, salaryFrom, rateValue ?? 0),
          notes: notes.text.trim(),
          nationalId: idDigits,
          portalCode: portalCode.text.trim(),
          subjectIds: [...subjectIds],
        ),
      );
      showAppSnack(context, widget.teacher == null ? 'تمت إضافة المدرس' : 'تم حفظ بيانات المدرس');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final store = StoreScope.of(context);
    final ok = await confirmSheet(
      context,
      title: 'حذف المدرس',
      message: 'سيتم فك ارتباط المدرس بالمجموعات وحذف بياناته نهائياً.',
      confirmLabel: 'تأكيد الحذف',
    );
    if (!ok || !mounted) return;
    try {
      store.deleteTeacher(widget.teacher!.id);
      showAppSnack(context, 'تم حذف المدرس');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.teacher != null;
    final title = editing ? 'تعديل بيانات: ${widget.teacher!.name}' : 'إضافة مدرس جديد';
    if (!store.can('settings')) return _denied(store, title);
    final target = phoneTargetLength(prefix);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _formBar(title),
      bottomNavigationBar: FormActionBar(label: editing ? 'حفظ التعديلات' : 'إضافة المدرس', onSave: _save),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // ── ١. بيانات المدرس ─────────────────────────────────────────────
            const FormSection(icon: Icons.badge_outlined, title: 'بيانات المدرس', note: 'الحقول ذات * مطلوبة'),
            FieldLabel('اسم المدرس', key: errors.key('name'), requiredField: true),
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (errors.clear('name')) setState(() {});
              },
              decoration: InputDecoration(hintText: 'مثال: أ. محمد العلي', errorText: errors['name']),
            ),
            _gap,
            FieldLabel('رقم الهاتف', key: errors.key('phone'), requiredField: true),
            // الرقم يُقرأ من اليسار: المقدمة أولاً ثم بقيته، كنموذج الطالب
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: AppDropdown<String>(
                      value: prefix,
                      items: phonePrefixes.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (v) => setState(() => prefix = v ?? prefix),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) {
                        if (errors.clear('phone')) setState(() {});
                      },
                      style: const TextStyle(fontSize: 13.5, letterSpacing: 0.8),
                      decoration: InputDecoration(hintText: '$target أرقام', errorText: errors['phone']),
                    ),
                  ),
                ],
              ),
            ),
            _gap,
            const FieldLabel('البريد الإلكتروني'),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'name@mail.com'),
            ),

            // ── ٢. دخول البوابة ─────────────────────────────────────────────
            const FormSection(icon: Icons.vpn_key_outlined, title: 'دخول بوابة المعلم'),
            FieldPair(
              start: [
                FieldLabel('رقم الهوية', key: errors.key('nationalId')),
                TextField(
                  controller: nationalId,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  onChanged: (_) {
                    if (errors.clear('nationalId')) setState(() {});
                  },
                  decoration: InputDecoration(hintText: '9 أرقام', counterText: '', errorText: errors['nationalId']),
                ),
              ],
              end: [
                const FieldLabel('رمز الدخول'),
                TextField(
                  controller: portalCode,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '6 أرقام',
                    counterText: '',
                    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    suffixIcon: IconButton(
                      tooltip: 'توليد رمز جديد',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Icon(Icons.autorenew, size: 18, color: AppColors.amber),
                      onPressed: () => setState(() => portalCode.text = store.newPortalCode()),
                    ),
                  ),
                ),
              ],
            ),

            // ── ٣. المواد ───────────────────────────────────────────────────
            const FormSection(icon: Icons.menu_book_outlined, title: 'المواد التي يدرّسها'),
            if (store.subjects.isEmpty)
              const Text(
                'لا توجد مواد بعد — أضفها من تبويب «المواد».',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in store.subjects)
                    _choiceChip(s.name, subjectIds.contains(s.id), () {
                      setState(() {
                        if (subjectIds.contains(s.id)) {
                          subjectIds.remove(s.id);
                        } else {
                          subjectIds.add(s.id);
                        }
                      });
                    }),
                ],
              ),

            // ── ٤. المحاسبة ─────────────────────────────────────────────────
            const FormSection(icon: Icons.payments_outlined, title: 'المحاسبة والراتب'),
            FieldPair(
              start: [
                FieldLabel('الراتب الشهري (₪)', key: errors.key('rate'), requiredField: true),
                TextField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (errors.clear('rate')) setState(() {});
                  },
                  decoration: InputDecoration(errorText: errors['rate']),
                ),
              ],
              end: [
                const FieldLabel('يسري من شهر'),
                SelectField(
                  text: monthLabel(salaryFrom),
                  icon: Icons.event_outlined,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(DateTime.now().year - 2),
                      lastDate: DateTime(DateTime.now().year + 1, 12),
                    );
                    if (picked != null) setState(() => salaryFrom = monthKeyOf(picked));
                  },
                ),
              ],
            ),
            if ((widget.teacher?.salaryHistory ?? const []).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'سجل الراتب: ${widget.teacher!.salaryHistory.map(describeSalaryChange).join('  ·  ')}',
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
            _gap,
            const FieldLabel('ملاحظات'),
            TextField(
              controller: notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'ملاحظات اختيارية...'),
            ),
            if (editing) _DeleteButton(label: 'حذف المدرس', onPressed: _delete),
          ],
        ),
      ),
    );
  }
}

// ═══ المادة ═════════════════════════════════════════════════════════════════

class SubjectFormScreen extends StatefulWidget {
  const SubjectFormScreen({super.key, this.subject});

  final SubjectItem? subject;

  @override
  State<SubjectFormScreen> createState() => _SubjectFormScreenState();
}

class _SubjectFormScreenState extends State<SubjectFormScreen> {
  static const _general = 'عام / كل المراحل';

  late final name = TextEditingController(text: widget.subject?.name ?? '');
  late final code = TextEditingController(text: widget.subject?.code ?? '');
  late final description = TextEditingController(text: widget.subject?.description ?? '');
  String? grade;
  final errors = FieldErrors();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (grade != null) return;
    final store = StoreScope.of(context);
    final s = widget.subject;
    grade = (s?.gradeLevel.isNotEmpty ?? false)
        ? s!.gradeLevel
        : (store.gradeFees.isNotEmpty ? store.gradeFees.first.gradeName : _general);
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    description.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    setState(() {
      errors
        ..reset()
        ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المادة');
    });
    if (errors.report(context)) return;
    try {
      store.upsertSubject(
        SubjectItem(
          id: widget.subject?.id ?? store.newId(),
          name: name.text.trim(),
          code: code.text.trim(),
          gradeLevel: grade ?? _general,
          description: description.text.trim(),
        ),
      );
      showAppSnack(context, widget.subject == null ? 'تمت إضافة المادة' : 'تم حفظ المادة');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final store = StoreScope.of(context);
    final ok = await confirmSheet(
      context,
      title: 'حذف المادة',
      message: 'هل تريد حذف مادة «${widget.subject!.name}» نهائياً؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      store.deleteSubject(widget.subject!.id);
      showAppSnack(context, 'تم حذف المادة');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.subject != null;
    final title = editing ? 'تعديل مادة: ${widget.subject!.name}' : 'إضافة مادة دراسية';
    if (!store.can('settings')) return _denied(store, title);

    final grades = <String>{
      _general,
      ...store.gradeFees.map((g) => g.gradeName),
      ...store.rooms.map((r) => r.gradeLevel),
    }.where((g) => g.trim().isNotEmpty).toList();
    if (grade != null && !grades.contains(grade)) grades.add(grade!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _formBar(title),
      bottomNavigationBar: FormActionBar(label: editing ? 'حفظ التعديلات' : 'إضافة المادة', onSave: _save),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const FormSection(icon: Icons.menu_book_outlined, title: 'بيانات المادة', note: 'الحقول ذات * مطلوبة'),
            FieldLabel('اسم المادة الدراسية', key: errors.key('name'), requiredField: true),
            TextField(
              controller: name,
              onChanged: (_) {
                if (errors.clear('name')) setState(() {});
              },
              decoration: InputDecoration(hintText: 'مثال: الرياضيات، الفيزياء...', errorText: errors['name']),
            ),
            _gap,
            FieldPair(
              startFlex: 2,
              endFlex: 3,
              start: [
                const FieldLabel('رمز المادة'),
                TextField(
                  controller: code,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'MATH-1'),
                ),
              ],
              end: [
                const FieldLabel('المرحلة الدراسية'),
                AppDropdown<String>(
                  value: grade,
                  items: [
                    for (final g in grades) DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => grade = v ?? grade),
                ),
              ],
            ),
            _gap,
            const FieldLabel('وصف أو ملاحظات'),
            TextField(
              controller: description,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'ملاحظات توضيحية عن المنهاج...'),
            ),
            if (editing) _DeleteButton(label: 'حذف المادة', onPressed: _delete),
          ],
        ),
      ),
    );
  }
}

// ═══ المرحلة الدراسية ورسومها ═══════════════════════════════════════════════

class GradeFeeFormScreen extends StatefulWidget {
  const GradeFeeFormScreen({super.key, this.fee});

  final GradeFee? fee;

  @override
  State<GradeFeeFormScreen> createState() => _GradeFeeFormScreenState();
}

class _GradeFeeFormScreenState extends State<GradeFeeFormScreen> {
  late final name = TextEditingController(text: widget.fee?.gradeName ?? '');
  late final monthly = TextEditingController(text: widget.fee == null ? '' : trimNum(widget.fee!.monthlyFee));
  final section = TextEditingController();
  late String tier = educationalStageTiers.containsKey(widget.fee?.tier) ? widget.fee!.tier : 'secondary';
  final errors = FieldErrors();

  @override
  void dispose() {
    name.dispose();
    monthly.dispose();
    section.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    final value = double.tryParse(monthly.text.trim());
    setState(() {
      errors
        ..reset()
        ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المرحلة الدراسية')
        ..check('fee', value == null || value < 0, 'يرجى إدخال رسم شهري صحيح');
    });
    if (errors.report(context)) return;

    final f = widget.fee;
    try {
      if (f == null) {
        store.addGradeFee(
          GradeFee(
            id: store.newId(),
            gradeName: name.text.trim(),
            monthlyFee: value!,
            tier: tier,
            isCustom: true,
            orderIndex: store.gradeFees.length + 1,
          ),
          initialSection: section.text.trim(),
        );
      } else {
        store.updateGradeFee(
          GradeFee(
            id: f.id,
            gradeName: name.text.trim(),
            monthlyFee: value!,
            tier: tier,
            orderIndex: f.orderIndex,
            isCustom: f.isCustom,
          ),
        );
      }
      showAppSnack(context, f == null ? 'تمت إضافة المرحلة الدراسية' : 'تم حفظ المرحلة');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete() async {
    final store = StoreScope.of(context);
    final f = widget.fee!;
    final ok = await confirmSheet(
      context,
      title: 'حذف المرحلة',
      message: 'هل أنت متأكد من حذف مرحلة «${f.gradeName}»؟',
      confirmLabel: 'حذف',
    );
    if (!ok || !mounted) return;
    try {
      store.deleteGradeFee(f);
      showAppSnack(context, 'تم حذف المرحلة');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final editing = widget.fee != null;
    final title = editing ? 'تعديل مرحلة: ${widget.fee!.gradeName}' : 'مرحلة دراسية جديدة';
    if (!store.can('settings')) return _denied(store, title);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _formBar(title),
      bottomNavigationBar: FormActionBar(label: editing ? 'حفظ التعديلات' : 'إضافة المرحلة', onSave: _save),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const FormSection(icon: Icons.school_outlined, title: 'بيانات المرحلة', note: 'الحقول ذات * مطلوبة'),
            FieldLabel('اسم المرحلة أو الصف الدراسي', key: errors.key('name'), requiredField: true),
            TextField(
              controller: name,
              onChanged: (_) {
                if (errors.clear('name')) setState(() {});
              },
              decoration: InputDecoration(hintText: 'مثال: الصف الثاني عشر...', errorText: errors['name']),
            ),
            _gap,
            FieldPair(
              startFlex: 3,
              endFlex: 2,
              start: [
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
              end: [
                FieldLabel('الرسم الشهري (₪)', key: errors.key('fee'), requiredField: true),
                TextField(
                  controller: monthly,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) {
                    if (errors.clear('fee')) setState(() {});
                  },
                  decoration: InputDecoration(hintText: '200', errorText: errors['fee']),
                ),
              ],
            ),
            if (!editing) ...[
              _gap,
              const FieldLabel('الشعبة الأولى (اختياري)'),
              TextField(controller: section, decoration: const InputDecoration(hintText: 'مثال: الشعبة (أ)')),
            ],
            if (editing) _DeleteButton(label: 'حذف المرحلة', onPressed: _delete),
          ],
        ),
      ),
    );
  }
}

/// اختيار التبويبات التي يراها الحساب — المقابل لـ `AccessEditor.tsx`: سطر لكل
/// تبويب، والفرعي تحت أصله. إتاحة الفرع تتيح أصله، وإخفاء الأصل يخفي فروعه.
class AccessEditor extends StatelessWidget {
  const AccessEditor({super.key, required this.value, required this.onChanged, this.enabled = true});

  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = value.toSet();
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < accessSections.length; i++)
              _AccessRow(
                section: accessSections[i],
                on: selected.contains(accessSections[i].id),
                blocked: accessSections[i].parent != null && !selected.contains(accessSections[i].parent),
                last: i == accessSections.length - 1,
                onTap: enabled ? () => onChanged(toggleSection(value, accessSections[i].id)) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessRow extends StatelessWidget {
  const _AccessRow({
    required this.section,
    required this.on,
    required this.blocked,
    required this.last,
    required this.onTap,
  });

  final SectionDef section;
  final bool on;
  final bool blocked;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = section.parent != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(child ? 28 : 12, 10, 12, 10),
        decoration: BoxDecoration(
          color: on ? AppColors.successSoft : Colors.white,
          border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    section.label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  if (section.hint != null)
                    Text(section.hint!, style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309))),
                  if (blocked)
                    Text(
                      'يحتاج إتاحة «${sectionLabel(section.parent!)}»',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.chip),
                color: on ? AppColors.success : Colors.white,
                border: Border.all(color: on ? AppColors.success : AppColors.lineStrong),
              ),
              child: on ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final name = TextEditingController();
  String role = 'receptionist';
  List<String> sections = [...roles['receptionist']!.sections];
  final errors = FieldErrors();

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    setState(() {
      errors
        ..reset()
        ..check('name', name.text.trim().isEmpty, 'يرجى إدخال اسم المستخدم');
    });
    if (errors.report(context)) return;
    try {
      store.addUser(AppUser(id: store.newId(), name: name.text.trim(), role: role, capabilities: [...sections]));
      showAppSnack(context, 'تمت إضافة المستخدم');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    const title = 'مستخدم جديد';
    if (!store.can('settings.users')) return _denied(store, title);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _formBar(title),
      bottomNavigationBar: FormActionBar(label: 'إضافة المستخدم', onSave: _save),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const FormSection(icon: Icons.person_outline, title: 'بيانات المستخدم', note: 'الحقول ذات * مطلوبة'),
            FieldPair(
              startFlex: 3,
              endFlex: 2,
              start: [
                FieldLabel('الاسم', key: errors.key('name'), requiredField: true),
                TextField(
                  controller: name,
                  onChanged: (_) {
                    if (errors.clear('name')) setState(() {});
                  },
                  decoration: InputDecoration(hintText: 'اسم المستخدم', errorText: errors['name']),
                ),
              ],
              end: [
                const FieldLabel('الدور'),
                AppDropdown<String>(
                  value: role,
                  items: [
                    for (final r in roleList) DropdownMenuItem(value: r.id, child: Text(r.label)),
                  ],
                  // الدور قالب بداية: اختياره يملأ التبويبات، ثم تُعدَّل واحداً واحداً
                  onChanged: (v) => setState(() {
                    role = v ?? role;
                    sections = [...roleDefinition(role).sections];
                  }),
                ),
              ],
            ),
            FormSection(
              icon: Icons.tab_outlined,
              title: 'التبويبات الظاهرة له',
              note: '${sections.length} من ${allSections.length}',
            ),
            AccessEditor(value: sections, onChanged: (v) => setState(() => sections = v)),
          ],
        ),
      ),
    );
  }
}

class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  late List<String> sections = effectiveSections(widget.user.capabilities, widget.user.role);

  void _save() {
    final store = StoreScope.of(context);
    final u = widget.user;
    try {
      store.updateUser(
        AppUser(id: u.id, name: u.name, role: u.role, email: u.email, isActive: u.isActive, capabilities: [...sections]),
      );
      showAppSnack(context, 'تم الحفظ');
      Navigator.pop(context);
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final u = widget.user;
    if (!store.can('settings.users')) return _denied(store, 'تبويبات ${u.name}');
    // الحساب المستخدم على هذا الجهاز الآن لا تُعدَّل تبويباته منه — كما في
    // AccessEditor.tsx — كي لا يُغلق المدير الباب على نفسه
    final locked = u.id == store.deviceUserId;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تبويبات ${u.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
            const SizedBox(height: 2),
            Text(
              roleLabel(u.role),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FormActionBar(label: 'حفظ التبويبات', onSave: locked ? null : _save),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (locked)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Corner.box),
                color: AppColors.amberSoft,
                border: Border.all(color: AppColors.amberBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تبويبات حسابك تُعدَّل من جهاز آخر',
                      style: TextStyle(color: AppColors.heading, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          FormSection(
            icon: Icons.tab_outlined,
            title: 'التبويبات الظاهرة له',
            note: '${sections.length} من ${allSections.length}',
          ),
          AccessEditor(value: sections, enabled: !locked, onChanged: (v) => setState(() => sections = v)),
        ],
      ),
    );
  }
}
