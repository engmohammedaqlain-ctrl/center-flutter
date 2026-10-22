part of 'portal_screens.dart';

// رفع ملفات المودل: اختيار عدة ملفات أو تصوير ورقة، ومساحة المدرسة، وصفحة
// «مشاركة» الملفات من تطبيق آخر إلى وحدة. الحدود في `material_limits.dart`.

/// اسم المادة كما في قائمة المودل: «رياضيات — علمي 1 (الحادي عشر)».
String _classLabel(TeacherClass k) => [
      if (k.subjectName.trim().isNotEmpty) k.subjectName.trim(),
      if (k.roomName.trim().isNotEmpty) '— ${k.roomName.trim()}',
      if (k.subjectName.trim().isEmpty)
        (k.roomName.trim().isNotEmpty ? k.roomName.trim() : cleanGroupName(k.group.name, k.group.gradeLevel)),
      if (k.group.gradeLevel.trim().isNotEmpty) '(${k.group.gradeLevel.trim()})',
    ].where((e) => e.trim().isNotEmpty).join(' ');

/// منتقي النظام بعدة ملفات: PDF وصور وأوفيس. بلا إذن تخزين.
Future<List<MaterialDraft>> _pickMaterialFiles() async {
  final picked = await openFiles(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'ملفات المادة',
        extensions: materialPickerExtensions,
        mimeTypes: materialPickerMimes,
        uniformTypeIdentifiers: const [
          'com.adobe.pdf',
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
          'com.microsoft.word.doc',
          'org.openxmlformats.wordprocessingml.document',
          'com.microsoft.powerpoint.ppt',
          'org.openxmlformats.presentationml.presentation',
          'com.microsoft.excel.xls',
          'org.openxmlformats.spreadsheetml.sheet',
        ],
      ),
    ],
  );
  final out = <MaterialDraft>[];
  for (final f in picked) {
    final bytes = await f.readAsBytes();
    out.add(MaterialDraft(name: f.name, size: bytes.length, mime: f.mimeType ?? '', bytes: bytes));
  }
  return out;
}

/// تصوير ورقة بالكاميرا — تُضغط عند الرفع كأي صورة. بلا إذن كاميرا: تطبيق
/// الكاميرا نفسه يصوّر.
Future<MaterialDraft?> _takeMaterialPhoto() async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, requestFullMetadata: false);
  if (shot == null) return null;
  final bytes = await shot.readAsBytes();
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return MaterialDraft(
    name: 'صورة ${two(now.day)}-${two(now.month)} ${two(now.hour)}:${two(now.minute)}.jpg',
    size: bytes.length,
    mime: 'image/jpeg',
    bytes: bytes,
  );
}

IconData _materialIcon(MaterialDraft f) {
  if (!f.ok) return Icons.error_outline;
  return switch (checkMaterial(name: f.name, size: 0, mime: f.mime).kind) {
    MaterialKind.image => Icons.image_outlined,
    MaterialKind.pdf => Icons.picture_as_pdf_outlined,
    MaterialKind.word => Icons.description_outlined,
    MaterialKind.powerpoint => Icons.slideshow_outlined,
    MaterialKind.excel => Icons.table_chart_outlined,
    null => Icons.insert_drive_file_outlined,
  };
}

/// قائمة الملفات المختارة وزرّا الاختيار والتصوير، وتقدّم الرفع.
class _MaterialFilesBox extends StatelessWidget {
  const _MaterialFilesBox({
    required this.files,
    required this.failures,
    required this.onPick,
    required this.onCamera,
    required this.onRemove,
    this.progress,
  });

  final List<MaterialDraft> files;

  /// سبب فشل رفع ملف صالح (اتصال، مساحة...).
  final Map<MaterialDraft, String> failures;
  final VoidCallback? onPick;
  final VoidCallback? onCamera;
  final ValueChanged<MaterialDraft>? onRemove;

  /// أثناء الرفع: (المرفوع، الكل).
  final ({int done, int total})? progress;

  @override
  Widget build(BuildContext context) {
    final full = files.length >= materialBatchMax;
    final p = progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Soft(
              label: 'ملفات',
              icon: Icons.attach_file,
              fg: _C.navy,
              bg: _C.soft,
              border: _C.soft,
              height: 36,
              onTap: full ? null : onPick,
            ),
            const SizedBox(width: 8),
            _Soft(
              label: 'تصوير',
              icon: Icons.photo_camera_outlined,
              fg: _C.navy,
              bg: _C.soft,
              border: _C.soft,
              height: 36,
              onTap: full ? null : onCamera,
            ),
            const Spacer(),
            if (files.isNotEmpty)
              Tooltip(
                message: 'PDF أو صورة أو Word أو PowerPoint أو Excel، حتى 25 ميجا للملف',
                child: Text(
                  '${files.length}/$materialBatchMax',
                  style: const TextStyle(color: _C.faint, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
        for (final f in files) ...[
          const SizedBox(height: 6),
          _MaterialFileRow(file: f, failure: failures[f], onRemove: onRemove == null ? null : () => onRemove!(f)),
        ],
        if (p != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p.total == 0 ? null : p.done / p.total,
              minHeight: 4,
              backgroundColor: _C.line,
              color: _C.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'جارٍ الرفع ${p.done < p.total ? p.done + 1 : p.total} من ${p.total}',
            style: const TextStyle(color: _C.muted, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}

class _MaterialFileRow extends StatelessWidget {
  const _MaterialFileRow({required this.file, required this.failure, required this.onRemove});

  final MaterialDraft file;
  final String? failure;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final reason = file.error ?? failure;
    final bad = reason != null;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: bad ? _C.rose50 : _C.bg,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: bad ? _C.rose200 : _C.line),
      ),
      child: Row(
        children: [
          Icon(bad ? Icons.error_outline : _materialIcon(file), size: 16, color: bad ? _C.rose700 : _C.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _C.text, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  reason ?? formatBytes(file.size),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: bad ? _C.rose700 : _C.faint, fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'إزالة',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 16, color: _C.muted),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// مساحة المدرسة: شريط رفيع ورقمان. لا شيء إن تعذّر السؤال.
class _StorageLine extends StatelessWidget {
  const _StorageLine(this.status);

  final StorageStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    final color = s.full ? _C.rose600 : (s.ratio >= 0.8 ? _C.amber600 : _C.navy);
    return Tooltip(
      message: 'مساحة المدرسة',
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 14, color: s.full ? _C.rose600 : _C.faint),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: s.ratio, minHeight: 3, backgroundColor: _C.line, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatBytes(s.usedBytes)} من ${formatBytes(s.quotaBytes)}',
            style: TextStyle(color: s.full ? _C.rose700 : _C.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// نتيجة صفحة المشاركة: أين رُفعت الملفات، لتفتح البوابة عليها.
typedef _SharedUploadResult = ({String groupId, String term, int count});

/// ملفات مشارَكة من تطبيق آخر ← مادة ← وحدة (أو وحدة جديدة) ← دروس.
class _ShareToMoodlePage extends StatefulWidget {
  const _ShareToMoodlePage({
    required this.service,
    required this.offline,
    required this.tenantId,
    required this.classes,
    required this.initialGroupId,
    required this.initialTerm,
    required this.files,
    required this.color,
  });

  final PortalService service;
  final PortalOffline offline;
  final String tenantId;
  final List<TeacherClass> classes;
  final String initialGroupId;
  final String initialTerm;
  final List<MaterialDraft> files;
  final Color color;

  @override
  State<_ShareToMoodlePage> createState() => _ShareToMoodlePageState();
}

class _ShareToMoodlePageState extends State<_ShareToMoodlePage> {
  late String groupId = widget.classes.any((c) => c.group.id == widget.initialGroupId)
      ? widget.initialGroupId
      : widget.classes.first.group.id;
  late String term = widget.initialTerm == 'general' ? 'other' : widget.initialTerm;
  late List<MaterialDraft> files = [...widget.files];
  final failures = <MaterialDraft, String>{};
  final newUnit = TextEditingController();

  List<CourseSection> sections = const [];
  String sectionId = '';
  bool loadingSections = false;
  bool creatingUnit = false;
  bool busy = false;
  ({int done, int total})? progress;
  StorageStatus? storage;
  String? error;
  int uploaded = 0;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _loadSections();
    widget.service.storageStatus().then((s) {
      if (mounted) setState(() => storage = s);
    });
  }

  @override
  void dispose() {
    newUnit.dispose();
    super.dispose();
  }

  Future<void> _loadSections() async {
    final token = ++_token;
    final cached = widget.offline.loadSections(groupId, term);
    setState(() {
      sections = cached ?? const [];
      loadingSections = cached == null;
      if (!sections.any((s) => s.id == sectionId)) sectionId = sections.isEmpty ? '' : sections.last.id;
    });
    try {
      final list = await widget.service
          .groupSections(tenantId: widget.tenantId, groupId: groupId, term: term, includeHidden: true)
          .timeout(const Duration(seconds: 10));
      await widget.offline.saveSections(groupId, term, list);
      if (!mounted || token != _token) return;
      setState(() {
        sections = list;
        loadingSections = false;
        if (!sections.any((s) => s.id == sectionId)) sectionId = sections.isEmpty ? '' : sections.last.id;
      });
    } catch (_) {
      if (mounted && token == _token) setState(() => loadingSections = false);
    }
  }

  Future<void> _createUnit() async {
    final title = newUnit.text.trim();
    if (title.isEmpty || creatingUnit) return;
    setState(() {
      creatingUnit = true;
      error = null;
    });
    try {
      final created = await widget.service.createSection(
        tenantId: widget.tenantId,
        groupId: groupId,
        term: term,
        title: title,
        sortOrder: sections.length,
      );
      if (!mounted) return;
      newUnit.clear();
      setState(() {
        sections = [...sections, created];
        sectionId = created.id;
        creatingUnit = false;
      });
      await widget.offline.saveSections(groupId, term, sections);
    } catch (_) {
      if (mounted) {
        setState(() {
          creatingUnit = false;
          error = 'إنشاء الوحدة يحتاج اتصالاً بالإنترنت';
        });
      }
    }
  }

  Future<void> _addFiles(Future<List<MaterialDraft>> Function() pick) async {
    try {
      final more = await pick();
      if (!mounted || more.isEmpty) return;
      setState(() => files = [...files, ...more].take(materialBatchMax).toList());
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الملف', error: true);
    }
  }

  Future<void> _upload() async {
    final section = sections.where((s) => s.id == sectionId).firstOrNull;
    final ready = files.where((f) => f.ok).toList();
    if (section == null) {
      setState(() => error = 'اختر وحدة');
      return;
    }
    if (ready.isEmpty) {
      setState(() => error = 'لا ملفات صالحة للرفع');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      failures.clear();
      progress = (done: 0, total: ready.length);
    });
    final result = await widget.service.uploadMaterialBatch(
      files: ready,
      tenantId: widget.tenantId,
      section: section,
      onProgress: (done, total, _) {
        if (mounted) setState(() => progress = (done: done, total: total));
      },
    );
    if (!mounted) return;
    uploaded += result.created.length;
    final failedNames = {for (final f in result.failed) f.name: f.error};
    final updated = section.copyWith(items: [...section.items, ...result.created]);
    sections = [for (final s in sections) s.id == section.id ? updated : s];
    await widget.offline.saveSections(groupId, term, sections);
    if (!mounted) return;
    if (result.failed.isEmpty) {
      Navigator.pop<_SharedUploadResult>(context, (groupId: groupId, term: term, count: uploaded));
      return;
    }
    final storageNow = await widget.service.storageStatus();
    if (!mounted) return;
    setState(() {
      busy = false;
      progress = null;
      storage = storageNow ?? storage;
      // الباقي في القائمة: ما فشل وحده، بسببه، ليُعاد أو يُزال
      files = [
        for (final f in files)
          if (!f.ok || failedNames.containsKey(f.name)) f,
      ];
      for (final f in files) {
        if (failedNames[f.name] case final reason?) failures[f] = reason;
      }
      error = result.created.isEmpty ? null : 'رُفع ${result.created.length}، وتعذّر ${result.failed.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final readyCount = files.where((f) => f.ok).length;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text(
            'رفع إلى المودل',
            style: TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'إغلاق',
            onPressed: busy
                ? null
                : () => Navigator.pop<_SharedUploadResult>(
                      context,
                      uploaded > 0 ? (groupId: groupId, term: term, count: uploaded) : null,
                    ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 24 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('المادة:'),
                  _Select<String>(
                    value: groupId,
                    height: 36,
                    items: [
                      for (final k in widget.classes)
                        DropdownMenuItem(
                          value: k.group.id,
                          child: Text(_classLabel(k), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            if (v == null || v == groupId) return;
                            setState(() {
                              groupId = v;
                              sectionId = '';
                            });
                            _loadSections();
                          },
                  ),
                  const SizedBox(height: 10),
                  _TermSwitch(
                    value: term,
                    onChanged: (t) {
                      if (busy || t == term) return;
                      setState(() {
                        term = t;
                        sectionId = '';
                      });
                      _loadSections();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Label('الوحدة:'),
                  if (loadingSections)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _C.navy)),
                      ),
                    ),
                  for (var i = 0; i < sections.length; i++) ...[
                    _UnitChoice(
                      section: sections[i],
                      index: i,
                      selected: sections[i].id == sectionId,
                      onTap: busy ? null : () => setState(() => sectionId = sections[i].id),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(child: _Input(controller: newUnit, hint: 'وحدة جديدة', dense: true)),
                      const SizedBox(width: 8),
                      _Soft(
                        label: 'إضافة',
                        icon: Icons.add,
                        fg: _C.navy,
                        height: 36,
                        onTap: busy || creatingUnit ? null : _createUnit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MaterialFilesBox(
                    files: files,
                    failures: failures,
                    progress: progress,
                    onPick: busy ? null : () => _addFiles(_pickMaterialFiles),
                    onCamera: busy
                        ? null
                        : () => _addFiles(() async {
                              final shot = await _takeMaterialPhoto();
                              return shot == null ? const <MaterialDraft>[] : [shot];
                            }),
                    onRemove: busy ? null : (f) => setState(() => files = [for (final x in files) if (!identical(x, f)) x]),
                  ),
                  if (storage != null) ...[
                    const SizedBox(height: 12),
                    _StorageLine(storage),
                  ],
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              _MaterialError(error!),
            ],
            const SizedBox(height: 14),
            _Solid(
              label: busy ? 'جارٍ الرفع...' : 'رفع $readyCount',
              icon: Icons.cloud_upload_outlined,
              color: widget.color,
              busy: busy,
              height: 44,
              onTap: readyCount == 0 || sectionId.isEmpty ? null : _upload,
            ),
          ],
        ),
      ),
    );
  }
}

/// وحدة قابلة للاختيار بلونها ورقمها.
class _UnitChoice extends StatelessWidget {
  const _UnitChoice({required this.section, required this.index, required this.selected, required this.onTap});

  final CourseSection section;
  final int index;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = unitColor(section, index);
    return Material(
      color: selected ? unitHeaderBg(color) : Colors.white,
      borderRadius: BorderRadius.circular(Corner.box),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.box),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.box),
            border: Border.all(color: selected ? color : _C.line, width: selected ? 1.4 : 1),
          ),
          child: Row(
            children: [
              UnitNumber(n: index + 1, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppText.family, color: color, fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              Text('${section.items.length}', style: const TextStyle(color: _C.faint, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: selected ? color : _C.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialError extends StatelessWidget {
  const _MaterialError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _C.rose50,
        borderRadius: BorderRadius.circular(Corner.box),
        border: Border.all(color: _C.rose200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: _C.rose700),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: const TextStyle(color: _C.rose700, fontSize: 12, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}
