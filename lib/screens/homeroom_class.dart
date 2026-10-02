import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/arabic_search.dart';
import '../data/grading.dart';
import '../data/institution.dart';
import '../data/portal.dart';
import '../data/doc_export.dart';
import '../data/printing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// «صفي» — المقابل لـ `HomeroomClass.tsx`: مربي الصف يعرف طلاب شعبته — بياناتهم
/// ودرجاتهم — ويسلّمهم رمزي الدخول (الطالب وولي الأمر). لا شيء مالي هنا.
class HomeroomClassView extends StatefulWidget {
  const HomeroomClassView({
    super.key,
    required this.data,
    required this.loading,
    required this.error,
    required this.onReload,
    required this.branding,
  });

  final HomeroomClassData? data;
  final bool loading;
  final String error;
  final VoidCallback onReload;
  final PortalBranding branding;

  @override
  State<HomeroomClassView> createState() => _HomeroomClassViewState();
}

String _credentialsText(HomeroomStudent s, String school) => [
      'بيانات الدخول إلى بوابة $school',
      'الطالب: ${s.name}',
      'رقم الهوية: ${s.nationalId.isEmpty ? '—' : s.nationalId}',
      'كلمة مرور الطالب: ${s.portalCode.isEmpty ? '—' : s.portalCode}',
      'كلمة مرور ولي الأمر: ${s.parentPortalCode.isEmpty ? '—' : s.parentPortalCode}',
    ].join('\n');

class _HomeroomClassViewState extends State<HomeroomClassView> {
  String roomId = '';
  String? openId;
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  HomeroomRoom? get _room {
    final rooms = widget.data?.rooms ?? const [];
    return rooms.where((r) => r.id == roomId).firstOrNull ?? rooms.firstOrNull;
  }

  Future<void> _print(HomeroomRoom room, List<HomeroomStudent> students) {
    final school = widget.branding.name;
    return runBusyOp(context, () async {
      final title = 'بطاقات الدخول — ${room.label}';
      final bytes = await PdfKit.buildSafe(
        title: title,
        institutionName: school,
        logoBase64: widget.branding.logo,
        header: (_) => PdfKit.docHeader(
          institution: school,
          title: title,
          academicYearLabel: academicYear(),
          dateLabel: isoDate(DateTime.now()),
          logo: PdfKit.decodeImage(widget.branding.logo),
        ),
        body: (_) => [
          PdfKit.table(
            headers: const ['م', 'اسم الطالب', 'رقم الهوية', 'مرور الطالب', 'مرور ولي الأمر'],
            rows: [
              for (var i = 0; i < students.length; i++)
                [
                  '${i + 1}',
                  students[i].name,
                  students[i].nationalId.isEmpty ? '-' : students[i].nationalId,
                  students[i].portalCode.isEmpty ? '-' : students[i].portalCode,
                  students[i].parentPortalCode.isEmpty ? '-' : students[i].parentPortalCode,
                ],
            ],
            flex: const [1, 5, 3, 3, 3],
            ltrColumns: const {2, 3, 4},
            accentColumns: const {3, 4},
          ),
        ],
        endMatter: <pw.Widget>[],
      );
      if (!mounted) return;
      if (bytes == null) {
        showAppSnack(context, 'تعذّر تجهيز البطاقات', error: true);
        return;
      }
      try {
        // بلا انتظار: مؤشر التجهيز يُغلق ويُختار الإجراء فوقه
      DocExport.showActions(context, bytes, PdfKit.fileName(title));
      } catch (_) {
        if (mounted) showAppSnack(context, 'تعذّر تنزيل البطاقات', error: true);
      }
    }, message: 'جارٍ تجهيز البطاقات...');
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (widget.loading && data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (widget.error.isNotEmpty && data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Text(widget.error, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 12)),
            TextButton(onPressed: widget.onReload, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    final room = _room;
    if (data == null || room == null) {
      return const EmptyState(message: 'لست مربياً لأي شعبة', icon: Icons.groups_outlined);
    }

    final roomStudents = [for (final s in data.students) if (s.roomId == room.id) s];
    final q = search.text.trim();
    final shown = [
      for (final s in roomStudents)
        if (q.isEmpty || matchArabicName(s.name, q) || s.nationalId.contains(q)) s,
    ];
    final evalsByStudent = <String, List<StudentEvaluation>>{};
    for (final e in data.evaluations) {
      evalsByStudent.putIfAbsent(e.studentId, () => []).add(e);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: data.rooms.length > 1
                        ? AppDropdown<String>(
                            value: room.id,
                            items: [for (final r in data.rooms) DropdownMenuItem(value: r.id, child: Text(r.label))],
                            onChanged: (v) => setState(() {
                              roomId = v ?? roomId;
                              openId = null;
                            }),
                          )
                        : Text(room.label, style: AppText.title),
                  ),
                  const SizedBox(width: 8),
                  Text('${roomStudents.length} طالب', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: search,
                      hint: 'الاسم أو رقم الهوية',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'بطاقات الدخول',
                    onPressed: roomStudents.isEmpty ? null : () => _print(room, roomStudents),
                    icon: const Icon(Icons.print_outlined, color: AppColors.muted),
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: widget.loading ? null : widget.onReload,
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          EmptyState(message: roomStudents.isEmpty ? 'لا طلاب في هذه الشعبة' : 'لا نتائج', icon: Icons.person_search_outlined)
        else
          for (var i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StudentCard(
                student: shown[i],
                index: i,
                open: openId == shown[i].id,
                onToggle: () => setState(() => openId = openId == shown[i].id ? null : shown[i].id),
                evaluations: evalsByStudent[shown[i].id] ?? const [],
                subjects: data.subjects,
                branding: widget.branding,
              ),
            ),
      ],
    );
  }
}

class _StudentCard extends StatefulWidget {
  const _StudentCard({
    required this.student,
    required this.index,
    required this.open,
    required this.onToggle,
    required this.evaluations,
    required this.subjects,
    required this.branding,
  });

  final HomeroomStudent student;
  final int index;
  final bool open;
  final VoidCallback onToggle;
  final List<StudentEvaluation> evaluations;
  final Map<String, String> subjects;
  final PortalBranding branding;

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool showCodes = false;

  String _mask(String v) => v.isEmpty ? '—' : (showCodes ? v : '••••••');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _credentialsText(widget.student, widget.branding.name)));
    if (mounted) showAppSnack(context, 'تم النسخ');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final accent = parseHexColor(widget.branding.colors.primaryButton) ?? AppColors.heading;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: accent.withAlpha(0x14), borderRadius: BorderRadius.circular(8)),
                    child: Text('${widget.index + 1}', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 11.5)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        Text(s.nationalId.isEmpty ? '—' : s.nationalId, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                  Icon(widget.open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.faint),
                ],
              ),
            ),
          ),
          if (widget.open)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Info('تاريخ الميلاد', s.birthDate, mono: true),
                  _Info('الجنس', s.gender),
                  _Info('جوال الطالب', s.phone, mono: true),
                  _Info('ولي الأمر', [s.parentName, if (s.guardianRelationship.isNotEmpty) '(${s.guardianRelationship})'].where((v) => v.isNotEmpty).join(' ')),
                  _Info('جوال ولي الأمر', s.parentPhone, mono: true),
                  _Info('جوال بديل', s.parentSecondaryPhone, mono: true),
                  _Info('العنوان', [s.neighborhood, s.detailedAddress].where((v) => v.isNotEmpty).join(' — ')),
                  _Info('الحالة الصحية', [s.healthStatus, s.medicalCondition].where((v) => v.isNotEmpty).join(' — ')),
                  if (s.parentPhone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    GhostButton(label: 'اتصال بولي الأمر', icon: Icons.call_outlined, onPressed: () => launchTel(s.parentPhone)),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.sunken,
                      borderRadius: BorderRadius.circular(Corner.box),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key_outlined, size: 15, color: AppColors.heading),
                            const SizedBox(width: 6),
                            const Expanded(child: Text('بيانات الدخول', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                            TextButton.icon(
                              onPressed: () => setState(() => showCodes = !showCodes),
                              icon: Icon(showCodes ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 15),
                              label: Text(showCodes ? 'إخفاء' : 'إظهار', style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                        _Info('رقم الهوية', s.nationalId.isEmpty ? '—' : s.nationalId, mono: true),
                        _Info('كلمة مرور الطالب', _mask(s.portalCode), mono: true),
                        _Info('كلمة مرور ولي الأمر', _mask(s.parentPortalCode), mono: true),
                        if (s.portalCode.isEmpty || s.parentPortalCode.isEmpty)
                          Text('كلمة مرور غير مولّدة', style: TextStyle(color: AppColors.amberDark, fontSize: 10.5)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: GhostButton(label: 'نسخ', icon: Icons.copy_outlined, onPressed: _copy)),
                            if (s.parentPhone.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: PrimaryButton(
                                  label: 'واتساب',
                                  color: const Color(0xFF059669),
                                  onPressed: () => launchWaWithText(s.parentPhone, _credentialsText(s, widget.branding.name)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('الدرجات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  const SizedBox(height: 6),
                  _Grades(evaluations: widget.evaluations, subjects: widget.subjects, scheme: widget.branding.gradingScheme),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, fontFamily: mono ? 'monospace' : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// درجات الطالب بنظام علامات المدرسة: ف1 وف2 والسنة لكل مادة، وإلا المعدلات الشهرية.
class _Grades extends StatelessWidget {
  const _Grades({required this.evaluations, required this.subjects, required this.scheme});

  final List<StudentEvaluation> evaluations;
  final Map<String, String> subjects;
  final GradingScheme scheme;

  @override
  Widget build(BuildContext context) {
    final summaries = subjectGradeSummaries(
      [for (final e in evaluations) e.toEvaluation()],
      scheme,
      (id) => subjects[id] ?? 'مادة',
    )..sort((a, b) => a.subjectName.compareTo(b.subjectName));

    if (summaries.isEmpty) {
      final monthly = [for (final e in evaluations) if (e.type == 'monthly' && e.subjectId.isEmpty) e]
        ..sort((a, b) => b.evaluationDate.compareTo(a.evaluationDate));
      if (monthly.isEmpty) return const Text('لا درجات بعد', style: TextStyle(color: AppColors.faint, fontSize: 11));
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in monthly)
            StatusChip.muted(
              '${e.title.isNotEmpty ? e.title : (e.evaluationDate.length >= 7 ? e.evaluationDate.substring(0, 7) : e.evaluationDate)}: '
              '${(e.score ?? 0).round()}/${e.maxScore.round()}',
            ),
        ],
      );
    }

    String term(TermGrade t) =>
        t.components.isEmpty || t.currentScore == null ? '—' : '${(t.isComplete ? t.termScore : t.currentScore!).round()}';
    const head = TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700);
    const cell = TextStyle(fontSize: 11.5, fontFamily: 'monospace');
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Corner.box), border: Border.all(color: AppColors.line)),
      child: Column(
        children: [
          Container(
            color: AppColors.sunken,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: const Row(
              children: [
                Expanded(child: Text('المادة', style: head)),
                SizedBox(width: 40, child: Text('ف1', textAlign: TextAlign.center, style: head)),
                SizedBox(width: 40, child: Text('ف2', textAlign: TextAlign.center, style: head)),
                SizedBox(width: 50, child: Text('السنة', textAlign: TextAlign.center, style: head)),
              ],
            ),
          ),
          for (final r in summaries)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${r.subjectName} /${r.fullMark.round()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                  ),
                  SizedBox(width: 40, child: Text(term(r.term1), textAlign: TextAlign.center, style: cell)),
                  SizedBox(width: 40, child: Text(term(r.term2), textAlign: TextAlign.center, style: cell)),
                  SizedBox(
                    width: 50,
                    child: Text(
                      r.yearGrade == null ? '—' : '${r.yearGrade!.percent.round()}%',
                      textAlign: TextAlign.center,
                      style: cell.copyWith(fontWeight: FontWeight.w800),
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
