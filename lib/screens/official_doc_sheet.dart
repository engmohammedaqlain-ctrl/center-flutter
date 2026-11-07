import 'package:flutter/material.dart';

import '../data/doc_export.dart';
import '../data/official_docs.dart';
import '../data/school_options.dart';
import '../data/store.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

/// ورقة رسمية من ملف الطالب — `OfficialDocModal`: اختيار نوعها، ثم معاينة نصها وجهتها،
/// ثم «تنزيل PDF». تحتها الأوراق الصادرة، فيعرف المدير ما طلع ولمن.
Future<void> showOfficialDocSheet(BuildContext context, AppStore store, Student student) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _OfficialDocSheet(store: store, student: student),
  );
}

const _kindIcons = <String, IconData>{
  'enrollment': Icons.school_outlined,
  'conduct': Icons.verified_outlined,
  'whom': Icons.description_outlined,
  'transfer': Icons.swap_horiz_rounded,
};

class _OfficialDocSheet extends StatefulWidget {
  const _OfficialDocSheet({required this.store, required this.student});

  final AppStore store;
  final Student student;

  @override
  State<_OfficialDocSheet> createState() => _OfficialDocSheetState();
}

class _OfficialDocSheetState extends State<_OfficialDocSheet> {
  String? kind;
  final toWhom = TextEditingController();
  final note = TextEditingController();
  bool busy = false;
  List<IssuedDocRow>? issued;

  String get _school => widget.store.institutionName;
  String get _year => (widget.store.operationalAcademicYear ?? widget.store.viewedAcademicYear)?.label ?? '';

  @override
  void initState() {
    super.initState();
    studentIssuedDocs(widget.student.id).then((rows) {
      if (mounted) setState(() => issued = rows);
    });
  }

  @override
  void dispose() {
    toWhom.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final k = kind;
    if (k == null) return;
    setState(() => busy = true);
    try {
      final store = widget.store;
      final principal = store.settings.principalName.trim().isNotEmpty
          ? store.settings.principalName.trim()
          : store.currentTenant?.ownerName.trim() ?? '';
      final res = await buildOfficialDoc(
        kind: k,
        student: widget.student,
        school: _school,
        year: _year,
        logo: store.institutionLogo,
        toWhom: toWhom.text,
        note: note.text,
        principal: principal,
      );
      if (!mounted) return;
      if (res.bytes == null) {
        showAppSnack(context, 'تعذّر تجهيز الملف', error: true);
        return;
      }
      final messenger = Navigator.of(context).context;
      showAppSnack(messenger, 'صدرت ${res.label} برقم ${res.issued.serial}');
      await DocExport.showActions(messenger, res.bytes!, '${res.label}_${widget.student.fullName}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر إصدار الورقة'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = kind;
    return NoonSheetFrame(
      title: k == null ? 'ورقة رسمية' : officialDocKinds[k]!,
      footer: k == null
          ? null
          : [
              NoonButton(label: 'رجوع', onPressed: busy ? null : () => setState(() => kind = null)),
              NoonButton(
                label: 'تنزيل PDF',
                icon: Icons.download_outlined,
                tone: NoonTone.sun,
                busy: busy,
                onPressed: busy ? null : _download,
              ),
            ],
      children: k == null
          ? [
              // قائمة بنود بأيقونة وسهم، بدل أزرار حدّها أسود ونصها برتقالي
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: noonPanel(),
                child: Column(
                  children: [
                    for (final (n, d) in officialDocKinds.entries.indexed)
                      InkWell(
                        onTap: () => setState(() => kind = d.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: n > 0 ? BoxDecoration(border: Border(top: BorderSide(color: AdminNoon.line))) : null,
                          child: Row(
                            children: [
                              Icon(_kindIcons[d.key] ?? Icons.description_outlined, size: 20, color: AdminNoon.ink),
                              const SizedBox(width: 12),
                              Expanded(child: Text(d.value, style: NoonText.style(14, weight: FontWeight.w700))),
                              Icon(Icons.chevron_right_rounded, size: 20, color: AdminNoon.faint),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (issued != null && issued!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'الأوراق الصادرة',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    for (final d in issued!) IssuedDocTile(doc: d),
                  ],
                ),
            ]
          : [
              TextField(
                controller: toWhom,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: k == 'transfer' ? 'المدرسة المنقول إليها' : 'الجهة',
                  hintText: k == 'transfer' ? 'اسم المدرسة' : 'من يهمه الأمر',
                ),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(isDense: true, labelText: 'ملاحظة (اختيارية)', hintText: 'تُطبع تحت النص'),
              ),
              // معاينة النص كما يُطبع: يقرأه المدير قبل أن يصدر برقم
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.sunken,
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  officialDocText(kind: k, student: widget.student, school: _school, year: _year, toWhom: toWhom.text),
                  style: const TextStyle(fontSize: 13, height: 1.9),
                ),
              ),
            ],
    );
  }
}

/// سطر ورقة صادرة: نوعها وجهتها ورقمها وتاريخها.
class IssuedDocTile extends StatelessWidget {
  const IssuedDocTile({super.key, required this.doc});

  final IssuedDocRow doc;

  @override
  Widget build(BuildContext context) {
    final day = doc.issuedAt.length >= 10 ? doc.issuedAt.substring(0, 10) : doc.issuedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(doc.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.heading)),
          if (doc.toWhom.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                doc.toWhom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            '${doc.serial} · $day',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
