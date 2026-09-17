import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/balance.dart';
import '../data/fee_plan.dart';
import '../data/grade_plan_sync.dart';
import '../data/grading.dart';
import '../data/installment_adjustments.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';
import 'payment_form_screen.dart';
import 'receipt_screen.dart';
import 'student_credit_sheet.dart';
import 'student_subjects_card.dart';
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
        final insts = store.installments.where((i) => i.studentId == student.id).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final marks = store.attendance.where((a) => a.studentId == student.id).toList();
        // السند الملغى لا يُحتسب، والخصم يفسّر لماذا يزيد المسدَّد على المقبوض نقداً
        final activePays = pays.where((p) => !p.cancelled);
        final totalPaid = activePays.fold<double>(0, (a, p) => a + p.amount);
        final totalDiscount = activePays.fold<double>(0, (a, p) => a + p.discountAmount);
        final present = marks.where((m) => m.status == 'present').length;
        final absent = marks.where((m) => m.status == 'absent').length;
        final excused = marks.where((m) => m.status == 'excused').length;
        // الالتزام يحتسب الحاضر وحده — مطابق لـ attendanceStats في StudentDetail.tsx
        final rate = marks.isEmpty ? 100 : ((present / marks.length) * 100).round();
        final settled = store.isSettledToDate(student.id) && insts.every((i) => i.isPaid) && student.balance >= -cent;
        final dueNow = store.outstandingDue(student.id);
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
                    if (!student.isActiveStudent) ...[const SizedBox(width: 6), StudentStatusChip(status: student.status, compact: true)],
                  ],
                ),
              ],
            ),
          ),
          bottomNavigationBar: (canCollect || canEdit || canRefundStudent)
              ? _ActionBar(
                  showPay: canCollect,
                  onPay: canCollect ? (settled ? null : pay) : null,
                  showRefund: canRefundStudent,
                  onRefund: canRefundStudent
                      ? () async {
                          final receipt = await showStudentCreditSheet(context, store, student);
                          if (receipt != null && context.mounted) {
                            ReceiptScreen.open(context, receipt);
                          }
                        }
                      : null,
                  onEdit: canEdit ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentFormScreen(student: student))) : null,
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
                          // المستحق الحالّ في البطاقة — مطابق لـ remainingDebt في StudentDetail.tsx
                          // والرصيد الموجب «له»؛ والدين الكامل يظهر في التفصيل تحته
                          value: dueNow > 0 ? 'عليه ${money(dueNow)}' : (student.balance > 0 ? 'له ${money(student.balance)}' : 'مسدد'),
                          color: dueNow > 0 ? AppColors.danger : (student.balance > 0 ? AppColors.amber : AppColors.success),
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

              // ── بيانات الطالب والتواصل ──
              _Card(
                title: 'بيانات الطالب والتواصل',
                children: [
                  // الرقمان متجاوران: عنوان صغير فوق رقم بارز، وأيقونتا الاتصال تحته
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ContactCell(label: 'هاتف الطالب', phone: student.phone),
                        ),
                        if (parentPhone.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ContactCell(label: parentName.isEmpty ? 'هاتف ولي الأمر' : 'ولي الأمر · $parentName', phone: parentPhone),
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
                      if (student.previousSchool.trim().isNotEmpty) _Field('المدرسة السابقة', student.previousSchool.trim()),
                      if (address.isNotEmpty) _Field('العنوان', address),
                      if (student.referralSource.trim().isNotEmpty) _Field('مصدر التعرف', student.referralSource.trim()),
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
              if (canFinance)
                _Card(
                  title: 'الأقساط المجدولة (${insts.length})',
                  trailing: PopupMenuButton<String>(
                    tooltip: 'إجراءات الأقساط',
                    icon: Icon(Icons.more_horiz, color: AppColors.heading, size: 20),
                    onSelected: (value) {
                      if (value == 'discount') {
                        _showStudentDiscountSheet(context, store, student);
                      } else if (value == 'extra') {
                        _showExtraChargeSheet(context, store, student);
                      } else if (value == 'custom') {
                        _showCustomPlanSheet(context, store, student);
                      } else if (value == 'return') {
                        _returnToGradePlan(context, store, student);
                      }
                    },
                    itemBuilder: (_) => [
                      if (!student.usesCustomPlan && student.gradeLevel.trim().isNotEmpty) const PopupMenuItem(value: 'discount', child: Text('خصم للطالب')),
                      const PopupMenuItem(value: 'extra', child: Text('رسم خاص')),
                      if (store.can('finance.discount')) PopupMenuItem(value: 'custom', child: Text(student.usesCustomPlan ? 'تعديل المخصصة' : 'خطة مخصصة')),
                      if (student.usesCustomPlan && store.can('finance.discount')) const PopupMenuItem(value: 'return', child: Text('رجوع لخطة المرحلة')),
                    ],
                  ),
                  children: [
                    if (student.usesCustomPlan)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'خطة مخصصة — مستقلة عن خطة المرحلة',
                          style: TextStyle(color: AppColors.info, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    if (insts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'لا توجد أقساط بعد',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.faint),
                        ),
                      ),
                    for (final inst in insts) _InstallmentTile(student: student, inst: inst, canCollect: canCollect, canAdjust: canFinance),
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
                        TextSpan(
                          text: money(totalPaid),
                          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.heading),
                        ),
                        if (totalDiscount > 0)
                          TextSpan(
                            text: '  + خصم ${money(totalDiscount)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                          ),
                      ],
                    ),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  children: [
                    if (pays.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'لا توجد دفعات مسجلة حتى الآن',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      )
                    else
                      for (final p in pays) _PaymentTile(payment: p, student: student),
                  ],
                ),

              // ── الحضور والالتزام: ملخص بسطر واحد كما في Center ──────────────
              if (marks.isNotEmpty && store.can('attendance'))
                _Card(
                  title: 'سجل الحضور والالتزام',
                  trailing: Text(
                    'الالتزام: $rate%',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                  ),
                  children: [
                    InfoStrip(
                      // الأرقام تتقلّص ولا تطفح على الشاشات الضيقة
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: FittedBox(fit: BoxFit.scaleDown, child: TallyText('حضور', present, AppColors.success)),
                          ),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          Expanded(
                            child: FittedBox(fit: BoxFit.scaleDown, child: TallyText('غياب', absent, AppColors.danger)),
                          ),
                          const Text('•', style: TextStyle(color: AppColors.faint)),
                          Expanded(
                            child: FittedBox(fit: BoxFit.scaleDown, child: TallyText('مأذون', excused, const Color(0xFFD97706))),
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
              if (store.can('classes')) ...[StudentSubjectsCard(student: student), const SizedBox(height: 10)],

              // ── الدرجات والتقييمات ─────────────────────────────────────────
              if (store.features.enableEvaluations && store.can('evaluations'))
                _EvaluationsCard(studentId: student.id, evaluations: store.evaluationsOfStudent(student.id)),

              _AttachmentsCard(studentId: student.id),

              // الحذف زر كامل العرض بلون التحذير في آخر الصفحة، بعيداً عن الإبهام:
              // فعل لا رجعة فيه يُرى بوضوح ولا يُضغط سهواً
              if (store.can('students'))
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
                        final blocked = store.countActivePayments(student.id);
                        if (blocked > 0) {
                          // كويب: أرشفة بدل الحذف عند وجود سندات
                          final archive = await confirmSheet(
                            context,
                            title: 'لا يمكن حذف الطالب',
                            message: 'عليه $blocked سند قبض. يمكن أرشفته بدل الحذف (تُسقط الأقساط المستقبلية ويُحتفظ بالسجل المالي).',
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

// ═══ عناصر الصفحة ═══════════════════════════════════════════════════════════

/// شريط الإجراءات الثابت: تسديد دفعة أولاً وأعرض، ثم تعديل البيانات.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.showPay, required this.onPay, required this.showRefund, required this.onRefund, required this.onEdit});

  final bool showPay;
  final VoidCallback? onPay;
  final bool showRefund;
  final VoidCallback? onRefund;
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
            if (showPay && (showRefund || onEdit != null)) const SizedBox(width: 8),
            if (showRefund)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: GhostButton(label: 'رد مبلغ', icon: Icons.currency_exchange, onPressed: onRefund),
                ),
              ),
            if (showRefund && onEdit != null) const SizedBox(width: 8),
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
/// الملف طويل: كل أقسامه مطويّة عند الفتح ويُفتح منها ما يُطلب، فيظهر الملف
/// كله في شاشة واحدة بدل تمرير طويل. البطاقة بلا عنوان لا تُطوى.
class _Card extends StatefulWidget {
  const _Card({this.title, this.trailing, required this.children});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool open = false;

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
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
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
                  if (student.balance > 0) 'له رصيد ${money(student.balance)}',
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
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: overdue > 0 ? AppColors.danger : AppColors.success),
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
BoxDecoration _cellBox() => BoxDecoration(
  borderRadius: BorderRadius.circular(Corner.box),
  color: AppColors.bg,
  border: Border.all(color: AppColors.line),
);

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
                    label: Text(
                      'توليد',
                      style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12),
                    ),
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
                style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 12.5, letterSpacing: 1.2, color: AppColors.heading),
              ),
            ),
            action(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, visible ? 'إخفاء' : 'إظهار', () => setState(() => visible = !visible)),
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              number.isEmpty ? '—' : number,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5, color: number.isEmpty ? AppColors.faint : AppColors.heading),
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
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[if (i > 0) const SizedBox(width: _gap), Expanded(child: _cell(cells[i]))],
            ],
          ),
        ),
      );
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
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: _gap), rows[i]],
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
          Text(
            f.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
          ),
          const SizedBox(height: 3),
          f.child ??
              Text(
                empty ? '—' : f.value.trim(),
                maxLines: f.wide ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: f.ltr ? TextDirection.ltr : null,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.45, color: empty ? AppColors.faint : AppColors.text),
              ),
        ],
      ),
    );
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
                decoration: InputDecoration(labelText: percentage ? 'النسبة %' : 'المبلغ ₪'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'السبب (مطلوب)'),
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
                    onPressed: () => save(PlanDiscount(percentage: percentage, value: double.tryParse(value.text) ?? 0, reason: reason.text)),
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
  final due = TextEditingController(text: isoDate(DateTime.now()));
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => Padding(
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
            decoration: const InputDecoration(labelText: 'اسم الرسم (كتاب، غرامة، نشاط...)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ ₪'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: due,
            decoration: const InputDecoration(labelText: 'تاريخ الاستحقاق YYYY-MM-DD'),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'إضافة', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) {
    try {
      InstallmentAdjustments(
        store,
      ).addExtraCharge(studentId: student.id, title: title.text, amount: double.tryParse(amount.text) ?? 0, dueDate: parseIsoDate(due.text) ?? DateTime.now());
      showAppSnack(context, 'تمت إضافة الرسم الخاص');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }
  title.dispose();
  amount.dispose();
  due.dispose();
}

Future<void> _showCustomPlanSheet(BuildContext context, AppStore store, Student student) async {
  final existing = store.installments.where((i) => i.studentId == student.id && isCustomInstallmentId(i.id)).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final count = TextEditingController(text: existing.isEmpty ? '8' : '${existing.length}');
  final amount = TextEditingController(text: existing.isEmpty ? '' : '${existing.first.amount}');
  final firstDate = TextEditingController(text: existing.isEmpty ? isoDate(student.enrollmentDate) : isoDate(existing.first.dueDate));
  final every = TextEditingController(text: '1');
  final reason = TextEditingController(text: student.usesCustomPlan && student.exceptionReason.isNotEmpty ? student.exceptionReason : 'خطة مخصصة');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(student.usesCustomPlan ? 'تعديل الخطة المخصصة' : 'خطة مخصصة للطالب', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('أقساط خاصة بهذا الطالب — مستقلة عن خطة مرحلته.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 10),
            TextField(
              controller: count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد الأقساط'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'مبلغ كل قسط ₪'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: firstDate,
              decoration: const InputDecoration(labelText: 'تاريخ أول قسط YYYY-MM-DD'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: every,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المسافة بين الأقساط (شهر)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'السبب / ملاحظة'),
            ),
            const SizedBox(height: 12),
            PrimaryButton(label: student.usesCustomPlan ? 'استبدال الخطة' : 'إنشاء الخطة', onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ),
    ),
  );
  if (ok == true && context.mounted) {
    try {
      final rows = generatePlanItems(
        count: int.tryParse(count.text) ?? 0,
        amount: double.tryParse(amount.text) ?? 0,
        firstDueDate: firstDate.text,
        everyMonths: int.tryParse(every.text) ?? 1,
        titlePrefix: 'قسط مخصص',
        newId: store.newId,
      );
      store.applyCustomPlan(student.id, schedule: rows, reason: reason.text);
      showAppSnack(context, 'تم حفظ الخطة المخصصة');
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }
  count.dispose();
  amount.dispose();
  firstDate.dispose();
  every.dispose();
  reason.dispose();
}

Future<void> _returnToGradePlan(BuildContext context, AppStore store, Student student) async {
  final ok = await confirmSheet(
    context,
    title: 'رجوع لخطة المرحلة',
    message: 'تُحذف الأقساط المخصصة غير المدفوعة، ويبقى المدفوع في السجل، ثم تُطبّق خطة «${student.gradeLevel}».',
    confirmLabel: 'رجوع للخطة',
    confirmColor: AppColors.heading,
  );
  if (!ok || !context.mounted) return;
  try {
    store.returnToGradePlan(student.id);
    showAppSnack(context, 'تم الرجوع لخطة المرحلة');
  } on StoreException catch (e) {
    showAppSnack(context, e.message, error: true);
  }
}

Future<void> _showInstallmentActionSheet(BuildContext context, AppStore store, Installment installment) async {
  final hasDiscount = installment.isExempt || installment.discountAmount > cent;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.dialog))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(installment.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('قيمة القسط: ${money(installment.amount + installment.discountAmount)}'),
          ),
          const Divider(height: 1),
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
      ),
    ),
  );
  if (action == null || !context.mounted) return;
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
                    ? 'إعفاء كامل'
                    : 'خصم بمبلغ',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              if (!exempt && !removing) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onChanged: (_) => refreshPreview(),
                  decoration: const InputDecoration(labelText: 'مبلغ الخصم ₪'),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                onChanged: (_) => refreshPreview(),
                decoration: InputDecoration(labelText: removing && store.can('finance.discount') ? 'السبب (اختياري)' : 'السبب (مطلوب)'),
              ),
              if (preview != null && preview!.paid > cent) ...[const SizedBox(height: 10), _MoneyMovesView(preview!)],
              if (!store.can('finance.discount')) ...[
                const SizedBox(height: 8),
                Text('لا تملك هذه الصلاحية: يُرسل طلباً للمدير ويُنفّذ بعد موافقته.', style: TextStyle(color: AppColors.amberDark, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              PrimaryButton(
                label: store.can('finance.discount') ? (removing ? 'حذف' : 'حفظ') : 'إرسال للمدير',
                color: removing ? AppColors.danger : null,
                onPressed: save,
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
        onLongPress: canAdjust ? () => _showInstallmentActionSheet(context, store, inst) : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: tileDecoration(white: !inst.isPaid && !inst.isExempt),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inst.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text),
                    ),
                  ),
                  if (canAdjust)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'إجراءات القسط',
                      icon: const Icon(Icons.more_vert, size: 19, color: AppColors.muted),
                      onPressed: () => _showInstallmentActionSheet(context, store, inst),
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
                Text(inst.exemptReason, style: const TextStyle(color: AppColors.faint, fontSize: 11)),
              ],
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
                          Text(inst.isExempt ? 'المطلوب: 0' : 'المطلوب: ${money(inst.amount)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                          if (!inst.isExempt && !inst.isPaid)
                            Text(
                              'المتبقي: ${money(inst.remaining)}',
                              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (canAdjust) ...[
                const SizedBox(height: 4),
                Text('اضغط مطوّلاً لإجراءات الخصم والإعفاء', style: const TextStyle(color: AppColors.faint, fontSize: 10)),
              ],
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
                      child: Text(
                        p.receiptNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.heading),
                      ),
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
                  [StoreScope.of(context).paymentMethodLabel(p.method), if (purpose.trim().isNotEmpty) purpose, if (p.cancelled) 'ملغاة'].join('  •  '),
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

/// الدرجات والتقييمات — مطابق لبطاقة «الدرجات والتقييمات» في StudentDetail.tsx.
///
/// المعدل موزون لكل مادة على حدة وفق مخطط المدرسة، لا خلط بين المواد.
class _EvaluationsCard extends StatelessWidget {
  const _EvaluationsCard({required this.studentId, required this.evaluations});
  final String studentId;
  final List<Evaluation> evaluations;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = store.gradingScheme;
    final summaries = store.subjectGradesOf(studentId);

    Widget termLine(String label, TermGrade term) {
      final avg = term.components.isEmpty || term.currentAverage == null
          ? '—'
          : term.isComplete
          ? '${term.total.round()}%'
          : '${term.currentAverage!.round()}% (حالي)';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.text),
                ),
              ),
              Text(
                avg,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: term.isComplete ? AppColors.success : AppColors.amber,
                ),
              ),
            ],
          ),
          for (final c in term.components)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.component.name} (${trimNum(c.component.weight)}%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ),
                  Text(
                    c.achievedPercent == null ? '—' : '${c.achievedPercent!.round()}%',
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppColors.muted),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return _Card(
      title: 'الدرجات والتقييمات (${evaluations.length})',
      children: [
        if (!scheme.isEmpty && summaries.isNotEmpty) ...[
          for (final s in summaries)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(Corner.box),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.subjectName,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.heading),
                        ),
                      ),
                      if (s.yearAverage != null)
                        Text(
                          'السنة: ${s.yearAverage!.round()}%',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.success),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (scheme.isConfigured('term_1')) termLine('الفصل الأول', s.term1),
                  if (scheme.isConfigured('term_1') && scheme.isConfigured('term_2')) const SizedBox(height: 6),
                  if (scheme.isConfigured('term_2')) termLine('الفصل الثاني', s.term2),
                ],
              ),
            ),
          const _Rule(),
        ],
        if (evaluations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'لا توجد نتائج مسجلة حتى الآن',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.faint, fontSize: 12),
            ),
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
                        child: Text(
                          e.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.text),
                        ),
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
                          [if (store.subjectName(e.subjectId).isNotEmpty) store.subjectName(e.subjectId), e.typeLabel].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
                        ),
                      ),
                      if (e.evaluationDate.isNotEmpty) Text(e.evaluationDate, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
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
        Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _Thumb(label: items[i].$1, data: items[i].$2),
              ),
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
