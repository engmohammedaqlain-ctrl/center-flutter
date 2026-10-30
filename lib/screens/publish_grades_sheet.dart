import 'package:flutter/material.dart';

import '../data/academic_matching.dart';
import '../data/arabic_search.dart';
import '../data/grade_publish.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

String _dmy(String d) => d.split('-').reversed.join('/');

/// العلامات المرصودة ولم تُنشر بعد بالقواعد نفسها التي تقرأ بها البوابة، ومحصورة بمادة
/// أو صف إن طُلب — `usePendingGrades` في PublishGrades.tsx.
int pendingGrades(AppStore store, {String subjectId = '', String grade = ''}) {
  final s = store.settings;
  var n = 0;
  for (final e in store.evaluations) {
    if (e.subjectId.isEmpty) continue;
    final g = (store.studentById(e.studentId)?.gradeLevel ?? '').trim();
    if (subjectId.isNotEmpty && e.subjectId != subjectId) continue;
    if (grade.isNotEmpty && g != grade) continue;
    if (!isGradePublished(e.evaluationDate, s, subjectId: e.subjectId, grade: g, manual: true)) n++;
  }
  return n;
}

/// زر رأس صفحة الدرجات حين تختار المدرسة «بعد اعتماد الإدارة» — `PublishGradesButton`.
class PublishGradesButton extends StatelessWidget {
  const PublishGradesButton({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (!store.settings.gradesPublishManual) return const SizedBox.shrink();
    final pending = pendingGrades(store);
    final until = store.settings.gradesPublishedUntil;
    return IconButton(
      tooltip: pending > 0 ? 'اعتماد ونشر ($pending)' : (until.isEmpty ? 'لم يُعتمد شيء بعد' : 'آخر اعتماد: ${_dmy(until)}'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (_) => StoreScope(store: store, child: const _PublishSheet()),
      ),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        child: Icon(pending > 0 ? Icons.send_outlined : Icons.done_all_rounded),
      ),
    );
  }
}

/// لوحة الاعتماد: الكل أو مادة أو صف، حتى اليوم أو حتى تاريخ — `PublishGradesPanel`.
class _PublishSheet extends StatefulWidget {
  const _PublishSheet();

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  String subjectId = '';
  String grade = '';

  Future<bool> _write(AppStore store, Map<String, dynamic> patch, String done, {String? confirm}) async {
    if (confirm != null && !await confirmSheet(context, title: 'تأكيد', message: confirm, confirmColor: AdminNoon.tealD)) return false;
    try {
      await store.writeSettingsPatch(patch, section: 'evaluations');
      if (mounted) showAppSnack(context, done);
      return true;
    } on StoreException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
      return false;
    }
  }

  Future<void> _publish(AppStore store, String until, {String? confirm}) async {
    final scoped = store.settings.gradesPublishedScoped;
    final all = subjectId.isEmpty && grade.isEmpty;
    final ok = all
        // النشر العام يغني عن النشرات الجزئية التي لا تتجاوزه
        ? await _write(
            store,
            {
              'grades_published_until': until,
              'grades_published_scoped': [for (final p in scoped) if (p.until.compareTo(until) > 0) p.toMap()],
            },
            'نُشرت العلامات للأهل',
            confirm: confirm,
          )
        : await _write(
            store,
            {
              'grades_published_scoped': [
                for (final p in scoped)
                  if (p.subjectId != subjectId || p.grade != grade) p.toMap(),
                PublishScope(until: until, subjectId: subjectId, grade: grade).toMap(),
              ],
            },
            'نُشرت العلامات للأهل',
            confirm: confirm,
          );
    if (ok && all && mounted) Navigator.pop(context);
  }

  Future<void> _byDate(AppStore store) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      helpText: 'ما رُصد حتى هذا اليوم',
    );
    if (picked != null) await _publish(store, isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        final scoped = s.gradesPublishedScoped;
        final subjects = [...store.subjectsInViewedYear]..sort((a, b) => compareArabicNames(a.name, b.name));
        final options = store.gradeOptions;
        final grades = {
          for (final st in store.students)
            if (st.gradeLevel.trim().isNotEmpty) st.gradeLevel.trim(),
        }.toList()
          ..sort((a, b) {
            int rank(String g) {
              final i = options.indexWhere((x) => isSameGrade(x, g));
              return i < 0 ? options.length : i;
            }

            return rank(a).compareTo(rank(b));
          });
        String subjectName(String id) => store.subjectById(id)?.name ?? 'مادة محذوفة';
        String scopeLabel(PublishScope p) => [if (p.subjectId.isNotEmpty) subjectName(p.subjectId), if (p.grade.isNotEmpty) p.grade].join(' · ');
        final pending = pendingGrades(store, subjectId: subjectId, grade: grade);
        final scopeText = [if (subjectId.isNotEmpty) subjectName(subjectId), if (grade.isNotEmpty) grade].join(' · ');
        final until = s.gradesPublishedUntil;

        return NoonSheetFrame(
          title: 'اعتماد العلامات',
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: subjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المادة', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كل المواد')),
                      for (final sub in subjects) DropdownMenuItem(value: sub.id, child: Text(sub.name)),
                    ],
                    onChanged: (v) => setState(() => subjectId = v ?? ''),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: grade,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الصف', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('كل الصفوف')),
                      for (final g in grades) DropdownMenuItem(value: g, child: Text(g)),
                    ],
                    onChanged: (v) => setState(() => grade = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pending > 0 ? '$pending علامة بانتظار الاعتماد' : 'لا علامات جديدة',
              style: NoonText.style(13, weight: FontWeight.w700),
            ),
            if (until.isNotEmpty)
              Text('آخر اعتماد عام ${_dmy(until)}', style: NoonText.style(11.5, color: AdminNoon.muted)),
            const SizedBox(height: 12),
            if (pending > 0)
              NoonButton(
                tone: NoonTone.sun,
                icon: Icons.send_outlined,
                label: scopeText.isNotEmpty ? 'اعتماد ونشر' : 'اعتماد ونشر الكل',
                expand: true,
                onPressed: () => _publish(
                  store,
                  isoDate(DateTime.now()),
                  confirm: 'نشر $pending علامة${scopeText.isNotEmpty ? ' ($scopeText)' : ''} للأهل والطلاب؟',
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: () => _byDate(store), child: const Text('حتى تاريخ')),
                const Spacer(),
                if (until.isNotEmpty || scoped.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48)),
                    onPressed: () async {
                      final ok = await _write(
                        store,
                        {'grades_published_until': null, 'grades_published_scoped': null},
                        'أُوقف النشر',
                        confirm: 'إخفاء كل العلامات عن الأهل حتى الاعتماد التالي؟',
                      );
                      if (ok && context.mounted) Navigator.pop(context);
                    },
                    child: const Text('إيقاف النشر'),
                  ),
              ],
            ),
            if (scoped.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('منشور جزئياً:', style: NoonText.style(11.5, color: AdminNoon.muted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < scoped.length; i++)
                    InputChip(
                      label: Text('${scopeLabel(scoped[i])} حتى ${_dmy(scoped[i].until)}', style: const TextStyle(fontSize: 12)),
                      onDeleted: () => _write(
                        store,
                        {
                          'grades_published_scoped': [
                            for (var j = 0; j < scoped.length; j++)
                              if (j != i) scoped[j].toMap(),
                          ],
                        },
                        'أُلغي هذا النشر',
                        confirm: 'إخفاء علامات ${scopeLabel(scoped[i])} عن الأهل؟',
                      ),
                      deleteButtonTooltipMessage: 'إلغاء هذا النشر',
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
