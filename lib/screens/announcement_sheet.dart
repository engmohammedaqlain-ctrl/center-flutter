import 'package:flutter/material.dart';

import '../data/notes.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

const _durations = <String, int>{'يوم': 1, 'أسبوع': 7, 'شهر': 30};

/// نافذة الإعلان — `AnnouncementModal`: الوجهة هي التصفية الحالية (المرحلة والشعبة،
/// أو كل المدرسة)، ثم النص والمدة، وتحتها الإعلانات السابقة بحذفها.
Future<void> showAnnouncementSheet(BuildContext context, {String grade = '', String section = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _AnnouncementSheet(grade: grade, section: section),
  );
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({required this.grade, required this.section});

  final String grade;
  final String section;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final _service = const NotesService();
  final _text = TextEditingController();
  int days = 7;
  bool busy = false;
  List<SchoolAnnouncement>? list;

  String get _to => announcementTargetLabel(
        scope: widget.section.isNotEmpty ? 'section' : (widget.grade.isNotEmpty ? 'grade' : 'all'),
        grade: widget.grade,
        section: widget.section,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _service.schoolAnnouncements();
      if (mounted) setState(() => list = rows);
    } catch (_) {
      if (mounted) setState(() => list = const []);
    }
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await _service.postAnnouncement(body: _text.text, grade: widget.grade, section: widget.section, days: days);
      if (!mounted) return;
      showAppSnack(context, 'نُشر الإعلان: $_to');
      _text.clear();
      await _load();
    } on NotesException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove(SchoolAnnouncement a) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف الإعلان',
      message: 'حذف الإعلان؟ يختفي من البوابات فوراً',
      confirmLabel: 'حذف',
    );
    if (!ok) return;
    try {
      await _service.deleteAnnouncement(a.id);
      await _load();
    } on NotesException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = list;
    final now = DateTime.now();
    return NoonSheetFrame(
      title: 'إعلان · $_to',
      footer: [
        Expanded(
          child: NoonButton(
            label: 'نشر',
            tone: NoonTone.sun,
            expand: true,
            busy: busy,
            onPressed: busy ? null : _send,
          ),
        ),
      ],
      children: [
        TextField(
          controller: _text,
          maxLines: 4,
          maxLength: noteMax,
          decoration: const InputDecoration(hintText: 'نص الإعلان'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('يظهر لمدة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
              child: NoonSegment(
                value: days,
                options: [for (final d in _durations.entries) (d.value, d.key)],
                onChanged: (v) => setState(() => days = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: AppLoader(message: 'جارٍ تحميل الإعلانات', compact: true, size: 22)),
          )
        else if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'لا إعلانات سابقة',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.faint, fontSize: 12),
            ),
          )
        else
          for (final a in rows)
            Opacity(
              opacity: (DateTime.tryParse(a.endsAt)?.isBefore(now) ?? false) ? 0.6 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.body, style: const TextStyle(fontSize: 12.5)),
                          const SizedBox(height: 4),
                          Text(
                            '${announcementTargetLabel(scope: a.scope, grade: a.gradeLevel, section: a.section)}'
                            ' · ${noteTime(a.createdAt)}'
                            '${(DateTime.tryParse(a.endsAt)?.isBefore(now) ?? false) ? ' · انتهى' : ''}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    NoonButton(
                      icon: Icons.delete_outline_rounded,
                      tone: NoonTone.danger,
                      small: true,
                      tooltip: 'حذف',
                      onPressed: () => _remove(a),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
