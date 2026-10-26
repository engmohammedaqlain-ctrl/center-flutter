import 'dart:async';

import 'package:flutter/material.dart';

import '../data/notes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/noon_ui.dart';
import '../widgets/widgets.dart';

/// الملاحظات بشكل المحادثات — المقابل لـ `NotesParts.tsx` و`Announcements.tsx` في الويب،
/// بهوية نون.
///
/// قائمة محادثات (طالب عند المعلم، أو معلم عند الأسرة) تُفتح على فقاعات بترتيب
/// الزمن وخانة كتابة في أسفلها، كالواتساب. الملاحظة من المدرسة، والرد من ولي
/// الأمر على آخرها.

String _errText(Object e, String fallback) => e is NotesException ? e.message : fallback;

// ── الأشرطة ─────────────────────────────────────────────────────────────────

/// لوح بشريط بلون الإجراء على بدايته: أيقونة، وعنوان وسطر، و«فتح».
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.text, required this.onOpen});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(NoonRadius.panel);
    return Container(
      decoration: nPanelDecoration(),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            highlightColor: Noon.mist2,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: Noon.action),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: Noon.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(14, weight: FontWeight.w700)),
                                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('فتح', style: nText(12, weight: FontWeight.w700, color: Noon.tealD)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط فوق محتوى بوابة الأسرة حين تصل ملاحظة لم تُقرأ.
class NewNotesBanner extends StatelessWidget {
  const NewNotesBanner({super.key, required this.threads, required this.onOpen});

  final List<NoteThread> threads;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final fresh = threads.where((t) => !t.read).toList();
    if (fresh.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: NoonSize.gap),
      child: _Banner(
        icon: Icons.chat_bubble_outline_rounded,
        title: fresh.length > 1 ? '${fresh.length} رسائل جديدة' : 'رسالة من ${authorLabel(fresh.first.note)}',
        text: fresh.first.note.body,
        onOpen: onOpen,
      ),
    );
  }
}

// ── قائمة المحادثات ─────────────────────────────────────────────────────────

/// صف محادثة: حرف أول في دائرة، الاسم وآخر رسالة، والوقت وعدد الجديد.
class NoteChatRow extends StatelessWidget {
  const NoteChatRow({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.preview,
    this.time = '',
    this.unread = 0,
    this.last = false,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String preview;
  final String time;
  final int unread;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hot = unread > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: Noon.mist,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Noon.line))),
          child: Row(
            children: [
              NInitial(name: title.trim().isEmpty ? '؟' : title, size: 40, fontSize: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: title,
                              children: [
                                if (subtitle.isNotEmpty)
                                  TextSpan(text: ' · $subtitle', style: TextStyle(color: Noon.muted, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nText(14, weight: FontWeight.w700),
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            time,
                            style: nText(11, weight: hot ? FontWeight.w700 : FontWeight.w500, color: hot ? Noon.tealD : Noon.muted),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nText(12, weight: hot ? FontWeight.w700 : FontWeight.w500, color: hot ? Noon.text : Noon.muted),
                          ),
                        ),
                        if (hot) ...[const SizedBox(width: 8), UnreadBadge(count: unread)],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عدد الجديد في دائرة بلون العنصر النشط (أو أبيض على زر ممتلئ).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.onDark = false});

  final int count;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final h = onDark ? 18.0 : 20.0;
    return Container(
      constraints: BoxConstraints(minWidth: h),
      height: h,
      padding: EdgeInsets.symmetric(horizontal: onDark ? 4 : 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: onDark ? Colors.white : Noon.teal, borderRadius: BorderRadius.circular(h / 2)),
      child: Text(
        '$count',
        style: nText(onDark ? 10 : 11, weight: FontWeight.w700, color: onDark ? Noon.tealD : Noon.onTeal, height: 1),
      ),
    );
  }
}

/// آخر رسالة تحت الاسم: «ولي الأمر:» عند المعلم لرد الأهل، و«أنت:» عند الأسرة لردها.
String notePreview(Conversation c, {required bool school}) {
  final prefix = c.last.fromSchool ? '' : (school ? 'ولي الأمر: ' : 'أنت: ');
  return '$prefix${c.last.body}';
}

/// محادثات الأسرة بلا بطاقة مادة (الإدارة، أو معلم لا يدرّس الطالب مادة): صفوف فوق بطاقات المواد.
class FamilyOtherChats extends StatelessWidget {
  const FamilyOtherChats({super.key, required this.convs, required this.onOpen});

  final List<Conversation> convs;
  final ValueChanged<Conversation> onOpen;

  @override
  Widget build(BuildContext context) {
    if (convs.isEmpty) return const SizedBox.shrink();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: nPanelDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < convs.length; i++)
            NoteChatRow(
              title: convs[i].title,
              subtitle: convs[i].subtitle,
              preview: notePreview(convs[i], school: false),
              time: noteTime(convs[i].last.createdAt),
              unread: convs[i].unread,
              last: i == convs.length - 1,
              onTap: () => onOpen(convs[i]),
            ),
        ],
      ),
    );
  }
}

/// زر «رسائل» على بطاقة المادة حين كتب معلمها، وعليه عدد الجديد.
class SubjectChatButton extends StatelessWidget {
  const SubjectChatButton({super.key, required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hot = unread > 0;
    final radius = BorderRadius.circular(NoonRadius.btn);
    final fg = hot ? Colors.white : Noon.text;
    return Material(
      color: hot ? Noon.teal : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: hot ? Noon.teal : Noon.line)),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 16, color: fg),
              const SizedBox(width: 6),
              Text('رسائل', style: nText(12, weight: FontWeight.w700, color: fg)),
              if (hot) ...[const SizedBox(width: 6), UnreadBadge(count: unread, onDark: true)],
            ],
          ),
        ),
      ),
    );
  }
}

// ── المحادثة ────────────────────────────────────────────────────────────────

/// فقاعة: رسائل صاحب الشاشة في جهة النهاية بتظليل `mist`، والطرف الآخر أبيض. ملاحظة
/// المدرسة تحمل لمن كُتبت، وعند كاتبها علامتا القراءة. لمس فقاعة يمكن حذفها يُظهر «حذف».
class _Bubble extends StatefulWidget {
  const _Bubble({
    super.key,
    required this.m,
    required this.mine,
    required this.school,
    this.showAuthor = false,
    this.fresh = false,
    this.onDelete,
  });

  final ChatMessage m;
  final bool mine;

  /// شاشة المعلم أو الإدارة، وإلا الأسرة.
  final bool school;
  final bool showAuthor;
  final bool fresh;
  final VoidCallback? onDelete;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  bool picked = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final mine = widget.mine;
    const r = Radius.circular(12);
    const tip = Radius.circular(4);
    final metaStyle = nText(10, weight: FontWeight.w500, color: Noon.muted);
    final meta = <Widget>[
      if (m.fromSchool && widget.school && m.audience == 'student') Text('للطالب', style: metaStyle),
      if (m.fromSchool && !widget.school && m.subject.isNotEmpty) Text(m.subject, style: metaStyle),
      Text(noteTime(m.createdAt), style: metaStyle),
      if (m.fromSchool && widget.school)
        Tooltip(
          message: m.readAt.isNotEmpty ? 'قُرئت' : 'لم تُقرأ',
          child: Icon(
            m.readAt.isNotEmpty ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: m.readAt.isNotEmpty ? Noon.green600 : Noon.muted,
          ),
        ),
    ];
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: mine ? Noon.mist : Colors.white,
        // ذيل الفقاعة في ركنها العلوي من جهة كاتبها
        borderRadius: BorderRadiusDirectional.only(
          topStart: mine ? r : tip,
          topEnd: mine ? tip : r,
          bottomStart: r,
          bottomEnd: r,
        ),
        border: Border.all(
          color: widget.fresh ? Noon.action : (mine ? Noon.headLine : Noon.line),
          width: widget.fresh ? 2 : 1,
        ),
        boxShadow: const [BoxShadow(color: Color(0x0F0A3336), blurRadius: 0.9, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showAuthor)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m.author, style: nText(11, weight: FontWeight.w700, color: Noon.tealD)),
            ),
          Text(m.body, style: nText(14, height: 24 / 14)),
          const SizedBox(height: 2),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < meta.length; i++) ...[if (i > 0) const SizedBox(width: 6), meta[i]],
              ],
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            widget.onDelete == null ? bubble : GestureDetector(onTap: () => setState(() => picked = !picked), child: bubble),
            if (picked && widget.onDelete != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: NBtn(tone: NBtnTone.danger, small: true, icon: Icons.delete_outline_rounded, label: 'حذف', onTap: widget.onDelete),
              ),
          ],
        ),
      ),
    );
  }
}

/// الفقاعات بترتيب الزمن، وتنزل إلى آخرها عند الفتح وكل رسالة جديدة.
class _ChatList extends StatefulWidget {
  const _ChatList({
    required this.messages,
    required this.school,
    this.showAuthor = false,
    this.fresh = const {},
    this.onDelete,
  });

  final List<ChatMessage> messages;
  final bool school;
  final bool showAuthor;
  final Set<String> fresh;

  /// حذف ملاحظة المدرسة (معرّف الأصل). بلاه لا حذف.
  final ValueChanged<String>? onDelete;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void didUpdateWidget(covariant _ChatList old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length) _toEnd();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.messages;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (msgs.isEmpty) const NEmpty(text: 'لا رسائل بعد', icon: Icons.chat_bubble_outline_rounded, dashed: false),
        for (final m in msgs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _Bubble(
              key: ValueKey(m.id),
              m: m,
              // رسائل صاحب الشاشة: المدرسة عند المعلم، والرد عند الأسرة
              mine: widget.school == m.fromSchool,
              school: widget.school,
              showAuthor: widget.showAuthor && m.fromSchool,
              fresh: widget.fresh.contains(m.id),
              onDelete: widget.onDelete != null && m.fromSchool ? () => widget.onDelete!(m.noteId) : null,
            ),
          ),
      ],
    );
  }
}

/// خانة الكتابة في أسفل المحادثة: عبارات جاهزة بلمسة (للمدرسة)، ولمن تُرسل، والنص وزر الإرسال.
/// بلا [withAudience] = رد ولي الأمر.
class NoteComposer extends StatefulWidget {
  const NoteComposer({
    super.key,
    required this.onSend,
    this.withAudience = false,
    this.quick = false,
    this.placeholder = 'اكتب رسالة',
    this.disabledText = '',
  });

  /// يرمي [NotesException] عند الفشل، فيبقى النص في الخانة.
  final Future<void> Function(String body, String audience) onSend;
  final bool withAudience;
  final bool quick;
  final String placeholder;
  final String disabledText;

  @override
  State<NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<NoteComposer> {
  final _text = TextEditingController();
  String audience = 'parent';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.onSend(_text.text, audience);
      if (mounted) _text.clear();
    } catch (e) {
      if (mounted) showAppSnack(context, _errText(e, 'تعذّر الإرسال'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.disabledText.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(widget.disabledText, textAlign: TextAlign.center, style: nText(12, weight: FontWeight.w500, color: Noon.muted)),
      );
    }
    final radius = BorderRadius.circular(NoonRadius.btn);
    final canSend = _text.text.trim().isNotEmpty && !busy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.quick) ...[
          SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: quickNotes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: Noon.line)),
                child: InkWell(
                  borderRadius: radius,
                  onTap: () => _text.text = quickNotes[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(child: Text(quickNotes[i], style: nText(11, weight: FontWeight.w700, color: Noon.muted))),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.withAudience) ...[
              Tooltip(
                message: 'لمن تُرسل',
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: Noon.line)),
                  child: InkWell(
                    borderRadius: radius,
                    onTap: () => setState(() => audience = audience == 'parent' ? 'student' : 'parent'),
                    child: SizedBox(
                      height: 40,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(audience == 'parent' ? Icons.people_alt_outlined : Icons.person_outline_rounded, size: 16, color: Noon.teal),
                            const SizedBox(width: 6),
                            Text(audienceLabels[audience]!, style: nText(11, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40, maxHeight: 112),
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: noteMax,
                  textInputAction: TextInputAction.newline,
                  style: nText(14, height: 24 / 14),
                  decoration: nInputDecoration(hint: widget.placeholder).copyWith(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'إرسال',
              child: Opacity(
                opacity: canSend ? 1 : 0.4,
                child: Material(
                  color: Noon.teal,
                  borderRadius: radius,
                  child: InkWell(
                    borderRadius: radius,
                    onTap: canSend ? _send : null,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: busy
                          ? Center(
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Noon.onTeal)),
                            )
                          // السهم يشير إلى جهة الإرسال في العربية
                          : Transform.flip(flipX: true, child: Icon(Icons.send_rounded, size: 18, color: Noon.onTeal)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// صفحة محادثة (`NPage`): ترويسة الحبر بالعنوان، والفقاعات، وخانة الكتابة في تذييلها.
class _ChatScaffold extends StatelessWidget {
  const _ChatScaffold({required this.title, this.subtitle = '', required this.body, this.composer});

  final String title;
  final String subtitle;
  final Widget body;
  final Widget? composer;

  @override
  Widget build(BuildContext context) {
    return NPageScaffold(title: title, subtitle: subtitle, body: body, footer: composer, children: const []);
  }
}

// ── الأسرة ──────────────────────────────────────────────────────────────────

/// محادثة الأسرة مع معلم (أو الإدارة): تُفتح من بطاقة مادته أو من شريط «ملاحظة جديدة»
/// أو من الإشعار. فتحها يعلّم ملاحظاتها وحدها مقروءة، وولي الأمر يرد على آخرها.
/// الطالب يقرأ ولا يرد.
class FamilyChatPage extends StatefulWidget {
  const FamilyChatPage({
    super.key,
    required this.conv,
    required this.canReply,
    this.service = const NotesService(),
  });

  final Conversation conv;
  final bool canReply;
  final NotesService service;

  @override
  State<FamilyChatPage> createState() => _FamilyChatPageState();
}

class _FamilyChatPageState extends State<FamilyChatPage> {
  late Conversation conv = widget.conv;
  late final Set<String> fresh = {
    for (final t in widget.conv.threads)
      if (!t.read) t.id,
  };

  @override
  void initState() {
    super.initState();
    unawaited(widget.service.markFamilyRead(fresh.toList()).catchError((_) {}));
  }

  Future<void> _reply(String body) async {
    await widget.service.reply(conv.threads.first.id, body);
    try {
      final next = byAuthor(await widget.service.family()).where((c) => c.key == conv.key).firstOrNull;
      if (next != null && mounted) setState(() => conv = next);
    } catch (_) {
      // الرد وصل؛ يظهر عند الفتح التالي
    }
  }

  @override
  Widget build(BuildContext context) {
    final latest = conv.threads.first;
    return _ChatScaffold(
      title: conv.title,
      subtitle: conv.subtitle,
      body: _ChatList(messages: chatMessages(conv.threads), school: false, fresh: fresh),
      composer: widget.canReply
          ? NoteComposer(
              placeholder: 'اكتب ردك',
              disabledText: latest.replies.length >= replyLimit ? 'وصلت حد الردود' : '',
              onSend: (body, _) => _reply(body),
            )
          : null,
    );
  }
}

/// محادثة الأسرة التي فيها الملاحظة [noteId] (الإشعار يحملها)، وإلا التي فيها أحدث ملاحظة لم تُقرأ.
Conversation? familyConversationOf(List<Conversation> convs, {String noteId = ''}) {
  if (noteId.isNotEmpty) {
    final hit = convs.where((c) => c.threads.any((t) => t.id == noteId)).firstOrNull;
    if (hit != null) return hit;
  }
  return convs.where((c) => c.unread > 0).firstOrNull;
}

/// إعلانات المدرسة فوق محتوى البوابة: بطاقة واحدة بتدرّج ألوان المدرسة تتنقل بينها،
/// وكل إعلان يُخفى على هذا الجهاز. تُجلب عند الفتح وكلما تغيّر [reloadTick].
class FamilyAnnouncementsCard extends StatefulWidget {
  const FamilyAnnouncementsCard({super.key, this.service = const NotesService(), this.reloadTick = 0});

  final NotesService service;
  final int reloadTick;

  @override
  State<FamilyAnnouncementsCard> createState() => _FamilyAnnouncementsCardState();
}

class _FamilyAnnouncementsCardState extends State<FamilyAnnouncementsCard> {
  List<SchoolAnnouncement> items = const [];
  List<String> dismissed = const [];
  int index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(withDismissed: true));
  }

  @override
  void didUpdateWidget(covariant FamilyAnnouncementsCard old) {
    super.didUpdateWidget(old);
    if (old.reloadTick != widget.reloadTick) unawaited(_load());
  }

  Future<void> _load({bool withDismissed = false}) async {
    if (withDismissed) {
      final d = await DismissedAnnouncements.load();
      if (mounted) setState(() => dismissed = d);
    }
    try {
      final list = await widget.service.announcements();
      if (mounted) setState(() => items = list);
    } catch (_) {}
  }

  Future<void> _dismiss(String id) async {
    setState(() => dismissed = [...dismissed, id]);
    final kept = await DismissedAnnouncements.add(dismissed.where((x) => x != id).toList(), id);
    if (mounted) setState(() => dismissed = kept);
  }

  @override
  Widget build(BuildContext context) {
    final shown = items.where((a) => !dismissed.contains(a.id)).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final i = index.clamp(0, shown.length - 1);
    final a = shown[i];
    final dim = Colors.white.withValues(alpha: 0.8);
    final stops = Noon.hero(NoonHeroTone.theme);
    Widget arrow(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 16, color: dim)),
          ),
        );
    // بطاقة واحدة بتدرّج ثيم المدرسة (كبطاقات الأرقام المهمة)، والإعلانات الأخرى بالتنقل بينها
    return Container(
      margin: const EdgeInsets.only(bottom: NoonSize.gap),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: NoonRadius.hero,
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, stops: const [0, 0.58, 1], colors: stops),
        boxShadow: [BoxShadow(color: stops.first.withValues(alpha: 0.28), blurRadius: 14.7, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -60,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Positioned(left: 0, right: 0, top: 0, child: Container(height: 1, color: Colors.white.withValues(alpha: 0.12))),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(NoonRadius.tile),
                      ),
                      child: const Icon(Icons.campaign_outlined, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إعلان من المدرسة · ${noteTime(a.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nText(12.5, weight: FontWeight.w500, color: dim),
                      ),
                    ),
                    if (shown.length > 1) ...[
                      arrow(Icons.chevron_right_rounded, 'السابق', () => setState(() => index = i == 0 ? shown.length - 1 : i - 1)),
                      Text('${i + 1}/${shown.length}', style: nText(11, weight: FontWeight.w700, color: dim)),
                      arrow(Icons.chevron_left_rounded, 'التالي', () => setState(() => index = (i + 1) % shown.length)),
                    ],
                    Tooltip(
                      message: 'إخفاء',
                      child: InkWell(
                        onTap: () => _dismiss(a.id),
                        child: SizedBox(width: 32, height: 32, child: Icon(Icons.close_rounded, size: 16, color: dim)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(a.body, style: nText(15, weight: FontWeight.w700, color: Colors.white, height: 28 / 15)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── المعلم والإدارة ─────────────────────────────────────────────────────────

/// محادثة طالب عند المعلم أو الإدارة: ما كُتب له وردود أهله، والكتابة في أسفلها.
/// [threads] ما في يد الشاشة الآن؛ بلاه تُجلب محادثة الطالب (الإدارة من الإشعار).
/// فتحها يعلّم ردود الأهل مقروءة، وتبقى مميزة في هذه الفتحة.
class SchoolChatPage extends StatefulWidget {
  const SchoolChatPage({
    super.key,
    required this.studentId,
    required this.title,
    this.subtitle = '',
    this.subject = '',
    this.threads,
    this.showAuthor = false,
    this.service = const NotesService(),
  });

  final String studentId;
  final String title;
  final String subtitle;

  /// مادة المعلم: تُكتب مع الملاحظة فتظهر للأسرة في محادثة مادته.
  final String subject;
  final List<NoteThread>? threads;

  /// اسم الكاتب فوق الفقاعة: عند الإدارة أكثر من معلم في محادثة واحدة.
  final bool showAuthor;
  final NotesService service;

  @override
  State<SchoolChatPage> createState() => _SchoolChatPageState();
}

class _SchoolChatPageState extends State<SchoolChatPage> {
  List<NoteThread> threads = const [];
  bool loading = true;
  String error = '';
  final fresh = <String>{};

  @override
  void initState() {
    super.initState();
    final given = widget.threads;
    if (given != null) {
      threads = given;
      loading = false;
      _markRead();
    }
    unawaited(_reload());
  }

  void _markRead() {
    if (unreadReplies(threads) == 0) return;
    for (final t in threads) {
      for (final r in t.replies) {
        if (!r.read) fresh.add(r.id);
      }
    }
    unawaited(widget.service.markRead().catchError((_) {}));
  }

  Future<void> _reload() async {
    try {
      final list = await widget.service.school(studentId: widget.studentId);
      if (!mounted) return;
      setState(() {
        threads = list;
        loading = false;
        error = '';
      });
      _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (threads.isEmpty) error = _errText(e, 'تعذّر تحميل الرسائل');
      });
    }
  }

  Future<void> _remove(String id) async {
    final ok = await confirmSheet(context, title: 'حذف الرسالة؟', message: 'تختفي عند الأسرة أيضاً', confirmLabel: 'حذف');
    if (!ok || !mounted) return;
    try {
      await widget.service.remove(id);
      await _reload();
    } catch (e) {
      if (mounted) showAppSnack(context, _errText(e, 'تعذّر الحذف'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ChatScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      body: loading
          ? ListView(children: const [NLoading(text: 'جارٍ التحميل')])
          : error.isNotEmpty
              ? ListView(
                  padding: const EdgeInsets.all(NoonSize.page),
                  children: [NNotice(text: error, sun: true)],
                )
              : _ChatList(
                  messages: chatMessages(threads),
                  school: true,
                  showAuthor: widget.showAuthor,
                  fresh: fresh,
                  onDelete: _remove,
                ),
      composer: NoteComposer(
        withAudience: true,
        quick: true,
        onSend: (body, audience) async {
          await widget.service.send(studentId: widget.studentId, body: body, audience: audience, subject: widget.subject);
          await _reload();
        },
      ),
    );
  }
}

/// «رسالة للصف»: تصل كل أسرة نسخة خاصة، وردّها يظهر في محادثة ابنها. يعيد عدد من وصلتهم.
class ClassMessagePage extends StatelessWidget {
  const ClassMessagePage({
    super.key,
    required this.studentIds,
    this.subject = '',
    this.service = const NotesService(),
  });

  final List<String> studentIds;
  final String subject;
  final NotesService service;

  @override
  Widget build(BuildContext context) {
    return _ChatScaffold(
      title: 'رسالة للصف',
      subtitle: subject,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          NNotice(
            icon: Icons.campaign_outlined,
            text: 'تصل كل أسرة من ${studentIds.length} نسخة خاصة، وردّها يظهر في محادثة ابنها',
          ),
        ],
      ),
      composer: NoteComposer(
        withAudience: true,
        quick: true,
        placeholder: 'اكتب رسالة للصف',
        onSend: (body, audience) async {
          final n = await service.sendMany(studentIds: studentIds, body: body, audience: audience, subject: subject);
          if (!context.mounted) return;
          showAppSnack(context, 'أُرسلت لـ $n طالب');
          Navigator.of(context).pop(n);
        },
      ),
    );
  }
}
