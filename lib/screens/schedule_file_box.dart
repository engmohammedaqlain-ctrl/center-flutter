import '../widgets/empty_note.dart';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/doc_export.dart';
import '../data/schedule_files.dart';
import '../data/store.dart';
import '../data/user_message.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

/// عرض الجدول داخل التطبيق — `ScheduleFileView`: الصورة بتكبير وتصغير، والـPDF مضمَّناً.
class ScheduleFileView extends StatefulWidget {
  const ScheduleFileView({super.key, required this.file, required this.title, this.height});

  final ScheduleFile file;
  final String title;
  final double? height;

  @override
  State<ScheduleFileView> createState() => _ScheduleFileViewState();
}

class _ScheduleFileViewState extends State<ScheduleFileView> {
  Uint8List? bytes;
  String error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ScheduleFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.storagePath != widget.file.storagePath) {
      setState(() {
        bytes = null;
        error = '';
      });
      _load();
    }
  }

  Future<void> _load() async {
    final got = await ScheduleFiles.download(widget.file);
    if (!mounted) return;
    setState(() {
      bytes = got;
      error = got == null ? 'تعذّر فتح الجدول' : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? MediaQuery.sizeOf(context).height * 0.62;
    final data = bytes;
    if (error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
      );
    }
    if (data == null) {
      return SizedBox(height: 180, child: Center(child: AppLoader(message: 'جارٍ فتح الجدول', compact: true, size: 24)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: widget.file.isPdf
              ? PdfPreview(
                  build: (_) async => data,
                  useActions: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                )
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.memory(data, fit: BoxFit.contain),
                ),
        ),
        const SizedBox(height: 8),
        GhostButton(
          label: 'تنزيل',
          icon: Icons.download_outlined,
          onPressed: () => DocExport.download(
            context,
            data,
            widget.file.downloadName(widget.title),
            mime: widget.file.mime,
          ),
        ),
      ],
    );
  }
}

/// ملف جدول شعبة أو معلم للإدارة — `ScheduleFileBox`: رفع واستبدال وحذف وعرض داخل التطبيق.
class ScheduleFileBox extends StatefulWidget {
  const ScheduleFileBox({super.key, required this.kind, required this.ownerId, required this.title});

  final String kind;
  final String ownerId;
  final String title;

  @override
  State<ScheduleFileBox> createState() => _ScheduleFileBoxState();
}

class _ScheduleFileBoxState extends State<ScheduleFileBox> {
  ScheduleFile? file;
  bool loading = true;
  bool busy = false;
  String error = '';

  @override
  void initState() {
    super.initState();
    ScheduleFiles.get(widget.kind, widget.ownerId).then((f) {
      if (mounted) {
        setState(() {
          file = f;
          loading = false;
        });
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          error = userMessage(e, 'تعذّر جلب الجدول');
          loading = false;
        });
      }
    });
  }

  Future<void> _pick(AppStore store) async {
    const type = XTypeGroup(label: 'الجدول', extensions: scheduleExtensions);
    final picked = await openFile(acceptedTypeGroups: const [type]);
    if (picked == null || !mounted) return;
    setState(() => busy = true);
    try {
      final saved = await ScheduleFiles.save(
        tenantId: store.tenantId ?? '',
        kind: widget.kind,
        ownerId: widget.ownerId,
        name: picked.name,
        bytes: await picked.readAsBytes(),
      );
      if (mounted) setState(() => file = saved);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الرفع'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove() async {
    final current = file;
    if (current == null) return;
    final ok = await confirmSheet(context, title: 'حذف الجدول', message: 'حذف الجدول؟', confirmLabel: 'حذف');
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      await ScheduleFiles.remove(current);
      if (mounted) setState(() => file = null);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر الحذف'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (error.isNotEmpty) return Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12));
    if (loading) return const Center(child: AppLoader(compact: true, size: 22));
    final current = file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (current == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: EmptyNote('لم يُرفع جدول بعد'),
          )
        else ...[
          Text(
            [current.fileName, scheduleSizeLabel(current.sizeBytes)].where((x) => x.isNotEmpty).join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          ScheduleFileView(file: current, title: widget.title, height: 320),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: current == null ? 'رفع صورة أو PDF' : 'استبدال',
                icon: Icons.upload_file_outlined,
                expand: true,
                busy: busy,
                onPressed: busy ? null : () => _pick(store),
              ),
            ),
            if (current != null) ...[
              const SizedBox(width: 8),
              GhostButton(label: 'حذف', onPressed: busy ? null : _remove),
            ],
          ],
        ),
      ],
    );
  }
}

/// نافذة ملف جدول الشعبة من صفحة الصفوف — `ScheduleFileBoxModal`.
Future<void> showScheduleFileSheet(BuildContext context, {required String kind, required String ownerId, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.heading)),
            const SizedBox(height: 10),
            ScheduleFileBox(kind: kind, ownerId: ownerId, title: title),
          ],
        ),
      ),
    ),
  );
}
