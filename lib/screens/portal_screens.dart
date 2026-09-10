import 'package:flutter/material.dart';

import '../data/institution.dart';
import '../data/portal.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/widgets.dart';

/// ترويسة موحّدة لبوابتَي الطالب والمعلم.
class _PortalBar extends StatelessWidget {
  const _PortalBar({required this.branding, required this.user, required this.onExit});

  final PortalBranding branding;
  final PortalUser user;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final side = parseHexColor(branding.colors.sidebarBg) ?? AppColors.navy;

    return Container(
      padding: EdgeInsets.fromLTRB(14, top + 10, 14, 10),
      color: side,
      child: Row(
        children: [
          InstitutionBadge(logo: branding.logo, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.isTeacher ? 'بوابة المعلم' : 'بوابة الطالب'} · ${branding.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          PressableScale(
            onTap: onExit,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 13, color: Colors.white),
                  SizedBox(width: 5),
                  Text('خروج', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sectionCard({required String title, required IconData icon, required List<Widget> children}) {
  return AppCard(
    padding: const EdgeInsets.all(Gap.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.amber),
            const SizedBox(width: 7),
            Text(title, style: AppText.cardTitle),
          ],
        ),
        const SizedBox(height: Gap.md),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        const SizedBox(height: Gap.md),
        ...children,
      ],
    ),
  );
}

Widget _empty(String message) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(message, style: AppText.muted, textAlign: TextAlign.center),
    );

// ══════════════════════════════════════════════════════════════════════════
// بوابة الطالب
// ══════════════════════════════════════════════════════════════════════════

class StudentPortalScreen extends StatefulWidget {
  const StudentPortalScreen({super.key, required this.user, required this.onExit});

  final PortalUser user;
  final VoidCallback onExit;

  @override
  State<StudentPortalScreen> createState() => _StudentPortalScreenState();
}

class _StudentPortalScreenState extends State<StudentPortalScreen> {
  StudentPortalData? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await const PortalService().studentData(widget.user);
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
        if (result == null) error = 'تعذّر جلب بيانات الطالب.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _PortalBar(branding: branding, user: widget.user, onExit: widget.onExit),
          Expanded(
            child: loading
                ? Center(child: CircularProgressIndicator(color: AppColors.amber))
                : error != null
                    ? _error()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                          children: _sections(data!),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _error() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 34, color: AppColors.faint),
            const SizedBox(height: 10),
            Text(error!, style: AppText.muted),
            const SizedBox(height: 14),
            GhostButton(label: 'إعادة المحاولة', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );

  List<Widget> _sections(StudentPortalData d) {
    final f = d.finance;
    return [
      // الحالة المالية
      _sectionCard(
        title: 'الحالة المالية',
        icon: Icons.account_balance_wallet_outlined,
        children: [
          Row(
            children: [
              Expanded(child: _figure('المطلوب', f.totalDue, AppColors.heading)),
              Expanded(child: _figure('المسدَّد', f.totalPaid, AppColors.success)),
              Expanded(
                child: _figure('المتبقي', f.remaining, f.remaining > 0 ? AppColors.danger : AppColors.success),
              ),
            ],
          ),
          if (f.installments.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            for (final i in f.installments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(i.title, style: AppText.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('استحقاق ${formatDate(i.dueDate)}', style: AppText.label),
                    const SizedBox(width: 8),
                    i.isPaid ? StatusChip.success('مسدَّد') : StatusChip.danger(money(i.remaining)),
                  ],
                ),
              ),
          ],
        ],
      ),
      const SizedBox(height: Gap.md),

      // سندات القبض
      _sectionCard(
        title: 'سندات القبض (${f.payments.length})',
        icon: Icons.receipt_long_outlined,
        children: f.payments.isEmpty
            ? [_empty('لا توجد دفعات مسجّلة بعد.')]
            : [
                for (final p in f.payments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Text(p.receiptNumber, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(formatDate(p.date), style: AppText.label)),
                        Text(money(p.amount),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.success)),
                      ],
                    ),
                  ),
              ],
      ),
      const SizedBox(height: Gap.md),

      // الحضور
      _sectionCard(
        title: 'الحضور والالتزام',
        icon: Icons.fact_check_outlined,
        children: [
          Row(
            children: [
              Expanded(child: _count('حاضر', d.attendance.present, AppColors.success)),
              Expanded(child: _count('غائب', d.attendance.absent, AppColors.danger)),
              Expanded(child: _count('الالتزام %', d.attendance.rate, AppColors.heading)),
            ],
          ),
          if (d.attendance.records.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            for (final r in d.attendance.records.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(r.date, style: AppText.muted)),
                    _statusChip(r.status),
                  ],
                ),
              ),
          ],
        ],
      ),
      const SizedBox(height: Gap.md),

      // المواد والمعلمون
      _sectionCard(
        title: 'المواد والمعلمون',
        icon: Icons.menu_book_outlined,
        children: d.subjects.isEmpty
            ? [_empty('لا توجد مواد مسجّلة.')]
            : [
                for (final s in d.subjects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.subjectName, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            if (s.teacherName.isNotEmpty) s.teacherName,
                            if (s.groupName.isNotEmpty) s.groupName,
                            if (s.startTime.isNotEmpty) '${s.startTime} - ${s.endTime}',
                            if (s.roomName.isNotEmpty) s.roomName,
                          ].join('  ·  '),
                          style: AppText.label,
                        ),
                      ],
                    ),
                  ),
              ],
      ),
      const SizedBox(height: Gap.md),

      // التقييمات
      _sectionCard(
        title: 'التقييمات (${d.evaluations.length})',
        icon: Icons.star_outline,
        children: d.evaluations.isEmpty
            ? [_empty('لا توجد تقييمات بعد.')]
            : [
                for (final e in d.evaluations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.notes.isEmpty ? 'تقييم' : e.notes, style: AppText.body)),
                        if (e.score != null) StatusChip.amber(e.score!.toStringAsFixed(0)),
                      ],
                    ),
                  ),
              ],
      ),
      const SizedBox(height: Gap.md),

      // إعلانات الصف
      _sectionCard(
        title: 'إعلانات الصف (${d.announcements.length})',
        icon: Icons.campaign_outlined,
        children: d.announcements.isEmpty
            ? [_empty('لا توجد إعلانات.')]
            : [
                for (final a in d.announcements) _announcement(a),
              ],
      ),
    ];
  }

  Widget _figure(String label, double value, Color color) => Column(
        children: [
          Text(label, style: AppText.label),
          const SizedBox(height: 3),
          Text(money(value), style: AppText.figure.copyWith(color: color, fontSize: 13.5)),
        ],
      );

  Widget _count(String label, int value, Color color) => Column(
        children: [
          Text(label, style: AppText.label),
          const SizedBox(height: 3),
          AnimatedCount(value, style: AppText.figure.copyWith(color: color)),
        ],
      );
}

Widget _statusChip(String status) => switch (status) {
      'present' => StatusChip.success('حاضر'),
      'absent' => StatusChip.danger('غائب'),
      'late' => StatusChip.amber('متأخر'),
      'excused' => StatusChip.muted('معذور'),
      _ => StatusChip.muted('—'),
    };

Widget _announcement(ClassAnnouncement a) => Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(a.title, style: AppText.body.copyWith(fontWeight: FontWeight.w800))),
              if (a.createdAt.isNotEmpty)
                Text(a.createdAt.split('T').first, style: AppText.label),
            ],
          ),
          if (a.content.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(a.content, style: AppText.muted),
          ],
          if (a.groupName.isNotEmpty || a.teacherName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [if (a.teacherName.isNotEmpty) a.teacherName, if (a.groupName.isNotEmpty) a.groupName].join('  ·  '),
              style: AppText.label,
            ),
          ],
        ],
      ),
    );

// ══════════════════════════════════════════════════════════════════════════
// بوابة المعلم
// ══════════════════════════════════════════════════════════════════════════

class TeacherPortalScreen extends StatefulWidget {
  const TeacherPortalScreen({super.key, required this.user, required this.onExit});

  final PortalUser user;
  final VoidCallback onExit;

  @override
  State<TeacherPortalScreen> createState() => _TeacherPortalScreenState();
}

class _TeacherPortalScreenState extends State<TeacherPortalScreen> {
  TeacherPortalData? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await const PortalService().teacherData(widget.user);
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر الاتصال بالسحابة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = data?.branding ?? const PortalBranding();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _PortalBar(branding: branding, user: widget.user, onExit: widget.onExit),
          Expanded(
            child: loading
                ? Center(child: CircularProgressIndicator(color: AppColors.amber))
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, size: 34, color: AppColors.faint),
                            const SizedBox(height: 10),
                            Text(error!, style: AppText.muted),
                            const SizedBox(height: 14),
                            GhostButton(label: 'إعادة المحاولة', icon: Icons.refresh, onPressed: _load),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                          children: [
                            if (data!.classes.isEmpty)
                              const EmptyState(message: 'لا توجد مجموعات مسندة إليك.')
                            else
                              for (final c in data!.classes) _classCard(c),
                            const SizedBox(height: Gap.md),
                            _sectionCard(
                              title: 'إعلاناتي (${data!.announcements.length})',
                              icon: Icons.campaign_outlined,
                              children: data!.announcements.isEmpty
                                  ? [_empty('لم تنشر إعلاناً بعد.')]
                                  : [for (final a in data!.announcements) _announcement(a)],
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _classCard(TeacherClass c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: AppCard(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.group.name, style: AppText.cardTitle),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (c.subjectName.isNotEmpty) c.subjectName,
                          if (c.roomName.isNotEmpty) c.roomName,
                          '${c.students.length} طالب',
                        ].join('  ·  '),
                        style: AppText.label,
                      ),
                    ],
                  ),
                ),
                PrimaryButton(
                  label: 'رصد الحضور',
                  icon: Icons.fact_check_outlined,
                  onPressed: c.students.isEmpty ? null : () => _markAttendance(c),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'نشر إعلان',
                    icon: Icons.campaign_outlined,
                    onPressed: () => _publish(c),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GhostButton(
                    label: 'تقييم طالب',
                    icon: Icons.star_outline,
                    onPressed: c.students.isEmpty ? null : () => _evaluate(c),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAttendance(TeacherClass c) async {
    final date = isoDate(DateTime.now());
    final statuses = <String, String>{for (final s in c.students) s.id: 'present'};

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          var busy = false;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Expanded(child: Text('رصد حضور ${c.group.name} — $date', style: AppText.cardTitle)),
                        GhostButton(label: 'إغلاق', onPressed: () => Navigator.pop(ctx, false)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.line),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      itemCount: c.students.length,
                      itemBuilder: (_, i) {
                        final s = c.students[i];
                        final on = statuses[s.id] == 'present';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            children: [
                              Expanded(child: Text(s.fullName, style: AppText.body)),
                              PressableScale(
                                onTap: () => setSt(() => statuses[s.id] = on ? 'absent' : 'present'),
                                child: Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: on ? AppColors.success : AppColors.dangerSoft,
                                    border: Border.all(color: on ? AppColors.success : AppColors.dangerBorder),
                                  ),
                                  child: Text(
                                    on ? 'حاضر ✓' : 'غائب ✗',
                                    style: TextStyle(
                                      color: on ? Colors.white : AppColors.danger,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: PrimaryButton(
                      expand: true,
                      height: 42,
                      busy: busy,
                      label: 'حفظ الرصد',
                      icon: Icons.cloud_upload_outlined,
                      onPressed: () async {
                        setSt(() => busy = true);
                        try {
                          await const PortalService().saveAttendance(
                            group: c.group,
                            date: date,
                            statuses: statuses,
                            teacher: widget.user,
                            newId: AppStore.instance.newId,
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (_) {
                          setSt(() => busy = false);
                          if (ctx.mounted) showAppSnack(ctx, 'تعذّر حفظ الرصد', error: true);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved == true && mounted) showAppSnack(context, 'تم حفظ رصد الحضور');
  }

  Future<void> _publish(TeacherClass c) async {
    final title = TextEditingController();
    final content = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('إعلان لـ ${c.group.name}', style: AppText.cardTitle),
            const SizedBox(height: Gap.md),
            const FieldLabel('العنوان', requiredField: true),
            TextField(controller: title),
            const SizedBox(height: Gap.md),
            const FieldLabel('النص'),
            TextField(controller: content, maxLines: 4),
            const SizedBox(height: Gap.lg),
            PrimaryButton(
              expand: true,
              height: 42,
              label: 'نشر',
              icon: Icons.campaign_outlined,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (title.text.trim().isEmpty) {
      if (mounted) showAppSnack(context, 'يرجى إدخال عنوان الإعلان', error: true);
      return;
    }

    try {
      await const PortalService().publishAnnouncement(
        ClassAnnouncement(
          id: AppStore.instance.newId(),
          groupId: c.group.id,
          title: title.text.trim(),
          content: content.text.trim(),
          teacherId: widget.user.id,
        ),
        widget.user.tenantId,
      );
      if (!mounted) return;
      showAppSnack(context, 'تم نشر الإعلان');
      _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر نشر الإعلان', error: true);
    }
  }

  Future<void> _evaluate(TeacherClass c) async {
    var studentId = c.students.first.id;
    final score = TextEditingController();
    final notes = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تقييم طالب في ${c.group.name}', style: AppText.cardTitle),
              const SizedBox(height: Gap.md),
              const FieldLabel('الطالب', requiredField: true),
              AppDropdown<String>(
                value: studentId,
                items: [for (final s in c.students) DropdownMenuItem(value: s.id, child: Text(s.fullName))],
                onChanged: (v) => setSt(() => studentId = v ?? studentId),
              ),
              const SizedBox(height: Gap.md),
              const FieldLabel('الدرجة'),
              TextField(controller: score, keyboardType: TextInputType.number),
              const SizedBox(height: Gap.md),
              const FieldLabel('ملاحظات'),
              TextField(controller: notes, maxLines: 3),
              const SizedBox(height: Gap.lg),
              PrimaryButton(
                expand: true,
                height: 42,
                label: 'حفظ التقييم',
                icon: Icons.star_outline,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    try {
      await const PortalService().saveEvaluation(
        StudentEvaluation(
          id: AppStore.instance.newId(),
          studentId: studentId,
          teacherId: widget.user.id,
          subjectId: c.group.subjectId,
          score: double.tryParse(score.text.trim()),
          notes: notes.text.trim(),
        ),
        widget.user.tenantId,
      );
      if (mounted) showAppSnack(context, 'تم حفظ التقييم');
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر حفظ التقييم', error: true);
    }
  }
}
