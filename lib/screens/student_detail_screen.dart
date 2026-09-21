import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/balance.dart';
import '../data/attendance_days.dart';
import '../data/fee_plan.dart';
import '../data/grade_plan_sync.dart';
import '../data/grading.dart';
import '../data/installment_adjustments.dart';
import '../data/phone.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_plan_rows.dart';
import '../widgets/form_layout.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'return_to_grade_plan_sheet.dart';
import 'student_credit_sheet.dart';
import 'student_subjects_card.dart';
import 'student_form_screen.dart';

/// اقتراحات سبب خصم القسط — مطابق لـ InstallmentActionModals.
const _installmentReasonChips = ['ظرف مادي', 'أخوة', 'أبناء كادر', 'منحة', 'تفوق'];

/// اقتراحات سبب خصم الطالب على الخطة.
const _studentDiscountReasonChips = ['أخوة', 'أبناء كادر', 'منحة', 'ظرف مادي', 'تفوق'];

/// هوامش موحّدة لكاردات ملف الطالب.
/// 18 داخل الكارد يبعد النص عن الحدّ المستدير فيزول إحساس «الكلام ورا الهامش».
const _cardMargin = EdgeInsets.fromLTRB(16, 0, 16, 8);
const _cardHeaderPad = EdgeInsets.fromLTRB(18, 14, 18, 14);
const _cardRowPad = EdgeInsets.symmetric(horizontal: 18, vertical: 12);
const _cardHairlineInset = 18.0;

/// ملف الطالب — تخطيط ميداني للإبهام.
///
/// الملخص المالي أعلى الصفحة للقراءة، والأفعال اليومية (تسديد / رد / تعديل)
/// ثابتة أسفل الشاشة قرب اليد. الأقسام قابلة للطي ومجموعة بعناوين واضحة.
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
        if (!store.can('students')) {
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
        final insts = store.installments.where((i) => i.studentId == student.id).toList()..sort(compareInstallments);
        final rawMarks = store.attendance.where((a) => a.studentId == student.id).toList();
        // الإحصاء بالأيام لا بالسجلات: كشف شعبة + مواد كان يضاعف الغياب
        final days = dailyAttendance(rawMarks, store.sessions);
        final marks = [
          for (final d in days)
            AttendanceMark(id: d.date, studentId: student.id, date: d.date, status: d.status),
        ];
        // السند الملغى لا يُحتسب، والخصم يفسّر لماذا يزيد المسدَّد على المقبوض نقداً
        final activePays = pays.where((p) => !p.cancelled);
        final totalPaid = activePays.fold<double>(0, (a, p) => a + p.amount);
        final present = days.where((d) => d.status == 'present').length;
        final absent = days.where((d) => d.status == 'absent').length;
        final excused = days.where((d) => d.status == 'excused').length;
        // الالتزام يحتسب الحاضر وحده — مطابق لـ attendanceStats في StudentDetail.tsx
        final rate = days.isEmpty ? 100 : ((present / days.length) * 100).round();
        final settled = store.isSettledToDate(student.id) && insts.every((i) => i.isPaid) && student.balance >= -cent;
        final dueBuckets = dueAndScheduled(insts, fallbackBalance: student.balance);
        final dueNow = dueBuckets.due;
        final scheduledRemaining = dueBuckets.scheduled;
        final isDebtor = dueNow > cent;
        // مستحق أقساط أعوام سابقة (غير عام الطالب الحالي)
        final currentYearKey = student.academicYearId.trim().isNotEmpty
            ? student.academicYearId
            : (store.operationalAcademicYear?.id ?? store.viewedAcademicYearId);
        final previousYearsDue = insts.fold<double>(0, (sum, i) {
          final key = i.academicYearId.trim().isEmpty ? currentYearKey : i.academicYearId;
          if (key == currentYearKey) return sum;
          return sum + (isInstallmentDue(i) ? unpaidOf(i) : 0);
        });
        final studentPendingRequests =
            store.pendingFinanceRequests.where((r) => r.studentId == student.id).toList();
        // الأرصدة والدفعات تخصّ من يملك عرض المالية، والقبض من يملك القبض
        final canFinance = store.can('finance');
        final canCollect = store.can('finance.collect');
        final canEdit = store.can('students');
        final canRefundStudent = canFinance && store.studentRefundable(student.id) > cent;

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
          // أول قسط مستحق غير مسدَّد — مطابق لـ openPaymentForm في StudentDetail.tsx
          final next = insts.where((i) => !i.isPaid && i.remaining > cent && isInstallmentDue(i)).firstOrNull;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaymentFormScreen(studentId: student.id, installmentId: next?.id, amount: next?.remaining),
            ),
          );
        }

        Future<void> refund() async {
          final receipt = await showStudentCreditSheet(context, store, student);
          if (receipt != null && context.mounted) {
            ReceiptScreen.open(context, receipt);
          }
        }

        void edit() {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StudentFormScreen(student: student)),
          );
        }

        // ملخص للقراءة أعلى الشاشة — الأفعال اليومية أسفلها قرب الإبهام
        final showBottomBar = canCollect || canEdit || canRefundStudent;
        return Scaffold(
          backgroundColor: AppColors.bg,
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
                  style: const TextStyle(
                    fontFamily: AppText.family,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
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
          bottomNavigationBar: showBottomBar
              ? _ThumbBar(
                  showPay: canCollect,
                  onPay: canCollect && !settled ? pay : null,
                  showRefund: canRefundStudent,
                  onRefund: canRefundStudent ? refund : null,
                  showEdit: canEdit,
                  onEdit: canEdit ? edit : null,
                )
              : null,
          body: ListView(
            padding: EdgeInsets.fromLTRB(0, 10, 0, showBottomBar ? 12 : 28),
            children: [
              if (canFinance)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _FinanceStrip(
                    student: student,
                    totalPaid: totalPaid,
                    dueNow: dueNow,
                    scheduledRemaining: scheduledRemaining,
                    isDebtor: isDebtor,
                    previousYearsDue: previousYearsDue,
                    pendingRequests: studentPendingRequests,
                  ),
                ),

              _Card(
                title: 'بيانات التواصل',
                children: [
                  _DetailRow(
                    label: 'هاتف الطالب',
                    value: student.phone.trim().isEmpty
                        ? '—'
                        : formatPhoneDisplay(student.phone, student.phonePrefix),
                    ltr: student.phone.trim().isNotEmpty,
                    trailing: student.phone.trim().isEmpty
                        ? null
                        : _phoneActions(student.phone),
                  ),
                  // بلا اسم ولي أمر → لا اسم ولا هاتف ولا علاقة
                  if (parentName.isNotEmpty) ...[
                    const _Hairline(),
                    _DetailRow(
                      label: 'ولي الأمر',
                      value: [
                        parentName,
                        if (student.relation.trim().isNotEmpty) '(${student.relation.trim()})',
                      ].join(' '),
                    ),
                    if (parentPhone.isNotEmpty) ...[
                      const _Hairline(),
                      _DetailRow(
                        label: 'هاتف ولي الأمر',
                        value: formatPhoneDisplay(parentPhone, student.parentPhonePrefix),
                        ltr: true,
                        trailing: _phoneActions(parentPhone),
                      ),
                    ],
                  ],
                  if (student.nationalId.isNotEmpty) ...[
                    const _Hairline(),
                    _DetailRow(label: 'رقم الهوية', value: student.nationalId, ltr: true),
                  ],
                  if (address.isNotEmpty) ...[
                    const _Hairline(),
                    _DetailRow(label: 'العنوان', value: address),
                  ],
                  const _Hairline(),
                  _DetailRow(
                    label: 'تاريخ التسجيل',
                    value: formatDate(student.enrollmentDate),
                    ltr: true,
                  ),
                  if (!student.isActiveStudent) ...[
                    const _Hairline(),
                    _DetailRow(label: 'حالة الطالب', value: student.statusLabel),
                  ],
                ],
              ),

              if (_hasExtraIdentity(student, birth, medical))
                _Card(
                  title: 'بيانات إضافية',
                  children: [
                    ..._extraIdentityRows(student, birth, medical),
                  ],
                ),

              if (_studentYearHistory(store, student).length > 1)
                _Card(
                  title: 'السنوات الدراسية',
                  children: [
                    for (final row in _studentYearHistory(store, student)) ...[
                      Padding(
                        padding: _cardRowPad,
                        child: Text(row, style: AppText.body),
                      ),
                      const _Hairline(),
                    ],
                  ],
                ),

              _Card(
                title: 'بيانات الدخول',
                children: [
                  _SecretCode(
                    label: 'كلمة مرور الطالب',
                    code: student.portalCode,
                    onGenerate: canEdit ? () => store.generateStudentPortalCode(student.id, forParent: false) : null,
                  ),
                  const _Hairline(),
                  _SecretCode(
                    label: 'كلمة مرور ولي الأمر',
                    code: student.parentPortalCode,
                    onGenerate: canEdit ? () => store.generateStudentPortalCode(student.id, forParent: true) : null,
                  ),
                ],
              ),

              if (canFinance) ...[
                _Card(
                  title: 'الرسوم (${insts.length})',
                  titleBadge: () {
                    final label = _studentDiscountBadgeLabel(student);
                    return label == null ? null : StatusChip.amber(label);
                  }(),
                  initiallyOpen: true,
                  trailing: IconButton(
                    tooltip: 'إجراءات الرسوم',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(Icons.more_horiz, color: AppColors.heading, size: 22),
                    onPressed: () => _showFeesActionSheet(context, store, student),
                  ),
                  children: [
                    if (student.usesCustomPlan)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'خطة مخصصة — مستقلة عن خطة المرحلة',
                          style: TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (insts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        child: Column(
                          children: [
                            Text('لا توجد رسوم بعد', style: AppText.muted),
                            if (store.can('finance.discount'))
                              TextButton(
                                onPressed: () => _showCustomPlanSheet(context, store, student),
                                child: const Text(
                                  'بناء خطة مخصصة',
                                  style: TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      ..._groupedInstallmentTiles(
                        store: store,
                        student: student,
                        insts: insts,
                        currentYearKey: currentYearKey,
                        canCollect: canCollect,
                        canAdjust: canFinance,
                      ),
                  ],
                ),
                _Card(
                  title: 'الدفعات (${pays.length})',
                  trailing: Text(
                    money(totalPaid),
                    style: TextStyle(
                      fontFamily: AppText.family,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: AppColors.heading,
                    ),
                  ),
                  children: [
                    if (pays.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        child: Text('لا توجد دفعات مسجلة حتى الآن', style: AppText.muted),
                      )
                    else
                      for (var i = 0; i < pays.length; i++) ...[
                        _PaymentTile(payment: pays[i], student: student),
                        if (i < pays.length - 1) const _Hairline(),
                      ],
                  ],
                ),
              ],

              if (marks.isNotEmpty && store.can('attendance'))
                _Card(
                  title: 'الحضور والالتزام',
                  trailing: Text(
                    '$rate%',
                    style: TextStyle(
                      fontFamily: AppText.family,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.heading,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                      child: Row(
                        children: [
                          Expanded(child: _Tally('حضور', present, AppColors.success)),
                          Expanded(child: _Tally('غياب', absent, AppColors.danger)),
                          Expanded(child: _Tally('مأذون', excused, const Color(0xFFD97706))),
                        ],
                      ),
                    ),
                    ..._recentAttendance(marks),
                  ],
                ),

              if (store.can('classes')) StudentSubjectsCard(student: student),

              if (store.features.enableEvaluations && store.can('evaluations'))
                _EvaluationsCard(studentId: student.id, evaluations: store.evaluationsOfStudent(student.id)),

              _AttachmentsCard(studentId: student.id),

              if (store.can('students'))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.dangerBorder),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(Corner.field)),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف الطالب', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      onPressed: () async {
                        final blocked = store.countActivePayments(student.id);
                        if (blocked > 0) {
                          final archive = await confirmSheet(
                            context,
                            title: 'لا يمكن حذف الطالب',
                            message:
                                'له $blocked سند قبض (مقبوض أو ملغى). يمكن أرشفته بدل الحذف (تُسقط الأقساط المستقبلية ويُحتفظ بالسجل المالي).',
                            confirmLabel: 'أرشفة',
                            confirmColor: AppColors.heading,
                          );
                          if (!archive || !context.mounted) return;
                          try {
                            store.archiveStudent(student.id);
                            showAppSnack(context, 'تمت أرشفة الطالب');
                          } on StoreException catch (e) {
                            showAppSnack(context, e.message, error: true);
                          }
                          return;
                        }
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

bool _hasExtraIdentity(Student student, DateTime? birth, String medical) {
  return student.gender.trim().isNotEmpty ||
      student.nationality.trim().isNotEmpty ||
      student.birthPlace.trim().isNotEmpty ||
      birth != null ||
      student.healthStatus.trim().isNotEmpty ||
      medical.isNotEmpty ||
      student.housingStatus.trim().isNotEmpty ||
      student.gpa.trim().isNotEmpty ||
      student.previousSchool.trim().isNotEmpty ||
      student.referralSource.trim().isNotEmpty ||
      student.initialRating > 0;
}

// ═══ عناصر الصفحة ═══════════════════════════════════════════════════════════

/// شريط أفعال ثابت قرب الإبهام: تسديد أولاً، ثم رد وتعديل.
class _ThumbBar extends StatelessWidget {
  const _ThumbBar({
    required this.showPay,
    required this.onPay,
    required this.showRefund,
    required this.onRefund,
    required this.showEdit,
    required this.onEdit,
  });

  final bool showPay;
  final VoidCallback? onPay;
  final bool showRefund;
  final VoidCallback? onRefund;
  final bool showEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: const Color(0xFF091E42).withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if (showPay)
                Expanded(
                  flex: 3,
                  child: PrimaryButton(
                    label: 'تسديد دفعة',
                    icon: Icons.credit_card,
                    onPressed: onPay,
                  ),
                ),
              if (showPay && (showRefund || showEdit)) const SizedBox(width: 8),
              if (showRefund)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: GhostButton(label: 'رد مبلغ', onPressed: onRefund),
                  ),
                ),
              if (showRefund && showEdit) const SizedBox(width: 8),
              if (showEdit)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: GhostButton(
                      label: 'تعديل',
                      icon: Icons.edit_outlined,
                      onPressed: onEdit,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// قسم قابل للطي — بطاقة بيضاء بحدّ خفيف من الثيم.
class _Card extends StatefulWidget {
  const _Card({
    this.title,
    this.titleBadge,
    this.trailing,
    this.initiallyOpen = false,
    required this.children,
  });

  final String? title;
  /// شارة بجانب العنوان — مثل «خصم 50%» عند الرسوم.
  final Widget? titleBadge;
  final Widget? trailing;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  late bool open;

  @override
  void initState() {
    super.initState();
    open = widget.initiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Container(
      margin: _cardMargin,
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
          if (title != null)
            InkWell(
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: _cardHeaderPad,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (widget.titleBadge != null) ...[
                            const SizedBox(width: 8),
                            widget.titleBadge!,
                          ],
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 8),
                      widget.trailing!,
                    ],
                    const SizedBox(width: 4),
                    // في RTL يظهر السهم يساراً — موضع الطي المألوف
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more, size: 22, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
            ),
          if (title != null && open)
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.line,
              indent: _cardHairlineInset,
              endIndent: _cardHairlineInset,
            ),
          if (title == null || open) ...widget.children,
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        color: AppColors.line,
        indent: _cardHairlineInset,
        endIndent: _cardHairlineInset,
      );
}

class _Tally extends StatelessWidget {
  const _Tally(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontFamily: AppText.family,
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppText.family,
            color: AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// ملخص مالي في كارد واحد — «مجدول» فقط عند وجود متبقٍ غير مستحق.
class _FinanceStrip extends StatelessWidget {
  const _FinanceStrip({
    required this.student,
    required this.totalPaid,
    required this.dueNow,
    required this.scheduledRemaining,
    required this.isDebtor,
    required this.previousYearsDue,
    required this.pendingRequests,
  });

  final Student student;
  final double totalPaid;
  final double dueNow;
  final double scheduledRemaining;
  final bool isDebtor;
  final double previousYearsDue;
  final List<FinanceRequest> pendingRequests;

  @override
  Widget build(BuildContext context) {
    final notes = student.notes.trim();
    final showScheduled = scheduledRemaining > cent;

    final String dueLabel;
    final String dueValue;
    final Color dueColor;
    if (isDebtor) {
      dueLabel = 'مستحق';
      dueValue = money(dueNow);
      dueColor = AppColors.danger;
    } else if (student.balance > cent) {
      dueLabel = 'له';
      dueValue = money(student.balance);
      dueColor = AppColors.amberDark;
    } else {
      dueLabel = 'الحالة';
      dueValue = 'مسدد';
      dueColor = AppColors.success;
    }

    final metrics = <({String label, String value, Color color})>[
      (label: 'مقبوض', value: money(totalPaid), color: AppColors.success),
      (label: dueLabel, value: dueValue, color: dueColor),
      if (showScheduled)
        (label: 'مجدول', value: money(scheduledRemaining), color: AppColors.muted),
    ];

    final hasFooter =
        previousYearsDue > cent || pendingRequests.isNotEmpty || notes.isNotEmpty;

    return AppCard(
      margin: _cardMargin,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 40,
                    color: AppColors.line,
                  ),
                Expanded(
                  child: _FinanceCell(
                    label: metrics[i].label,
                    value: metrics[i].value,
                    color: metrics[i].color,
                  ),
                ),
              ],
            ],
          ),
          if (hasFooter) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Divider(height: 1, thickness: 1, color: AppColors.line),
            ),
            if (previousYearsDue > cent)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'منها مستحق سنوات سابقة ${money(previousYearsDue)}',
                  style: TextStyle(
                    fontFamily: AppText.family,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amberDark,
                  ),
                ),
              ),
            if (pendingRequests.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'بانتظار موافقة: ${pendingRequests.map((r) => financeRequestLabel(r.kind)).join('، ')}',
                  style: TextStyle(
                    fontFamily: AppText.family,
                    color: AppColors.amberDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.amberSoft,
                    borderRadius: BorderRadius.circular(Corner.box),
                    border: Border.all(color: AppColors.amberBorder),
                  ),
                  child: Text.rich(
                    TextSpan(
                      text: 'ملاحظة: ',
                      style: TextStyle(
                        fontFamily: AppText.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: AppColors.amberDark,
                      ),
                      children: [
                        TextSpan(
                          text: notes,
                          style: TextStyle(
                            fontFamily: AppText.family,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FinanceCell extends StatelessWidget {
  const _FinanceCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppText.family,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة خصم مختصرة بجانب عنوان الرسوم — مثل ويب StudentDetail.
String? _studentDiscountBadgeLabel(Student student) {
  final discount = studentDiscountOf(student);
  final legacyRate = student.academicDiscountRate;
  if (discount != null && discount.value > 0) {
    final isPercent = discount.percentage;
    return isPercent ? 'خصم ${trimNum(discount.value)}%' : 'خصم ${money(discount.value)}';
  }
  if ((student.academicDiscountApplied || legacyRate > 0) && legacyRate > 0) {
    return 'خصم ${trimNum(legacyRate)}%';
  }
  return null;
}

/// آخر أيام الحضور كصفوف قائمة مسطحة.
List<Widget> _recentAttendance(List<AttendanceMark> marks) {
  final recent = [...marks]..sort((a, b) => b.date.compareTo(a.date));
  if (recent.isEmpty) return const [];
  final shown = recent.take(5).toList();
  return [
    for (final m in shown) ...[
      _AttendanceTile(mark: m),
      const _Hairline(),
    ],
  ];
}

/// يوم واحد: تاريخ مقابل الحالة.
class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({required this.mark});

  final AttendanceMark mark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _cardRowPad,
      child: Row(
        children: [
          Expanded(
            child: Text(
              mark.date,
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
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
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

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

    return Padding(
      padding: _cardRowPad,
      child: Row(
        children: [
          Icon(Icons.key_outlined, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (code.isEmpty)
            widget.onGenerate == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text('غير محدد', style: AppText.muted),
                  )
                : TextButton.icon(
                    onPressed: () {
                      widget.onGenerate!();
                      showAppSnack(context, 'تم توليد ${widget.label}');
                    },
                    icon: Icon(Icons.autorenew, size: 15, color: AppColors.accent),
                    label: Text(
                      'توليد',
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  )
          else ...[
            Text(
              visible ? code : '••••••',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: AppText.family,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: visible ? 1 : 2,
                color: AppColors.heading,
              ),
            ),
            action(
              visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              visible ? 'إخفاء' : 'إظهار',
              () => setState(() => visible = !visible),
            ),
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

/// صف تفاصيل: تسمية، ثم القيمة مع الأزرار متلاصقة في الطرف الآخر (بلا فراغ وسط).
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.trailing,
    this.ltr = false,
    this.child,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final bool ltr;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim() ?? '';
    final empty = child == null && text.isEmpty;
    final valueWidget = child ??
        Text(
          empty ? '—' : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          textDirection: ltr ? TextDirection.ltr : null,
          style: TextStyle(
            fontFamily: AppText.family,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.35,
            letterSpacing: ltr ? 0.2 : 0,
            color: empty ? AppColors.faint : AppColors.text,
          ),
        );

    return Padding(
      padding: _cardRowPad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: AppText.label),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(child: valueWidget),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _phoneActions(String phone) {
  final number = phone.trim();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ContactAction(
        tooltip: 'اتصال',
        onTap: () => launchTel(number),
        background: AppColors.amberSoft,
        border: AppColors.amberBorder,
        child: Icon(Icons.call_rounded, size: 16, color: AppColors.amberDark),
      ),
      const SizedBox(width: 6),
      _ContactAction(
        tooltip: 'واتساب',
        onTap: () => launchWa(number),
        background: AppColors.successSoft,
        border: AppColors.successBorder,
        child: Icon(Icons.chat_rounded, size: 16, color: AppColors.success),
      ),
    ],
  );
}

class _ContactAction extends StatelessWidget {
  const _ContactAction({
    required this.tooltip,
    required this.onTap,
    required this.background,
    required this.border,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Color background;
  final Color border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Corner.box),
          child: Ink(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(Corner.box),
              border: Border.all(color: border),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// صفوف «بيانات إضافية» بنفس نمط _DetailRow مع فواصل.
List<Widget> _extraIdentityRows(Student student, DateTime? birth, String medical) {
  final rows = <({String label, String? value, Widget? child, bool ltr})>[
    if (student.gender.trim().isNotEmpty)
      (label: 'الجنس', value: genderLabel(student.gender), child: null, ltr: false),
    if (student.nationality.trim().isNotEmpty)
      (label: 'الجنسية', value: student.nationality.trim(), child: null, ltr: false),
    if (student.birthPlace.trim().isNotEmpty)
      (label: 'مكان الولادة', value: student.birthPlace.trim(), child: null, ltr: false),
    if (birth != null)
      (label: 'تاريخ الميلاد', value: formatDate(birth), child: null, ltr: true),
    if (student.healthStatus.trim().isNotEmpty)
      (label: 'الحالة الصحية', value: student.healthStatus.trim(), child: null, ltr: false),
    if (medical.isNotEmpty)
      (label: 'تفاصيل الحالة الصحية', value: medical, child: null, ltr: false),
    if (student.housingStatus.trim().isNotEmpty)
      (label: 'طبيعة السكن', value: student.housingStatus.trim(), child: null, ltr: false),
    if (student.gpa.trim().isNotEmpty)
      (label: 'المعدل', value: student.gpa.trim(), child: null, ltr: true),
    if (student.previousSchool.trim().isNotEmpty)
      (label: 'المدرسة السابقة', value: student.previousSchool.trim(), child: null, ltr: false),
    if (student.referralSource.trim().isNotEmpty)
      (label: 'مصدر التعرف', value: student.referralSource.trim(), child: null, ltr: false),
    if (student.initialRating > 0)
      (
        label: 'التقييم المبدئي',
        value: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                i <= student.initialRating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 16,
                color: i <= student.initialRating ? const Color(0xFFF59E0B) : AppColors.lineStrong,
              ),
          ],
        ),
        ltr: false,
      ),
  ];

  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const _Hairline(),
      _DetailRow(
        label: rows[i].label,
        value: rows[i].value,
        ltr: rows[i].ltr,
        child: rows[i].child,
      ),
    ],
  ];
}

/// إجراءات كارد الرسوم — ورقة سفلية بنفس لغة خصم/إعفاء القسط (لا قائمة منبثقة فارغة).
Future<void> _showFeesActionSheet(BuildContext context, AppStore store, Student student) async {
  final canDiscountPlan = !student.usesCustomPlan && student.gradeLevel.trim().isNotEmpty;
  final canCustom = store.can('finance.discount');
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('إجراءات الرسوم', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('خصم وخطة ورسوم إضافية'),
          ),
          const Divider(height: 1),
          if (canDiscountPlan)
            ListTile(
              leading: Icon(Icons.percent, color: AppColors.amberDark),
              title: const Text('خصم للطالب'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'discount'),
            ),
          ListTile(
            leading: const Icon(Icons.add_card_outlined, color: AppColors.info),
            title: const Text('رسم خاص'),
            dense: true,
            visualDensity: VisualDensity.compact,
            onTap: () => Navigator.pop(ctx, 'extra'),
          ),
          if (canCustom)
            ListTile(
              leading: Icon(Icons.tune, color: AppColors.heading),
              title: Text(student.usesCustomPlan ? 'تعديل المخصصة' : 'خطة مخصصة'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
          if (student.usesCustomPlan && canCustom)
            ListTile(
              leading: const Icon(Icons.undo, color: AppColors.muted),
              title: const Text('رجوع لخطة المرحلة'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'return'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'discount':
      await _showStudentDiscountSheet(context, store, student);
    case 'extra':
      await _showExtraChargeSheet(context, store, student);
    case 'custom':
      await _showCustomPlanSheet(context, store, student);
    case 'return':
      await _returnToGradePlan(context, store, student);
  }
}

Future<void> _showStudentDiscountSheet(BuildContext context, AppStore store, Student student) async {
  final current = studentDiscountOf(student);
  var percentage = current?.percentage ?? true;
  final value = TextEditingController(text: current == null ? '' : '${current.value}');
  final reason = TextEditingController(text: current?.reason ?? '');
  GradePlanSyncResult? preview;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void calculate() {
          final amount = double.tryParse(value.text) ?? 0;
          if (amount <= 0) {
            setState(() => preview = null);
            return;
          }
          try {
            setState(
              () => preview = InstallmentAdjustments(
                store,
              ).setStudentDiscount(student.id, PlanDiscount(percentage: percentage, value: amount, reason: reason.text)),
            );
          } on StoreException {
            setState(() => preview = null);
          }
        }

        Future<void> save(PlanDiscount? discount) async {
          try {
            InstallmentAdjustments(store).setStudentDiscount(student.id, discount, apply: true);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              showAppSnack(context, store.can('finance.discount') ? 'تم حفظ خصم الطالب' : 'أُرسل الطلب للمدير');
            }
          } on StoreException catch (e) {
            if (ctx.mounted) showAppSnack(ctx, e.message, error: true);
          }
        }

        final changed = preview == null ? 0 : preview!.reprice.installments + preview!.repricePaid.installments;
        final difference = preview == null ? 0.0 : preview!.reprice.difference + preview!.repricePaid.difference;
        final amountVal = double.tryParse(value.text) ?? 0;
        final canSave = reason.text.trim().isNotEmpty && amountVal > 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('خصم الطالب على أقساط خطته', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('نسبة %')),
                  ButtonSegment(value: false, label: Text('مبلغ من كل قسط')),
                ],
                selected: {percentage},
                onSelectionChanged: (selected) {
                  setState(() => percentage = selected.first);
                  calculate();
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onChanged: (_) => calculate(),
                decoration: InputDecoration(labelText: percentage ? 'النسبة %' : 'المبلغ شيكل'),
              ),
              if (!percentage)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'يُخصم هذا المبلغ من كل قسط، لا مرة واحدة من المجموع',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'السبب (مطلوب)'),
              ),
              const SizedBox(height: 6),
              _ReasonChips(
                reasons: _studentDiscountReasonChips,
                onPick: (r) => setState(() {
                  reason.text = r;
                }),
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: tileDecoration(),
                child: Text(
                  preview == null
                      ? 'أدخل قيمة لمعاينة الأثر'
                      : changed == 0
                      ? 'لا أقساط تتغير.'
                      : 'يتغير $changed قسط، الفرق ${difference >= 0 ? '+' : '−'}${money(difference.abs())}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (!store.can('finance.discount')) ...[
                const SizedBox(height: 7),
                Text('يُرسل الطلب للمدير ولا يتغير الحساب حتى يوافق.', style: TextStyle(color: AppColors.amberDark, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (current != null)
                    TextButton(
                      onPressed: () => save(null),
                      child: const Text('إزالة الخصم', style: TextStyle(color: AppColors.danger)),
                    ),
                  const Spacer(),
                  PrimaryButton(
                    label: store.can('finance.discount') ? 'حفظ' : 'إرسال للمدير',
                    onPressed: canSave
                        ? () => save(PlanDiscount(percentage: percentage, value: amountVal, reason: reason.text))
                        : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  value.dispose();
  reason.dispose();
}

Future<void> _showExtraChargeSheet(BuildContext context, AppStore store, Student student) async {
  final title = TextEditingController();
  final amount = TextEditingController();
  var dueDate = DateTime.now();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) {
        final titleOk = title.text.trim().isNotEmpty;
        final amountOk = (double.tryParse(amount.text) ?? 0) > 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('رسم خاص بالطالب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                autofocus: true,
                onChanged: (_) => setModal(() {}),
                decoration: const InputDecoration(labelText: 'اسم الرسم (كتاب، غرامة، نشاط...)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setModal(() {}),
                decoration: const InputDecoration(labelText: 'المبلغ شيكل'),
              ),
              const SizedBox(height: 8),
              const FieldLabel('تاريخ الاستحقاق'),
              SelectField(
                text: formatDate(dueDate),
                icon: Icons.calendar_today_outlined,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dueDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setModal(() => dueDate = picked);
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'منفصل عن خطة المرحلة: لا يمسّه تطبيق الخطة ولا تحديث أسعارها.',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'إضافة',
                onPressed: titleOk && amountOk ? () => Navigator.pop(ctx, true) : null,
              ),
            ],
          ),
        );
      },
    ),
  );
  if (ok == true && context.mounted) {
    try {
      InstallmentAdjustments(store).addExtraCharge(
        studentId: student.id,
        title: title.text,
        amount: double.tryParse(amount.text) ?? 0,
        dueDate: dueDate,
      );
      showAppSnack(context, 'تمت إضافة الرسم الخاص');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }
  title.dispose();
  amount.dispose();
}

Future<void> _showCustomPlanSheet(BuildContext context, AppStore store, Student student) async {
  final existing = store.installments.where((i) {
    if (i.studentId != student.id) return false;
    if (i.title.contains('حجز')) return false;
    if (i.paidAmount > cent) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  final rows = <CustomPlanRow>[
    for (final i in existing)
      CustomPlanRow(
        title: i.title,
        amount: trimNum(i.amount),
        dueDate: isoDate(i.dueDate),
      ),
  ];
  final reason = TextEditingController(
    text: student.usesCustomPlan && student.exceptionReason.isNotEmpty ? student.exceptionReason : 'خطة مخصصة',
  );

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModal) => Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                student.usesCustomPlan ? 'تعديل الخطة المخصصة' : 'خطة مخصصة للطالب',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              const Text(
                'أقساط خاصة بهذا الطالب — مستقلة عن خطة مرحلته. اكتب كل قسط باسمه ومبلغه وموعده.',
                style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 12),
              CustomPlanRowsEditor(
                rows: rows,
                fallbackDue: isoDate(student.enrollmentDate),
                onChanged: (_) => setModal(() {}),
              ),
              const SizedBox(height: 12),
              const FieldLabel('سبب / ملاحظة'),
              TextField(
                controller: reason,
                decoration: const InputDecoration(hintText: 'خطة مخصصة'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: 'اعتماد الخطة المخصصة',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (ok == true && context.mounted) {
    if (rows.isEmpty) {
      showAppSnack(context, 'أضف قسطاً واحداً على الأقل', error: true);
      reason.dispose();
      return;
    }
    if (rows.any((r) => r.dueDate.trim().isEmpty)) {
      showAppSnack(context, 'حدّد تاريخ استحقاق لكل قسط', error: true);
      reason.dispose();
      return;
    }
    final schedule = [
      for (var i = 0; i < rows.length; i++)
        PlanItem(
          id: 'slot_${i + 1}',
          title: rows[i].title.trim().isEmpty ? 'قسط ${i + 1}' : rows[i].title.trim(),
          amount: rows[i].amountValue,
          dueDate: rows[i].dueDate.trim(),
        ),
    ];
    final total = schedule.fold<double>(0, (s, r) => s + r.amount);
    final confirmed = await confirmSheet(
      context,
      title: 'اعتماد الخطة المخصصة؟',
      message:
          'إنشاء خطة مخصصة لهذا الطالب (${schedule.length} قسط بمجموع ${money(total)}).\n\n'
          'لن تعتمد خطة مرحلته بعد ذلك: تطبيق خطة المرحلة على الطلاب لن يمسّه.\n'
          'رسم الحجز والرسوم الإضافية تبقى، والأقساط المدفوعة لا تُحذف.',
      confirmLabel: 'تنفيذ',
    );
    if (!confirmed || !context.mounted) {
      reason.dispose();
      return;
    }
    try {
      final done = store.applyCustomPlan(student.id, schedule: schedule, reason: reason.text);
      showAppSnack(
        context,
        'تم: أُضيف ${done.added} قسط مخصص${done.removed > 0 ? ' وأُزيل ${done.removed} من خطة المرحلة' : ''}',
      );
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }
  reason.dispose();
}

Future<void> _returnToGradePlan(BuildContext context, AppStore store, Student student) async {
  await showReturnToGradePlanSheet(
    context: context,
    studentIds: [student.id],
    studentGrades: [student.gradeLevel],
  );
}

Future<void> _openInstallment(
  BuildContext context,
  AppStore store,
  Student student,
  Installment installment, {
  required bool canCollect,
  required bool canAdjust,
}) async {
  final payable = !installment.isExempt && !installment.isPaid && canCollect;
  if (!payable && !canAdjust) return;

  void goPay() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          studentId: student.id,
          installmentId: installment.id,
          amount: installment.remaining,
        ),
      ),
    );
  }

  // قبض فقط بلا صلاحية تعديل → مباشرة لنموذج التسديد
  if (payable && !canAdjust) {
    goPay();
    return;
  }

  final hasDiscount = installment.isExempt || installment.discountAmount > cent;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(installment.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('قيمة القسط: ${money(installment.amount + installment.discountAmount)}'),
          ),
          const Divider(height: 1),
          if (payable)
            ListTile(
              leading: Icon(Icons.payments_outlined, color: AppColors.amberDark),
              title: const Text('تسديد'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'pay'),
            ),
          if (canAdjust) ...[
            ListTile(
              leading: const Icon(Icons.percent, color: AppColors.info),
              title: const Text('خصم بمبلغ'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'amount'),
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism, color: AppColors.success),
              title: const Text('إعفاء كامل'),
              dense: true,
              visualDensity: VisualDensity.compact,
              onTap: () => Navigator.pop(ctx, 'exempt'),
            ),
            if (hasDiscount)
              ListTile(
                leading: Icon(Icons.undo, color: AppColors.heading),
                title: const Text('إزالة الخصم'),
                dense: true,
                visualDensity: VisualDensity.compact,
                onTap: () => Navigator.pop(ctx, 'none'),
              ),
            if (InstallmentAdjustments.canRemove(installment))
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('حذف'),
                dense: true,
                visualDensity: VisualDensity.compact,
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'pay') {
    goPay();
    return;
  }
  if (action == 'none') {
    try {
      InstallmentAdjustments(store).setDiscount(installment, const InstallmentDiscountInput.none());
      showAppSnack(context, store.can('finance.discount') ? 'تمت إزالة الخصم' : 'أُرسل الطلب للمدير');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
    return;
  }
  await _showInstallmentAdjustmentForm(context, store, installment, action);
}

Future<void> _showInstallmentAdjustmentForm(BuildContext context, AppStore store, Installment installment, String action) async {
  final amount = TextEditingController();
  final reason = TextEditingController();
  final adjustments = InstallmentAdjustments(store);
  final removing = action == 'remove';
  final exempt = action == 'exempt';
  MoneyMovePreview? preview;
  try {
    preview = adjustments.previewDiscount(installment, const InstallmentDiscountInput.exempt(''));
  } catch (_) {}
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void refreshPreview() {
          final input = exempt || removing
              ? InstallmentDiscountInput.exempt(reason.text)
              : InstallmentDiscountInput.amount(double.tryParse(amount.text) ?? 0, reason.text);
          setState(() => preview = adjustments.previewDiscount(installment, input));
        }

        Future<void> save() async {
          try {
            if (removing) {
              adjustments.remove(installment, reason: reason.text);
            } else {
              adjustments.setDiscount(
                installment,
                exempt ? InstallmentDiscountInput.exempt(reason.text) : InstallmentDiscountInput.amount(double.tryParse(amount.text) ?? 0, reason.text),
              );
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              showAppSnack(context, store.can('finance.discount') ? 'تم حفظ التعديل' : 'أُرسل الطلب للمدير');
            }
          } on StoreException catch (e) {
            if (ctx.mounted) showAppSnack(ctx, e.message, error: true);
          }
        }

        final reasonRequired = !(removing && store.can('finance.discount'));
        final amountOk = exempt || removing || (double.tryParse(amount.text) ?? 0) > 0;
        final canSave = amountOk && (!reasonRequired || reason.text.trim().isNotEmpty);
        final original = installment.amount + installment.discountAmount;
        final discountVal = exempt ? original : (double.tryParse(amount.text) ?? 0).clamp(0, original);
        final after = exempt ? 0.0 : (original - discountVal).clamp(0.0, original);

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                removing
                    ? 'حذف «${installment.title}»'
                    : exempt
                    ? 'إعفاء كامل على «${installment.title}»'
                    : 'خصم على «${installment.title}»',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              if (!removing) ...[
                const SizedBox(height: 6),
                Text('قيمة القسط: ${money(original)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text('يصير المطلوب: ${money(after)}', style: TextStyle(color: AppColors.heading, fontWeight: FontWeight.w800, fontSize: 12)),
              ],
              if (!exempt && !removing) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onChanged: (_) => refreshPreview(),
                  decoration: const InputDecoration(labelText: 'مبلغ الخصم شيكل'),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                onChanged: (_) => refreshPreview(),
                decoration: InputDecoration(labelText: reasonRequired ? 'السبب (مطلوب)' : 'السبب (اختياري)'),
              ),
              if (!removing) ...[
                const SizedBox(height: 6),
                _ReasonChips(
                  reasons: _installmentReasonChips,
                  onPick: (r) {
                    reason.text = r;
                    refreshPreview();
                  },
                ),
              ],
              if (preview != null && preview!.paid > cent) ...[const SizedBox(height: 10), _MoneyMovesView(preview!)],
              if (!store.can('finance.discount')) ...[
                const SizedBox(height: 8),
                Text('لا تملك هذه الصلاحية: يُرسل طلباً للمدير ويُنفّذ بعد موافقته.', style: TextStyle(color: AppColors.amberDark, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              PrimaryButton(
                label: store.can('finance.discount') ? (removing ? 'حذف' : 'حفظ') : 'إرسال للمدير',
                color: removing ? AppColors.danger : null,
                onPressed: canSave ? save : null,
              ),
            ],
          ),
        );
      },
    ),
  );
  amount.dispose();
  reason.dispose();
}

class _MoneyMovesView extends StatelessWidget {
  const _MoneyMovesView(this.preview);
  final MoneyMovePreview preview;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: tileDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('يتحرر من مدفوع القسط ${money(preview.paid)} ويُحسب على:', style: const TextStyle(fontSize: 11.5)),
        for (final move in preview.movesTo) Text('• ${move.title}: ${money(move.amount)}', style: const TextStyle(fontSize: 11)),
        if (preview.credit > cent) Text('• رصيد للطالب: ${money(preview.credit)}', style: const TextStyle(color: AppColors.success, fontSize: 11)),
      ],
    ),
  );
}

/// رقائق اقتراح السبب — تضغط فتملأ حقل السبب.
class _ReasonChips extends StatelessWidget {
  const _ReasonChips({required this.reasons, required this.onPick});
  final List<String> reasons;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final r in reasons)
          ActionChip(
            label: Text(r, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            onPressed: () => onPick(r),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}

/// أقساط مجمّعة برأس بسيط لكل عام دراسي.
List<Widget> _groupedInstallmentTiles({
  required AppStore store,
  required Student student,
  required List<Installment> insts,
  required String currentYearKey,
  required bool canCollect,
  required bool canAdjust,
}) {
  final groups = <String, List<Installment>>{};
  for (final i in insts) {
    final key = i.academicYearId.trim().isEmpty ? currentYearKey : i.academicYearId;
    groups.putIfAbsent(key, () => []).add(i);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == currentYearKey) return -1;
      if (b == currentYearKey) return 1;
      final ya = store.academicYears.where((y) => y.id == a).firstOrNull?.startsOn ?? '';
      final yb = store.academicYears.where((y) => y.id == b).firstOrNull?.startsOn ?? '';
      return yb.compareTo(ya);
    });
  final showHeaders = keys.length > 1;
  final out = <Widget>[];
  for (final key in keys) {
    if (showHeaders) {
      final year = store.academicYears.where((y) => y.id == key).firstOrNull;
      final label = year?.label ?? (key == currentYearKey ? 'العام الحالي' : 'عام دراسي');
      final suffix = key == currentYearKey ? ' (الحالية)' : '';
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$label$suffix · ${groups[key]!.length} قسط',
            style: AppText.label.copyWith(color: AppColors.heading, fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    final list = groups[key]!;
    for (var i = 0; i < list.length; i++) {
      out.add(_InstallmentTile(student: student, inst: list[i], canCollect: canCollect, canAdjust: canAdjust));
      if (i < list.length - 1) out.add(const _Hairline());
    }
  }
  return out;
}

/// سطور تاريخ السنوات الدراسية — الأقدم أولاً.
List<String> _studentYearHistory(AppStore store, Student student) {
  final rows = store.studentYears.where((y) => y.studentId == student.id).toList();
  final currentId = student.academicYearId.trim().isNotEmpty
      ? student.academicYearId
      : (store.operationalAcademicYear?.id ?? store.viewedAcademicYearId);
  final hasCurrent = rows.any((y) => y.academicYearId == currentId);
  if (!hasCurrent && currentId.isNotEmpty) {
    rows.add(
      StudentYear(
        id: 'current_$currentId',
        studentId: student.id,
        academicYearId: currentId,
        gradeLevel: student.gradeLevel,
        section: student.section,
        status: student.status,
        planDiscountType: student.planDiscountType,
        planDiscountValue: student.planDiscountValue,
        planDiscountReason: student.planDiscountReason,
      ),
    );
  }
  rows.sort((a, b) {
    final ya = store.academicYears.where((y) => y.id == a.academicYearId).firstOrNull;
    final yb = store.academicYears.where((y) => y.id == b.academicYearId).firstOrNull;
    return (ya?.startsOn ?? a.createdAt ?? '').compareTo(yb?.startsOn ?? b.createdAt ?? '');
  });
  return [
    for (final y in rows)
      () {
        final year = store.academicYears.where((a) => a.id == y.academicYearId).firstOrNull;
        final name = year?.label ?? 'عام دراسي';
        final grade = y.gradeLevel.trim().isEmpty ? '—' : y.gradeLevel.trim();
        final section = y.section.trim().isEmpty ? '' : ' — شعبة ${y.section.trim()}';
        final status = studentStatusLabel(y.status);
        final discount = y.planDiscountValue > 0
            ? (y.planDiscountType == 'fixed'
                ? ' · خصم ${money(y.planDiscountValue)}'
                : ' · خصم ${trimNum(y.planDiscountValue)}%')
            : '';
        return '$name · $grade$section · $status$discount';
      }(),
  ];
}

/// قسط مجدول — بلاطة مستقلة: العنوان وحالته، ثم الاستحقاق مقابل المبالغ.
/// غير المسدد أبيض ويُفتح للتسديد لمن يملك القبض، والمسدد رمادي فاتح.
class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.student, required this.inst, required this.canCollect, required this.canAdjust});

  final Student student;
  final Installment inst;
  final bool canCollect;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final future = dateOnly(inst.dueDate).isAfter(dateOnly(DateTime.now()));
    final payable = !inst.isExempt && !inst.isPaid && canCollect;
    final store = StoreScope.of(context);
    final tappable = payable || canAdjust;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable
            ? () => _openInstallment(
                  context,
                  store,
                  student,
                  inst,
                  canCollect: canCollect,
                  canAdjust: canAdjust,
                )
            : null,
        child: Padding(
          padding: _cardRowPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inst.title,
                      style: AppText.cardTitle.copyWith(fontSize: 14),
                    ),
                  ),
                  if (inst.isExempt)
                    StatusChip.muted('معفى')
                  else if (inst.isPaid)
                    StatusChip.success('مسدد')
                  else if (future)
                    StatusChip.muted('مجدول')
                  else
                    StatusChip.danger('مستحق'),
                ],
              ),
              if (inst.isExempt && inst.exemptReason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('إعفاء: ${inst.exemptReason}', style: AppText.muted.copyWith(fontSize: 12)),
              ] else if (!inst.isExempt && inst.discountAmount > cent) ...[
                const SizedBox(height: 4),
                Text(
                  'خصم ${money(inst.discountAmount)}${inst.discountReason.trim().isEmpty ? '' : ' — ${inst.discountReason.trim()}'}',
                  style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    formatDate(inst.dueDate),
                    style: AppText.muted.copyWith(fontSize: 12),
                  ),
                  const Spacer(),
                  if (inst.isExempt)
                    Text('0', style: AppText.muted)
                  else ...[
                    if (!inst.isPaid)
                      Text(
                        money(inst.remaining),
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: future ? AppColors.muted : AppColors.danger,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      )
                    else
                      Text(
                        money(inst.amount),
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                  ],
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
    final method = StoreScope.of(context).paymentMethodLabel(p.method);
    final isNegative = p.amount < 0;
    final meta = <String>[
      method,
      if (purpose.trim().isNotEmpty) purpose,
      if (p.discountAmount > cent) 'خصم ${money(p.discountAmount)}',
      if (p.cancelled) 'ملغاة${p.cancelReason.trim().isEmpty ? '' : ': ${p.cancelReason.trim()}'}',
      if (p.reversedByPaymentId != null && p.reversedByPaymentId!.isNotEmpty) 'معكوس',
    ];

    return Padding(
      padding: _cardRowPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.receiptNumber,
                      textDirection: TextDirection.ltr,
                      style: AppText.cardTitle.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatDate(p.date)}  ·  ${meta.join('  ·  ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppText.family,
                        color: p.cancelled ? AppColors.danger : AppColors.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                money(p.amount),
                style: TextStyle(
                  fontFamily: AppText.family,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: p.cancelled
                      ? AppColors.faint
                      : isNegative
                          ? AppColors.danger
                          : AppColors.success,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              TileButton(
                label: 'الوصل',
                icon: const Icon(Icons.print_outlined, size: 13),
                color: AppColors.heading,
                background: Colors.white,
                border: AppColors.lineStrong,
                onTap: () => ReceiptScreen.open(context, p),
              ),
              if (!p.cancelled) ...[
                const SizedBox(width: 6),
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

/// الدرجات والتقييمات — بترتيب الويب: لكل مادة سطرُها بنسبتها، وتحته تقييماتها
/// سطراً سطراً: اسم التقييم، ودرجته من أصلها، وتاريخه.
///
/// المعدل موزون لكل مادة على حدة وفق مخطط المدرسة، لا خلط بين المواد.
class _EvaluationsCard extends StatelessWidget {
  const _EvaluationsCard({required this.studentId, required this.evaluations});
  final String studentId;
  final List<Evaluation> evaluations;

  /// لون النسبة: هادئ في الحالات الثلاث فلا يصرخ الملف بالألوان.
  static Color _tone(double percent) {
    if (percent >= 85) return const Color(0xFF2E7D57);
    if (percent >= 60) return const Color(0xFF9A6700);
    return const Color(0xFFA5484A);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final grading = store.gradingForViewedYear;
    final scheme = grading.scheme.isEmpty ? store.gradingScheme : grading.scheme;
    final summaries = {for (final s in store.subjectGradesOf(studentId)) s.subjectId: s};
    final list = grading.mode == 'monthly'
        ? evaluations
        : evaluations.where((e) => !isMonthlyAverage(e)).toList();

    // التقييمات مجموعة بموادها، والأحدث أولاً داخل كل مادة
    final bySubject = <String, List<Evaluation>>{};
    for (final e in list) {
      bySubject.putIfAbsent(e.subjectId, () => []).add(e);
    }
    for (final rows in bySubject.values) {
      rows.sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
    }

    double? percentOf(String subjectId, List<Evaluation> rows) {
      final fromScheme = summaries[subjectId]?.yearAverage;
      if (fromScheme != null) return fromScheme;
      if (rows.isEmpty) return null;
      return rows.fold<double>(0, (a, e) => a + e.percent) / rows.length;
    }

    final percents = [
      for (final e in bySubject.entries)
        if (percentOf(e.key, e.value) != null) percentOf(e.key, e.value)!,
    ];
    final overall = percents.isEmpty ? null : percents.reduce((a, b) => a + b) / percents.length;

    /// سطر الفصلين تحت اسم المادة — يظهر حين تكون المدرسة على مخطط فصول.
    String? termsLine(String subjectId) {
      if (grading.mode == 'monthly' || scheme.isEmpty) return null;
      final s = summaries[subjectId];
      if (s == null) return null;
      String label(TermGrade t) {
        if (t.components.isEmpty || t.currentAverage == null) return '—';
        return t.isComplete ? '${t.total.round()}%' : '${t.currentAverage!.round()}% حالي';
      }

      return [
        if (scheme.isConfigured('term_1')) 'الفصل الأول ${label(s.term1)}',
        if (scheme.isConfigured('term_2')) 'الفصل الثاني ${label(s.term2)}',
      ].join('  ·  ');
    }

    return _Card(
      title: 'التقييمات (${list.length})',
      trailing: overall == null
          ? null
          : Text(
              '${overall.round()}%',
              style: TextStyle(
                fontFamily: AppText.family,
                color: _tone(overall),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
      children: [
        if (bySubject.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Text('لا توجد نتائج مسجلة حتى الآن', style: AppText.muted),
          )
        else
          for (final entry in bySubject.entries) ...[
            () {
              final name = entry.key.isEmpty ? 'بدون مادة' : store.subjectName(entry.key);
              final percent = percentOf(entry.key, entry.value);
              final terms = termsLine(entry.key);
              final tone = percent == null ? AppColors.muted : _tone(percent);
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                decoration: BoxDecoration(
                  color: AppColors.sunken,
                  border: BorderDirectional(start: BorderSide(color: tone, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: AppColors.heading,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (percent != null)
                          Text(
                            '${percent.round()}%',
                            style: TextStyle(
                              fontFamily: AppText.family,
                              color: tone,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    if (terms != null && terms.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(terms, style: const TextStyle(color: AppColors.faint, fontSize: 10.5)),
                    ],
                  ],
                ),
              );
            }(),
            for (final e in entry.value)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${trimNum(e.score)}/${trimNum(e.maxScore)}',
                      style: TextStyle(
                        fontFamily: AppText.family,
                        color: store.evaluationPassed(e) ? AppColors.text : const Color(0xFFA5484A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
    return FutureBuilder<StudentAttachments?>(future: _load, builder: (context, snap) => _card(snap.data ?? store.attachmentsOf(widget.studentId)));
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
        Padding(
          padding: _cardRowPad,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _Thumb(label: items[i].$1, data: items[i].$2),
                ),
              ],
            ],
          ),
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
                child: Text(
                  label,
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading),
                ),
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
