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
import '../data/report_cards.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/custom_plan_rows.dart';
import '../widgets/form_layout.dart';
import '../widgets/panels.dart';
import '../widgets/table_gate.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'return_to_grade_plan_sheet.dart';
import 'report_cards_sheet.dart';
import 'student_credit_sheet.dart';
import 'student_subjects_card.dart';
import 'student_form_screen.dart';

/// اقتراحات سبب خصم القسط — مطابق لـ InstallmentActionModals.
const _installmentReasonChips = ['ظرف مادي', 'أخوة', 'أبناء كادر', 'منحة', 'تفوق'];

/// اقتراحات سبب خصم الطالب على الخطة.
const _studentDiscountReasonChips = ['أخوة', 'أبناء كادر', 'منحة', 'ظرف مادي', 'تفوق'];

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
    // ملف الطالب يعرض مالية وحضوراً ودرجات — جداول مؤجّلة تُحمَّل هنا إن لم تُفتح شاشاتها بعد
    return TableGate(
      tables: const [
        'payments',
        'installments',
        'sessions',
        'attendance',
        'student_evaluations',
      ],
      message: 'جارٍ تحميل ملف الطالب...',
      child: ListenableBuilder(
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
                    const Text('لم يتم العثور على ملف الطالب', style: TextStyle(fontWeight: FontWeight.w600)),
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
        final status = student.status == 'inactive' ? 'withdrawn' : student.status;
        final yearRows = _studentYearHistory(store, student);
        final portalStudent = store.isFeatureOn('portal.student');
        final portalParent = store.isFeatureOn('portal.parent');
        final section = student.section.trim();
        final headerMeta = [
          student.gradeLevel.trim().isEmpty ? 'غير محدد' : student.gradeLevel.trim(),
          if (section.isNotEmpty) section.startsWith('شعبة') ? section : 'شعبة $section',
        ].join(' · ');
        final discountTotal = activePays.fold<double>(0, (a, p) => a + p.discountAmount);
        final canCustom = store.can('finance.discount');

        Widget sec(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: child);

        return Scaffold(
          backgroundColor: AdminNoon.paper,
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ملف الطالب',
                  style: TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17, height: 1.2),
                ),
                if (store.institutionName.trim().isNotEmpty)
                  Text(
                    store.institutionName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppText.family,
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 1.2,
                    ),
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
            padding: EdgeInsets.fromLTRB(12, 12, 12, showBottomBar ? 12 : 28),
            children: [
              // الرأس: الاسم وتحته المرحلة والشعبة، وحالته إن لم يكن نشطاً
              sec(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.fullName, style: NoonText.style(16, weight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            headerMeta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NoonText.style(12, weight: FontWeight.w500, color: AdminNoon.muted),
                          ),
                        ),
                        if (status != 'active' && studentStatusLabels.containsKey(status)) ...[
                          const SizedBox(width: 6),
                          NoonBadge(studentStatusLabel(status), tone: NoonBadgeTone.sun),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              if (canFinance)
                sec(
                  _FinanceStrip(
                    student: student,
                    totalPaid: totalPaid,
                    dueNow: dueNow,
                    scheduledRemaining: scheduledRemaining,
                    isDebtor: isDebtor,
                    previousYearsDue: previousYearsDue,
                  ),
                ),

              sec(
                NoonFoldCard(
                  title: 'بيانات التواصل',
                  children: [
                    _InfoTable(rows: [
                      (
                        'هاتف الطالب:',
                        student.phone.trim().isEmpty
                            ? _faintDash()
                            : _PhoneValue(phone: student.phone, prefix: student.phonePrefix),
                      ),
                      (
                        'ولي الأمر:',
                        Text(
                          [
                            parentName.isEmpty ? '—' : parentName,
                            if (student.relation.trim().isNotEmpty) '(${student.relation.trim()})',
                          ].join(' '),
                          style: NoonText.style(12, weight: FontWeight.w700),
                        ),
                      ),
                      (
                        'هاتف ولي الأمر:',
                        parentPhone.isEmpty
                            ? _faintDash()
                            : _PhoneValue(phone: parentPhone, prefix: student.parentPhonePrefix),
                      ),
                      (
                        'رقم الهوية:',
                        Text(
                          student.nationalId.trim().isEmpty ? '—' : student.nationalId.trim(),
                          style: NoonText.style(12, weight: FontWeight.w700),
                        ),
                      ),
                      (
                        'الحي السكني:',
                        Text(
                          student.neighborhood.trim().isNotEmpty
                              ? student.neighborhood.trim()
                              : (student.detailedAddress.trim().isNotEmpty ? student.detailedAddress.trim() : '—'),
                          style: NoonText.style(12, weight: FontWeight.w600),
                        ),
                      ),
                      ('تاريخ التسجيل:', Text(noonDate(student.enrollmentDate), style: NoonText.style(12))),
                    ]),
                  ],
                ),
              ),

              if (_hasExtraIdentity(student, birth, medical))
                sec(
                  NoonFoldCard(
                    title: 'بيانات إضافية',
                    children: [_InfoTable(rows: _extraIdentityRows(student, birth, medical))],
                  ),
                ),

              if (yearRows.length > 1 || yearRows.any((r) => r.periods.isNotEmpty))
                sec(
                  NoonFoldCard(
                    title: 'السنوات الدراسية',
                    gap: 4,
                    children: [for (final row in yearRows) _YearRow(row: row)],
                  ),
                ),

              if (portalStudent || portalParent)
                sec(
                  NoonFoldCard(
                    title: 'بيانات الدخول',
                    gap: 6,
                    children: [
                      if (portalStudent)
                        _SecretCode(
                          label: 'كلمة مرور الطالب:',
                          code: student.portalCode,
                          onGenerate: canEdit ? () => store.generateStudentPortalCode(student.id, forParent: false) : null,
                        ),
                      if (portalParent) ...[
                        _ParentLoginId(value: student.parentNationalId),
                        _SecretCode(
                          label: 'كلمة مرور ولي الأمر:',
                          code: student.parentPortalCode,
                          onGenerate: canEdit ? () => store.generateStudentPortalCode(student.id, forParent: true) : null,
                        ),
                      ],
                    ],
                  ),
                ),

              if (studentPendingRequests.isNotEmpty) sec(_PendingRequestsBanner(requests: studentPendingRequests)),

              if (canFinance) ...[
                sec(
                  NoonFoldCard(
                    title: 'الرسوم (${insts.length})',
                    initiallyOpen: true,
                    badge: _discountBadge(context, store, student),
                    headerExtra: _FeesMenu(store: store, student: student),
                    children: [
                      if (student.usesCustomPlan)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'خطة مخصصة',
                                style: NoonText.style(11, weight: FontWeight.w500, color: const Color(0xFF1E40AF)),
                              ),
                            ),
                            if (canCustom)
                              _MiniButton(
                                label: 'إرجاع للمرحلة',
                                color: const Color(0xFF1D4ED8),
                                background: const Color(0xFFEFF6FF),
                                border: const Color(0xFFBFDBFE),
                                onTap: () => _returnToGradePlan(context, store, student),
                              ),
                          ],
                        ),
                      if (insts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'لا توجد رسوم بعد',
                            textAlign: TextAlign.center,
                            style: NoonText.style(12, color: AppColors.faint),
                          ),
                        )
                      else
                        _InstallmentYears(
                          store: store,
                          student: student,
                          insts: insts,
                          currentYearKey: currentYearKey,
                          canCollect: canCollect,
                          canAdjust: canFinance,
                        ),
                    ],
                  ),
                ),
                sec(
                  NoonFoldCard(
                    title: 'الدفعات (${pays.length})',
                    gap: 6,
                    headerExtra: Text.rich(
                      TextSpan(
                        text: 'المقبوض: ',
                        children: [
                          TextSpan(
                            text: money(totalPaid),
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.heading),
                          ),
                          if (discountTotal > cent) ...[
                            const TextSpan(text: ' + خصم '),
                            TextSpan(text: money(discountTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                      style: NoonText.style(11, color: AppColors.muted),
                    ),
                    children: [
                      if (pays.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'لا توجد دفعات بعد',
                            textAlign: TextAlign.center,
                            style: NoonText.style(12, color: AppColors.muted),
                          ),
                        )
                      else
                        for (final p in pays) _PaymentTile(payment: p, student: student),
                    ],
                  ),
                ),
              ],

              if (marks.isNotEmpty && store.can('attendance'))
                sec(
                  NoonFoldCard(
                    title: 'الحضور',
                    gap: 4,
                    headerExtra: Text(
                      '$rate%',
                      style: NoonText.style(12, weight: FontWeight.w700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'حضور '),
                            TextSpan(text: '$present', style: const TextStyle(fontWeight: FontWeight.w700, color: AdminNoon.green700)),
                            const TextSpan(text: '      غياب '),
                            TextSpan(text: '$absent', style: const TextStyle(fontWeight: FontWeight.w700, color: AdminNoon.red600)),
                            const TextSpan(text: '      مأذون '),
                            TextSpan(text: '$excused', style: const TextStyle(fontWeight: FontWeight.w700, color: AdminNoon.warn)),
                          ],
                        ),
                        style: NoonText.style(11, color: AdminNoon.muted),
                      ),
                      ..._attendanceMisses(marks),
                    ],
                  ),
                ),

              if (store.can('classes')) StudentSubjectsCard(student: student),

              if (store.features.enableEvaluations && store.can('evaluations'))
                sec(_EvaluationsCard(studentId: student.id, evaluations: store.evaluationsOfStudent(student.id))),

              _AttachmentsCard(studentId: student.id),

              if (store.can('students'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: NoonButton(
                    label: 'حذف الطالب',
                    icon: Icons.delete_outline,
                    tone: NoonTone.danger,
                    expand: true,
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
            ],
          ),
        );
      },
    ),
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

/// الأفعال اليومية أسفل الشاشة قرب الإبهام: «تسديد دفعة» بلون الإجراء، ثم رد وتعديل.
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminNoon.line)),
        boxShadow: const [BoxShadow(color: Color(0x140A3336), blurRadius: 16, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (showPay)
                Expanded(
                  flex: 3,
                  child: NoonButton(
                    label: 'تسديد دفعة',
                    icon: Icons.credit_card,
                    tone: NoonTone.sun,
                    expand: true,
                    onPressed: onPay,
                  ),
                ),
              if (showPay && (showRefund || showEdit)) const SizedBox(width: 8),
              if (showRefund)
                Expanded(flex: 2, child: NoonButton(label: 'رد مبلغ', expand: true, onPressed: onRefund)),
              if (showRefund && showEdit) const SizedBox(width: 8),
              if (showEdit)
                Expanded(
                  flex: 2,
                  child: NoonButton(label: 'تعديل', icon: Icons.edit_outlined, expand: true, onPressed: onEdit),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ملخص مالي في لوح واحد: مقبوض، مستحق أو رصيد له أو الحالة، و«قادم» إن وُجد.
class _FinanceStrip extends StatelessWidget {
  const _FinanceStrip({
    required this.student,
    required this.totalPaid,
    required this.dueNow,
    required this.scheduledRemaining,
    required this.isDebtor,
    required this.previousYearsDue,
  });

  final Student student;
  final double totalPaid;
  final double dueNow;
  final double scheduledRemaining;
  final bool isDebtor;
  final double previousYearsDue;

  @override
  Widget build(BuildContext context) {
    final notes = student.notes.trim();
    final showScheduled = scheduledRemaining > cent;

    final cells = <(String, String, Color)>[
      ('مقبوض', money(totalPaid), AdminNoon.green700),
      if (isDebtor)
        ('مستحق', money(dueNow), AdminNoon.red700)
      else if (student.balance > cent)
        ('رصيد له', money(student.balance), AdminNoon.tealD)
      else
        ('الحالة', showScheduled ? 'مسدد حتى الآن' : 'مسدد', AdminNoon.green700),
      if (showScheduled) ('قادم', money(scheduledRemaining), AdminNoon.muted),
    ];
    final hasFooter = previousYearsDue > cent || notes.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: noonPanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) Container(width: 1, height: 40, color: AdminNoon.line),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Text(
                          cells[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NoonText.style(11.5, weight: FontWeight.w700, color: AdminNoon.muted),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            cells[i].$2,
                            maxLines: 1,
                            style: NoonText.style(15, weight: FontWeight.w700, color: cells[i].$3, height: 1.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasFooter)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AdminNoon.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (previousYearsDue > cent)
                    Text(
                      'منها مستحق سنوات سابقة ${money(previousYearsDue)}',
                      style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.tealD),
                    ),
                  if (previousYearsDue > cent && notes.isNotEmpty) const SizedBox(height: 8),
                  if (notes.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AdminNoon.mist,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AdminNoon.headLine),
                      ),
                      child: Text.rich(
                        TextSpan(
                          text: 'ملاحظة: ',
                          style: TextStyle(color: AdminNoon.tealD),
                          children: [TextSpan(text: notes, style: TextStyle(color: AdminNoon.text))],
                        ),
                        style: NoonText.style(12, weight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// طلبات بانتظار موافقة المدير على هذا الطالب — شريط كهرماني فوق الرسوم.
class _PendingRequestsBanner extends StatelessWidget {
  const _PendingRequestsBanner({required this.requests});

  final List<FinanceRequest> requests;

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF854D0E);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFCE8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بانتظار موافقة المدير:', style: NoonText.style(11, weight: FontWeight.w700, color: fg)),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${financeRequestLabel(r.kind)}: ${r.summary} — ${r.requestedByName}',
                style: NoonText.style(11, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}

/// شارة خصم الطالب بجانب عنوان الرسوم، تفتح تعديل الخصم — كالويب.
Widget? _discountBadge(BuildContext context, AppStore store, Student student) {
  if (student.usesCustomPlan) return null;
  final discount = studentDiscountOf(student);
  final legacyRate = student.academicDiscountRate;
  String? label;
  var reason = '';
  if (discount != null && discount.value > 0) {
    label = discount.percentage ? 'خصم ${trimNum(discount.value)}%' : 'خصم ${money(discount.value)}';
    reason = discount.reason.trim();
  } else if ((student.academicDiscountApplied || legacyRate > 0) && legacyRate > 0) {
    label = 'خصم ${trimNum(legacyRate)}%';
  }
  if (label == null) return null;
  return Tooltip(
    message: 'تعديل الخصم',
    child: InkWell(
      onTap: () => _showStudentDiscountSheet(context, store, student),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (reason.isNotEmpty) TextSpan(text: ' · $reason', style: const TextStyle(color: Color(0xFF3B82F6))),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NoonText.style(12, weight: FontWeight.w500, color: const Color(0xFF1E40AF)),
        ),
      ),
    ),
  );
}

/// «إجراءات ▾» في رأس الرسوم: الخصم والرسوم الخاصة والخطة المخصصة خلف زر واحد.
class _FeesMenu extends StatelessWidget {
  const _FeesMenu({required this.store, required this.student});

  final AppStore store;
  final Student student;

  @override
  Widget build(BuildContext context) {
    final canDiscountPlan = !student.usesCustomPlan && student.gradeLevel.trim().isNotEmpty;
    final canCustom = store.can('finance.discount');
    PopupMenuItem<String> item(String value, IconData icon, String label) => PopupMenuItem<String>(
          value: value,
          height: 36,
          child: Row(
            children: [
              Icon(icon, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(label, style: NoonText.style(12, color: AppColors.text)),
            ],
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'إجراءات الرسوم',
      position: PopupMenuPosition.under,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      constraints: const BoxConstraints(minWidth: 160),
      onSelected: (action) {
        switch (action) {
          case 'discount':
            _showStudentDiscountSheet(context, store, student);
          case 'extra':
            _showExtraChargeSheet(context, store, student);
          case 'custom':
            _showCustomPlanSheet(context, store, student);
        }
      },
      itemBuilder: (_) => [
        if (canDiscountPlan) item('discount', Icons.percent, 'خصم'),
        item('extra', Icons.add, 'رسوم خاصة'),
        if (canCustom) item('custom', Icons.tune, student.usesCustomPlan ? 'تعديل الخطة' : 'خطة مخصصة'),
      ],
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AdminNoon.rTile),
          border: Border.all(color: AppColors.lineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('إجراءات', style: NoonText.style(11, weight: FontWeight.w500, color: AppColors.muted)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// زر صغير بارتفاع 24 داخل البلاطات (خصم، حذف، معاينة، واتساب).
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.text,
    this.background = Colors.white,
    this.border = AppColors.lineStrong,
    this.weight = FontWeight.w500,
    this.fontSize = 11,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final Color color;
  final Color background;
  final Color border;
  final FontWeight weight;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(AdminNoon.rTile);
    return Material(
      color: background,
      borderRadius: r,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(borderRadius: r, border: Border.all(color: border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 4)],
              Text(label, style: NoonText.style(fontSize, weight: weight, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// أيام الغياب والإذن وحدها — أيام الحضور لا تحتاج عرضاً.
List<Widget> _attendanceMisses(List<AttendanceMark> marks) {
  final misses = marks.where((m) => m.status == 'absent' || m.status == 'excused').toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  if (misses.isEmpty) return const [];
  return [
    ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: misses.length,
        separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: AdminNoon.line),
        itemBuilder: (_, i) {
          final m = misses[i];
          final date = parseIsoDate(m.date);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    date == null ? m.date : noonDate(date),
                    style: NoonText.style(11, color: AdminNoon.muted),
                  ),
                ),
                Text(
                  m.status == 'absent' ? 'غائب' : 'مأذون',
                  style: NoonText.style(11, color: m.status == 'absent' ? AdminNoon.red600 : AdminNoon.warn),
                ),
              ],
            ),
          );
        },
      ),
    ),
  ];
}

Widget _faintDash() => Text('—', style: NoonText.style(12, color: AdminNoon.faint));

/// جدول «مفتاح: قيمة» بعمودين: المفتاح بعرض أطولها والقيمة بعدها مباشرة.
class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.rows});

  final List<(String, Widget)> rows;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(end: 12, top: i == 0 ? 0 : 8),
                child: Text(rows[i].$1, style: NoonText.style(12, weight: FontWeight.w500, color: AdminNoon.muted)),
              ),
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Align(alignment: AlignmentDirectional.centerStart, child: rows[i].$2),
              ),
            ],
          ),
      ],
    );
  }
}

/// الهاتف بأرقامه وزرّي الاتصال والواتساب بجانبه.
class _PhoneValue extends StatelessWidget {
  const _PhoneValue({required this.phone, required this.prefix});

  final String phone;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final number = phone.trim();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatPhoneDisplay(number, prefix),
          textDirection: TextDirection.ltr,
          style: NoonText.style(11, weight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        _ContactAction(
          tooltip: 'اتصال هاتفي',
          onTap: () => launchTel(number),
          background: const Color(0xFFF1F5F9),
          border: AppColors.lineStrong,
          child: Icon(Icons.call_outlined, size: 12, color: AppColors.heading),
        ),
        const SizedBox(width: 6),
        _ContactAction(
          tooltip: 'مراسلة واتساب',
          onTap: () => launchWa(number),
          background: const Color(0xFFDCFCE7),
          border: const Color(0xFF86EFAC),
          child: const MessageCircleIcon(color: Color(0xFF16A34A), size: 14),
        ),
      ],
      ),
    );
  }
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
        color: background,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// هوية ولي الأمر — رقم دخوله إلى بوابته.
class _ParentLoginId extends StatelessWidget {
  const _ParentLoginId({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final v = value.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AdminNoon.band,
        borderRadius: BorderRadius.circular(AdminNoon.rTile),
        border: Border.all(color: AdminNoon.line),
      ),
      child: Row(
        children: [
          Expanded(child: Text('هوية ولي الأمر:', style: NoonText.style(12, weight: FontWeight.w700))),
          Text(
            v.isEmpty ? 'غير مسجلة' : v,
            textDirection: TextDirection.ltr,
            style: NoonText.style(12, weight: FontWeight.w700, color: v.isEmpty ? AdminNoon.warn : AdminNoon.text)
                .copyWith(letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

/// كلمة مرور بوابة — `SecretCode`: مخفية بنقاط، وزرّا إظهار ونسخ، وتوليد لمن لا كلمة له.
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
    final name = widget.label.replaceAll(':', '');

    Widget action(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 14, color: AdminNoon.muted)),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AdminNoon.band,
        borderRadius: BorderRadius.circular(AdminNoon.rTile),
        border: Border.all(color: AdminNoon.line),
      ),
      child: Row(
        children: [
          Icon(Icons.key_outlined, size: 14, color: AdminNoon.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NoonText.style(12, weight: FontWeight.w700),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 72),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AdminNoon.line)),
            child: Text(
              code.isEmpty ? 'غير محدد' : (visible ? code : '••••••'),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: NoonText.style(12, weight: FontWeight.w700).copyWith(letterSpacing: 0.6),
            ),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(width: 6),
            action(
              visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              visible ? 'إخفاء' : 'إظهار',
              () => setState(() => visible = !visible),
            ),
            const SizedBox(width: 6),
            action(Icons.copy_outlined, 'نسخ', () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) showAppSnack(context, 'تم نسخ $name');
            }),
          ] else if (widget.onGenerate != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'توليد',
              child: InkWell(
                onTap: () {
                  widget.onGenerate!();
                  showAppSnack(context, 'تم توليد $name');
                },
                borderRadius: BorderRadius.circular(AdminNoon.rTile),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AdminNoon.rTile),
                    border: Border.all(color: AdminNoon.line),
                  ),
                  child: Text('توليد', style: NoonText.style(11, weight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// صفوف «بيانات إضافية» بجدول «مفتاح: قيمة» كبيانات التواصل.
List<(String, Widget)> _extraIdentityRows(Student student, DateTime? birth, String medical) {
  Widget v(String text) => Text(text, style: NoonText.style(12, weight: FontWeight.w700));
  return [
    if (student.gender.trim().isNotEmpty) ('الجنس:', v(genderLabel(student.gender))),
    if (student.nationality.trim().isNotEmpty) ('الجنسية:', v(student.nationality.trim())),
    if (student.birthPlace.trim().isNotEmpty) ('مكان الولادة:', v(student.birthPlace.trim())),
    if (birth != null) ('تاريخ الميلاد:', v(noonDate(birth))),
    if (student.healthStatus.trim().isNotEmpty) ('الحالة الصحية:', v(student.healthStatus.trim())),
    if (medical.isNotEmpty) ('تفاصيل الحالة الصحية:', v(medical)),
    if (student.housingStatus.trim().isNotEmpty) ('طبيعة السكن:', v(student.housingStatus.trim())),
    if (student.gpa.trim().isNotEmpty) ('المعدل:', v(student.gpa.trim())),
    if (student.previousSchool.trim().isNotEmpty) ('المدرسة السابقة:', v(student.previousSchool.trim())),
    if (student.referralSource.trim().isNotEmpty) ('مصدر التعرف:', v(student.referralSource.trim())),
    if (student.initialRating > 0)
      (
        'التقييم المبدئي:',
        Row(
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
      ),
  ];
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
              const Text('خصم الطالب على أقساط خطته', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
              const Text('رسم خاص بالطالب', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
              ActionButtons(
                primaryFlex: 1,
                gap: 8,
                primary: PrimaryButton(
                  label: 'اعتماد الخطة المخصصة',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                secondary: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx, false)),
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
  bool allowRemove = true,
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
            title: Text(installment.title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
            if (allowRemove && InstallmentAdjustments.canRemove(installment))
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              if (!removing) ...[
                const SizedBox(height: 6),
                Text('قيمة القسط: ${money(original)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text('يصير المطلوب: ${money(after)}', style: TextStyle(color: AppColors.heading, fontWeight: FontWeight.w600, fontSize: 12)),
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

/// الرسوم سنةً سنة: رأس لكل سنة (اسمها والباقي فيها) يطويها حين تتعدد السنوات،
/// والسنة الحالية مفتوحة.
class _InstallmentYears extends StatefulWidget {
  const _InstallmentYears({
    required this.store,
    required this.student,
    required this.insts,
    required this.currentYearKey,
    required this.canCollect,
    required this.canAdjust,
  });

  final AppStore store;
  final Student student;
  final List<Installment> insts;
  final String currentYearKey;
  final bool canCollect;
  final bool canAdjust;

  @override
  State<_InstallmentYears> createState() => _InstallmentYearsState();
}

class _InstallmentYearsState extends State<_InstallmentYears> {
  final open = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final groups = <String, List<Installment>>{};
    for (final i in widget.insts) {
      final key = i.academicYearId.trim().isEmpty ? widget.currentYearKey : i.academicYearId;
      groups.putIfAbsent(key, () => []).add(i);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == widget.currentYearKey) return -1;
        if (b == widget.currentYearKey) return 1;
        final ya = store.academicYears.where((y) => y.id == a).firstOrNull?.startsOn ?? '';
        final yb = store.academicYears.where((y) => y.id == b).firstOrNull?.startsOn ?? '';
        return yb.compareTo(ya);
      });
    final multi = keys.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var k = 0; k < keys.length; k++) ...[
          if (k > 0) const SizedBox(height: 12),
          () {
            final key = keys[k];
            final current = key == widget.currentYearKey;
            final isOpen = !multi || (open[key] ?? current);
            final rows = groups[key]!;
            final remaining = rows.fold<double>(0, (a, i) => a + (i.isExempt ? 0 : i.remaining));
            final label = store.academicYears.where((y) => y.id == key).firstOrNull?.label ?? 'السنة الحالية';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (multi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => setState(() => open[key] = !isOpen),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: current ? const Color(0xFFF8FAFC) : Colors.white,
                          border: Border.all(color: current ? AppColors.lineStrong : AppColors.line),
                        ),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: isOpen ? 0 : 0.25,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.muted),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(label, style: NoonText.style(11, weight: FontWeight.w600, color: AppColors.heading)),
                            ),
                            Text.rich(
                              TextSpan(
                                text: 'باقٍ ',
                                children: [
                                  TextSpan(
                                    text: money(remaining),
                                    style: remaining > cent
                                        ? const TextStyle(color: Color(0xFFBA1A1A), fontWeight: FontWeight.w600)
                                        : null,
                                  ),
                                ],
                              ),
                              style: NoonText.style(11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (isOpen)
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _InstallmentTile(
                      student: widget.student,
                      inst: rows[i],
                      canCollect: widget.canCollect,
                      canAdjust: widget.canAdjust,
                    ),
                  ],
              ],
            );
          }(),
        ],
      ],
    );
  }
}

/// سطر في «السنوات الدراسية»؛ `periods` تظهر فقط إن تنقّل بين أكثر من شعبة في السنة.
typedef _YearHistoryRow = ({
  String yearLabel,
  String grade,
  String section,
  String status,
  String discount,
  bool current,
  List<(String, String, String)> periods,
});

/// السنوات الدراسية — الأقدم أولاً.
List<_YearHistoryRow> _studentYearHistory(AppStore store, Student student) {
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
  // فترات الشعب في كل عام: تظهر إن تنقّل الطالب بين أكثر من شعبة فيه
  final periods = store.sectionPeriodsOf(student.id);
  List<(String, String, String)> periodsOf(String yearId) {
    final list = [for (final p in periods) if ('${p['academic_year_id'] ?? ''}' == yearId) p];
    if (list.length < 2) return const [];
    return [
      for (final p in list)
        (
          '${p['section'] ?? ''}',
          '${p['from_date'] ?? ''}'.split('T').first,
          '${p['to_date'] ?? ''}'.isEmpty ? 'الآن' : '${p['to_date']}'.split('T').first,
        ),
    ];
  }

  return [
    for (final y in rows)
      (
        yearLabel: store.academicYears.where((a) => a.id == y.academicYearId).firstOrNull?.label ?? 'عام دراسي',
        grade: y.gradeLevel.trim().isEmpty ? '—' : y.gradeLevel.trim(),
        section: y.section.trim(),
        status: studentStatusLabel(y.status),
        discount: y.planDiscountValue > 0
            ? (y.planDiscountType == 'fixed' ? 'خصم ${money(y.planDiscountValue)}' : 'خصم ${trimNum(y.planDiscountValue)}%')
            : '',
        current: y.academicYearId == currentId,
        periods: periodsOf(y.academicYearId),
      ),
  ];
}

class _YearRow extends StatelessWidget {
  const _YearRow({required this.row});

  final _YearHistoryRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(row.yearLabel, style: NoonText.style(12, color: AppColors.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${row.grade}${row.section.isEmpty ? '' : ' — ${row.section}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NoonText.style(12, weight: FontWeight.w700, color: row.current ? AppColors.heading : AppColors.muted),
              ),
            ),
            Text(
              '${row.status}${row.discount.isEmpty ? '' : ' · ${row.discount}'}',
              style: NoonText.style(10, color: AppColors.muted),
            ),
          ],
        ),
        for (final p in row.periods)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, top: 4),
            child: Row(
              children: [
                Expanded(child: Text(p.$1, style: NoonText.style(10, color: AppColors.muted))),
                Text('${p.$2} — ${p.$3}', style: NoonText.style(10, color: AppColors.muted)),
              ],
            ),
          ),
      ],
    );
  }
}

/// قسط — بلاطة: العنوان ووسم حالته، ثم «استحقاق» مقابل المطلوب والمتبقي،
/// وتحتها «خصم» و«حذف». غير المسدد أبيض ولمسه يفتح التسديد، والمسدد رمادي فاتح.
class _InstallmentTile extends StatelessWidget {
  const _InstallmentTile({required this.student, required this.inst, required this.canCollect, required this.canAdjust});

  final Student student;
  final Installment inst;
  final bool canCollect;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final future = dateOnly(inst.dueDate).isAfter(dateOnly(DateTime.now()));
    final paid = inst.isExempt || inst.isPaid;
    final payable = !paid && canCollect;
    // المسدد انقفل: خصمه أو حذفه يقلب ما دُفع رصيداً زائداً
    final settled = !inst.isExempt && inst.remaining <= cent;
    final canDiscount = canAdjust && !settled && !student.usesCustomPlan;
    final canRemove = canAdjust && !settled && InstallmentAdjustments.canRemove(inst);

    final (String badge, Color fg, Color bg, Color border) = inst.isExempt
        ? ('معفى', AppColors.text, const Color(0xFFF8FAFC), AppColors.lineStrong)
        : inst.isPaid
            ? ('مسدد', const Color(0xFF16A34A), const Color(0xFFF0FDF4), const Color(0xFFBBF7D0))
            : future
                ? ('قادم', const Color(0xFF6B7280), const Color(0xFFF3F4F6), AppColors.line)
                : ('مستحق', const Color(0xFFDC2626), const Color(0xFFFEF2F2), const Color(0xFFFCA5A5));

    final amountText = TextSpan(
      children: [
        if (!inst.isExempt && inst.discountAmount > cent)
          TextSpan(
            text: '${money(inst.amount + inst.discountAmount)} ',
            style: const TextStyle(color: Color(0xFF9CA3AF), decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w400),
          ),
        TextSpan(
          text: money(inst.amount),
          style: inst.isExempt
              ? const TextStyle(color: Color(0xFF9CA3AF), decoration: TextDecoration.lineThrough)
              : null,
        ),
      ],
    );

    return Material(
      color: payable ? Colors.white : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: payable
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentFormScreen(studentId: student.id, installmentId: inst.id, amount: inst.remaining),
                  ),
                )
            : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(inst.title, style: NoonText.style(12, weight: FontWeight.w700, color: AppColors.text)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      badge,
                      style: NoonText.style(10, weight: badge == 'مستحق' ? FontWeight.w700 : FontWeight.w600, color: fg),
                    ),
                  ),
                ],
              ),
              if (inst.isExempt && inst.exemptReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('إعفاء: ${inst.exemptReason}', style: NoonText.style(10, color: AppColors.muted)),
                )
              else if (!inst.isExempt && inst.discountAmount > cent)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'خصم ${money(inst.discountAmount)}${inst.discountReason.trim().isEmpty ? '' : ' — ${inst.discountReason.trim()}'}',
                    style: NoonText.style(10, color: const Color(0xFF1D4ED8)),
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text('استحقاق: ${noonDate(inst.dueDate)}', style: NoonText.style(11, color: AppColors.muted)),
                  Wrap(
                    spacing: 8,
                    children: [
                      Text.rich(
                        TextSpan(text: 'المطلوب: ', children: [amountText]),
                        style: NoonText.style(11, color: AppColors.muted),
                      ),
                      if (!paid)
                        Text(
                          'المتبقي: ${money(inst.remaining)}',
                          style: NoonText.style(11, weight: FontWeight.w700, color: const Color(0xFFDC2626)),
                        ),
                    ],
                  ),
                ],
              ),
              if (canAdjust)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.only(top: 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.hover))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!canDiscount && !canRemove)
                        Text('—', style: NoonText.style(11, color: AppColors.lineStrong)),
                      if (canDiscount)
                        _MiniButton(
                          label: 'خصم',
                          onTap: () => _openInstallment(context, store, student, inst, canCollect: false, canAdjust: true, allowRemove: false),
                        ),
                      if (canDiscount && canRemove) const SizedBox(width: 6),
                      if (canRemove)
                        _MiniButton(
                          label: 'حذف',
                          color: const Color(0xFFDC2626),
                          border: const Color(0xFFFECACA),
                          onTap: () => _showInstallmentAdjustmentForm(context, store, inst, 'remove'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// سند قبض — بلاطة: الرقم والتاريخ مقابل المبلغ، ثم طريقة الدفع وغرضه مقابل
/// «معاينة» و«واتساب».
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.student});
  final Payment payment;
  final Student student;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final purpose = paymentPurposeNames[p.purpose] ?? p.purpose;
    final method = StoreScope.of(context).paymentMethodLabel(p.method);
    final reversed = p.reversedByPaymentId != null && p.reversedByPaymentId!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.sunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.amber),
              const SizedBox(width: 6),
              Text(
                p.receiptNumber,
                textDirection: TextDirection.ltr,
                style: NoonText.style(12, weight: FontWeight.w700, color: AppColors.heading),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(noonDate(p.date), style: NoonText.style(10, color: AppColors.muted)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(p.amount),
                    textDirection: TextDirection.ltr,
                    style: NoonText.style(
                      12,
                      weight: FontWeight.w700,
                      color: p.cancelled
                          ? AppColors.faint
                          : p.amount < 0
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF16A34A),
                    ).copyWith(decoration: p.cancelled ? TextDecoration.lineThrough : null),
                  ),
                  if (p.cancelled)
                    Text('ملغى', style: NoonText.style(10, color: const Color(0xFFDC2626)))
                  else if (reversed)
                    Text('معكوس', style: NoonText.style(10, color: const Color(0xFF9A4F05))),
                ],
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.hover))),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [method, if (purpose.trim().isNotEmpty) purpose].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NoonText.style(11, color: AppColors.muted),
                  ),
                ),
                _MiniButton(
                  label: 'معاينة',
                  icon: Icon(Icons.visibility_outlined, size: 12, color: AppColors.heading),
                  color: AppColors.heading,
                  weight: FontWeight.w700,
                  fontSize: 10,
                  onTap: () => ReceiptScreen.open(context, p),
                ),
                if (!p.cancelled) ...[
                  const SizedBox(width: 4),
                  _MiniButton(
                    label: 'واتساب',
                    icon: const MessageCircleIcon(color: Color(0xFF16A34A), size: 12),
                    color: const Color(0xFF16A34A),
                    background: const Color(0xFFDCFCE7),
                    border: const Color(0xFF86EFAC),
                    weight: FontWeight.w700,
                    fontSize: 10,
                    onTap: () => ReceiptScreen.sendWhatsApp(context, p, student),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// التقييمات — كالويب: سطر لكل مادة بفصليها وسنتها، ثم العلامات مجمّعة بالمادة
/// (اسمها ونسبتها، وتحتها كل علامة بدرجتها وتاريخها).
class _EvaluationsCard extends StatelessWidget {
  const _EvaluationsCard({required this.studentId, required this.evaluations});
  final String studentId;
  final List<Evaluation> evaluations;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final grading = store.gradingForViewedYear;
    final scheme = grading.scheme.isEmpty ? store.gradingScheme : grading.scheme;
    final summaryList = grading.mode == 'monthly' || scheme.isEmpty ? <SubjectGradeSummary>[] : store.subjectGradesOf(studentId);
    final summaries = {for (final s in summaryList) s.subjectId: s};
    final list = grading.mode == 'monthly' ? evaluations : evaluations.where((e) => !isMonthlyAverage(e)).toList();

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

    /// نسبة الفصل: المكتمل بلونه، والجاري بلون التنبيه.
    InlineSpan? termPct(String label, TermGrade t) {
      if (t.components.isEmpty || t.currentAverage == null) return null;
      final pct = t.isComplete ? (t.termScore / t.fullMark * 100).round() : t.currentAverage!.round();
      return TextSpan(
        text: '$label $pct%  ',
        style: TextStyle(color: t.isComplete ? AppColors.text : const Color(0xFFD97706)),
      );
    }

    final student = store.studentById(studentId);
    final canReport = student != null && summaryList.isNotEmpty;
    final mono = const [FontFeature.tabularFigures()];

    return NoonFoldCard(
      title: 'التقييمات (${list.length})',
      headerExtra: canReport
          ? InkWell(
              onTap: () => showReportCardsSheet(
                context,
                store,
                cards: [studentReportCard(store, student)],
                title: 'شهادة ${student.fullName}',
              ),
              borderRadius: BorderRadius.circular(AdminNoon.rTile),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AdminNoon.rTile),
                  border: Border.all(color: AdminNoon.line),
                ),
                child: Text('الشهادة', style: NoonText.style(11, weight: FontWeight.w700)),
              ),
            )
          : null,
      children: [
        if (summaryList.isNotEmpty)
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.line))),
            child: Column(
              children: [
                for (var i = 0; i < summaryList.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: i > 0 ? BoxDecoration(border: Border(top: BorderSide(color: AdminNoon.line))) : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            store.subjectName(summaryList[i].subjectId).isEmpty
                                ? summaryList[i].subjectName
                                : store.subjectName(summaryList[i].subjectId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NoonText.style(11, weight: FontWeight.w600),
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              ?termPct('الفصل الأول', summaryList[i].term1),
                              ?termPct('الفصل الثاني', summaryList[i].term2),
                              if (summaryList[i].yearAverage != null)
                                TextSpan(
                                  text: 'السنة ${summaryList[i].yearAverage!.round()}%',
                                  style: const TextStyle(color: AdminNoon.green700, fontWeight: FontWeight.w700),
                                ),
                            ],
                          ),
                          style: NoonText.style(11, color: AdminNoon.muted).copyWith(fontFeatures: mono),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (bySubject.isEmpty)
          const NoonEmpty('لا توجد علامات', dashed: false)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 288),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in bySubject.entries) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.line))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key.isEmpty ? 'مادة' : store.subjectName(entry.key),
                              style: NoonText.style(11, weight: FontWeight.w600),
                            ),
                          ),
                          if (percentOf(entry.key, entry.value) != null)
                            Text(
                              '${percentOf(entry.key, entry.value)!.round()}%',
                              style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.green700)
                                  .copyWith(fontFeatures: mono),
                            ),
                        ],
                      ),
                    ),
                    for (final e in entry.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NoonText.style(11, color: AdminNoon.muted),
                              ),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '${trimNum(e.score)}/${trimNum(e.maxScore)}',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: NoonText.style(11, weight: FontWeight.w700).copyWith(fontFeatures: mono),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                e.evaluationDate.length >= 10
                                    ? '${e.evaluationDate.substring(8, 10)}/${e.evaluationDate.substring(5, 7)}'
                                    : '',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: NoonText.style(11, color: AdminNoon.faint).copyWith(fontFeatures: mono),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
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
    return FutureBuilder<StudentAttachments?>(future: _load, builder: (context, snap) => _card(snap.data ?? store.attachmentsOf(widget.studentId)));
  }

  Widget _card(StudentAttachments? att) {
    if (att == null || att.isEmpty) return const SizedBox.shrink();

    final items = <(String, String)>[
      if (att.studentIdPhoto.isNotEmpty) ('صورة هوية الطالب', att.studentIdPhoto),
      if (att.birthCertificate.isNotEmpty) ('شهادة الميلاد', att.birthCertificate),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NoonFoldCard(
        title: 'المرفقات',
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
      ),
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
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.heading),
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
