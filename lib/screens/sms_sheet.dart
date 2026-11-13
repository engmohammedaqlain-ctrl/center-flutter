import 'dart:async';

import 'package:flutter/material.dart';

import '../data/arabic_search.dart';
import '../data/phone.dart';
import '../data/sms_service.dart';
import '../data/sms_text.dart';
import '../models/models.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

const _maxText = 670; // 10 أجزاء عربية

/// طلاب ما بنراسلهم: الأرشيف والمنسحبين.
const _hidden = {'archived', 'withdrawn'};

/// ورقة SMS من شاشة الطلاب — `SmsPage` على الويب بتبويبين: «رسالة جديدة» لطلاب التصفية
/// الحالية، و«المرسلة والاستهلاك». المستحق واسم المدرسة بينحسبوا قبل الفتح ويوصلوا جاهزين،
/// فالورقة ما بتسمع للمخزن ولا بتنبني مع المزامنة.
Future<void> showSmsSheet(
  BuildContext context, {
  required List<Student> students,
  required String target,
  required Map<String, double> due,
  required String school,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _SmsSheet(
      students: [for (final s in students) if (!_hidden.contains(s.status)) smsStudentOf(s)],
      target: target,
      due: due,
      school: school,
    ),
  );
}

enum _Tab { compose, sent }

enum _Group { all, due }

class _SmsSheet extends StatefulWidget {
  const _SmsSheet({required this.students, required this.target, required this.due, required this.school});

  final List<SmsStudent> students;
  final String target;
  final Map<String, double> due;
  final String school;

  @override
  State<_SmsSheet> createState() => _SmsSheetState();
}

class _SmsSheetState extends State<_SmsSheet> {
  final _service = const SmsService();
  final _text = TextEditingController();

  SmsStatus? status;
  String? loadError;
  SmsUsage? usage;
  List<SentSms>? history;
  _Tab tab = _Tab.compose;
  SmsAudience audience = SmsAudience.parents;
  _Group group = _Group.all;
  final excluded = <String>{};
  bool busy = false;

  // ناتج الحساب: بينعاد بس لما يتغير النص أو المستلمون، مش مع كل بناء
  List<SmsStudent> pool = const [];
  List<SmsMessage> messages = const [];
  int missing = 0;
  int noPhone = 0;
  int selected = 0;
  SmsCount? count;
  int totalParts = 0;
  Timer? _typing;

  double _dueOf(String id) => widget.due[id] ?? 0;

  @override
  void initState() {
    super.initState();
    _recompute();
    _service.status().then((s) {
      if (!mounted) return;
      setState(() => status = s);
      if (s.connected) _loadUsage();
    }, onError: (Object e) {
      if (mounted) setState(() => loadError = '$e');
    });
  }

  @override
  void dispose() {
    _typing?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _loadUsage() {
    _service.usage().then((u) {
      if (mounted) setState(() => usage = u);
    }, onError: (_) {});
  }

  Future<void> _loadHistory() async {
    setState(() => history = null);
    try {
      final list = await _service.history();
      if (mounted) setState(() => history = list);
    } on SmsException catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.message, error: true);
      setState(() => history = const []);
    }
  }

  void _recompute() {
    pool = group == _Group.all ? widget.students : [for (final s in widget.students) if (_dueOf(s.id) > 0) s];
    final included = [for (final s in pool) if (!excluded.contains(s.id)) s];
    noPhone = 0;
    for (final s in pool) {
      if (!smsHasPhone(s, audience)) noPhone++;
    }
    final body = _text.text.trim();
    // قبل الكتابة: عدد الأرقام المختلفة. ومع متغيرات الطالب: رسالة لكل طالب
    final r = buildSmsMessages(included, body.isEmpty ? '.' : body, audience: audience, school: widget.school, dueOf: _dueOf);
    messages = r.messages;
    missing = r.missing;
    // المحددين: اللي إلهم رقم وما انشالوا
    selected = included.length - r.missing;
    // العدّاد على أطول رسالة فعلية (بعد الأسماء والمبالغ)، والرصيد على مجموع أجزاء كل الرسائل
    count = body.isEmpty ? null : smsParts(longestSmsMessage(messages, body).trim());
    totalParts = body.isEmpty ? 0 : totalSmsParts(messages);
  }

  void _update(VoidCallback change) {
    _typing?.cancel();
    setState(() {
      change();
      _recompute();
    });
  }

  /// مع الكتابة: الحساب على كل المستلمين بيستنى وقفة قصيرة، فالكتابة ما بتتقّل مع مئات الطلاب.
  void _onTyping() {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(_recompute);
    });
  }

  void _insert(String tag) {
    final sel = _text.selection;
    final text = _text.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    var next = text.replaceRange(start, end, tag);
    if (next.length > _maxText) next = next.substring(0, _maxText);
    final at = start + tag.length > next.length ? next.length : start + tag.length;
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at));
    _update(() {});
  }

  Future<void> _saveTemplates(List<SmsTemplate> list, String done) async {
    try {
      final saved = await _service.saveTemplates(list);
      if (!mounted) return;
      setState(() => status = status?.withTemplates(saved));
      showAppSnack(context, done);
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  Future<void> _openTemplates() async {
    final templates = status?.templates ?? const <SmsTemplate>[];
    final body = _text.text.trim();
    final pick = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => NoonSheetFrame(
        title: 'القوالب',
        footer: [
          Expanded(
            child: NoonButton(
              label: 'حفظ النص كقالب',
              icon: Icons.bookmark_add_outlined,
              expand: true,
              onPressed: body.isEmpty ? null : () => Navigator.pop(ctx, 'save'),
            ),
          ),
        ],
        children: [
          if (templates.isEmpty)
            const NoonEmpty('ما في قوالب. اكتب رسالة واحفظها كقالب', icon: Icons.description_outlined, dashed: false)
          else
            for (final t in templates)
              InkWell(
                onTap: () => Navigator.pop(ctx, t),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
                  decoration: BoxDecoration(border: Border.all(color: AdminNoon.line), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, weight: FontWeight.w700)),
                            Text(t.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11, color: AdminNoon.muted)),
                          ],
                        ),
                      ),
                      NoonButton(
                        icon: Icons.delete_outline_rounded,
                        tone: NoonTone.danger,
                        small: true,
                        tooltip: 'حذف',
                        onPressed: () => Navigator.pop(ctx, ('delete', t)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
    if (!mounted || pick == null) return;
    if (pick is SmsTemplate) {
      _text.value = TextEditingValue(text: pick.body, selection: TextSelection.collapsed(offset: pick.body.length));
      _update(() {});
    } else if (pick == 'save') {
      final values = await smsInputSheet(
        context,
        title: 'حفظ كقالب',
        confirmLabel: 'حفظ',
        fields: const [(label: 'اسم القالب', hint: 'تذكير بالقسط', initial: '', number: false)],
      );
      final title = values?.first.trim() ?? '';
      if (title.isEmpty) return;
      await _saveTemplates([...templates.where((t) => t.title != title), SmsTemplate(title: title, body: body)], 'انحفظ القالب');
    } else if (pick is (String, SmsTemplate)) {
      final t = pick.$2;
      final ok = await confirmSheet(context, title: 'حذف القالب', message: 'حذف قالب «${t.title}»؟', confirmLabel: 'حذف');
      if (!ok) return;
      await _saveTemplates([...templates.where((x) => !identical(x, t))], 'انحذف القالب');
    }
  }

  Future<void> _editRecipients() async {
    final next = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _RecipientsSheet(
        pool: pool,
        audience: audience,
        excluded: excluded,
        dueOf: group == _Group.due ? _dueOf : null,
      ),
    );
    if (next == null || !mounted) return;
    _update(() {
      excluded
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _send() async {
    // آخر حرف انكتب قبل الوقفة: الرسائل بتنحسب على النص كما هو هلأ
    _typing?.cancel();
    _recompute();
    final body = _text.text.trim();
    if (body.isEmpty || messages.isEmpty) return;
    final bundle = usage?.bundle;
    final over = bundle != null && totalParts > bundle.remaining;
    final ok = await confirmSheet(
      context,
      title: 'إرسال SMS',
      message: 'إرسال ${messages.length} رسالة'
          '${totalParts > messages.length ? ' ($totalParts من رصيد الشريحة)' : ''}؟'
          '${over ? '\nأكثر من الباقي بالرصيد (${bundle?.remaining})' : ''}',
      confirmLabel: 'إرسال',
      confirmColor: AdminNoon.ink,
    );
    if (!ok || !mounted) return;
    setState(() => busy = true);
    try {
      final n = await _service.send(messages);
      if (!mounted) return;
      showAppSnack(context, 'انبعثت للجوال: $n رسالة');
      _text.clear();
      _update(() => tab = _Tab.sent);
      _loadUsage();
      _loadHistory();
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final ready = s != null && s.connected;
    return NoonSheetFrame(
      title: 'SMS · ${widget.target}',
      footer: ready && tab == _Tab.compose ? [Expanded(child: _sendBar())] : null,
      children: [
        if (loadError != null)
          NoonEmpty(loadError!, icon: Icons.sms_failed_outlined, dashed: false)
        else if (s == null)
          const NoonLoading()
        else if (!s.connected)
          NoonEmpty(s.error ?? 'اربط بوابة الرسائل من الإعدادات ← المدرسة', icon: Icons.sms_outlined)
        else ...[
          NoonSegment<_Tab>(
            value: tab,
            options: const [(_Tab.compose, 'رسالة جديدة'), (_Tab.sent, 'المرسلة والاستهلاك')],
            onChanged: (v) {
              setState(() => tab = v);
              if (v == _Tab.sent && history == null) _loadHistory();
            },
          ),
          _DeviceLine(status: s),
          if (tab == _Tab.compose) ..._compose(s) else ..._sent(),
        ],
      ],
    );
  }

  // ── رسالة جديدة ─────────────────────────────────────────────────────────

  List<Widget> _compose(SmsStatus s) {
    final who = audience == SmsAudience.parents ? 'ولي أمر' : 'طالب';
    final c = count;
    final body = _text.text.trim();
    final preview = body.isEmpty || messages.isEmpty ? null : messages.first;
    String? previewName;
    if (preview != null) {
      for (final st in pool) {
        if (st.id == preview.ref) {
          previewName = st.firstName;
          break;
        }
      }
    }
    final templates = s.templates;

    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NoonSheetLabel('لمين'),
          NoonSegment<SmsAudience>(
            value: audience,
            options: const [(SmsAudience.parents, 'أولياء الأمور'), (SmsAudience.students, 'الطلاب')],
            onChanged: (v) => _update(() => audience = v),
          ),
          const SizedBox(height: 12),
          const NoonSheetLabel('مين منهم'),
          NoonSegment<_Group>(
            value: group,
            options: const [(_Group.all, 'الكل'), (_Group.due, 'عليهم مستحق')],
            onChanged: (v) => _update(() => group = v),
          ),
        ],
      ),
      // المستلمون بعددهم، والاستثناء من قائمة
      InkWell(
        onTap: pool.isEmpty ? null : _editRecipients,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
          decoration: BoxDecoration(color: AdminNoon.band, border: Border.all(color: AdminNoon.line), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(Icons.groups_outlined, size: 18, color: AdminNoon.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$selected', style: NoonText.style(13, weight: FontWeight.w700)),
                    TextSpan(text: ' ${audience == SmsAudience.parents ? 'ولي أمر' : 'طالب'}'),
                    if (messages.length != selected && body.isNotEmpty) TextSpan(text: ' · ${messages.length} رقم'),
                    if (noPhone > 0) TextSpan(text: ' · $noPhone بلا رقم', style: NoonText.style(12, color: AdminNoon.faint)),
                    if (excluded.isNotEmpty) TextSpan(text: ' · ${excluded.length} مستثنى', style: NoonText.style(12, color: AdminNoon.warn)),
                  ]),
                  style: NoonText.style(12, color: AdminNoon.muted),
                ),
              ),
              if (pool.isNotEmpty) Text('تعديل', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.tealD)),
              Icon(Icons.chevron_left_rounded, size: 20, color: AdminNoon.faint),
            ],
          ),
        ),
      ),
      // النص وتحته المتغيرات والعدّاد: مربع واحد زي محررات الرسائل
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('الرسالة', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted))),
              NoonButton(
                label: templates.isEmpty ? 'القوالب' : 'القوالب (${templates.length})',
                icon: Icons.description_outlined,
                tone: NoonTone.ghost,
                small: true,
                onPressed: _openTemplates,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AdminNoon.line), borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: _maxText,
                  style: NoonText.style(14, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'اكتب الرسالة…',
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => _onTyping(),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  decoration: BoxDecoration(color: AdminNoon.band, border: Border(top: BorderSide(color: AdminNoon.line))),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final v in smsVars)
                        Tooltip(
                          message: 'بيتبدّل بـ«${v.label}» لكل $who',
                          child: InkWell(
                            onTap: () => _insert(v.tag),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 26,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: AdminNoon.line),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 12, color: AdminNoon.tealD),
                                  Text(v.label, style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.tealD)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // عدّاد زي الجوال: الأحرف من سعة الرسالة، وعدد الرسائل
          Row(
            children: [
              Expanded(
                child: c == null
                    ? const SizedBox.shrink()
                    : Text(
                        '${c.parts > 1 ? 'احذف ${c.toFewer} ${smsLetters(c.toFewer)} لترجع ${c.parts - 1 == 1 ? 'رسالة وحدة' : '${c.parts - 1} رسائل'}' : 'باقي ${c.remaining} ${smsLetters(c.remaining)}'}'
                        '${c.emoji ? ' · الإيموجي بحرفين' : ''}'
                        '${messages.length > 1 && hasPerStudentVars(body) ? ' · العدّ على أطول رسالة' : ''}',
                        style: NoonText.style(11, color: c.parts > 1 ? AdminNoon.warn : AdminNoon.muted),
                      ),
              ),
              Tooltip(
                message: c?.unicode == false
                    ? 'إنجليزي: 160 حرف بالرسالة، والأطول كل 153 رسالة'
                    : 'عربي أو رموز: 70 حرف بالرسالة، والأطول كل 67 رسالة. المسافات والأسطر بتنعد، والإيموجي بحرفين',
                triggerMode: TooltipTriggerMode.tap,
                child: Text(
                  '${c == null ? '0/70' : '${c.chars}/${c.capacity}'} · ${(c?.parts ?? 0) <= 1 ? 'رسالة' : '${c!.parts} رسائل'}',
                  textDirection: TextDirection.rtl,
                  style: NoonText.style(11.5, weight: FontWeight.w700, color: (c?.parts ?? 0) > 1 ? AdminNoon.warn : AdminNoon.muted),
                ),
              ),
            ],
          ),
        ],
      ),
      // معاينة أول رسالة بقيمها الفعلية، بشكل فقاعة رسالة
      if (preview != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoonSheetLabel('معاينة${previewName != null ? ' · $previewName' : ''}'),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AdminNoon.mist,
                  border: Border.all(color: AdminNoon.headLine),
                  borderRadius: const BorderRadiusDirectional.only(
                    topStart: Radius.circular(4),
                    topEnd: Radius.circular(16),
                    bottomStart: Radius.circular(16),
                    bottomEnd: Radius.circular(16),
                  ),
                ),
                child: Text(preview.message, style: NoonText.style(13.5, height: 1.5)),
              ),
            ),
          ],
        ),
    ];
  }

  /// شريط الإرسال: «N رسالة · M من الرصيد · بيضل X» جنب الزر.
  Widget _sendBar() {
    final body = _text.text.trim();
    final bundle = usage?.bundle;
    final over = bundle != null && totalParts > bundle.remaining;
    return Row(
      children: [
        Expanded(
          child: body.isEmpty || messages.isEmpty
              ? const SizedBox.shrink()
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${messages.length}', style: NoonText.style(12.5, weight: FontWeight.w700)),
                    const TextSpan(text: ' رسالة · '),
                    TextSpan(
                      text: '$totalParts',
                      style: NoonText.style(12.5, weight: FontWeight.w700, color: over ? AdminNoon.red700 : AdminNoon.text),
                    ),
                    const TextSpan(text: ' من الرصيد'),
                    if (bundle != null)
                      TextSpan(
                        text: over ? ' · أكثر من الباقي (${bundle.remaining})' : ' · بيضل ${bundle.remaining - totalParts}',
                        style: over ? NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.red700) : null,
                      ),
                  ]),
                  style: NoonText.style(12, color: AdminNoon.muted),
                ),
        ),
        const SizedBox(width: 8),
        NoonButton(
          label: 'إرسال',
          icon: Icons.send_rounded,
          tone: NoonTone.sun,
          busy: busy,
          onPressed: busy || body.isEmpty || messages.isEmpty ? null : _send,
        ),
      ],
    );
  }

  // ── المرسلة والاستهلاك ──────────────────────────────────────────────────

  List<Widget> _sent() {
    return [
      SmsBundleCard(usage: usage, onChange: (u) => setState(() => usage = u)),
      if (usage != null) _UsageLine(usage: usage!),
      SmsHistoryList(
        list: history,
        names: {for (final s in widget.students) s.id: s.fullName.isNotEmpty ? s.fullName : s.firstName},
        onRefresh: () {
          _loadHistory();
          _loadUsage();
        },
      ),
    ];
  }
}

/// حالة جوال الشريحة: نقطة ملوّنة و«الجوال متصل» أو «مش متصل».
class _DeviceLine extends StatelessWidget {
  const _DeviceLine({required this.status});

  final SmsStatus status;

  @override
  Widget build(BuildContext context) {
    final on = status.online;
    return Tooltip(
      message: status.hasDevice ? '${status.deviceModel ?? 'الجوال'} · ${smsTimeAgo(status.lastSeen)}' : 'الجوال ما دخل التطبيق لسا',
      triggerMode: TooltipTriggerMode.tap,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: on ? const Color(0xFF10B981) : const Color(0xFFF59E0B), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(on ? 'الجوال متصل' : 'الجوال مش متصل', style: NoonText.style(11.5, color: AdminNoon.muted)),
          if (status.name.isNotEmpty) ...[
            Text(' · ', style: NoonText.style(11.5, color: AdminNoon.faint)),
            Flexible(
              child: Text(status.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11.5, color: AdminNoon.muted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// الرصيد: «باقي 950 من 1000 · 32 يوم» بشريط، و«شحن» بيضيف عليه، والقلم بيصحّحه للرقم الفعلي.
/// كل رسالة انبعثت بتنقص منه بأجزائها.
class SmsBundleCard extends StatefulWidget {
  const SmsBundleCard({super.key, required this.usage, required this.onChange});

  final SmsUsage? usage;
  final ValueChanged<SmsUsage> onChange;

  @override
  State<SmsBundleCard> createState() => _SmsBundleCardState();
}

class _SmsBundleCardState extends State<SmsBundleCard> {
  bool busy = false;

  Future<void> _edit({required bool topUp}) async {
    final b = widget.usage?.bundle;
    final values = await smsInputSheet(
      context,
      title: topUp ? 'شحن الرصيد' : 'تصحيح الرصيد',
      confirmLabel: topUp ? 'شحن' : 'حفظ',
      fields: topUp
          ? const [
              (label: 'عدد الرسائل', hint: '1000', initial: '', number: true),
              (label: 'صالحة لـ (يوم) · فاضي = بلا مدة', hint: '50', initial: '', number: true),
            ]
          : [(label: 'كم رسالة باقية فعلياً؟', hint: '', initial: b == null ? '' : '${b.remaining}', number: true)],
    );
    if (values == null || !mounted) return;
    final n = int.tryParse(digitsOnly(values[0]));
    final daysText = topUp ? digitsOnly(values[1]) : '';
    final d = daysText.isEmpty ? null : int.tryParse(daysText);
    if (n == null || n < (topUp ? 1 : 0)) {
      showAppSnack(context, 'اكتب عدد الرسائل', error: true);
      return;
    }
    if (d != null && d < 1) {
      showAppSnack(context, 'اكتب عدد أيام صحيح', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final u = topUp ? await const SmsService().topUp(n, d) : await const SmsService().setBalance(n);
      if (!mounted) return;
      widget.onChange(u);
      showAppSnack(context, topUp ? 'انضاف ${smsAmount(n)} للرصيد' : 'تصحّح الرصيد');
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usage;
    if (u == null) return const SizedBox(height: 4, child: LinearProgressIndicator(minHeight: 2));
    final b = u.bundle;
    final color = b != null && b.low ? AdminNoon.red700 : AdminNoon.text;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
      decoration: noonPanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: b == null
                    ? Text('الرصيد مش محدد', style: NoonText.style(12.5, color: AdminNoon.muted))
                    : b.expired
                        ? Text('انتهى الرصيد', style: NoonText.style(13, weight: FontWeight.w700, color: AdminNoon.red700))
                        : Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'باقي '),
                              TextSpan(text: smsAmount(b.remaining), style: NoonText.style(15, weight: FontWeight.w700, color: color)),
                              if (b.size > 0) TextSpan(text: ' من ${smsAmount(b.size)}'),
                              if (b.daysLeft != null) TextSpan(text: ' · ${smsDays(b.daysLeft!)}'),
                            ]),
                            style: NoonText.style(12.5, color: AdminNoon.muted),
                          ),
              ),
              if (b != null)
                NoonButton(
                  icon: Icons.edit_outlined,
                  tone: NoonTone.ghost,
                  small: true,
                  tooltip: 'تصحيح الرصيد',
                  onPressed: busy ? null : () => _edit(topUp: false),
                ),
              NoonButton(
                label: 'شحن',
                icon: Icons.add_rounded,
                small: true,
                busy: busy,
                tooltip: 'أضف رسائل للرصيد',
                onPressed: busy ? null : () => _edit(topUp: true),
              ),
            ],
          ),
          if (b != null && b.size > 0 && !b.expired) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (b.remaining / b.size).clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                backgroundColor: AdminNoon.band,
                color: b.low ? AdminNoon.red600 : AdminNoon.teal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// الاستهلاك بفترة تختارها: «30 رسالة انبعثت · 49 من الرصيد · 1 فشلت».
class _UsageLine extends StatefulWidget {
  const _UsageLine({required this.usage});

  final SmsUsage usage;

  @override
  State<_UsageLine> createState() => _UsageLineState();
}

class _UsageLineState extends State<_UsageLine> {
  String period = 'today';

  @override
  Widget build(BuildContext context) {
    final p = widget.usage.periods[period] ?? const SmsPeriod();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoonSegment<String>(
          value: period,
          options: const [('today', 'اليوم'), ('yesterday', 'أمس'), ('week', '7 أيام'), ('month', 'هالشهر')],
          onChanged: (v) => setState(() => period = v),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: smsAmount(p.messages), style: NoonText.style(13, weight: FontWeight.w700)),
            const TextSpan(text: ' رسالة انبعثت · '),
            TextSpan(text: smsAmount(p.parts), style: NoonText.style(13, weight: FontWeight.w700)),
            const TextSpan(text: ' من الرصيد'),
            if (p.failed > 0) ...[
              const TextSpan(text: ' · '),
              TextSpan(text: '${p.failed} فشلت', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.red700)),
            ],
          ]),
          style: NoonText.style(12, color: AdminNoon.muted),
        ),
      ],
    );
  }
}

/// المرسلة: تصفية بالأعداد، وتنبيه «N فشلت» بزر إعادة الإرسال، وسطر لكل رسالة.
/// [list] فاضي = لسا بتتحمّل. [names] اسم الطالب من `ref`.
class SmsHistoryList extends StatefulWidget {
  const SmsHistoryList({super.key, required this.list, required this.names, required this.onRefresh, this.filters = true});

  final List<SentSms>? list;
  final Map<String, String> names;
  final VoidCallback onRefresh;
  final bool filters;

  @override
  State<SmsHistoryList> createState() => _SmsHistoryListState();
}

class _SmsHistoryListState extends State<SmsHistoryList> {
  SmsDelivery? filter;
  bool retrying = false;

  Future<void> _retry(List<SentSms> failed) async {
    final ok = await confirmSheet(
      context,
      title: 'إعادة الإرسال',
      message: 'إعادة ${failed.length} رسالة فشلت؟',
      confirmLabel: 'إعادة',
      confirmColor: AdminNoon.ink,
    );
    if (!ok || !mounted) return;
    setState(() => retrying = true);
    try {
      await const SmsService().send([for (final m in failed) SmsMessage(to: m.phone, message: m.body, ref: m.ref ?? '')]);
      if (!mounted) return;
      showAppSnack(context, 'انبعثت من جديد: ${failed.length}');
      widget.onRefresh();
    } on SmsException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    if (list == null) return const NoonLoading(text: 'جارٍ جلب الرسائل');
    final counts = {for (final s in SmsDelivery.values) s: 0};
    for (final m in list) {
      counts[m.status] = counts[m.status]! + 1;
    }
    final failed = [for (final m in list) if (m.status == SmsDelivery.failed) m];
    final shown = filter == null ? list : [for (final m in list) if (m.status == filter) m];
    String label(String text, int n) => n > 0 ? '$text $n' : text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.filters
                  ? NoonSegment<SmsDelivery?>(
                      value: filter,
                      scroll: true,
                      options: [
                        (null, label('الكل', list.length)),
                        (SmsDelivery.sent, label('انبعثت', counts[SmsDelivery.sent]!)),
                        (SmsDelivery.failed, label('فشلت', counts[SmsDelivery.failed]!)),
                        (SmsDelivery.pending, label('بالانتظار', counts[SmsDelivery.pending]!)),
                      ],
                      onChanged: (v) => setState(() => filter = v),
                    )
                  : const SizedBox.shrink(),
            ),
            NoonButton(icon: Icons.refresh_rounded, tone: NoonTone.ghost, small: true, tooltip: 'تحديث', onPressed: widget.onRefresh),
          ],
        ),
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 8),
          NoonNotice(
            '${failed.length} فشلت',
            sun: true,
            icon: Icons.error_outline_rounded,
            trailing: NoonButton(
              label: 'إعادة الإرسال',
              icon: Icons.replay_rounded,
              small: true,
              busy: retrying,
              onPressed: retrying ? null : () => _retry(failed),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (shown.isEmpty)
          NoonEmpty(list.isEmpty ? 'ما انبعثت رسائل لسا' : 'ما في رسائل بهالحالة', icon: Icons.sms_outlined, dashed: false)
        else
          Container(
            decoration: BoxDecoration(border: Border.all(color: AdminNoon.line), borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  SmsHistoryTile(sms: shown[i], name: shown[i].ref == null ? null : widget.names[shown[i].ref], last: i == shown.length - 1),
              ],
            ),
          ),
      ],
    );
  }
}

/// سطر رسالة: الاسم، الرقم، الوقت، الحالة، ×أجزاء لو أكثر من 1، النص (يتوسّع باللمس)، وسبب الفشل.
class SmsHistoryTile extends StatefulWidget {
  const SmsHistoryTile({super.key, required this.sms, this.name, this.last = false});

  final SentSms sms;
  final String? name;
  final bool last;

  @override
  State<SmsHistoryTile> createState() => _SmsHistoryTileState();
}

class _SmsHistoryTileState extends State<SmsHistoryTile> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.sms;
    final (String label, Color color) = switch (m.status) {
      SmsDelivery.sent => ('انبعثت', AdminNoon.green700),
      SmsDelivery.failed => ('فشلت', AdminNoon.red700),
      SmsDelivery.pending => ('بالانتظار', AdminNoon.warn),
    };
    final name = widget.name;
    final phone = Text(m.phone, textDirection: TextDirection.ltr, style: NoonText.style(11, color: AdminNoon.muted));
    return InkWell(
      onTap: () => setState(() => open = !open),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: widget.last ? null : Border(bottom: BorderSide(color: AdminNoon.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: name == null
                      ? Text(m.phone, textDirection: TextDirection.ltr, style: NoonText.style(13, weight: FontWeight.w700))
                      : Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(13, weight: FontWeight.w700)),
                ),
                if (name != null) ...[const SizedBox(width: 6), phone],
                const Spacer(),
                if (m.parts > 1)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Tooltip(
                      message: 'رسالة طويلة: بتنحسب أكثر من رسالة من الرصيد',
                      child: Text('×${m.parts}', style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.warn)),
                    ),
                  ),
                Text(smsTimeAgo(m.time), style: NoonText.style(11, color: AdminNoon.muted)),
                const SizedBox(width: 8),
                Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(label, style: NoonText.style(11, weight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              m.body,
              maxLines: open ? null : 1,
              overflow: open ? null : TextOverflow.ellipsis,
              style: NoonText.style(12, height: 1.45),
            ),
            if (m.status == SmsDelivery.failed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(smsErrorLabel(m.error), style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.red700)),
              ),
          ],
        ),
      ),
    );
  }
}

/// قائمة المستلمين للاستثناء: علامة لكل طالب (الشيل استثناء)، وتحديد الكل، وبحث.
/// القائمة كسولة (`ListView.builder`) فما بتثقل مع مئات الطلاب.
class _RecipientsSheet extends StatefulWidget {
  const _RecipientsSheet({required this.pool, required this.audience, required this.excluded, this.dueOf});

  final List<SmsStudent> pool;
  final SmsAudience audience;
  final Set<String> excluded;
  final double Function(String id)? dueOf;

  @override
  State<_RecipientsSheet> createState() => _RecipientsSheetState();
}

class _RecipientsSheetState extends State<_RecipientsSheet> {
  late final Set<String> excluded = {...widget.excluded};
  late final List<SmsStudent> withPhone = [for (final s in widget.pool) if (smsHasPhone(s, widget.audience)) s];
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    final shown = q.isEmpty
        ? widget.pool
        : [
            for (final s in widget.pool)
              if (matchStudentSearch(fullName: s.fullName.isNotEmpty ? s.fullName : s.firstName, query: q, phone: s.phone, parentPhone: s.parentPhone, parentName: s.parentName)) s,
          ];
    final selected = withPhone.where((s) => !excluded.contains(s.id)).length;
    final allOn = withPhone.isNotEmpty && selected == withPhone.length;
    final bottom = MediaQuery.paddingOf(context).bottom;
    void toggleAll() => setState(() {
          if (allOn) {
            excluded.addAll(withPhone.map((s) => s.id));
          } else {
            excluded.removeAll(withPhone.map((s) => s.id));
          }
        });
    void toggle(String id) => setState(() {
          if (!excluded.remove(id)) excluded.add(id);
        });

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 14, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AdminNoon.line))),
            child: Row(
              children: [
                Expanded(child: Text('المستلمون', style: NoonText.style(16, weight: FontWeight.w700))),
                NoonButton(label: 'تم', tone: NoonTone.ink, small: true, onPressed: () => Navigator.pop(context, excluded)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              decoration: const InputDecoration(hintText: 'بحث باسم أو رقم', prefixIcon: Icon(Icons.search_rounded, size: 18), isDense: true),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          InkWell(
            onTap: withPhone.isEmpty ? null : toggleAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Checkbox(value: allOn, onChanged: withPhone.isEmpty ? null : (_) => toggleAll()),
                  Text('$selected محدد', style: NoonText.style(12.5, weight: FontWeight.w700)),
                  if (widget.pool.length > withPhone.length)
                    Text(' · ${widget.pool.length - withPhone.length} بلا رقم', style: NoonText.style(12, color: AdminNoon.faint)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AdminNoon.line),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: NoonEmpty('ما في طلاب مطابقين', dashed: false))
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: bottom + 8),
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final s = shown[i];
                      final ok = smsHasPhone(s, widget.audience);
                      final on = ok && !excluded.contains(s.id);
                      final grade = [s.gradeLevel, s.section].where((x) => x.isNotEmpty).join(' ');
                      final due = widget.dueOf?.call(s.id);
                      return Opacity(
                        opacity: ok ? 1 : 0.45,
                        child: InkWell(
                          onTap: ok ? () => toggle(s.id) : null,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 16, 2),
                            child: Row(
                              children: [
                                Checkbox(value: on, onChanged: ok ? (_) => toggle(s.id) : null),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.fullName.isNotEmpty ? s.fullName : s.firstName,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12.5, weight: FontWeight.w700)),
                                      Text.rich(
                                        TextSpan(children: [
                                          TextSpan(text: grade),
                                          if (due != null)
                                            TextSpan(text: ' · ${smsAmount(due)}', style: NoonText.style(11, color: AdminNoon.red700)),
                                        ]),
                                        maxLines: 1,
                                        style: NoonText.style(11, color: AdminNoon.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  ok ? smsPhoneOf(s, widget.audience) : 'بلا رقم',
                                  textDirection: TextDirection.ltr,
                                  style: NoonText.style(11, color: AdminNoon.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// ورقة إدخال قصيرة: اسم القالب، أو عدد رسائل الشحن ومدته. بترجّع القيم بترتيب الحقول.
Future<List<String>?> smsInputSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required List<({String label, String hint, String initial, bool number})> fields,
}) {
  final controllers = [for (final f in fields) TextEditingController(text: f.initial)];
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (ctx) => NoonSheetFrame(
      title: title,
      footer: [
        Expanded(
          child: NoonButton(
            label: confirmLabel,
            tone: NoonTone.sun,
            expand: true,
            onPressed: () => Navigator.pop(ctx, [for (final c in controllers) c.text]),
          ),
        ),
      ],
      children: [
        for (var i = 0; i < fields.length; i++)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoonSheetLabel(fields[i].label),
              TextField(
                controller: controllers[i],
                autofocus: i == 0,
                keyboardType: fields[i].number ? TextInputType.number : TextInputType.text,
                maxLength: fields[i].number ? 7 : 40,
                decoration: InputDecoration(hintText: fields[i].hint, counterText: '', filled: true, fillColor: Colors.white),
              ),
            ],
          ),
      ],
    ),
  ).whenComplete(() {
    // بعد ما تخلص حركة الإغلاق: التخلص بنفس اللحظة بيخرّب الحقل وهو لسا بينرسم
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      for (final c in controllers) {
        c.dispose();
      }
    });
  });
}

/// رسائل SMS اللي انبعتت لطالب (لولي أمره أو إله) من الويب أو الجوال: كل رسالة بتحمل رقم الطالب
/// (`ref`). من ملف الطالب، للمدير. ما بتتحمّل إلا لما تنفتح الورقة.
Future<void> showStudentSmsSheet(BuildContext context, {required String studentId, required String name}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _StudentSmsSheet(studentId: studentId, name: name),
  );
}

class _StudentSmsSheet extends StatefulWidget {
  const _StudentSmsSheet({required this.studentId, required this.name});

  final String studentId;
  final String name;

  @override
  State<_StudentSmsSheet> createState() => _StudentSmsSheetState();
}

class _StudentSmsSheetState extends State<_StudentSmsSheet> {
  List<SentSms>? list;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      list = null;
      error = null;
    });
    try {
      final all = await const SmsService().history();
      if (mounted) setState(() => list = [for (final m in all) if (m.ref == widget.studentId) m]);
    } on SmsException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NoonSheetFrame(
      title: 'رسائل SMS · ${widget.name}',
      children: [
        if (error != null)
          NoonEmpty(error!, icon: Icons.sms_failed_outlined, dashed: false)
        else
          SmsHistoryList(list: list, names: const {}, onRefresh: _load, filters: false),
      ],
    );
  }
}
