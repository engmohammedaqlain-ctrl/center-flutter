import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/balance.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
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

        // الأحدث أولاً: آخر سند هو ما يُبحث عنه عادةً
        final pays = store.paymentsOf(student.id);
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (!student.isActiveStudent) ...[
                      const SizedBox(width: 6),
                      StudentStatusChip(status: student.status, compact: true),
                    ],
                  ],
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
              // ── الوضع المالي: بطاقتان مستقلتان متجاورتان، لا صندوقان داخل بطاقة ──
              if (canFinance) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: StatCard(
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
                        child: StatCard(label: 'إجمالي المقبوضات', value: money(totalPaid), color: AppColors.heading),
                      ),
                    ],
                  ),
                ),
                // من أين جاء الرصيد: المقبوض مقابل المطالبات، والمستحق اليوم
                _BalanceBreakdown(student: student, totalPaid: totalPaid, installments: insts),
                // خصم الرسوم إن وُجد: نسبته وسببه والصافي الشهري بعده
                _DiscountBadge(student: student),
                const SizedBox(height: 10),
              ],

              // ── بيانات الدخول: كلمتا مرور البوابة ──────────────────────────
              _Card(
                title: 'بيانات الدخول',
                children: [
                  // للطالب ولولي أمره، مخفيتان حتى تُطلبا
                  _SecretCode(
                    label: 'كلمة مرور الطالب',
                    code: student.portalCode,
                    onGenerate: canEdit ? () => store.ensureStudentPortalCodes([student]) : null,
                  ),
                  const SizedBox(height: 6),
                  _SecretCode(
                    label: 'كلمة مرور ولي الأمر',
                    code: student.parentPortalCode,
                    onGenerate: canEdit ? () => store.ensureStudentPortalCodes([student]) : null,
                  ),
                ],
              ),

              // ── بيانات الطالب والتواصل: القسم الوحيد المفتوح، ويُطوى إن شاء ──
              _Card(
                initiallyOpen: true,
                title: 'بيانات الطالب والتواصل',
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
                      _Field('حالة الطالب', student.statusLabel),
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
                      if (medical.isNotEmpty) _Field('تفاصيل الحالة الصحية', medical),
                      if (student.previousSchool.trim().isNotEmpty)
                        _Field('المدرسة السابقة', student.previousSchool.trim()),
                      if (address.isNotEmpty) _Field('العنوان', address),
                      if (student.referralSource.trim().isNotEmpty)
                        _Field('مصدر التعرف', student.referralSource.trim()),
                      // الملاحظة القصيرة خانة كبقيتها تُكمل الصف، والطويلة وحدها بعرض السطر
                      if (student.notes.trim().isNotEmpty) _Field('ملاحظات', student.notes.trim()),
                      if (student.initialRating > 0)
                        _Field(
                          'التقييم المبدئي',
                          '',
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
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
                        ),
                    ],
                  ),
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
                    InfoStrip(
                      // الأرقام تتقلّص ولا تطفح على الشاشات الضيقة
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TallyText('حضور', present, AppColors.success),
                            ),
                          ),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TallyText('غياب', absent, AppColors.danger),
                            ),
                          ),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TallyText('مأذون', excused, const Color(0xFFD97706)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // آخر ما رُصد: الأيام الخمسة الأخيرة كما تعرض النسخة المكتبية
                    // أحدث السجلات لا الجدول كاملاً
                    ..._recentAttendance(marks),
                  ],
                ),

              // ── الصفوف والمجموعات: مواد الشعبة ومعلموها في المدرسة، ومجموعات المركز ──
              if (store.can('schedule.view')) ...[
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
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.field))),
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
/// بطاقة قسم في ملف الطالب، تُطوى بالضغط على عنوانها — المقابل لـ
/// `CollapsibleSection` في StudentDetail.tsx.
///
/// الملف طويل: الوضع المالي والأقساط مفتوحان لأنهما سبب فتحه غالباً، وما عداهما
/// مطويٌّ حتى يُطلب فلا تضيع الصفحة في التمرير. البطاقة بلا عنوان لا تُطوى.
class _Card extends StatefulWidget {
  const _Card({this.title, this.trailing, this.initiallyOpen = false, required this.children});

  final String? title;
  final Widget? trailing;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  late bool open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
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
                    child: InkWell(
                      onTap: () => setState(() => open = !open),
                      child: Row(
                        children: [
                          // مطوي: سهم لأعلى — «اضغط ليرتفع المحتوى». مفتوح: لأسفل
                          AnimatedRotation(
                            turns: open ? 0 : 0.5,
                            duration: const Duration(milliseconds: 150),
                            child: const Icon(Icons.expand_more, size: 18, color: AppColors.faint),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ?widget.trailing,
                ],
              ),
              if (open)
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 8),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),
            ],
            if (title == null || open) ...widget.children,
          ],
        ),
      ),
    );
  }
}

/// آخر خمسة أيام مرصودة: بلاطتان في السطر كما في شبكة الحضور بالنسخة المكتبية.
///
/// السطر الكامل لتاريخ وحالة يترك نصف العرض فارغاً، فتُقسم البلاطات عمودين.
List<Widget> _recentAttendance(List<AttendanceMark> marks) {
  final recent = [...marks]..sort((a, b) => b.date.compareTo(a.date));
  if (recent.isEmpty) return const [];
  final shown = recent.take(5).toList();
  return [
    const _Rule(),
    for (var i = 0; i < shown.length; i += 2)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: _AttendanceTile(mark: shown[i])),
            const SizedBox(width: 6),
            // الفردي الأخير يبقى بعرض بلاطة لا بعرض السطر
            Expanded(child: i + 1 < shown.length ? _AttendanceTile(mark: shown[i + 1]) : const SizedBox.shrink()),
          ],
        ),
      ),
  ];
}

/// يوم واحد: تاريخه وحالته داخل بلاطة خفيفة.
class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.mark});

  final AttendanceMark mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: _cellBox(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              mark.date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.text),
            ),
          ),
          const SizedBox(width: 4),
          _AttendanceChip(status: mark.status),
        ],
      ),
    );
  }
}

/// حالة يوم واحد بلونها — مطابق لـ `ATTENDANCE_STATUS_STYLE`.
class _AttendanceChip extends StatelessWidget {
  const _AttendanceChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, background, border) = switch (status) {
      'absent' => ('غائب', AppColors.danger, AppColors.dangerSoft, AppColors.dangerBorder),
      'excused' => ('مأذون', const Color(0xFFD97706), const Color(0xFFFEF3C7), const Color(0xFFFDE68A)),
      _ => ('حاضر', AppColors.success, AppColors.successSoft, AppColors.successBorder),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Corner.chip),
        border: Border.all(color: border),
      ),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// تفصيل الرصيد: المقبوض مقابل المطالبات، ومنها المستحق اليوم.
///
/// الرصيد رقمٌ واحد يجمع أشياء عدة، فيبدو مخالفاً للحدس: طالبٌ سدّد كل ما استُحق
/// عليه يبقى «عليه» قيمة أقساطه القادمة، لأن القسط المجدول مطالبة قائمة —
/// هكذا تحسبه النسخة المكتبية. هذا السطر يُظهر الأرقام التي بُني منها.
class _BalanceBreakdown extends StatelessWidget {
  const _BalanceBreakdown({required this.student, required this.totalPaid, required this.installments});

  final Student student;
  final double totalPaid;
  final List<Installment> installments;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final dueSoFar = installments.where(isInstallmentDue).fold<double>(0, (a, i) => a + i.amount);
    final dues = installments.fold<double>(0, (a, i) => a + i.amount);
    final fees = store.enrollments
        .where((e) => e.studentId == student.id && (e.status == 'active' || e.status == 'completed'))
        .fold<double>(0, (a, e) => a + (e.appliedPrice ?? e.customPrice ?? 0));
    final overdue = overdueByStudent(installments)[student.id] ?? 0;
    if (dues == 0 && fees == 0 && totalPaid == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [
                  'المقبوض ${money(totalPaid)}',
                  // المطالبة اليوم هي المستحق حتى تاريخه، والباقي مجدول لم يحن
                  if (dues > 0) 'المستحق حتى اليوم ${money(dueSoFar)} من ${money(dues)}',
                  if (fees > 0) 'رسوم التسجيل ${money(fees)}',
                ].join('  ·  '),
                maxLines: 2,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              overdue > 0 ? 'المستحق اليوم: ${money(overdue)}' : 'لا مستحق اليوم',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: overdue > 0 ? AppColors.danger : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// خصم رسوم الطالب — المقابل لشارة «خصم الرسوم» في StudentDetail.tsx.
///
/// تظهر لمن له خصم فقط: نسبته إن كانت نسبة، وسببه، والرسم الشهري بعده.
class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final net = student.customMonthlyFee;
    final hasDiscount = student.academicDiscountApplied || (net != null && net > 0);
    if (!hasDiscount) return const SizedBox.shrink();

    final rate = student.academicDiscountRate;
    final reason = student.exceptionReason.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(Corner.box),
          border: Border.all(color: AppColors.amberBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.sell_outlined, size: 15, color: AppColors.amberDark),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'خصم الرسوم',
                  children: [
                    if (rate > 0)
                      TextSpan(
                        text: '  ${trimNum(rate)}%',
                        style: TextStyle(fontFamily: 'monospace', color: AppColors.amberDark),
                      ),
                    if (reason.isNotEmpty)
                      TextSpan(
                        text: '  ($reason)',
                        style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.heading),
              ),
            ),
            if (net != null && net > 0) ...[
              const SizedBox(width: 6),
              Text(
                'الصافي الشهري: ${money(net)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success),
              ),
            ],
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

/// صندوق خانة واحدة: خلفية رمادية خفيفة وإطار رفيع، ومحتوى في المنتصف.
BoxDecoration _cellBox() => BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), color: AppColors.bg, border: Border.all(color: AppColors.line));

/// كلمة مرور بوابة — مطابقة لـ `SecretCode` في StudentDetail.tsx: مخفية بنقاط،
/// وزرّا إظهار ونسخ، وتوليد لمن لا كلمة له.
class _SecretCode extends StatefulWidget {
  const _SecretCode({required this.label, required this.code, this.onGenerate});

  final String label;
  final String code;

  /// `null` لمن لا يملك تعديل الطلاب: لا زر توليد.
  final VoidCallback? onGenerate;

  @override
  State<_SecretCode> createState() => _SecretCodeState();
}

class _SecretCodeState extends State<_SecretCode> {
  bool visible = false;

  @override
  Widget build(BuildContext context) {
    final code = widget.code.trim();

    Widget action(IconData icon, String tooltip, VoidCallback onTap) => IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 16, color: AppColors.muted),
          onPressed: onTap,
        );

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.box),
        color: AppColors.amberSoft,
        border: Border.all(color: AppColors.amberBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.key_outlined, size: 15, color: AppColors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.heading, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          if (code.isEmpty)
            widget.onGenerate == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text('غير محدد', style: TextStyle(color: AppColors.faint, fontSize: 11.5)),
                  )
                : TextButton.icon(
                    onPressed: () {
                      widget.onGenerate!();
                      showAppSnack(context, 'تم توليد ${widget.label}');
                    },
                    icon: Icon(Icons.autorenew, size: 15, color: AppColors.amber),
                    label: Text('توليد', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12)),
                  )
          else ...[
            Container(
              constraints: const BoxConstraints(minWidth: 76),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                visible ? code : '••••••',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  letterSpacing: 1.2,
                  color: AppColors.heading,
                ),
              ),
            ),
            action(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, visible ? 'إخفاء' : 'إظهار',
                () => setState(() => visible = !visible)),
            action(Icons.copy_outlined, 'نسخ', () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) showAppSnack(context, 'تم نسخ ${widget.label}');
            }),
          ],
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
  const _Field(this.label, this.value, {this.child, this.ltr = false, bool? wide}) : _wide = wide;

  final String label;
  final String value;
  final Widget? child;
  final bool ltr;
  final bool? _wide;

  /// النص الطويل وحده يأخذ السطر كاملاً؛ القصير خانة كبقيته فلا يبقى نصف السطر
  /// فارغاً. «طبيعة السكن» و«ملاحظة قصيرة» كانا سطرين كاملين بلا داعٍ.
  bool get wide => _wide ?? value.trim().length > 30;
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
          decoration: tileDecoration(white: !inst.isPaid),
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
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 15, color: AppColors.amber),
              const SizedBox(width: 6),
              // الرقم والتاريخ في حيّز واحد يتقلّص قبل المبلغ — هو أهم ما في
              // السطر. ولا يجوز أن يكونا مرنَين بجوار `Spacer`: الثلاثة يقتسمون
              // الفراغ أثلاثاً، فما لا يستهلكه النص يبقى فجوة قبل المبلغ.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(p.receiptNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        formatDate(p.date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                    StoreScope.of(context).paymentMethodLabel(p.method),
                    if (purpose.trim().isNotEmpty) purpose,
                    if (p.cancelled) 'ملغاة',
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.cancelled ? AppColors.danger : AppColors.muted, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              TileButton(
                label: 'الوصل',
                icon: const Icon(Icons.print_outlined, size: 13),
                color: AppColors.heading,
                background: Colors.white,
                border: AppColors.lineStrong,
                onTap: () => ReceiptScreen.open(context, p),
              ),
              if (!p.cancelled) ...[
                const SizedBox(width: 5),
                TileButton(
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
              decoration: tileDecoration(),
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

/// المرفقات الرسمية مع التكبير — تُجلب عند فتح الملف، لا مع كل مزامنة.
class _AttachmentsCard extends StatefulWidget {
  const _AttachmentsCard({required this.studentId});
  final String studentId;

  @override
  State<_AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends State<_AttachmentsCard> {
  Future<StudentAttachments?>? _load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (_load != null || !store.features.enableStudentAttachments) return;
    _load = store.loadAttachments(widget.studentId);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.features.enableStudentAttachments) return const SizedBox.shrink();
    return FutureBuilder<StudentAttachments?>(
      future: _load,
      builder: (context, snap) => _card(snap.data ?? store.attachmentsOf(widget.studentId)),
    );
  }

  Widget _card(StudentAttachments? att) {
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
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Corner.dialog))),
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
            clipBehavior: Clip.antiAlias,
            decoration: tileDecoration(),
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
