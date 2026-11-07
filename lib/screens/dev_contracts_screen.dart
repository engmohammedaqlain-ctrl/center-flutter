import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../data/doc_export.dart';
import '../data/printing.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../data/tenant_contracts.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

const _fieldDefs = <(String, String, String)>[
  ('school_name', 'المدرسة', ''),
  ('school_address', 'العنوان', ''),
  ('rep_name', 'ممثل المدرسة', ''),
  ('rep_title', 'صفته', ''),
  ('rep_phone', 'جواله', 'tel'),
  ('students', 'عدد الطلاب حتى', 'number'),
  ('price', 'الاشتراك ₪', 'number'),
  ('price_words', 'المبلغ بالحروف', ''),
  ('duration', 'المدة', ''),
  ('start_date', 'يبدأ في', 'date'),
  ('date', 'تاريخ العقد', 'date'),
  ('owner_name', 'ممثل نون', ''),
  ('owner_title', 'صفته في نون', ''),
  ('owner_id', 'هويته', ''),
  ('owner_phone', 'جواله', 'tel'),
];

String _periodLabel(String? p) => p == 'monthly' ? 'شهري' : (p == 'yearly' ? 'سنوي' : '');

/// العقود: تعبئة عقد الاشتراك وتنزيله PDF، وصور النسخة الموقّعة — `DevContracts`.
class DevContractsScreen extends StatefulWidget {
  const DevContractsScreen({super.key});

  @override
  State<DevContractsScreen> createState() => _DevContractsScreenState();
}

class _DevContractsScreenState extends State<DevContractsScreen> {
  List<TenantContract>? rows;
  var failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ContractsService.list();
    if (!mounted) return;
    setState(() {
      rows = list;
      failed = list == null;
    });
  }

  Future<void> _open(TenantContract? existing) async {
    final last = rows?.firstOrNull?.fields;
    final draft = existing ??
        TenantContract(
          id: const Uuid().v4(),
          fields: {
            ...emptyContract,
            'date': isoDate(DateTime.now()),
            'duration': 'سنة',
            'owner_name': last?['owner_name'] ?? '',
            'owner_title': last?['owner_title'] ?? '',
            'owner_id': last?['owner_id'] ?? '',
            'owner_phone': last?['owner_phone'] ?? emptyContract['owner_phone']!,
          },
        );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ContractEditor(contract: draft, isNew: existing == null)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text('العقود${list == null ? '' : ' (${list.length})'}'),
        actions: [
          TextButton.icon(
            onPressed: list == null ? null : () => _open(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('عقد جديد'),
          ),
        ],
      ),
      body: failed
          ? Center(child: TextButton(onPressed: _load, child: const Text('تعذّر تحميل العقود، إعادة المحاولة')))
          : list == null
              ? const Center(child: AppLoader(compact: true))
              : list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(12), child: EmptyState(message: 'لا عقود'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final f = c.fields;
                        final school = (f['school_name'] ?? '').isEmpty ? 'بدون اسم' : f['school_name']!;
                        final signed = c.images.isNotEmpty;
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.line)),
                            onTap: () => _open(c),
                            title: Text(school, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [f['date'] ?? '', if ((f['price'] ?? '').isNotEmpty) '${f['price']} ₪', _periodLabel(f['period'])].where((s) => s.isNotEmpty).join(' · '),
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                            trailing: Text(
                              signed ? 'موقّع' : 'بانتظار التوقيع',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: signed ? AppColors.success : const Color(0xFFB45309)),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _ContractEditor extends StatefulWidget {
  const _ContractEditor({required this.contract, required this.isNew});

  final TenantContract contract;
  final bool isNew;

  @override
  State<_ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends State<_ContractEditor> {
  late final TenantContract c = widget.contract;
  late var saved = !widget.isNew;
  late final Map<String, TextEditingController> ctl = {
    for (final d in _fieldDefs) d.$1: TextEditingController(text: c.fields[d.$1] ?? ''),
  };
  var busy = false;
  final urls = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  @override
  void dispose() {
    for (final x in ctl.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUrls() async {
    for (final p in c.images) {
      if (urls.containsKey(p)) continue;
      final u = await storageSignedUrl(contractsBucket, p);
      if (!mounted) return;
      if (u != null) setState(() => urls[p] = u);
    }
  }

  void _collect() {
    for (final d in _fieldDefs) {
      c.fields[d.$1] = ctl[d.$1]!.text;
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    _collect();
    await ContractsService.save(c);
    saved = true;
  }

  /// كل عقد يُنزَّل يُحفظ أولاً، فيبقى له سجل تُرفع عليه صوره بعد التوقيع.
  Future<void> _download() => _run(() async {
        await _save();
        final bytes = await buildContractPdf(c.fields);
        if (!mounted) return;
        DocExport.showActions(context, bytes, contractFileName(c.fields));
      });

  Future<void> _upload() async {
    final files = await ImagePicker().pickMultiImage(maxWidth: 2200, maxHeight: 2200, imageQuality: 80);
    if (files.isEmpty || !mounted) return;
    await _run(() async {
      if (!saved) await _save();
      final list = [for (final f in files) await f.readAsBytes()];
      c.images = await ContractsService.addImages(c, list);
      await _loadUrls();
    });
  }

  Future<void> _removeImage(String path) async {
    final ok = await confirmSheet(context, title: 'حذف الصورة', message: 'حذف الصورة؟', confirmLabel: 'حذف');
    if (!ok || !mounted) return;
    await _run(() async {
      c.images = await ContractsService.removeImage(c, path);
    });
  }

  Future<void> _delete() async {
    final ok = await confirmSheet(context, title: 'حذف العقد', message: 'حذف العقد وصوره؟', confirmLabel: 'حذف');
    if (!ok || !mounted) return;
    await _run(() async {
      await ContractsService.delete(c);
      if (mounted) Navigator.pop(context);
    });
  }

  void _pickSchool(String? id, List<Tenant> tenants) {
    final t = tenants.where((x) => x.id == id).firstOrNull;
    setState(() {
      c.tenantId = t?.id;
      if (t != null) {
        ctl['school_name']!.text = t.name;
        if (t.ownerName.isNotEmpty) ctl['rep_name']!.text = t.ownerName;
        if (t.ownerPhone.isNotEmpty) ctl['rep_phone']!.text = t.ownerPhone;
      }
    });
  }

  Future<void> _pickDate(String key) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctl[key]!.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => ctl[key]!.text = isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final tenants = StoreScope.of(context).tenants;
    final period = c.fields['period'] ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(saved && (c.fields['school_name'] ?? '').isNotEmpty ? c.fields['school_name']! : 'عقد جديد'),
        actions: [
          if (saved)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppDropdown<String>(
            value: tenants.any((t) => t.id == c.tenantId) ? c.tenantId : '',
            items: [
              const DropdownMenuItem(value: '', child: Text('مدرسة مسجّلة: لا')),
              for (final t in tenants) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) => _pickSchool(id, tenants),
          ),
          const SizedBox(height: 10),
          for (final (key, label, type) in _fieldDefs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: ctl[key],
                readOnly: type == 'date',
                onTap: type == 'date' ? () => _pickDate(key) : null,
                keyboardType: type == 'number' ? TextInputType.number : (type == 'tel' ? TextInputType.phone : TextInputType.text),
                textDirection: type == 'tel' || type == 'number' || type == 'date' ? TextDirection.ltr : null,
                textAlign: TextAlign.start,
                onChanged: key == 'price'
                    ? (value) {
                        final n = double.tryParse(value.trim()) ?? 0;
                        ctl['price_words']!.text = n > 0 ? amountInArabicWords(n) : '';
                      }
                    : null,
                decoration: InputDecoration(isDense: true, labelText: label),
              ),
            ),
          const Text('الدفع', style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final p in const ['monthly', 'yearly'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Center(child: Text(_periodLabel(p))),
                      selected: period == p,
                      onSelected: (_) => setState(() => c.fields['period'] = period == p ? '' : p),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: PrimaryButton(label: 'تنزيل PDF', expand: true, busy: busy, onPressed: busy ? null : _download)),
              const SizedBox(width: 8),
              GhostButton(
                label: 'حفظ',
                onPressed: busy
                    ? null
                    : () => _run(() async {
                          await _save();
                          if (mounted) showAppSnack(context, 'حُفظ');
                        }),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('النسخة الموقّعة (${c.images.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
              ),
              GhostButton(label: 'رفع صور', icon: Icons.upload_outlined, onPressed: busy ? null : _upload),
            ],
          ),
          const SizedBox(height: 8),
          if (c.images.isEmpty)
            const EmptyState(message: 'لا صور')
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3 / 4,
              children: [
                for (final p in c.images)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.sunken,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: urls[p] == null
                            ? const Center(child: AppLoader(compact: true))
                            : InteractiveViewer(child: Image.network(urls[p]!, fit: BoxFit.cover)),
                      ),
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: IconButton.filledTonal(
                          tooltip: 'حذف',
                          iconSize: 16,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, color: AppColors.danger),
                          onPressed: busy ? null : () => _removeImage(p),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
