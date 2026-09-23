import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/portal.dart';
import '../data/printing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// تبويب «صفي» — قائمة ودجات داخل ListView.
List<Widget> teacherHomeroomTabChildren({
  required List<HomeroomClass> homerooms,
  required PortalBranding branding,
  required PortalService service,
  required Color accent,
}) {
  if (homerooms.isEmpty) {
    return [
      const SizedBox(height: 48),
      const Icon(Icons.groups_outlined, size: 40, color: AppColors.faint),
      const SizedBox(height: 12),
      const Text(
        'لست مربياً لأي شعبة هذا العام',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text),
      ),
      const SizedBox(height: 6),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'عندما تُعيَّن مربياً لشعبة تظهر هنا قائمة طلابها وكلمات المرور والدرجات.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45),
        ),
      ),
    ];
  }

  return [
    for (final h in homerooms) ...[
      _HomeroomCard(
        homeroom: h,
        branding: branding,
        service: service,
        accent: accent,
      ),
      const SizedBox(height: 12),
    ],
  ];
}

class _HomeroomCard extends StatelessWidget {
  const _HomeroomCard({
    required this.homeroom,
    required this.branding,
    required this.service,
    required this.accent,
  });

  final HomeroomClass homeroom;
  final PortalBranding branding;
  final PortalService service;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final room = homeroom.room;
    final students = homeroom.students;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Corner.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.class_outlined, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name.isEmpty ? 'شعبة' : room.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        [
                          if (room.gradeLevel.isNotEmpty) room.gradeLevel,
                          '${students.length} طالب',
                        ].join('  ·  '),
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (students.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => printHomeroomRoster(
                        context,
                        branding: branding,
                        room: room,
                        students: students,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('كشف الصف', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.line),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => printHomeroomPasswords(
                        context,
                        branding: branding,
                        room: room,
                        students: students,
                      ),
                      icon: const Icon(Icons.vpn_key_outlined, size: 16),
                      label: const Text('كلمات المرور', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.line),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: AppColors.line),
          if (students.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'لا طلاب في هذه الشعبة بعد',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            )
          else
            for (var i = 0; i < students.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
              InkWell(
                onTap: () => showHomeroomStudentSheet(
                  context,
                  student: students[i],
                  room: room,
                  branding: branding,
                  service: service,
                  accent: accent,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}', style: AppText.label),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              students[i].fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body,
                            ),
                            if (students[i].phone.trim().isNotEmpty)
                              Text(
                                students[i].phone.trim(),
                                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left, size: 18, color: AppColors.faint),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

Future<void> showHomeroomStudentSheet(
  BuildContext context, {
  required Student student,
  required PortalRoom room,
  required PortalBranding branding,
  required PortalService service,
  required Color accent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
    ),
    builder: (ctx) => _HomeroomStudentSheet(
      student: student,
      room: room,
      branding: branding,
      service: service,
      accent: accent,
    ),
  );
}

class _HomeroomStudentSheet extends StatefulWidget {
  const _HomeroomStudentSheet({
    required this.student,
    required this.room,
    required this.branding,
    required this.service,
    required this.accent,
  });

  final Student student;
  final PortalRoom room;
  final PortalBranding branding;
  final PortalService service;
  final Color accent;

  @override
  State<_HomeroomStudentSheet> createState() => _HomeroomStudentSheetState();
}

class _HomeroomStudentSheetState extends State<_HomeroomStudentSheet> {
  List<StudentEvaluation>? evals;
  Map<String, String>? attendance;
  String? loadError;
  bool loadingExtra = true;

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  Future<void> _loadExtra() async {
    setState(() {
      loadingExtra = true;
      loadError = null;
    });
    try {
      final now = DateTime.now();
      final dates = [
        for (var i = 0; i < 30; i++)
          isoDate(now.subtract(Duration(days: i))),
      ];
      final results = await Future.wait([
        widget.service.studentEvaluations(widget.student.id),
        widget.service.studentAttendanceMarks(
          studentId: widget.student.id,
          roomId: widget.room.id,
          dates: dates,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        evals = results[0] as List<StudentEvaluation>;
        attendance = results[1] as Map<String, String>;
        loadingExtra = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = 'تعذّر جلب الدرجات أو الحضور';
        loadingExtra = false;
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) {
      showAppSnack(context, 'لا يوجد $label بعد', error: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (mounted) showAppSnack(context, 'تم نسخ $label');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final present = attendance?.values.where((v) => v == 'present').length ?? 0;
    final absent = attendance?.values.where((v) => v == 'absent').length ?? 0;
    final excused = attendance?.values.where((v) => v == 'excused').length ?? 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(s.fullName, style: AppText.cardTitle),
                const SizedBox(height: 4),
                Text(
                  [
                    if (widget.room.gradeLevel.isNotEmpty) widget.room.gradeLevel,
                    if (widget.room.name.isNotEmpty) widget.room.name,
                  ].join('  ·  '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _sectionTitle('التواصل'),
                _infoRow('هاتف الطالب', s.phone.trim().isEmpty ? '—' : s.phone.trim()),
                _infoRow('ولي الأمر', s.parentName.trim().isEmpty ? '—' : s.parentName.trim()),
                _infoRow(
                  'هاتف ولي الأمر',
                  s.parentPhone.trim().isEmpty ? '—' : s.parentPhone.trim(),
                ),
                _infoRow(
                  'هوية الطالب',
                  s.nationalId.trim().isEmpty ? '—' : s.nationalId.trim(),
                ),
                const SizedBox(height: 14),
                _sectionTitle('بيانات الدخول'),
                _codeRow(
                  'كلمة مرور الطالب',
                  s.portalCode,
                  onCopy: () => _copy('كلمة مرور الطالب', s.portalCode),
                ),
                _codeRow(
                  'كلمة مرور ولي الأمر',
                  s.parentPortalCode,
                  onCopy: () => _copy('كلمة مرور ولي الأمر', s.parentPortalCode),
                ),
                const SizedBox(height: 14),
                _sectionTitle('الحضور (آخر 30 يوماً)'),
                if (loadingExtra)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (loadError != null)
                  Text(loadError!, style: const TextStyle(color: AppColors.danger, fontSize: 12))
                else
                  Text(
                    'حاضر $present  ·  غائب $absent  ·  بعذر $excused',
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                const SizedBox(height: 14),
                _sectionTitle('الدرجات'),
                if (loadingExtra)
                  const SizedBox.shrink()
                else if (evals == null || evals!.isEmpty)
                  const Text(
                    'لا درجات مرصودة بعد',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  )
                else
                  for (final e in evals!.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.title.trim().isEmpty ? 'تقييم' : e.title.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          Text(
                            e.maxScore > 0
                                ? '${_trimNum(e.score ?? 0)} / ${_trimNum(e.maxScore)}'
                                : _trimNum(e.score ?? 0),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: widget.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: AppColors.navy,
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _codeRow(String label, String code, {required VoidCallback onCopy}) {
    final empty = code.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(
                  empty ? 'بلا رمز' : code.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: empty ? 0 : 1.2,
                    color: empty ? AppColors.faint : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: empty ? null : onCopy,
            icon: const Icon(Icons.copy_outlined, size: 18),
            color: AppColors.navy,
          ),
        ],
      ),
    );
  }
}

String _trimNum(num n) {
  if (n == n.roundToDouble()) return '${n.round()}';
  return n.toStringAsFixed(1);
}

/// كشف طلاب شعبة المربي PDF.
Future<void> printHomeroomRoster(
  BuildContext context, {
  required PortalBranding branding,
  required PortalRoom room,
  required List<Student> students,
}) {
  return runBusyOp(context, () async {
    final title = 'كشف طلاب ${room.name}';
    final bytes = await PdfKit.buildSafe(
      title: title,
      institutionName: branding.name,
      logoBase64: branding.logo.isEmpty ? null : branding.logo,
      subtitle: room.gradeLevel.isEmpty ? 'مربي الصف' : '${room.gradeLevel} · مربي الصف',
      body: (_) => [
        PdfKit.table(
          headers: const ['م', 'اسم الطالب', 'الهاتف', 'ولي الأمر', 'هاتف ولي الأمر'],
          rows: [
            for (var i = 0; i < students.length; i++)
              [
                '${i + 1}',
                students[i].fullName,
                students[i].phone.trim().isEmpty ? '-' : students[i].phone.trim(),
                students[i].parentName.trim().isEmpty ? '-' : students[i].parentName.trim(),
                students[i].parentPhone.trim().isEmpty ? '-' : students[i].parentPhone.trim(),
              ],
          ],
          flex: const [1, 4, 3, 3, 3],
          ltrColumns: const {2, 4},
        ),
      ],
      endMatter: [
        PdfKit.signatureRow(const ['مربي الصف', 'الإدارة']),
      ],
    );
    if (bytes == null || !context.mounted) return;
    await PdfKit.share(bytes, 'roster_${room.id}.pdf');
  });
}

/// كلمات مرور بوابة شعبة المربي PDF.
Future<void> printHomeroomPasswords(
  BuildContext context, {
  required PortalBranding branding,
  required PortalRoom room,
  required List<Student> students,
}) {
  return runBusyOp(context, () async {
    final bytes = await PdfKit.buildSafe(
      title: 'كلمات مرور البوابة — ${room.name}',
      institutionName: branding.name,
      logoBase64: branding.logo.isEmpty ? null : branding.logo,
      subtitle: room.gradeLevel.isEmpty ? null : room.gradeLevel,
      body: (_) => [
        PdfKit.table(
          headers: const [
            'م',
            'اسم الطالب',
            'هوية الطالب',
            'مرور الطالب',
            'هوية ولي الأمر',
            'مرور ولي الأمر',
          ],
          rows: [
            for (var i = 0; i < students.length; i++)
              [
                '${i + 1}',
                students[i].fullName,
                students[i].nationalId.trim().isEmpty ? '-' : students[i].nationalId.trim(),
                students[i].portalCode.trim().isEmpty ? '-' : students[i].portalCode.trim(),
                students[i].parentNationalId.trim().isEmpty ? '-' : students[i].parentNationalId.trim(),
                students[i].parentPortalCode.trim().isEmpty ? '-' : students[i].parentPortalCode.trim(),
              ],
          ],
          flex: const [1, 4, 3, 3, 3, 3],
          ltrColumns: const {2, 3, 4, 5},
          accentColumns: const {3, 5},
        ),
      ],
    );
    if (bytes == null || !context.mounted) return;
    await PdfKit.share(bytes, 'passwords_${room.id}.pdf');
  });
}
