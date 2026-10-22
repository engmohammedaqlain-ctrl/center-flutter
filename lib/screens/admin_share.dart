import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/arabic_search.dart';
import '../data/portal.dart';
import '../data/share_inbox.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/form_layout.dart';
import '../widgets/widgets.dart';
import 'parent_payments.dart' show receiptsFromShared;
import 'payment_form_screen.dart';
import 'portal_screens.dart' show MoodleShareResult, MoodleShareTarget, ShareToMoodlePage;

// «مشاركة» ← نون بحساب المدرسة: ملفات من المعرض أو صورة إشعار بنك تذهب إلى
// ملف طالب، أو محتوى مودل لمادة، أو سند قبض. الرفع بالخدمات نفسها: مرفقات
// الطالب (`saveStudentAttachments`)، ودفعة المودل (`uploadMaterialBatch` بحدودها)،
// وإشعار السند (`saveFinanceAttachment` عند اعتماد الدفعة).

enum AdminShareDestination { studentFile, moodle, receipt }

/// الوجهات المتاحة لهذا الحساب ولهذه الملفات: الصور وPDF لملف الطالب والسند،
/// وأي ملف مادة للمودل.
List<AdminShareDestination> adminShareDestinations(AppStore store, List<SharedFile> files) {
  final hasPicture = files.any((f) => !f.unreadable && !f.tooLarge && (f.isImage || f.isPdf));
  return [
    if (hasPicture && store.features.enableStudentAttachments && store.can('students')) AdminShareDestination.studentFile,
    if (store.isFeatureOn('moodle') && store.can('moodle') && store.tenantId != null) AdminShareDestination.moodle,
    if (hasPicture && store.can('finance.collect')) AdminShareDestination.receipt,
  ];
}

/// مواد العام المعروض كما يختارها المدير: «رياضيات — علمي 1، علمي 2 (الحادي عشر)».
List<MoodleShareTarget> adminMoodleTargets(AppStore store) {
  final out = <(String, MoodleShareTarget)>[];
  for (final g in store.groupsInViewedYear.where((g) => g.isActive)) {
    final ids = {
      if (g.roomId.isNotEmpty) g.roomId,
      ...g.roomIds.where((id) => id.isNotEmpty),
    };
    final rooms = [
      for (final id in ids)
        if (store.roomById(id) case final r?) PortalRoom(id: r.id, name: r.name),
    ];
    final subject = store.subjectById(g.subjectId)?.name.trim() ?? '';
    final grade = g.gradeLevel.trim();
    final label = [
      subject.isNotEmpty ? subject : cleanGroupName(g.name, g.gradeLevel),
      if (rooms.isNotEmpty) '— ${rooms.map((r) => r.name).join('، ')}',
      if (grade.isNotEmpty) '($grade)',
    ].join(' ');
    out.add((grade, MoodleShareTarget(groupId: g.id, label: label, rooms: rooms)));
  }
  out.sort((a, b) {
    final byGrade = a.$1.compareTo(b.$1);
    return byGrade != 0 ? byGrade : a.$2.label.compareTo(b.$2.label);
  });
  return [for (final e in out) e.$2];
}

/// ملفات وصلت والإدارة داخلة: اختيار الوجهة ثم صفحتها.
Future<void> openAdminShare(BuildContext context, List<SharedFile> files) async {
  if (files.isEmpty) return;
  final store = AppStore.instance;
  final options = adminShareDestinations(store, files);
  if (options.isEmpty) {
    showAppSnack(context, 'لا وجهة لهذه الملفات في حسابك', error: true);
    return;
  }
  final picked = await showModalBottomSheet<AdminShareDestination>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              files.length == 1 ? 'مشاركة ملف' : 'مشاركة ${files.length} ملفات',
              style: TextStyle(fontFamily: AppText.family, color: AppColors.heading, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(switch (o) {
                AdminShareDestination.studentFile => Icons.badge_outlined,
                AdminShareDestination.moodle => Icons.menu_book_outlined,
                AdminShareDestination.receipt => Icons.receipt_long_outlined,
              }, color: AppColors.navy),
              title: Text(
                switch (o) {
                  AdminShareDestination.studentFile => 'ملف طالب',
                  AdminShareDestination.moodle => 'محتوى مودل',
                  AdminShareDestination.receipt => 'سند قبض',
                },
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              trailing: const AppChevron(size: 18),
              onTap: () => Navigator.pop(ctx, o),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  switch (picked) {
    case AdminShareDestination.moodle:
      await _toMoodle(context, store, files);
    case AdminShareDestination.receipt:
      await _toReceipt(context, files);
    case AdminShareDestination.studentFile:
      await _toStudentFile(context, files);
  }
}

Future<void> _toMoodle(BuildContext context, AppStore store, List<SharedFile> files) async {
  final targets = adminMoodleTargets(store);
  final tid = store.tenantId;
  if (targets.isEmpty || tid == null) {
    showAppSnack(context, 'لا مواد في العام الحالي', error: true);
    return;
  }
  final result = await Navigator.of(context).push<MoodleShareResult>(
    MaterialPageRoute(
      builder: (_) => ShareToMoodlePage(
        service: const PortalService(),
        tenantId: tid,
        targets: targets,
        files: [for (final f in files) f.toDraft()],
        color: AppColors.navy,
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  store.announceChange(const ['course_sections', 'course_items']);
  showAppSnack(context, 'رُفع ${result.count} ملف');
}

Future<void> _toReceipt(BuildContext context, List<SharedFile> files) async {
  final got = await receiptsFromShared(files, max: 1);
  if (!context.mounted) return;
  if (got.images.isEmpty) {
    showAppSnack(context, 'الإشعار صورة أو PDF', error: true);
    return;
  }
  if (got.skipped > 0) showAppSnack(context, 'أُرفقت الصورة الأولى');
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => PaymentFormScreen(initialNotice: got.images.first)),
  );
}

Future<void> _toStudentFile(BuildContext context, List<SharedFile> files) async {
  final got = await receiptsFromShared(files, max: AppStore.studentDocKinds.length);
  if (!context.mounted) return;
  if (got.images.isEmpty) {
    showAppSnack(context, 'المرفق صورة أو PDF', error: true);
    return;
  }
  if (got.skipped > 0) showAppSnack(context, 'أُرفق ${got.images.length} من ${got.images.length + got.skipped}');
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ShareToStudentFilePage(images: got.images)),
  );
}

const _kindLabels = {'student_id_photo': 'صورة الهوية', 'birth_certificate': 'شهادة الميلاد'};

/// صور مشارَكة ← طالب ← خانتها في ملفه (صورة الهوية أو شهادة الميلاد).
class ShareToStudentFilePage extends StatefulWidget {
  const ShareToStudentFilePage({super.key, required this.images});

  /// صور `data:` جاهزة، واحدة أو اثنتان.
  final List<String> images;

  @override
  State<ShareToStudentFilePage> createState() => _ShareToStudentFilePageState();
}

class _ShareToStudentFilePageState extends State<ShareToStudentFilePage> {
  final search = TextEditingController();
  String? studentId;
  StudentAttachments? existing;
  bool loadingExisting = false;
  bool busy = false;

  /// خانة كل صورة بترتيبها: الأولى للهوية والثانية لشهادة الميلاد.
  late List<String> kinds = [
    for (var i = 0; i < widget.images.length; i++) AppStore.studentDocKinds[i % AppStore.studentDocKinds.length],
  ];

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _select(Student s) async {
    final store = StoreScope.of(context);
    setState(() {
      studentId = s.id;
      existing = null;
      loadingExisting = true;
      search.clear();
    });
    final att = await store.loadAttachments(s.id);
    if (!mounted || studentId != s.id) return;
    setState(() {
      existing = att;
      loadingExisting = false;
    });
  }

  /// صورتان: تبديل خانة واحدة يبدّل الأخرى، فلا تقعان في خانة واحدة.
  void _setKind(int index, String kind) {
    setState(() {
      final old = kinds[index];
      kinds = [
        for (var i = 0; i < kinds.length; i++)
          i == index ? kind : (kinds[i] == kind ? old : kinds[i]),
      ];
    });
  }

  void _save() {
    final store = StoreScope.of(context);
    final id = studentId;
    final student = id == null ? null : store.studentById(id);
    if (student == null) return;
    final prev = existing;
    // خانة لا تُستبدل وملفها في السحابة لم يُنزَّل: الحفظ كان سيمسحه
    final keep = AppStore.studentDocKinds.where((k) => !kinds.contains(k));
    if (prev != null && keep.any((k) => prev.dataOf(k).isEmpty && prev.pathOf(k).isNotEmpty)) {
      showAppSnack(context, 'تعذّر تحميل مرفقات الطالب الحالية. تحقق من الاتصال', error: true);
      return;
    }
    if (prev == null && store.offline) {
      showAppSnack(context, 'الإرفاق يحتاج اتصالاً بالإنترنت', error: true);
      return;
    }
    String pick(String kind) {
      final i = kinds.indexOf(kind);
      return i >= 0 ? widget.images[i] : (prev?.dataOf(kind) ?? '');
    }

    setState(() => busy = true);
    try {
      store.saveStudentAttachments(
        student.id,
        StudentAttachments(
          id: student.id,
          studentIdPhoto: pick('student_id_photo'),
          birthCertificate: pick('birth_certificate'),
          studentIdPhotoPath: prev?.studentIdPhotoPath ?? '',
          birthCertificatePath: prev?.birthCertificatePath ?? '',
          createdAt: prev?.createdAt,
        ),
      );
      Navigator.pop(context);
      showAppSnack(context, 'أُرفق في ملف ${student.fullName}');
    } on StoreException catch (e) {
      setState(() => busy = false);
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final selected = studentId == null ? null : store.studentById(studentId!);
    final q = search.text.trim();
    final matches = selected != null || q.isEmpty
        ? const <Student>[]
        : store.studentsInViewedYear
            .where((s) =>
                matchStudentSearch(
                  fullName: s.fullName,
                  query: q,
                  phone: s.phone,
                  parentPhone: s.parentPhone,
                  nationalId: s.nationalId,
                  parentName: s.parentName,
                  parentNationalId: s.parentNationalId,
                ) ||
                s.gradeLevel.contains(q))
            .take(30)
            .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('إرفاق في ملف طالب')),
      bottomNavigationBar: FormActionBar(
        label: 'حفظ',
        busy: busy,
        onSave: selected == null || loadingExisting || busy ? null : _save,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (var i = 0; i < widget.images.length; i++) ...[
            _ImageSlot(
              image: widget.images[i],
              kind: kinds[i],
              replaces: (existing?.dataOf(kinds[i]).isNotEmpty ?? false) || (existing?.pathOf(kinds[i]).isNotEmpty ?? false),
              onKind: busy ? null : (k) => _setKind(i, k),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          const FieldLabel('الطالب', requiredField: true),
          if (selected != null)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text),
                      ),
                      if (selected.gradeLevel.trim().isNotEmpty)
                        Text(selected.gradeLevel.trim(), style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (loadingExisting)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                TextButton.icon(
                  onPressed: busy ? null : () => setState(() => studentId = null),
                  style: TextButton.styleFrom(foregroundColor: AppColors.amber),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('تغيير', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            )
          else ...[
            SearchField(
              controller: search,
              hint: 'الاسم، رقم الهوية، أو الهاتف...',
              onChanged: (_) => setState(() {}),
            ),
            for (final s in matches)
              InkWell(
                onTap: () => _select(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text),
                        ),
                      ),
                      if (s.gradeLevel.trim().isNotEmpty)
                        Text(s.gradeLevel.trim(), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      const AppChevron(size: 18),
                    ],
                  ),
                ),
              ),
            if (q.isNotEmpty && matches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'لا طلاب مطابقون',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// صورة مشارَكة وخانتها في ملف الطالب.
class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.image, required this.kind, required this.replaces, required this.onKind});

  final String image;
  final String kind;

  /// في الخانة صورة سابقة تُستبدل.
  final bool replaces;
  final ValueChanged<String>? onKind;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Corner.box),
          child: Image.memory(base64Decode(image.split(',').last), width: 64, height: 64, fit: BoxFit.cover),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in AppStore.studentDocKinds)
                    ChoiceChip(
                      label: Text(_kindLabels[k] ?? k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      selected: k == kind,
                      onSelected: onKind == null ? null : (_) => onKind!(k),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (replaces)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Tooltip(
                    message: 'في الملف صورة سابقة لهذه الخانة',
                    child: Text('تستبدل الحالية', style: TextStyle(color: AppColors.warn, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
