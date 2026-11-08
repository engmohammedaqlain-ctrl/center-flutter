import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../data/portal.dart';
import '../data/supabase.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'teacher_payslips.dart';

const _plansBucket = 'lesson-plans';

/// زر «ملفي» في شريط المعلم — `TeacherSelfModal`: الإجازات والتحضير، و«الراتب» لمن صُرف له.
class TeacherSelfButton extends StatelessWidget {
  const TeacherSelfButton({
    super.key,
    required this.tenantId,
    required this.teacherId,
    required this.classes,
    required this.slips,
    required this.color,
  });

  final String tenantId;
  final String teacherId;
  final List<TeacherClass> classes;
  final List<Payslip> slips;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'ملفي',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.person_outline_rounded, size: 19, color: color),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.white,
          builder: (_) => _SelfSheet(tenantId: tenantId, teacherId: teacherId, classes: classes, slips: slips),
        ),
      );
}

class _SelfSheet extends StatefulWidget {
  const _SelfSheet({required this.tenantId, required this.teacherId, required this.classes, required this.slips});

  final String tenantId;
  final String teacherId;
  final List<TeacherClass> classes;
  final List<Payslip> slips;

  @override
  State<_SelfSheet> createState() => _SelfSheetState();
}

class _SelfSheetState extends State<_SelfSheet> {
  String tab = 'leave';

  @override
  Widget build(BuildContext context) {
    return NoonSheetFrame(
      title: 'ملفي',
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 'leave', label: Text('الإجازات')),
            const ButtonSegment(value: 'plans', label: Text('التحضير')),
            if (widget.slips.isNotEmpty) const ButtonSegment(value: 'pay', label: Text('الراتب')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        switch (tab) {
          'pay' => payslipListView(widget.slips),
          'plans' => _Plans(tenantId: widget.tenantId, teacherId: widget.teacherId, classes: widget.classes),
          _ => _Leaves(tenantId: widget.tenantId, teacherId: widget.teacherId),
        },
      ],
    );
  }
}

class _Leaves extends StatefulWidget {
  const _Leaves({required this.tenantId, required this.teacherId});

  final String tenantId;
  final String teacherId;

  @override
  State<_Leaves> createState() => _LeavesState();
}

class _LeavesState extends State<_Leaves> {
  final _reason = TextEditingController();
  late String from = isoDate(DateTime.now());
  String to = '';
  bool busy = false;
  List<Map<String, dynamic>>? list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await supabaseSelect(
      'leave_requests',
      filters: {'teacher_id': 'eq.${widget.teacherId}'},
      order: 'from_date.desc',
      limit: 30,
    );
    if (mounted) setState(() => list = rows ?? const []);
  }

  Future<void> _send() async {
    setState(() => busy = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await supabaseUpsert('leave_requests', [
        {
          'id': const Uuid().v4(),
          'tenant_id': widget.tenantId,
          'teacher_id': widget.teacherId,
          'from_date': from,
          'to_date': to.isNotEmpty && to.compareTo(from) >= 0 ? to : from,
          'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
        },
      ]);
      if (!mounted) return;
      _reason.clear();
      setState(() => to = '');
      showAppSnack(context, 'أُرسل الطلب');
      await _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر إرسال الطلب', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick(bool start) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(start ? from : (to.isEmpty ? from : to)) ?? today,
      firstDate: start ? today : (parseIsoDate(from) ?? today),
      lastDate: DateTime(today.year + 2),
    );
    if (picked == null) return;
    setState(() => start ? from = isoDate(picked) : to = isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    const statuses = {
      'pending': ('بانتظار المدير', Color(0xFF475569)),
      'approved': ('موافق عليها', Color(0xFF15803D)),
      'rejected': ('مرفوضة', Color(0xFFBE123C)),
    };
    final rows = list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: GhostButton(label: 'من $from', onPressed: () => _pick(true))),
            const SizedBox(width: 8),
            Expanded(child: GhostButton(label: to.isEmpty ? 'إلى (اختياري)' : 'إلى $to', onPressed: () => _pick(false))),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          maxLength: 300,
          decoration: const InputDecoration(isDense: true, hintText: 'السبب', counterText: ''),
        ),
        const SizedBox(height: 8),
        PrimaryButton(label: 'طلب إجازة', expand: true, busy: busy, onPressed: busy ? null : _send),
        const SizedBox(height: 10),
        if (rows == null)
          const Center(child: AppLoader(compact: true, size: 22))
        else
          for (final l in rows)
            () {
              final s = statuses['${l['status']}'] ?? statuses['pending']!;
              final start = '${l['from_date'] ?? ''}';
              final end = '${l['to_date'] ?? start}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Text(
                      start == end ? start : '$start ← $end',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l['reason'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                    Text(
                      '${s.$1}${l['status'] == 'approved' && l['paid'] == false ? ' · بلا راتب' : ''}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.$2),
                    ),
                  ],
                ),
              );
            }(),
      ],
    );
  }
}

class _Plans extends StatefulWidget {
  const _Plans({required this.tenantId, required this.teacherId, required this.classes});

  final String tenantId;
  final String teacherId;
  final List<TeacherClass> classes;

  @override
  State<_Plans> createState() => _PlansState();
}

/// لمن التحضير: مادة يدرّسها المعلم بشعبها، أو شعبة واحدة منها — `PlanScope`.
class _Scope {
  const _Scope(this.key, this.label, this.subjectId, this.roomIds);

  final String key;
  final String label;
  final String subjectId;
  final List<String> roomIds;
}

class _PlansState extends State<_Plans> {
  final _title = TextEditingController();
  String scopeKey = '';
  bool busy = false;
  List<Map<String, dynamic>>? list;

  List<_Scope> get _scopes => [
        for (final c in widget.classes) ...[
          _Scope('s:${c.group.id}', c.subjectName, c.group.subjectId, const []),
          if (c.rooms.length > 1)
            for (final r in c.rooms) _Scope('r:${c.group.id}:${r.id}', '${c.subjectName} · ${r.name}', c.group.subjectId, [r.id]),
        ],
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await supabaseSelect(
      'lesson_plans',
      filters: {'teacher_id': 'eq.${widget.teacherId}'},
      order: 'created_at.desc',
    );
    if (mounted) setState(() => list = rows ?? const []);
  }

  Future<void> _upload() async {
    const type = XTypeGroup(label: 'ملف', extensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png']);
    final file = await openFile(acceptedTypeGroups: const [type]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 10 * 1024 * 1024) {
      showAppSnack(context, 'الملف أكبر من 10 ميجابايت', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final id = const Uuid().v4();
      final ext = file.name.split('.').last.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
      final path = '${widget.tenantId}/${widget.teacherId}/$id.$ext';
      const mimes = {
        'pdf': 'application/pdf',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'png': 'image/png',
      };
      await storageUpload(_plansBucket, path, bytes, mimes[ext] ?? 'image/jpeg');
      final scope = _scopes.where((s) => s.key == scopeKey).firstOrNull;
      final title = _title.text.trim().isEmpty ? file.name : _title.text.trim();
      await supabaseUpsert('lesson_plans', [
        {
          'id': id,
          'tenant_id': widget.tenantId,
          'teacher_id': widget.teacherId,
          'title': title.length > 200 ? title.substring(0, 200) : title,
          'file_name': file.name,
          'storage_path': path,
          'size_bytes': bytes.length,
          if (scope != null) 'subject_id': scope.subjectId,
          if (scope != null && scope.roomIds.isNotEmpty) 'room_ids': scope.roomIds,
        },
      ]);
      if (!mounted) return;
      _title.clear();
      showAppSnack(context, 'رُفع الملف');
      await _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر رفع الملف (الصيغ: PDF وWord وPowerPoint والصور)', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    final url = await storageSignedUrl(_plansBucket, '${p['storage_path']}');
    if (url == null) {
      if (mounted) showAppSnack(context, 'تعذّر فتح الملف', error: true);
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _remove(Map<String, dynamic> p) async {
    final ok = await confirmSheet(context, title: 'حذف الملف', message: 'حذف «${p['title']}»؟', confirmLabel: 'حذف');
    if (!ok) return;
    try {
      await supabaseDelete('lesson_plans', {'id': 'eq.${p['id']}'});
      await storageRemove(_plansBucket, ['${p['storage_path']}']);
      await _load();
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر الحذف', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = list;
    final scopes = _scopes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(isDense: true, hintText: 'عنوان الملف (اختياري)'),
        ),
        if (scopes.isNotEmpty)
          DropdownButton<String>(
            isExpanded: true,
            value: scopeKey,
            items: [
              const DropdownMenuItem(value: '', child: Text('عام', style: TextStyle(fontSize: 12.5))),
              for (final s in scopes)
                DropdownMenuItem(value: s.key, child: Text(s.label, style: const TextStyle(fontSize: 12.5))),
            ],
            onChanged: (v) => setState(() => scopeKey = v ?? ''),
          ),
        const SizedBox(height: 6),
        PrimaryButton(
          label: 'رفع ملف تحضير',
          icon: Icons.upload_file_outlined,
          expand: true,
          busy: busy,
          onPressed: busy ? null : _upload,
        ),
        const SizedBox(height: 10),
        if (rows == null)
          const Center(child: AppLoader(compact: true, size: 22))
        else
          for (final p in rows)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, size: 20),
              title: Text('${p['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${p['created_at'] ?? ''}'.split('T').first,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              onTap: () => _open(p),
              trailing: IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                onPressed: () => _remove(p),
              ),
            ),
      ],
    );
  }
}
