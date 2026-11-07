import 'package:flutter/material.dart';

import '../data/grade_approval.dart';
import '../data/grade_publish.dart';
import '../data/payroll_calc.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../data/user_message.dart';
import '../data/year_closing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/finance_documents.dart';
import '../widgets/widgets.dart';
import 'student_promotion_sheet.dart';

double _round2(num n) => (n * 100).round() / 100;

/// إقفال السنة المالية — `YearCloseModal`: رصيد كل حساب آخرها كما حُسب، ويُكتب
/// المعدود فعلاً إن اختلف، فيصير افتتاحياً للسنة التالية. إعادة الإقفال تكتب فوقه،
/// و«فتح الإقفال» يعيد السنة مفتوحة.
Future<void> showYearCloseSheet(
  BuildContext context,
  AppStore store, {
  required AcademicYear year,
  required YearBalances wallets,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _YearCloseSheet(store: store, year: year, wallets: wallets),
  );
}

class _YearCloseSheet extends StatefulWidget {
  const _YearCloseSheet({required this.store, required this.year, required this.wallets});

  final AppStore store;
  final AcademicYear year;
  final YearBalances wallets;

  @override
  State<_YearCloseSheet> createState() => _YearCloseSheetState();
}

class _YearCloseSheetState extends State<_YearCloseSheet> {
  late final List<String> methods;
  final counted = <String, TextEditingController>{};
  bool busy = false;

  YearBalances get w => widget.wallets;

  @override
  void initState() {
    super.initState();
    methods = {...w.computed.keys, ...?w.closed?.balances.keys}
        .where((m) => (w.computed[m] ?? 0).abs() >= 0.01 || (w.closed?.balances[m] ?? 0).abs() >= 0.01)
        .toList();
    for (final m in methods) {
      final v = w.closed != null && !w.stale ? (w.closed!.balances[m] ?? 0) : (w.computed[m] ?? 0);
      counted[m] = TextEditingController(text: trimNum(v));
    }
  }

  @override
  void dispose() {
    for (final c in counted.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _value(String m) => _round2(double.tryParse(counted[m]!.text.trim()) ?? 0);

  Future<void> _save({bool reopen = false}) async {
    setState(() => busy = true);
    try {
      final store = widget.store;
      if (reopen) {
        await store.reopenYearClosing(widget.year);
      } else {
        await store.closeYearBalances(
          widget.year,
          balances: {for (final m in methods) m: _value(m)},
          computed: w.computed,
        );
      }
      if (!mounted) return;
      showAppSnack(context, reopen ? 'فُتح الإقفال' : 'أُقفلت سنة ${widget.year.label} ورُحّلت أرصدتها');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showAppSnack(context, userMessage(e, 'تعذّر الإقفال'), error: true);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إقفال سنة ${widget.year.label}',
              style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'رصيد كل حساب آخر السنة يصير افتتاحي السنة التالية. اكتب الموجود فعلاً إن اختلف عن المحسوب.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
            if (w.closed != null) ...[
              const SizedBox(height: 6),
              Text(
                w.stale
                    ? 'تغيّرت حركة السنة بعد إقفالها: راجع الأرقام وأعد الإقفال'
                    : 'مقفلة ${w.closed!.at.length >= 10 ? w.closed!.at.substring(0, 10) : ''} · ${w.closed!.by}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: w.stale ? AppColors.amberDark : AppColors.success,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (methods.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'لا حركة في حسابات هذه السنة',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.faint, fontSize: 12),
                ),
              )
            else
              for (final m in methods)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.isEmpty ? 'بلا طريقة' : store.paymentMethodLabel(m),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.heading, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'المحسوب ${webMoney(w.computed[m] ?? 0)}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 104,
                        child: TextField(
                          controller: counted[m],
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true, labelText: 'الموجود فعلاً'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 58,
                        child: () {
                          final diff = _round2(_value(m) - (w.computed[m] ?? 0));
                          return Text(
                            diff == 0 ? '—' : trimNum(diff),
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: diff == 0 ? AppColors.faint : (diff < 0 ? AppColors.danger : AppColors.success),
                            ),
                          );
                        }(),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (w.closed != null) ...[
                  Expanded(
                    child: GhostButton(label: 'فتح الإقفال', onPressed: busy ? null : () => _save(reopen: true)),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: PrimaryButton(
                    label: 'إقفال وترحيل',
                    busy: busy,
                    expand: true,
                    onPressed: busy || methods.isEmpty ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ما يجب حسمه قبل إغلاق السنة — `yearEndChecks`: تنبيهات لا منع.
Future<List<({String label, int count})>> _yearEndChecks(AppStore store, AcademicYear year) async {
  final today = isoDate(DateTime.now());
  final tests = store.settings.gradesPublishManual
      ? pendingTests(
          [
            for (final e in store.evaluations)
              if (e.evaluationDate.compareTo(year.startsOn) >= 0 &&
                  (year.endsOn.isEmpty || e.evaluationDate.compareTo(year.endsOn) <= 0))
                (groupId: e.groupId, subjectId: e.subjectId, teacherId: e.teacherId, title: e.title, date: e.evaluationDate),
          ],
          store.settings.gradesApproved,
        ).length
      : 0;

  // كل موظف بأجر وكل شهر من أشهر السنة حتى اليوم بلا راتب مصروف
  var unpaid = 0;
  final entries = await PayrollEntries.all() ?? const <PayrollEntryRow>[];
  final lastMonth = (year.endsOn.isNotEmpty && year.endsOn.compareTo(today) < 0 ? year.endsOn : today).substring(0, 7);
  final months = <String>[];
  if (year.startsOn.length >= 7) {
    var y = int.parse(year.startsOn.substring(0, 4));
    var m = int.parse(year.startsOn.substring(5, 7));
    while (true) {
      final key = '$y-${m.toString().padLeft(2, '0')}';
      if (key.compareTo(lastMonth) > 0) break;
      if (key.compareTo(today.substring(0, 7)) < 0 || key == lastMonth) months.add(key);
      m = m == 12 ? 1 : m + 1;
      if (m == 1) y++;
    }
  }
  for (final t in store.teachersInViewedYear) {
    for (final month in months) {
      final terms = termsFor(t, month);
      if (!(terms.fixed > 0 || terms.sessionRate > 0 || terms.percent > 0)) continue;
      if (t.contractStart.length >= 7 && t.contractStart.substring(0, 7).compareTo(month) > 0) continue;
      final ids = store.linkedTeacherIds(t.id);
      final paid = alreadyPaid(
        store.teacherPayouts.where((p) => ids.contains(p.teacherId)).toList(),
        entries.where((e) => ids.contains(e.teacherId)).toList(),
        month,
      );
      if (!paid) unpaid++;
    }
  }

  return [
    (label: 'طلبات مالية بانتظار الموافقة', count: store.pendingFinanceRequests.length),
    (label: 'دفعات أهل بانتظار القبول', count: store.pendingPaymentRequests.length),
    (label: 'اختبارات غير معتمدة', count: tests),
    (label: 'رواتب أشهر غير مصروفة (موظف × شهر)', count: unpaid),
  ];
}

/// إغلاق السنة بخطوة واحدة وبترتيبه الصحيح — `YearEndWizard`: فحص، جرد الحسابات
/// وإقفالها، إغلاق السنة الدراسية وفتح التالية، ثم ترقية الطلاب.
Future<void> showYearEndWizard(BuildContext context, AppStore store, AcademicYear year) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _YearEndWizard(store: store, year: year),
  );
}

class _YearEndWizard extends StatefulWidget {
  const _YearEndWizard({required this.store, required this.year});

  final AppStore store;
  final AcademicYear year;

  @override
  State<_YearEndWizard> createState() => _YearEndWizardState();
}

const _steps = ['فحص', 'جرد الحسابات', 'الإغلاق', 'ترقية الطلاب'];

class _YearEndWizardState extends State<_YearEndWizard> {
  int step = 0;
  List<({String label, int count})>? checks;
  bool busy = false;
  AcademicYear? opened;

  AppStore get store => widget.store;
  AcademicYear get year => widget.year;
  YearBalances? get wallets => store.yearBook[year.id];

  @override
  void initState() {
    super.initState();
    _yearEndChecks(store, year).then((value) {
      if (mounted) setState(() => checks = value);
    }).catchError((Object _) {
      if (mounted) setState(() => checks = const []);
    });
  }

  Future<void> _closeYear() async {
    final ok = await confirmSheet(
      context,
      title: 'إغلاق ${year.label}',
      message: 'إغلاق ${year.label} وفتح السنة الجديدة؟ بعده لا تُعدَّل أرقام ${year.label}.',
      confirmLabel: 'إغلاق',
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      final w = wallets;
      if (w?.closed == null) {
        await store.closeYearBalances(year, balances: w?.computed ?? const {}, computed: w?.computed ?? const {});
      }
      final res = await store.closeCurrentAndOpenNext();
      if (!mounted) return;
      setState(() {
        opened = res.opened;
        step = 3;
        busy = false;
      });
    } catch (e) {
      if (mounted) {
        showAppSnack(context, userMessage(e, 'تعذّر إغلاق السنة'), error: true);
        setState(() => busy = false);
      }
    }
  }

  Widget _stepBar() => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < _steps.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: i == step ? AppColors.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${i < step ? '✓' : '${i + 1}'} ${_steps[i]}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: i == step ? Colors.white : (i < step ? AppColors.success : AppColors.faint),
                ),
              ),
            ),
        ],
      );

  Widget _note(String text, {Color color = AppColors.muted, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
        ),
      );

  Widget _body() {
    final w = wallets;
    final hasMoney = w != null && w.computed.values.any((v) => v.abs() >= 0.01);
    final counted = w?.closed != null && !w!.stale;
    switch (step) {
      case 0:
        final open = (checks ?? const <({String label, int count})>[]).where((c) => c.count > 0).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (checks == null)
              _note('جارِ الفحص...')
            else if (open.isEmpty)
              _note('لا شيء معلق', color: AppColors.success, bold: true)
            else ...[
              for (final c in open)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Text(
                        '${c.count}',
                        style: TextStyle(color: AppColors.amberDark, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(c.label, style: TextStyle(color: AppColors.heading, fontSize: 12.5))),
                    ],
                  ),
                ),
              _note('الأفضل حسمها قبل الإغلاق: بعده لا تُكتب حركة بتاريخ السنة.'),
            ],
            PrimaryButton(label: 'التالي', expand: true, onPressed: checks == null ? null : () => setState(() => step = 1)),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasMoney)
              _note('لا حركة في حسابات هذه السنة')
            else if (counted)
              _note('الحسابات مجرودة ومقفلة، وأرصدتها مرحّلة للسنة الجديدة', color: AppColors.success, bold: true)
            else
              _note('اعدّ الموجود في كل حساب (النقد، البنك، المحافظ) واكتبه، فيصير افتتاحي السنة الجديدة.'),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'السابق', onPressed: () => setState(() => step = 0))),
                const SizedBox(width: 8),
                Expanded(
                  child: hasMoney && !counted
                      ? PrimaryButton(
                          label: 'جرد وإقفال',
                          expand: true,
                          onPressed: () async {
                            await showYearCloseSheet(context, store, year: year, wallets: w!);
                            if (mounted) setState(() {});
                          },
                        )
                      : PrimaryButton(label: 'التالي', expand: true, onPressed: () => setState(() => step = 2)),
                ),
              ],
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note('تُغلق ${year.label}، ولا تُكتب بعدها حركة بتاريخها إلا بفتح الإقفال من الأرباح.'),
            _note('تُفتح السنة الجديدة بصفوفها وموادها ومعلميها وخططها، بلا طلاب.'),
            _note('يُحفظ نظام علامات ${year.label} كما هو، وتُزاح مواعيد الرصد سنة.'),
            Row(
              children: [
                Expanded(child: GhostButton(label: 'السابق', onPressed: busy ? null : () => setState(() => step = 1))),
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    label: 'إغلاق ${year.label}',
                    color: AppColors.danger,
                    busy: busy,
                    expand: true,
                    onPressed: busy ? null : _closeYear,
                  ),
                ),
              ],
            ),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(
              'أُغلقت ${year.label}${opened == null ? '' : ' وفُتحت ${opened!.label}'}.',
              color: AppColors.success,
              bold: true,
            ),
            _note('رقِّ الطلاب للسنة الجديدة: من لا يُرقّى يبقى في السنة المغلقة.'),
            GhostButton(label: 'ترقية الطلاب', onPressed: () => showStudentPromotionSheet(context, store)),
            const SizedBox(height: 8),
            PrimaryButton(label: 'تم', expand: true, onPressed: () => Navigator.pop(context)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إغلاق سنة ${year.label}',
              style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            _stepBar(),
            const SizedBox(height: 8),
            _body(),
          ],
        ),
      ),
    );
  }
}
