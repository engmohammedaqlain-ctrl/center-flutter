import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../data/image_shrink.dart';
import '../data/portal.dart';
import '../data/share_inbox.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/noon_ui.dart';
import '../widgets/widgets.dart';

/// تسديد دفعة من بوابة ولي الأمر — المقابل لـ `ParentPayments.tsx`.
///
/// ولي الأمر يحوّل (بنك أو محفظة) ثم يرسل صورة الإشعار ومن حوّل وإلى أين والمبلغ.
/// الطلب لا يمسّ حساب الطالب: المالية تراجعه، فإن قبلته صدر سند قبض عادي، وإن
/// رفضته كتبت سبباً يراه هنا.
class ParentPaymentsSection extends StatefulWidget {
  const ParentPaymentsSection({
    super.key,
    required this.user,
    required this.suggestedAmount,
    required this.accent,
    this.refreshTick = 0,
    this.service = const PortalService(),
    this.sharedReceipts = const [],
    this.onSharedReceiptsUsed,
    this.summary,
  });

  final PortalUser user;

  /// سطر ملخص الرسوم بجانب الزر.
  final Widget? summary;

  /// إشعار تحويل شورك من تطبيق البنك أو المحفظة: يفتح نموذج الدفع به مرفقاً.
  final List<String> sharedReceipts;
  final VoidCallback? onSharedReceiptsUsed;

  /// المستحق الآن: يُقترح مبلغاً للدفعة.
  final double suggestedAmount;
  final Color accent;

  /// يتغير مع كل إشارة «تغيّر» من المدرسة: تُعاد القائمة فيظهر القرار.
  final int refreshTick;
  final PortalService service;

  @override
  State<ParentPaymentsSection> createState() => _ParentPaymentsSectionState();
}

class _ParentPaymentsSectionState extends State<ParentPaymentsSection> {
  List<PaymentRequest> requests = const [];
  bool sent = false;

  @override
  void initState() {
    super.initState();
    _load();
    _openShared();
  }

  @override
  void didUpdateWidget(ParentPaymentsSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick || old.user.id != widget.user.id) _load();
    if (!identical(old.sharedReceipts, widget.sharedReceipts)) _openShared();
  }

  void _openShared() {
    final images = widget.sharedReceipts;
    if (images.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onSharedReceiptsUsed?.call();
      _openForm(initialImages: images);
    });
  }

  Future<void> _load() async {
    final list = await widget.service.paymentRequestsOf(widget.user.id);
    if (mounted && list != null) setState(() => requests = list);
  }

  Future<void> _openForm({List<String> initialImages = const []}) async {
    setState(() => sent = false);
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PaymentRequestForm(
          user: widget.user,
          suggestedAmount: widget.suggestedAmount,
          accent: widget.accent,
          service: widget.service,
          initialImages: initialImages,
        ),
      ),
    );
    if (done != true || !mounted) return;
    setState(() => sent = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // الأحدث أولاً
    final sorted = [...requests]..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    // طلب معلّق أو مرفوض في آخر 7 أيام: يبدأ القسم مفتوحاً ليراه ولي الأمر
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final needsAttention = sorted.any((r) {
      if (r.status != 'pending' && r.status != 'rejected') return false;
      final at = DateTime.tryParse(r.decidedAt ?? r.createdAt ?? '');
      return at != null && !at.isBefore(weekAgo);
    });
    final approvedTotal = requests.where((r) => r.status == 'approved').fold<double>(0, (s, r) => s + r.amount);
    return NColumn(
      gap: 12,
      children: [
        Row(
          children: [
            if (widget.summary != null) Expanded(child: widget.summary!) else const Spacer(),
            const SizedBox(width: 12),
            NBtn(
              tone: NBtnTone.sun,
              small: true,
              icon: Icons.send_rounded,
              label: 'تسديد دفعة',
              tooltip: 'تُحسب بعد مراجعة المالية للإشعار',
              onTap: () => _openForm(),
            ),
          ],
        ),
        if (sent)
          const NNotice(
            icon: Icons.check_rounded,
            text: 'أُرسل الطلب للمراجعة',
            tooltip: 'يُحسب في حسابك بعد مراجعة المالية للإشعار',
          ),
        if (requests.isNotEmpty)
          NFold(
            key: ValueKey('requests:$needsAttention'),
            title: 'طلبات الدفع',
            count: requests.length,
            summary: 'آخرها ${sorted.first.statusLabel}',
            defaultOpen: needsAttention,
            foot: approvedTotal > 0 ? NFootRow(label: 'إجمالي المعتمد', value: nMoney(approvedTotal), tone: Noon.green700, horizontal: 16) : null,
            rows: [for (final r in sorted) _RequestRow(request: r)],
          ),
      ],
    );
  }
}

/// طلب دفع: المبلغ وتحته المحوِّل وجهته والتاريخ، ووسم الحالة، وسبب الرفض أو «أُضيفت».
class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request});

  final PaymentRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final (tone, icon) = switch (r.status) {
      'approved' => (NTone.green, Icons.check_circle_outline_rounded),
      'rejected' => (NTone.red, Icons.cancel_outlined),
      _ => (NTone.sun, Icons.schedule_rounded),
    };
    final date = nFullDayLabel(r.transferDate.isNotEmpty ? r.transferDate : (r.createdAt ?? ''));
    final who = '${r.senderName}${r.transferChannel.isNotEmpty ? ' ← ${r.transferChannel}' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: NColumn(
        gap: 8,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nMoney(r.amount), style: nText(14, weight: FontWeight.w700)),
                    Text('$who · $date', maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(11, weight: FontWeight.w500, color: Noon.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              NBadge(r.statusLabel, tone: tone, icon: icon),
            ],
          ),
          if (r.status == 'rejected' && r.rejectionReason.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Noon.red50,
                borderRadius: BorderRadius.circular(NoonRadius.tile),
                border: Border.all(color: Noon.red200),
              ),
              child: Text('سبب الرفض: ${r.rejectionReason}', style: nText(12, weight: FontWeight.w700, color: Noon.red700, height: 1.625)),
            ),
          if (r.status == 'approved')
            Row(
              children: [
                Icon(Icons.inbox_outlined, size: 14, color: Noon.green700),
                const SizedBox(width: 4),
                Text('أُضيفت إلى سجل الدفعات', style: nText(11, weight: FontWeight.w700, color: Noon.green700)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── نموذج الإرسال ─────────────────────────────────────────────────────────────

class _PaymentRequestForm extends StatefulWidget {
  const _PaymentRequestForm({
    required this.user,
    required this.suggestedAmount,
    required this.accent,
    required this.service,
    this.initialImages = const [],
  });

  final PortalUser user;
  final double suggestedAmount;
  final Color accent;
  final PortalService service;

  /// صور الإشعار المشارَكة من تطبيق آخر (`data:` URLs).
  final List<String> initialImages;

  @override
  State<_PaymentRequestForm> createState() => _PaymentRequestFormState();
}

class _PaymentRequestFormState extends State<_PaymentRequestForm> {
  late final amount = TextEditingController(text: widget.suggestedAmount > 0 ? trimNum(widget.suggestedAmount) : '');
  late final sender = TextEditingController(
    text: widget.user.name.trim().isNotEmpty && widget.user.name != 'ولي الأمر' ? widget.user.name.trim() : '',
  );
  final channel = TextEditingController();
  final notes = TextEditingController();
  List<({String id, String name, String accountNumber})> methods = const [];

  /// الوسيلة المختارة؛ الفارغ = لا وسائل للمدرسة، فالجهة تُكتب باليد.
  String methodId = '';
  String date = isoDate(DateTime.now());
  late final images = <String>[...widget.initialImages.take(maxRequestImages)];
  bool busy = false;
  String error = '';

  /// رقم الوسيلة نُسخ للتو — يتبدّل الزر إلى «نُسخ» لحظة.
  bool copied = false;

  /// الوسيلة المختارة برقمها، إن كانت من القائمة.
  ({String id, String name, String accountNumber})? get _method =>
      methods.where((m) => m.id == methodId).firstOrNull;

  Future<void> _copyNumber() async {
    final number = _method?.accountNumber ?? '';
    if (number.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: number));
    if (!mounted) return;
    setState(() => copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.service.transferMethods(widget.user.tenantId).then((list) {
      if (!mounted) return;
      setState(() {
        methods = list;
        if (list.isNotEmpty) methodId = list.first.id;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    amount.dispose();
    sender.dispose();
    channel.dispose();
    notes.dispose();
    super.dispose();
  }

  bool get _ready =>
      (double.tryParse(amount.text.trim()) ?? 0) > 0 &&
      sender.text.trim().isNotEmpty &&
      images.isNotEmpty &&
      (methodId.isNotEmpty || channel.text.trim().isNotEmpty);

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 1400, maxHeight: 1400);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // حد حاوية الطلبات 2 ميجابايت
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) showAppSnack(context, 'الصورة أكبر من 2 ميجابايت', error: true);
        return;
      }
      if (!mounted) return;
      setState(() => images.add('data:${file.mimeType ?? 'image/jpeg'};base64,${base64Encode(bytes)}'));
    } catch (_) {
      if (mounted) showAppSnack(context, 'تعذّر اختيار الصورة', error: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseIsoDate(date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => date = isoDate(picked));
  }

  Future<void> _submit() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final methodName = methods.where((m) => m.id == methodId).map((m) => m.name).firstOrNull;
      await widget.service.submitPaymentRequest(
        tenantId: widget.user.tenantId,
        studentId: widget.user.id,
        studentName: widget.user.studentName.isNotEmpty ? widget.user.studentName : widget.user.name,
        amount: double.tryParse(amount.text.trim()) ?? 0,
        senderName: sender.text,
        paymentMethod: methodId,
        transferChannel: methodId.isNotEmpty ? (methodName ?? '') : channel.text,
        transferDate: date,
        notes: notes.text,
        images: images,
      );
      if (mounted) Navigator.pop(context, true);
    } on PortalException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'الإرسال يحتاج اتصالاً بالإنترنت');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _method?.accountNumber ?? '';
    final radius = BorderRadius.circular(NoonRadius.btn);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: NPageScaffold(
        title: 'تسديد دفعة',
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            NBtn(label: 'إلغاء', onTap: busy ? null : () => Navigator.pop(context)),
            const SizedBox(width: 8),
            NBtn(
              tone: NBtnTone.ink,
              icon: Icons.send_rounded,
              label: 'إرسال للمراجعة',
              busy: busy,
              onTap: _ready ? _submit : null,
            ),
          ],
        ),
        children: [
          NField(
            label: 'حوّل إلى',
            hint: 'تُحسب الدفعة بعد مراجعة المالية للإشعار',
            child: NColumn(
              gap: 8,
              children: [
                if (methods.isNotEmpty)
                  NFieldBox(
                    trailing: Icons.keyboard_arrow_down_rounded,
                    onTap: _pickMethod,
                    child: Text(_method?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                else
                  TextField(
                    controller: channel,
                    style: nText(14, weight: FontWeight.w500),
                    decoration: nInputDecoration(hint: 'اسم البنك أو المحفظة'),
                    onChanged: (_) => setState(() {}),
                  ),
                // رقم الحساب أو المحفظة: يحوّل إليه ولي الأمر دون أن يسأل المدرسة عنه
                if (account.isNotEmpty)
                  Container(
                    height: 48,
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 6, 0),
                    decoration: BoxDecoration(color: Noon.mist2, borderRadius: radius, border: Border.all(color: Noon.line)),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            account,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.right,
                            style: nText(16, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NBtn(small: true, icon: copied ? Icons.check_rounded : Icons.copy_rounded, label: copied ? 'نُسخ' : 'نسخ', onTap: _copyNumber),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NField(
                  label: 'المبلغ (شيكل)',
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: nText(14, weight: FontWeight.w500),
                    decoration: nInputDecoration(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NField(
                  label: 'اسم المحوِّل',
                  child: TextField(
                    controller: sender,
                    style: nText(14, weight: FontWeight.w500),
                    decoration: nInputDecoration(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          NField(
            label: 'صورة الإشعار',
            child: LayoutBuilder(
              builder: (context, box) {
                final w = (box.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < images.length; i++)
                      SizedBox(
                        width: w,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 88,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: radius, border: Border.all(color: Noon.line)),
                              child: Image.memory(base64Decode(images[i].split(',').last), width: double.infinity, fit: BoxFit.contain),
                            ),
                            PositionedDirectional(
                              top: -8,
                              start: -8,
                              child: Tooltip(
                                message: 'حذف',
                                child: GestureDetector(
                                  onTap: () => setState(() => images.removeAt(i)),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(color: Noon.red600, borderRadius: BorderRadius.circular(NoonRadius.tag)),
                                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (images.length < maxRequestImages)
                      SizedBox(
                        width: w,
                        height: 88,
                        child: InkWell(
                          onTap: _pickImage,
                          borderRadius: BorderRadius.circular(NoonRadius.tile),
                          child: CustomPaint(
                            painter: NDashedBorder(color: Noon.line, radius: NoonRadius.tile),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 20, color: Noon.teal),
                                const SizedBox(height: 4),
                                Text(
                                  images.isEmpty ? 'أرفق صورة الإشعار' : 'صورة إضافية',
                                  textAlign: TextAlign.center,
                                  style: nText(11, weight: FontWeight.w700, color: Noon.teal),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          NField(
            label: 'تاريخ التحويل',
            child: NFieldBox(
              onTap: _pickDate,
              trailing: Icons.calendar_today_outlined,
              child: Text(date, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            ),
          ),
          NField(
            label: 'ملاحظة',
            child: TextField(
              controller: notes,
              minLines: 2,
              maxLines: 3,
              style: nText(14, weight: FontWeight.w500),
              decoration: nInputDecoration(hint: 'مثال: عن قسط شهر 10'),
            ),
          ),
          if (error.isNotEmpty) NNotice(text: error, sun: true),
        ],
      ),
    );
  }

  /// اختيار الوسيلة من ورقة سفلية.
  Future<void> _pickMethod() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in methods)
              ListTile(
                title: Text(m.name, style: nText(14, weight: FontWeight.w700)),
                trailing: m.id == methodId ? Icon(Icons.check_rounded, color: Noon.teal) : null,
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      methodId = picked;
      copied = false;
    });
  }
}

/// إشعارات تحويل شوركت من تطبيق البنك أو المحفظة ← صور لطلب الدفع.
///
/// تطبيقات البنوك والمحافظ (بنك فلسطين، جوال باي، PalPay) تشارك الإشعار صورةً
/// أو PDF. الطلب يحمل صوراً فقط، فالـ PDF تُرسم صفحته الأولى صورة. ما سوى ذلك
/// يُعدّ في [skipped].
///
/// [max] أقصى عدد يُؤخذ: صور طلب الدفع، وللإدارة صورة السند أو صورتا ملف الطالب.
Future<({List<String> images, int skipped})> receiptsFromShared(List<SharedFile> files, {int max = maxRequestImages}) async {
  final images = <String>[];
  var skipped = 0;
  for (final f in files) {
    if (images.length >= max || f.path.isEmpty || f.unreadable) {
      skipped++;
      continue;
    }
    try {
      final raw = await File(f.path).readAsBytes();
      Uint8List? picture;
      if (f.isPdf) {
        await for (final page in Printing.raster(raw, pages: const [0], dpi: 150)) {
          picture = await page.toPng();
          break;
        }
      } else if (f.isImage) {
        picture = raw;
      }
      final jpg = picture == null ? null : await ImageShrink.forReceipt(picture);
      // حد حاوية الطلبات 2 ميجابايت
      if (jpg == null || jpg.length > 2 * 1024 * 1024) {
        skipped++;
        continue;
      }
      images.add('data:image/jpeg;base64,${base64Encode(jpg)}');
    } catch (_) {
      skipped++;
    }
  }
  return (images: images, skipped: skipped);
}
