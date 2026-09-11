import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'schedule_screen.dart';
import 'student_form_screen.dart';

/// ملف الطالب — بتخطيط واجهة الهاتف في `pages/StudentDetail.tsx`.
///
/// بطاقات مدمجة متتالية كما في Center، وكل عنصر متكرر فيها — قسط، سند،
/// تقييم — بلاطة خفيفة مستقلة. البيانات الأساسية شبكة من عمودين: عنوان صغير
/// فوق قيمته، فتُقرأ بلمحة بدل أسطر متفاوتة الأطوال. اسم الطالب عنوان الصفحة،
/// وتسديد الدفعة وتعديل البيانات ثابتان أسفل الشاشة.
class StudentDetailScreen extends StatelessWidget {
  const StudentDetailScreen({super.key, required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // الملف يُفتح من المالية والصفوف أيضاً، فتُحرس الشاشة نفسها لا زرّ الوصول وحده
        if (!store.can('students.view')) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('ملف الطالب')),
            body: NoAccess(section: 'students', roleName: store.roleName),
          );
        }
        final student = store.studentById(studentId);
        if (student == null) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(title: const Text('ملف الطالب')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('لم يتم العثور على ملف الطالب', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  GhostButton(label: 'العودة لقائمة الطلاب', onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
          );
        }

        final pays = store.payments.where((p) => p.studentId == student.id).toList();
        final insts = store.installments.where((i) => i.studentId == student.id).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final marks = store.attendance.where((a) => a.studentId == student.id).toList();
        final totalPaid = pays.where((p) => !p.cancelled).fold<double>(0, (a, p) => a + p.amount);
        final present = marks.where((m) => m.status == 'present').length;
        final absent = marks.where((m) => m.status == 'absent').length;
        final excused = marks.where((m) => m.status == 'excused').length;
        // الالتزام يحتسب الحاضر وحده — مطابق لـ attendanceStats في StudentDetail.tsx
        final rate = marks.isEmpty ? 100 : ((present / marks.length) * 100).round();
        final settled = !student.isDebtor && insts.every((i) => i.isPaid);
        // الأرصدة والدفعات تخصّ من يملك عرض المالية، والقبض من يملك القبض
        final canFinance = store.can('finance.view');
        final canCollect = store.can('finance.collect');
        final canEdit = store.can('students.edit');

        final grade = student.gradeLevel.trim().isEmpty ? 'مرحلة غير محددة' : student.gradeLevel.trim();
        final meta = student.section.trim().isEmpty ? grade : '$grade  ·  شعبة ${student.section.trim()}';
        final address = [
          if (student.neighborhood.trim().isNotEmpty) student.neighborhood.trim(),
          if (student.detailedAddress.trim().isNotEmpty) student.detailedAddress.trim(),
        ].join('  ·  ');
        final birth = parseIsoDate(student.birthDate);
        final medical = student.healthStatus.trim() == 'مريض' ? student.medicalCondition.trim() : '';
        final parentName = student.parentName.trim();
        final parentPhone = student.parentPhone.trim();

        void pay() {
          final next = insts.where((i) => !i.isPaid).firstOrNull;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaymentFormScreen(studentId: student.id, installmentId: next?.id, amount: next?.remaining),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          // اسم الطالب عنوان الصفحة، والمرحلة تحته — فلا يتكرر الاسم في المحتوى
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  student.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          bottomNavigationBar: (canCollect || canEdit)
              ? _ActionBar(
                  showPay: canCollect,
                  onPay: canCollect ? (settled ? null : pay) : null,
                  onEdit: canEdit
                      ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentFormScreen(student: student)))
                      : null,
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              // ── الوضع المالي السريع: الرصيد والمقبوضات متجاوران ──────────────
              if (canFinance)
                _Card(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Stat(
                              label: 'الرصيد المالي الحالي',
                              value: student.isDebtor
                                  ? 'عليه ${money(student.balance)}'
                                  : student.balance > 0
                                      ? 'له ${money(student.balance)}'
                                      : 'مسدد بالكامل',
                              color: student.isDebtor ? AppColors.danger : AppColors.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Stat(label: 'إجمالي المقبوضات', value: money(totalPaid), color: AppColors.heading),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

              // ── بيانات الطالب والتواصل ─────────────────────────────────────
              _Card(
                title: 'بيانات الطالب والتواصل',
                trailing: _PortalCodeChip(student: student, canEdit: canEdit),
                children: [
                  // الرقمان متجاوران: عنوان صغير فوق رقم بارز، وأيقونتا الاتصال تحته
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ContactCell(label: 'هاتف الطالب', phone: student.phone)),
                        if (parentPhone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ContactCell(
                              label: parentName.isEmpty ? 'هاتف ولي الأمر' : 'ولي الأمر · $parentName',
                              phone: parentPhone,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const _Rule(),
                  _FieldGrid(
                    fields: [
                      if (student.nationalId.isNotEmpty) _Field('رقم الهوية', student.nationalId, ltr: true),
                      if (student.gender.trim().isNotEmpty) _Field('الجنس', genderLabel(student.gender)),
                      if (student.relation.trim().isNotEmpty) _Field('صلة القرابة', student.relation.trim()),
                      if (parentName.isNotEmpty && parentPhone.isEmpty) _Field('ولي الأمر', parentName),
                      if (student.nationality.trim().isNotEmpty) _Field('الجنسية', student.nationality.trim()),
                      if (student.birthPlace.trim().isNotEmpty) _Field('مكان الولادة', student.birthPlace.trim()),
                      if (birth != null) _Field('تاريخ الميلاد', formatDate(birth), ltr: true),
                      if (student.healthStatus.trim().isNotEmpty) _Field('الحالة الصحية', student.healthStatus.trim()),
                      if (student.housingStatus.trim().isNotEmpty) _Field('طبيعة السكن', student.housingStatus.trim()),
                      if (student.gpa.trim().isNotEmpty) _Field('المعدل', student.gpa.trim(), ltr: true),
                      if (medical.isNotEmpty) _Field('تفاصيل الحالة الصحية', medical, wide: true),
                      if (student.previousSchool.trim().isNotEmpty)
                        _Field('المدرسة السابقة', student.previousSchool.trim(), wide: true),
                      if (address.isNotEmpty) _Field('العنوان', address, wide: true),
                      if (student.referralSource.trim().isNotEmpty)
                        _Field('مصدر التعرف', student.referralSource.trim(), wide: true),
                      if (student.initialRating > 0)
                        _Field(
                          'التقييم المبدئي',
                          '',
                          wide: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 1; i <= 5; i++)
                                Icon(
                                  i <= student.initialRating ? Icons.star_rounded : Icons.star_outline_rounded,
                                  size: 17,
                                  color: i <= student.initialRating ? const Color(0xFFF59E0B) : AppColors.lineStrong,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (student.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _Strip(
                      child: Text(student.notes, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.6)),
                    ),
                  ],
                ],
              ),

              // ── الأقساط المجدولة ────────────────────────────────────────────
              if (canFinance && insts.isNotEmpty)
                _Card(
                  title: 'الأقساط المجدولة (${insts.length})',
                  children: [
                    for (final inst in insts) _InstallmentTile(student: student, inst: inst, canCollect: canCollect),
                  ],
                ),

              // ── سجل الدفعات ─────────────────────────────────────────────────
              if (canFinance)
                _Card(
                  title: 'سجل الدفعات (${pays.length})',
                  trailing: Text.rich(
                    TextSpan(
                      text: 'المقبوض: ',
                      children: [
                        TextSpan(text: money(totalPaid), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
                      ],
                    ),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  children: [
                    if (pays.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('لا توجد دفعات مسجلة حتى الآن',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      )
                    else
                      for (final p in pays) _PaymentTile(payment: p, student: student),
                  ],
                ),

              // ── الحضور والالتزام: ملخص بسطر واحد كما في Center ──────────────
              if (marks.isNotEmpty && store.can('attendance.view'))
                _Card(
                  title: 'سجل الحضور والالتزام',
                  trailing: Text('الالتزام: $rate%',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                  children: [
                    _Strip(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Tally('حضور', present, AppColors.success),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          _Tally('غياب', absent, AppColors.danger),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          _Tally('مأذون', excused, const Color(0xFFD97706)),
                        ],
                      ),
                    ),
                  ],
                ),

              // ── المجموعات (للمراكز) ─────────────────────────────────────────
              if (!store.isSchool && store.can('schedule.view')) ...[
                StudentGroupsCard(student: student),
                const SizedBox(height: 10),
              ],

              // ── الدرجات والتقييمات ─────────────────────────────────────────
              if (store.features.enableEvaluations && store.can('attendance.view'))
                _EvaluationsCard(evaluations: store.evaluationsOfStudent(student.id)),

              _AttachmentsCard(studentId: student.id),

              // الحذف زر كامل العرض بلون التحذير في آخر الصفحة، بعيداً عن الإبهام:
              // فعل لا رجعة فيه يُرى بوضوح ولا يُضغط سهواً
              if (store.can('students.delete'))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.dangerBorder),
                        shape: const RoundedRectangleBorder(),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف الطالب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      onPressed: () async {
                        final ok = await confirmSheet(
                          context,
                          title: 'تأكيد حذف الطالب',
                          message: 'هل تريد حذف هذا الطالب نهائياً من النظام؟',
                          confirmLabel: 'حذف',
                        );
                        if (!ok || !context.mounted) return;
                        try {
                          store.deleteStudent(student.id);
                          Navigator.pop(context);
                        } on StoreException catch (e) {
                          showAppSnack(context, e.message, error: true);
                        }
                      },
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

// ═══ عناصر الصفحة ═══════════════════════════════════════════════════════════

/// شريط الإجراءات الثابت: تسديد دفعة أولاً وأعرض، ثم تعديل البيانات.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.showPay, required this.onPay, required this.onEdit});

  final bool showPay;
  final VoidCallback? onPay;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            if (showPay)
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 44,
                  child: PrimaryButton(label: 'تسديد دفعة', icon: Icons.credit_card, onPressed: onPay),
                ),
              ),
            if (showPay && onEdit != null) const SizedBox(width: 10),
            if (onEdit != null)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: GhostButton(label: 'تعديل البيانات', icon: Icons.edit_outlined, onPressed: onEdit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة مدمجة كبطاقات Center: عنوان وخط رفيع تحته، ثم المحتوى.
class _Card extends StatelessWidget {
  const _Card({this.title, this.trailing, required this.children});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(title!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading)),
                  ),
                  ?trailing,
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
              ),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// خط رفيع يفصل مجموعتين داخل البطاقة الواحدة.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Divider(height: 1, color: Color(0xFFF1F5F9)),
    );
  }
}

/// شريط رمادي فاتح بإطار رفيع — للملخصات والملاحظات، كما في Center.
class _Strip extends StatelessWidget {
  const _Strip({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
      child: child,
    );
  }
}

/// بلاطة عنصر متكرر: خلفية فاتحة وإطار رفيع.
BoxDecoration _tile({bool white = false}) => BoxDecoration(
      color: white ? Colors.white : AppColors.bg,
      border: Border.all(color: AppColors.line),
    );

/// صندوق خانة واحدة: خلفية رمادية خفيفة وإطار رفيع، ومحتوى في المنتصف.
BoxDecoration _cellBox() => BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line));

/// رقم إحصائي في بطاقة المالية: صندوق، عنوان صغير فوق قيمة بارزة بلونها، في المنتصف.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: _cellBox(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17)),
          ),
        ],
      ),
    );
  }
}

/// كود البوابة شارةً في رأس بطاقة البيانات — كشارة «كود البوابة» في رأس الملف بـ Center.
class _PortalCodeChip extends StatelessWidget {
  const _PortalCodeChip({required this.student, required this.canEdit});
  final Student student;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final code = student.portalCode.trim();
    if (code.isEmpty) {
      if (!canEdit) return const SizedBox.shrink();
      return InkWell(
        onTap: () {
          store.ensureStudentPortalCodes([student]);
          showAppSnack(context, 'تم توليد رمز الدخول');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('توليد كود البوابة', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 11.5)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: AppColors.amberSoft, border: Border.all(color: AppColors.amberBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vpn_key_outlined, size: 12, color: AppColors.amber),
          const SizedBox(width: 4),
          Text(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1,
              color: AppColors.heading,
            ),
          ),
        ],
      ),
    );
  }
}

/// رقم تواصل في صندوق: العنوان، ثم الرقم بارزاً، ثم أيقونتا الاتصال والواتساب — كلها في المنتصف.
class _ContactCell extends StatelessWidget {
  const _ContactCell({required this.label, required this.phone});
  final String label;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final number = phone.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 9, 6, 2),
      decoration: _cellBox(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              number.isEmpty ? '—' : number,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.5,
                color: number.isEmpty ? AppColors.faint : AppColors.heading,
              ),
            ),
          ),
          if (number.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ContactIconButton(
                  tooltip: 'اتصال',
                  onTap: () => launchTel(number),
                  child: const Icon(Icons.phone_outlined, size: 18, color: AppColors.muted),
                ),
                ContactIconButton(
                  tooltip: 'واتساب',
                  onTap: () => launchWa(number),
                  child: const MessageCircleIcon(color: AppColors.success),
                ),
              ],
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// حقل في الشبكة: عنوان صغير فوق قيمته.
class _Field {
  const _Field(this.label, this.value, {this.child, this.ltr = false, this.wide = false});
  final String label;
  final String value;
  final Widget? child;
  final bool ltr;

  /// يأخذ السطر كله — للنصوص الطويلة كالعنوان.
  final bool wide;
}

/// شبكة صناديق بثلاثة أعمدة، محتوى كل صندوق في منتصفه. الصف الأخير الناقص
/// تتمدّد صناديقه لتملأ العرض بدل ترك فراغ، والنص الطويل صندوق بعرض السطر.
class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.fields});
  final List<_Field> fields;

  static const _columns = 3;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final pending = <_Field>[];

    void flush() {
      if (pending.isEmpty) return;
      final cells = [...pending];
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: _cell(cells[i])),
            ],
          ],
        ),
      ));
      pending.clear();
    }

    for (final f in fields) {
      if (f.wide) {
        flush();
        rows.add(_cell(f));
      } else {
        pending.add(f);
        if (pending.length == _columns) flush();
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: _gap),
          rows[i],
        ],
      ],
    );
  }

  Widget _cell(_Field f) {
    final empty = f.child == null && f.value.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: _cellBox(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(f.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 3),
          f.child ??
              Text(
                empty ? '—' : f.value.trim(),
                maxLines: f.wide ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: f.ltr ? TextDirection.ltr : null,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.45,
                  color: empty ? AppColors.faint : AppColors.text,
                ),
              ),
        ],
      ),
    );
  }
}

/// «حضور: 12» بلون الحالة — ملخص الحضور في سطر واحد.
class _Tally extends StatelessWidget {
  const _Tally(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label: ',
        children: [TextSpan(text: '$value', style: const TextStyle(fontWeight: FontWeight.w900))],
      ),
      style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
    );
  }
}

/// قسط مجدول — بلاطة مستقلة: العنوان وحالته، ثم الاستحقاق مقابل المبالغ.
/// غير المسدد أبيض ويُفتح للتسديد لمن يملك القبض، والمسدد رمادي فاتح.
class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.student, required this.inst, required this.canCollect});

  final Student student;
  final Installment inst;
  final bool canCollect;

  @override
  Widget build(BuildContext context) {
    final future = dateOnly(inst.dueDate).isAfter(dateOnly(DateTime.now()));
    final payable = !inst.isPaid && canCollect;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: payable
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentFormScreen(studentId: student.id, installmentId: inst.id, amount: inst.remaining),
                  ),
                );
              }
            : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: _tile(white: !inst.isPaid),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(inst.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text)),
                  ),
                  if (inst.isPaid)
                    StatusChip.success('مسدد')
                  else if (future)
                    StatusChip.muted('مجدول')
                  else
                    StatusChip.danger('مستحق'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('استحقاق: ${formatDate(inst.dueDate)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        alignment: WrapAlignment.end,
                        children: [
                          Text('المطلوب: ${money(inst.amount)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          if (!inst.isPaid)
                            Text('المتبقي: ${money(inst.remaining)}',
                                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// سند قبض — بلاطة مستقلة: الرقم والتاريخ مقابل المبلغ، ثم خط رفيع، ثم طريقة
/// الدفع وغرضه مقابل زرّي الوصل والواتساب كما في Center.
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.student});
  final Payment payment;
  final Student student;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final purpose = paymentPurposeNames[p.purpose] ?? p.purpose;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: _tile(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 15, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(p.receiptNumber,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
              const SizedBox(width: 8),
              Text(formatDate(p.date), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
              const Spacer(),
              Text(
                money(p.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: p.cancelled ? AppColors.faint : AppColors.success,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.line),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    paymentMethodNames[p.method] ?? p.method,
                    if (purpose.trim().isNotEmpty) purpose,
                    if (p.cancelled) 'ملغاة',
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.cancelled ? AppColors.danger : AppColors.muted, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              _TileButton(
                label: 'الوصل',
                icon: const Icon(Icons.print_outlined, size: 13),
                color: AppColors.heading,
                background: Colors.white,
                border: AppColors.lineStrong,
                onTap: () => ReceiptScreen.open(context, p),
              ),
              if (!p.cancelled) ...[
                const SizedBox(width: 5),
                _TileButton(
                  label: 'واتساب',
                  icon: const MessageCircleIcon(color: AppColors.success, size: 12),
                  color: AppColors.success,
                  background: AppColors.successSoft,
                  border: const Color(0xFF86EFAC),
                  onTap: () => ReceiptScreen.sendWhatsApp(context, p, student),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// زر صغير داخل البلاطة: أيقونة ونص بإطار.
class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final Color color;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: background, border: Border.all(color: border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(data: IconThemeData(color: color), child: icon),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// الدرجات والتقييمات — مطابق لبطاقة «الدرجات والتقييمات (Mobile)» في StudentDetail.tsx.
class _EvaluationsCard extends StatelessWidget {
  const _EvaluationsCard({required this.evaluations});
  final List<Evaluation> evaluations;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return _Card(
      title: 'الدرجات والتقييمات (${evaluations.length})',
      children: [
        if (evaluations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('لا توجد نتائج مسجلة حتى الآن',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.faint, fontSize: 12)),
          )
        else
          for (final e in evaluations)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: _tile(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text)),
                      ),
                      e.passed
                          ? StatusChip.success('${trimNum(e.score)} / ${trimNum(e.maxScore)} (${e.percent}%)')
                          : StatusChip.danger('${trimNum(e.score)} / ${trimNum(e.maxScore)} (${e.percent}%)'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (store.subjectName(e.subjectId).isNotEmpty) store.subjectName(e.subjectId),
                            e.typeLabel,
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                        ),
                      ),
                      if (e.evaluationDate.isNotEmpty)
                        Text(e.evaluationDate, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// المرفقات الرسمية مع التكبير.
class _AttachmentsCard extends StatelessWidget {
  const _AttachmentsCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final att = store.attachmentsOf(studentId);
    if (att == null || att.isEmpty) return const SizedBox.shrink();

    final items = <(String, String)>[
      if (att.studentIdPhoto.isNotEmpty) ('صورة هوية الطالب', att.studentIdPhoto),
      if (att.birthCertificate.isNotEmpty) ('شهادة الميلاد', att.birthCertificate),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return _Card(
      title: 'المرفقات والوثائق (${items.length})',
      children: [
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _Thumb(label: items[i].$1, data: items[i].$2)),
            ],
          ],
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.label, required this.data});
  final String label;
  final String data;

  Uint8List? get _bytes {
    try {
      final comma = data.indexOf(',');
      return base64Decode(comma >= 0 ? data.substring(comma + 1) : data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return const SizedBox.shrink();
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading)),
              ),
              Flexible(child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes))),
              Padding(
                padding: const EdgeInsets.all(10),
                child: GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx)),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 90,
            decoration: _tile(),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}
