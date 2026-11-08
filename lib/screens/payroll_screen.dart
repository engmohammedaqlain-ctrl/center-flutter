import 'package:flutter/material.dart';

import '../data/doc_export.dart';
import '../data/pay_terms.dart';
import '../data/payroll_calc.dart';
import '../data/printing.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../data/xlsx_styled.dart';
import '../data/teacher_salary.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart' show AdminHero, HeroTone, NoonOffline;
import '../widgets/empty_note.dart';
import '../widgets/noon_ui.dart' show NLoading;
import '../widgets/owner_fold.dart';
import '../widgets/widgets.dart';
import 'expense_voucher_screen.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// صف موظف في شهر — `PayrollRow`.
class _Row {
  const _Row({
    required this.teacher,
    required this.calc,
    required this.entry,
    required this.status,
    required this.payout,
    required this.amount,
    required this.cols,
  });

  final Teacher teacher;
  final PayrollCalc calc;
  final PayrollEntryRow? entry;

  /// `open` أو `paid` أو `legacy`.
  final String status;
  final TeacherPayout? payout;
  final double amount;
  final PayrollColumns cols;

  bool get done => status != 'open';
  RowAmounts get amounts => rowAmounts(cols, amount);
  ({int absence, int advance, int other}) get cuts {
    final a = amounts;
    return splitCut(a.cut, cols.absence, status == 'open' ? calc.advance : _paidAdvance);
  }

  double get _paidAdvance => status == 'paid' ? (entry?.advanceRecovered ?? 0) : 0;

  /// ما يُعتمد: صافٍ يُصرف، أو صافٍ صفر أكلته السلفة فيُسوّى بلا سند.
  bool get payable => status == 'open' && (amount > 0 || calc.advance > 0);
}

/// الرواتب جدول واحد — `PayrollDesk`: الراتب − غياب − سلفة − خصم + إضافة = الصافي، بحالتين:
/// «صرف» أو «صُرف». المصروف أرقام ثابتة، والمفتوح يُعدَّل في مكانه.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late String month = isoDate(DateTime.now()).substring(0, 7);
  List<_Row>? rows;
  List<PayrollEntryRow> entries = const [];
  bool failed = false;
  bool busy = false;

  AppStore get store => StoreScope.of(context);
  bool get perLessonOn => store.isFeatureOn('payroll.per_lesson');
  PayrollSettings get settings =>
      PayrollSettings.fromMap(store.settings.extra['payroll'], weekend: store.settings.extra['weekend']);
  List<Map<String, dynamic>> get calendar => [
        if (store.settings.extra['calendar'] is List)
          for (final e in store.settings.extra['calendar'] as List)
            if (e is Map) Map<String, dynamic>.from(e),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final store = this.store;
    final m = month;
    final daysFuture = StaffService.days('$m-01', monthEnd(m), force: true);
    final leavesFuture = StaffService.leaves(force: true);
    final entriesFuture = PayrollEntries.all();
    final days = await daysFuture;
    final leaves = await leavesFuture ?? const <LeaveRequest>[];
    final all = await entriesFuture;
    if (!mounted || m != month) return;
    if (days == null || all == null) {
      setState(() => failed = true);
      return;
    }
    entries = all;
    final subjectNames = {for (final s in store.subjects) s.id: s.name};
    final out = <_Row>[];
    for (final t in store.teachersInViewedYear) {
      final ids = store.linkedTeacherIds(t.id);
      final payouts = store.teacherPayouts.where((p) => ids.contains(p.teacherId)).toList();
      final mine = all.where((e) => ids.contains(e.teacherId)).toList();
      final entry = mine.where((e) => e.month == m).firstOrNull;
      final terms = termsFor(t, m);
      final calc = computePayroll(
        teacher: t,
        month: m,
        settings: settings,
        perLessonOn: perLessonOn,
        calendar: calendar,
        attendance: [
          for (final d in days)
            if (ids.contains(d.teacherId)) StaffDay(teacherId: t.id, date: d.date, status: d.status, periods: d.periods),
        ],
        leaves: [
          for (final l in leaves)
            if (ids.contains(l.teacherId))
              LeaveRequest(id: l.id, teacherId: t.id, fromDate: l.fromDate, toDate: l.toDate, status: l.status, paid: l.paid),
        ],
        entry: entry,
        percentRooms: terms.percent > 0
            ? percentRooms(
                teacherIds: ids,
                groups: store.groupsInViewedYear,
                rooms: store.roomsInViewedYear,
                students: store.students,
                installments: store.installments,
                payments: store.payments,
                month: m,
                percent: terms.percent,
                basis: terms.percentBasis,
                subjectNames: subjectNames,
              )
            : const [],
        advanceBalance: advanceBalance(payouts, mine, m),
      );
      final salaries = payouts.where((p) => (p.payoutType.isEmpty || p.payoutType == 'salary') && payoutMonthOf(p) == m).toList();
      if (salaries.length > 1) calc.warnings.insert(0, 'صُرف راتب الشهر ${salaries.length} مرات: احذف الزائد');
      final linked = entry != null && entry.payoutId.isNotEmpty
          ? payouts.where((p) => p.id == entry.payoutId).firstOrNull
          : null;
      final legacy = linked == null ? salaries.firstOrNull : null;
      // مصروف بسنده، أو مسوّى بلا سند حين أكلت السلفة الراتب كله
      final settledZero = entry != null && entry.hasSnapshot && entry.payoutId.isEmpty && (entry.paid ?? -1) == 0;
      final status = (linked != null || settledZero) && (entry?.hasSnapshot ?? false)
          ? 'paid'
          : (legacy != null ? 'legacy' : 'open');
      final amount = switch (status) {
        'paid' => entry?.paid ?? 0.0,
        'legacy' => legacy!.amount,
        _ => calc.payable,
      };
      final cols = switch (status) {
        'paid' => snapshotColumns(entry?.snapshot, entry?.adjustments ?? const []),
        'legacy' => PayrollColumns(due: amount, extra: 0, absence: 0, cuts: 0),
        _ => payrollColumns(calc),
      };
      out.add(_Row(teacher: t, calc: calc, entry: entry, status: status, payout: linked ?? legacy, amount: amount, cols: cols));
    }
    bool hasPay(_Row r) => r.done || r.calc.gross > 0 || r.calc.advanceBalance > 0;
    setState(() {
      failed = false;
      rows = [...out.where(hasPay), ...out.where((r) => !hasPay(r))];
    });
  }

  Future<void> _save(_Row r, Map<String, dynamic> patch) async {
    try {
      store.assertOpenDate(['$month-01'], 'رواتب ${monthLabel(month)}');
      await PayrollEntries.saveEntry(
        tenantId: store.tenantId ?? '',
        teacherId: r.teacher.id,
        month: month,
        patch: patch,
        isNew: r.entry == null,
      );
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  /// بند واحد بالإشارة في الشهر يُكتب في مكانه، وأي بنود أخرى تبقى — `withAdjustment`.
  List<Map<String, dynamic>> _withAdjustment(_Row r, int sign, double amount) {
    final list = <({String label, double amount})>[...?r.entry?.adjustments];
    final i = list.indexWhere((a) => a.amount.sign == sign);
    final label = i >= 0 ? list[i].label : (sign == 1 ? 'إضافة' : 'خصم');
    if (amount > 0) {
      if (i >= 0) {
        list[i] = (label: label, amount: sign * amount);
      } else {
        list.add((label: label, amount: sign * amount));
      }
    } else if (i >= 0) {
      list.removeAt(i);
    }
    return [for (final a in list) {'label': a.label, 'amount': a.amount}];
  }

  Future<void> _editNumber(_Row r, {required String title, required double current, required void Function(double?) onSave, String? hint}) async {
    final ctl = TextEditingController(text: current == 0 ? '' : trimNum(current));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('حفظ')),
        ],
      ),
    );
    final text = ctl.text;
    if (ok == true) onSave(numOrNull(text));
  }

  Future<void> _editSalary(_Row r) async {
    final t = r.calc.terms;
    final perLesson = isPerLesson(t, perLessonOn);
    String field(double n) => n > 0 ? trimNum(n) : '';
    final fixed = TextEditingController(text: field(t.fixed));
    final rate = TextEditingController(text: field(t.sessionRate));
    final percent = TextEditingController(text: field(t.percent));
    final auto = r.calc.sessions == null ? null : (r.calc.sessions! * 10).round() / 10;
    final sessions = TextEditingController(text: r.entry?.sessions != null ? trimNum(r.entry!.sessions!) : '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final hasSessions = perLesson || (numOrNull(rate.text) ?? 0) > 0;
          Widget box(String label, TextEditingController c, {String? hint}) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(isDense: true, labelText: label, hintText: hint ?? '0'),
                  ),
                ),
              );
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('أجر ${r.teacher.name}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.heading)),
                Text('يسري من ${monthLabel(month)} فما بعد', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (!perLesson) box('راتب ثابت', fixed),
                    box('سعر الحصة', rate),
                    if (!perLesson) box('نسبة %', percent),
                  ],
                ),
                if (hasSessions) ...[
                  const SizedBox(height: 10),
                  Row(children: [box('حصص ${monthLabel(month)}', sessions, hint: trimNum(auto ?? 0))]),
                ],
                const SizedBox(height: 14),
                PrimaryButton(label: 'حفظ', expand: true, onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          );
        },
      ),
    );
    final fixedV = numOrNull(fixed.text) ?? 0;
    final rateV = numOrNull(rate.text) ?? 0;
    final percentV = numOrNull(percent.text) ?? 0;
    final sessionsV = numOrNull(sessions.text);
    if (ok != true || !mounted) return;
    try {
      final input = payInputOf(r.teacher);
      store.saveTeacherPay(
        r.teacher,
        payUpdate(
          r.teacher,
          input.copyWith(
            fixed: perLesson ? 0 : fixedV,
            sessionRate: rateV,
            percent: perLesson ? 0 : (percentV > 100 ? 100 : percentV),
          ),
          month,
        ),
      );
      // حصص الشهر: الفارغ أو المساوي للمحسوب يعود للمحسوب من الدوام
      final v = perLesson || rateV > 0 ? sessionsV : null;
      final next = v == null || (v == auto && r.entry?.sessions == null) ? null : v;
      if (next != r.entry?.sessions) {
        await PayrollEntries.saveEntry(
          tenantId: store.tenantId ?? '',
          teacherId: r.teacher.id,
          month: month,
          patch: {'sessions': next},
          isNew: r.entry == null,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحفظ'), error: true);
    }
  }

  Future<void> _pay(List<_Row> list) async {
    final store = this.store;
    var date = DateTime.now();
    final methods = store.activePaymentMethods;
    var method = methods.where((m) => m.isDefault).firstOrNull?.id ?? methods.firstOrNull?.id ?? 'cash';
    final total = list.fold<double>(0, (n, r) => n + r.amount);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('صرف رواتب ${monthLabel(month)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.heading)),
              const SizedBox(height: 4),
              Text('${list.length} موظف · ${money(total)}', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              const Text('تاريخ الصرف', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              GhostButton(
                label: isoDate(date),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(DateTime.now().year + 1),
                  );
                  if (picked != null) setSheet(() => date = picked);
                },
              ),
              const SizedBox(height: 8),
              const Text('من حساب', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              AppDropdown<String>(
                value: method,
                items: methodDropdownItems(methods),
                onChanged: (v) => setSheet(() => method = v ?? method),
              ),
              const SizedBox(height: 14),
              PrimaryButton(label: 'صرف ${money(total)}', expand: true, onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final payDay = isoDate(date);
      store.assertOpenDate(['$month-01', payDay], 'رواتب ${monthLabel(month)}');
      var paid = 0;
      for (final r in list) {
        final ids = store.linkedTeacherIds(r.teacher.id);
        if (alreadyPaid(
          store.teacherPayouts.where((p) => ids.contains(p.teacherId)).toList(),
          entries.where((e) => ids.contains(e.teacherId)).toList(),
          month,
        )) {
          continue;
        }
        // السلفة أكلت الراتب كله: يُسوّى الشهر بلا سند (لا نقد يخرج)، ويُقتطع من رصيدها
        if (!(r.amount > 0)) {
          if (!(r.calc.advance > 0)) continue;
          await PayrollEntries.markPaid(
            tenantId: store.tenantId ?? '',
            teacherId: r.teacher.id,
            month: month,
            payoutId: '',
            snapshot: r.calc.snapshot(0),
            advanceRecovered: r.calc.advance,
          );
          paid++;
          continue;
        }
        final payout = store.addTeacherPayout(
          teacherId: r.teacher.id,
          amount: r.amount,
          paymentDate: payDay,
          payoutType: 'salary',
          periodStart: '$month-01',
          periodEnd: monthEnd(month),
          method: method,
          notes: 'راتب ${monthLabel(month)}',
        );
        await PayrollEntries.markPaid(
          tenantId: store.tenantId ?? '',
          teacherId: r.teacher.id,
          month: month,
          payoutId: payout.id,
          snapshot: r.calc.snapshot(r.amount),
          advanceRecovered: r.calc.advance,
        );
        paid++;
      }
      if (mounted) {
        showAppSnack(context, paid < list.length ? 'صُرف $paid، و${list.length - paid} مصروف من قبل' : 'صُرف $paid راتب');
      }
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الصرف'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// سلفة لموظف واحد — `PayrollAdvanceModal`: تدخل رصيده وتُقتطع من راتبه.
  Future<void> _advance() async {
    final store = this.store;
    final teachers = store.teachersInViewedYear;
    var teacherId = '';
    final amount = TextEditingController();
    final installment = TextEditingController();
    var date = DateTime.now();
    final methods = store.activePaymentMethods;
    var method = methods.where((m) => m.isDefault).firstOrNull?.id ?? methods.firstOrNull?.id ?? 'cash';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سلفة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.heading)),
              const SizedBox(height: 10),
              AppDropdown<String>(
                value: teacherId.isEmpty ? null : teacherId,
                hint: 'الموظف',
                // المعلمون ثم الإدارة، والإداري معلَّم باسم قسمه
                items: [
                  for (final t in [...teachers.where((t) => !t.isAdminStaff), ...teachers.where((t) => t.isAdminStaff)])
                    DropdownMenuItem(value: t.id, child: Text(t.isAdminStaff ? '${t.name} · إدارة' : t.name)),
                ],
                onChanged: (v) => setSheet(() => teacherId = v ?? ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, labelText: 'المبلغ'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: installment,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, labelText: 'قسط شهري (اختياري)', hintText: 'فارغ: تُقتطع كلها مرة واحدة'),
              ),
              const SizedBox(height: 8),
              GhostButton(
                label: isoDate(date),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(DateTime.now().year + 1),
                  );
                  if (picked != null) setSheet(() => date = picked);
                },
              ),
              const SizedBox(height: 8),
              AppDropdown<String>(
                value: method,
                items: methodDropdownItems(methods),
                onChanged: (v) => setSheet(() => method = v ?? method),
              ),
              const SizedBox(height: 14),
              PrimaryButton(label: 'صرف السلفة', expand: true, onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    final value = numOrNull(amount.text) ?? 0;
    final install = numOrNull(installment.text);
    if (ok != true || !mounted || teacherId.isEmpty || !(value > 0)) return;
    try {
      final day = isoDate(date);
      final m = day.substring(0, 7);
      store.addTeacherPayout(
        teacherId: teacherId,
        amount: value,
        paymentDate: day,
        payoutType: 'advance',
        periodStart: '$m-01',
        periodEnd: monthEnd(m),
        method: method,
        notes: 'سلفة',
      );
      if (install != null && install > 0) {
        final t = teachers.firstWhere((x) => x.id == teacherId);
        store.saveTeacherPay(t, {
          'pay_profile': {
            ...(t.payProfile is Map ? Map<String, dynamic>.from(t.payProfile as Map) : const <String, dynamic>{}),
            'advance_installment': install,
          },
        });
      }
      await _load();
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  /// قواعد الرواتب للمدرسة — `PayrollSettingsModal`.
  Future<void> _settings() async {
    final store = this.store;
    final s = settings;
    var absence = s.absenceDeduct;
    var late = s.lateFraction;
    var source = s.sessionsSource;
    final leave = TextEditingController(text: s.paidLeaveDays == 0 ? '' : '${s.paidLeaveDays}');
    final lateOptions = <double, String>{0: 'بلا خصم', 0.2: 'خمس يوم', 0.25: 'ربع يوم', 1 / 3: 'ثلث يوم', 0.5: 'نصف يوم'};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إعدادات الرواتب', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.heading)),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('خصم الغياب', style: TextStyle(fontSize: 13)),
                value: absence,
                onChanged: (v) => setSheet(() => absence = v),
              ),
              const Text('خصم التأخير', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              AppDropdown<double>(
                value: lateOptions.keys.firstWhere((k) => (k - late).abs() < 0.001, orElse: () => 0),
                items: [for (final e in lateOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setSheet(() => late = v ?? late),
              ),
              const SizedBox(height: 8),
              const Text('عدد الحصص', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              AppDropdown<String>(
                value: source == 'daily' ? 'daily' : 'load',
                items: const [
                  DropdownMenuItem(value: 'load', child: Text('من النصاب')),
                  DropdownMenuItem(value: 'daily', child: Text('تُرصد يومياً')),
                ],
                onChanged: (v) => setSheet(() => source = v ?? source),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: leave,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, labelText: 'إجازات مدفوعة (يوم بالسنة)'),
              ),
              const SizedBox(height: 14),
              PrimaryButton(label: 'حفظ', expand: true, onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    final days = (numOrNull(leave.text) ?? 0).floor();
    if (ok != true || !mounted) return;
    final prev = store.settings.extra['payroll'];
    await store.writeSchoolOption({
      'payroll': {
        if (prev is Map) ...Map<String, dynamic>.from(prev),
        'absence_deduct': absence,
        'late_fraction': late,
        'sessions_source': source,
        'paid_leave_days': days,
      },
    });
    await _load();
  }

  Future<void> _export(bool excel) async {
    final store = this.store;
    final list = (rows ?? const <_Row>[]).where((r) => r.amount > 0 || r.done).toList();
    const headers = ['الموظف', 'الراتب', 'غياب', 'سلفة', 'خصم', 'إضافة', 'الصافي', 'الحالة'];
    final table = [
      for (final r in list)
        [
          r.teacher.name,
          '${r.amounts.salary}',
          '${r.cuts.absence}',
          '${r.cuts.advance}',
          '${r.cuts.other}',
          '${r.amounts.extra}',
          '${r.amounts.net}',
          r.done ? (r.payout == null ? 'صُرف' : 'صُرف ${r.payout!.paymentDate.padRight(10).substring(0, 10).trim().split('-').reversed.join('/')}') : 'لم يُصرف',
        ],
    ];
    final title = 'كشف رواتب ${monthLabel(month)}';
    if (excel) {
      // كشف منسّق كالويب (`payrollSheet`)
      final sheet = StyledSheet(
        title: title,
        details: ['${list.length} موظف', 'الصافي ${money(list.fold<double>(0, (n, r) => n + r.amount))}'],
        headers: headers,
        rows: table,
        nameColumn: 0,
      );
      final bytes = styledXlsx([sheet], school: store.institutionName, logo: store.institutionLogo);
      await DocExport.download(context, bytes, 'رواتب_$month.xlsx', mime: _xlsxMime);
      return;
    }
    await runBusyOp(context, () async {
      final bytes = await PdfKit.buildSafe(
        title: title,
        institutionName: store.institutionName,
        logoBase64: store.institutionLogo,
        subtitle: '${list.length} موظف · الصافي ${money(list.fold<double>(0, (n, r) => n + r.amount))}',
        landscape: true,
        body: (_) => [
          PdfKit.table(headers: headers, rows: table, flex: const [4, 2, 2, 2, 2, 2, 2, 2]),
        ],
      );
      if (!mounted) return;
      if (bytes == null) {
        showAppSnack(context, 'تعذّر إعداد الكشف', error: true);
        return;
      }
      DocExport.showActions(context, bytes, title);
    }, message: 'جارٍ التجهيز...');
  }

  /// الموظفون المفتوحة تفاصيلهم: التفاصيل تُطوى افتراضياً فتتسع القائمة لكل الموظفين بشاشة واحدة.
  final _expanded = <String>{};

  String _typeLabel(PayTerms t) => switch (t.contractType) {
        'fixed' => 'راتب ثابت',
        'sessions' => 'بالحصة',
        'mixed' => 'مختلط',
        'percent' => 'نسبة',
        _ => 'بلا أجر محدد',
      };

  /// سطر في تفاصيل الموظف: عنوانه وقيمته، وقلم صغير حين يُعدَّل بلمسه.
  Widget _line(String label, int value, {Color? color, String sign = '', VoidCallback? onTap, bool strong = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: strong ? 14 : 13, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, color: strong ? AppColors.heading : AppColors.muted)),
              const Spacer(),
              Text(
                '$sign$value',
                style: TextStyle(fontSize: strong ? 16 : 14, fontWeight: FontWeight.w700, color: color ?? AppColors.heading),
              ),
              SizedBox(
                width: 26,
                child: onTap == null ? null : Icon(Icons.edit_outlined, size: 15, color: AppColors.faint),
              ),
            ],
          ),
        ),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _card(_Row r) {
    final a = r.amounts;
    final c = r.cuts;
    final s = settings;
    final applies = absenceApplies(r.calc.terms, r.calc.sessionsFrom, s.absenceDeduct, perLessonOn);
    final pay = r.calc.terms;
    final noPay = !r.done && pay.fixed <= 0 && pay.sessionRate <= 0 && pay.percent <= 0;
    final open = _expanded.contains(r.teacher.id);
    final name = r.teacher.name.trim();
    final initial = name.replaceFirst(RegExp(r'^أ\.\s*'), '').trim();

    Widget status;
    if (r.done) {
      status = _chip('صُرف', AppColors.success);
    } else if (noPay) {
      status = _chip('حدد الأجر', AppColors.danger);
    } else {
      status = _chip('مفتوح', AppColors.muted);
    }

    final deltas = <Widget>[
      if (c.absence > 0) _chip('غياب −${c.absence}', AppColors.danger),
      if (c.advance > 0) _chip('سلفة −${c.advance}', AppColors.danger),
      if (c.other > 0) _chip('خصم −${c.other}', AppColors.danger),
      if (a.extra > 0) _chip('إضافة +${a.extra}', AppColors.success),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open ? _expanded.remove(r.teacher.id) : _expanded.add(r.teacher.id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.08), shape: BoxShape.circle),
                    child: Text(initial.isEmpty ? '؟' : initial.substring(0, 1), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.heading)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              r.teacher.isAdminStaff ? 'إدارة · ${_typeLabel(pay)}' : _typeLabel(pay),
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                            if (r.calc.warnings.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: r.calc.warnings.join('\n'),
                                triggerMode: TooltipTriggerMode.tap,
                                child: const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF475569)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: '${a.net}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.heading),
                          children: const [TextSpan(text: ' شيكل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.muted))],
                        ),
                      ),
                      const SizedBox(height: 4),
                      status,
                    ],
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          ),
          if (!open && deltas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: deltas),
            ),
          if (open) ...[
            Divider(height: 1, thickness: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
              child: Column(
                children: [
                  if (noPay)
                    _line('الراتب', 0, onTap: () => _editSalary(r))
                  else
                    _line('الراتب', a.salary, onTap: r.done ? null : () => _editSalary(r)),
                  _line(
                    applies && !r.done && r.calc.absent > 0 ? 'غياب (${r.calc.absent} يوم)' : 'غياب',
                    c.absence,
                    sign: c.absence > 0 ? '−' : '',
                    color: c.absence > 0 ? AppColors.danger : AppColors.faint,
                    onTap: !r.done && applies
                        ? () => _editNumber(
                              r,
                              title: 'أيام الغياب المخصومة',
                              current: r.calc.absent.toDouble(),
                              onSave: (v) {
                                final days = v ?? 0;
                                final next = days == r.calc.attendanceAbsent ? null : days;
                                if (next != r.entry?.absentDays) _save(r, {'absent_days': next});
                              },
                            )
                        : null,
                  ),
                  _line(
                    'سلفة',
                    c.advance,
                    sign: c.advance > 0 ? '−' : '',
                    color: c.advance > 0 ? AppColors.danger : AppColors.faint,
                    onTap: !r.done && r.calc.advanceBalance > 0
                        ? () => _editNumber(
                              r,
                              title: 'مقتطع السلفة (باقي ${trimNum(r.calc.advanceBalance)})',
                              current: c.advance.toDouble(),
                              hint: 'فارغ = تلقائي',
                              onSave: (v) => _save(r, {'advance_recovered': v?.roundToDouble()}),
                            )
                        : null,
                  ),
                  _line(
                    'خصم',
                    c.other,
                    sign: c.other > 0 ? '−' : '',
                    color: c.other > 0 ? AppColors.danger : AppColors.faint,
                    onTap: r.done
                        ? null
                        : () => _editNumber(
                              r,
                              title: 'خصم ${monthLabel(month)}',
                              current: c.other.toDouble(),
                              onSave: (v) => _save(r, {'adjustments': _withAdjustment(r, -1, (v ?? 0).roundToDouble())}),
                            ),
                  ),
                  _line(
                    'إضافة',
                    a.extra,
                    sign: a.extra > 0 ? '+' : '',
                    color: a.extra > 0 ? AppColors.success : AppColors.faint,
                    onTap: r.done
                        ? null
                        : () => _editNumber(
                              r,
                              title: 'إضافة ${monthLabel(month)}',
                              current: a.extra.toDouble(),
                              onSave: (v) => _save(r, {'adjustments': _withAdjustment(r, 1, (v ?? 0).roundToDouble())}),
                            ),
                  ),
                  Divider(height: 1, thickness: 1, color: AppColors.line),
                  _line('الصافي', a.net, strong: true),
                ],
              ),
            ),
          ],
          if (r.done && r.payout != null)
            InkWell(
              onTap: () => ExpenseVoucher.open(context, ExpenseVoucher.fromPayout(r.payout!, fallbackName: r.teacher.name)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: AppColors.sunken, border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.heading),
                    const SizedBox(width: 6),
                    Text('عرض سند الصرف', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.heading)),
                  ],
                ),
              ),
            )
          else if (r.payable)
            InkWell(
              onTap: busy ? null : () => _pay([r]),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.06), border: Border(top: BorderSide(color: AppColors.line))),
                child: Center(
                  child: Text('صرف الراتب', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// شريط الشهر: السابق يميناً والتالي يساراً (لا تالي بعد الشهر الحالي).
  Widget _monthBar(String today, int workDays) {
    final months = payrollMonths(today);
    final i = months.indexOf(month);
    void go(String m) {
      setState(() {
        month = m;
        rows = null;
        _expanded.clear();
      });
      _load();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'الشهر السابق',
            icon: const Icon(Icons.chevron_left),
            onPressed: i >= 0 && i < months.length - 1 ? () => go(months[i + 1]) : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(monthLabel(month), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.heading)),
                Text('$workDays يوم دوام', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            icon: const Icon(Icons.chevron_right),
            onPressed: i > 0 ? () => go(months[i - 1]) : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    final open = (list ?? const <_Row>[]).where((r) => r.payable).toList();
    final today = isoDate(DateTime.now());
    final workDays = payrollWorkDays(month, settings.weekend, calendar).length;
    final total = (list ?? const <_Row>[]).fold<double>(0, (n, r) => n + r.amount);
    final paid = (list ?? const <_Row>[]).where((r) => r.done).fold<double>(0, (n, r) => n + r.amount);
    final remaining = open.fold<double>(0, (n, r) => n + r.amount);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الرواتب'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'advance':
                  _advance();
                case 'pdf':
                  _export(false);
                case 'xlsx':
                  _export(true);
                case 'settings':
                  _settings();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'advance', child: Text('سلفة')),
              PopupMenuItem(value: 'pdf', child: Text('تنزيل PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('تنزيل Excel')),
              PopupMenuItem(value: 'settings', child: Text('الإعدادات')),
            ],
          ),
        ],
      ),
      // «صرف الكل» ثابت أسفل الشاشة في متناول الإبهام، ومعه مجموع ما سيُصرف
      bottomNavigationBar: open.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
                child: PrimaryButton(
                  label: 'صرف الكل (${open.length}) · ${trimNum(remaining)} شيكل',
                  expand: true,
                  height: 48,
                  busy: busy,
                  onPressed: busy ? null : () => _pay(open),
                ),
              ),
            ),
      body: failed
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: NoonOffline(what: 'الرواتب', onRetry: _load)),
            )
          : list == null
              ? const NLoading(text: 'جارٍ تحميل الرواتب')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _monthBar(today, workDays),
                    const SizedBox(height: 12),
                    AdminHero(
                      label: 'صافي رواتب ${monthLabel(month)}',
                      icon: Icons.payments_outlined,
                      value: trimNum(total),
                      unit: 'شيكل',
                      end: '${list.length} موظف',
                      tone: remaining > 0 ? HeroTone.theme : HeroTone.paid,
                      chips: ['المصروف ${trimNum(paid)}', 'المتبقي ${trimNum(remaining)}'],
                    ),
                    const SizedBox(height: 14),
                    if (list.isEmpty)
                      const EmptyNote('لا موظفين')
                    else
                      for (final r in list) _card(r),
                  ],
                ),
    );
  }
}
