import 'dart:async';

import 'package:flutter/material.dart';

import '../data/notes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';

/// الملاحظات بشكل المحادثات — المقابل لـ `NotesParts.tsx` و`Announcements.tsx` في الويب.
///
/// قائمة محادثات (طالب عند المعلم، أو معلم عند الأسرة) تُفتح على فقاعات بترتيب
/// الزمن وخانة كتابة في أسفلها، كالواتساب. الملاحظة من المدرسة، والرد من ولي
/// الأمر على آخرها.

const _teal = Color(0xFF0E7C86);
const _mine = Color(0xFFE7F3F4);

String _errText(Object e, String fallback) => e is NotesException ? e.message : fallback;

// ── الأشرطة ─────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.text, required this.onOpen});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Corner.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.card),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              // خط بلون الإجراء في البداية: حدّ بلونين لا يجتمع مع زوايا مدوّرة
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(color: AppColors.amber, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 20, color: _teal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text('فتح', style: TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
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
      padding: const EdgeInsets.only(bottom: 10),
      child: _Banner(
        icon: Icons.chat_bubble_outline_rounded,
        title: fresh.length > 1 ? '${fresh.length} ملاحظات جديدة' : 'ملاحظة من ${authorLabel(fresh.first.note)}',
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
    final initial = title.trim().isEmpty ? '؟' : title.trim().characters.first;
    final hot = unread > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.hover)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: _mine, shape: BoxShape.circle),
              child: Text(initial, style: const TextStyle(color: _teal, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: title,
                            children: [
                              if (subtitle.isNotEmpty)
                                TextSpan(
                                  text: ' · $subtitle',
                                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          time,
                          style: TextStyle(
                            color: hot ? _teal : AppColors.faint,
                            fontSize: 10.5,
                            fontWeight: hot ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hot ? AppColors.text : AppColors.muted,
                            fontSize: 11.5,
                            fontWeight: hot ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (hot) ...[const SizedBox(width: 6), UnreadBadge(count: unread)],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// عدد الجديد في دائرة.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.onDark = false});

  final int count;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: onDark ? Colors.white : _teal, borderRadius: BorderRadius.circular(9)),
      child: Text(
        '$count',
        style: TextStyle(color: onDark ? _teal : Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
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
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
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
    return Material(
      color: hot ? _teal : Colors.white,
      borderRadius: BorderRadius.circular(Corner.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.field),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Corner.field),
            border: Border.all(color: hot ? _teal : AppColors.lineStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: hot ? Colors.white : AppColors.text),
              const SizedBox(width: 5),
              Text(
                'رسائل',
                style: TextStyle(color: hot ? Colors.white : AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              if (hot) ...[const SizedBox(width: 5), UnreadBadge(count: unread, onDark: true)],
            ],
          ),
        ),
      ),
    );
  }
}

// ── المحادثة ────────────────────────────────────────────────────────────────

/// فقاعة: رسائل صاحب الشاشة في جهة النهاية بلون فاتح، والطرف الآخر أبيض. ملاحظة
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
    final meta = <Widget>[
      if (m.fromSchool && widget.school && m.audience == 'student')
        const Text('للطالب', style: TextStyle(color: AppColors.faint, fontSize: 10)),
      if (m.fromSchool && !widget.school && m.subject.isNotEmpty)
        Text(m.subject, style: const TextStyle(color: AppColors.faint, fontSize: 10)),
      Text(noteTime(m.createdAt), style: const TextStyle(color: AppColors.faint, fontSize: 10)),
      if (m.fromSchool && widget.school)
        Tooltip(
          message: m.readAt.isNotEmpty ? 'قُرئت' : 'لم تُقرأ',
          child: Icon(
            m.readAt.isNotEmpty ? Icons.done_all_rounded : Icons.done_rounded,
            size: 14,
            color: m.readAt.isNotEmpty ? AppColors.success : AppColors.faint,
          ),
        ),
    ];
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
      decoration: BoxDecoration(
        color: mine ? _mine : Colors.white,
        borderRadius: BorderRadiusDirectional.only(
          topStart: mine ? r : tip,
          topEnd: mine ? tip : r,
          bottomStart: r,
          bottomEnd: r,
        ),
        border: Border.all(
          color: widget.fresh ? AppColors.amber : (mine ? const Color(0xFFCFE5E7) : AppColors.line),
          width: widget.fresh ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showAuthor)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m.author, style: const TextStyle(color: _teal, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
          Text(m.body, style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < meta.length; i++) ...[if (i > 0) const SizedBox(width: 6), meta[i]],
            ],
          ),
        ],
      ),
    );
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            widget.onDelete == null ? bubble : GestureDetector(onTap: () => setState(() => picked = !picked), child: bubble),
            if (picked && widget.onDelete != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger, visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('حذف', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: [
        if (msgs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Text(
              'لا رسائل بعد',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.faint, fontSize: 12),
            ),
          ),
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: widget.disabledText.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                widget.disabledText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.quick)
                  SizedBox(
                    height: 30,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final q in quickNotes)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ActionChip(
                              label: Text(q),
                              onPressed: () => _text.text = q,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              labelStyle: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppColors.line),
                              shape: const StadiumBorder(),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (widget.quick) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.withAudience) ...[
                      Tooltip(
                        message: 'لمن تُرسل',
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => audience = audience == 'parent' ? 'student' : 'parent'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            foregroundColor: AppColors.text,
                            side: const BorderSide(color: AppColors.lineStrong),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(
                            audience == 'parent' ? Icons.people_alt_outlined : Icons.person_outline,
                            size: 16,
                            color: _teal,
                          ),
                          label: Text(
                            audienceLabels[audience]!,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: noteMax,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                        decoration: InputDecoration(
                          hintText: widget.placeholder,
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          filled: true,
                          fillColor: Colors.white,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.lineStrong),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _teal),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: IconButton.filled(
                        tooltip: 'إرسال',
                        onPressed: _text.text.trim().isEmpty || busy ? null : _send,
                        style: IconButton.styleFrom(backgroundColor: _teal, disabledBackgroundColor: _teal.withValues(alpha: 0.4)),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            // السهم يشير إلى جهة الإرسال في العربية
                            : Transform.flip(flipX: true, child: const Icon(Icons.send_rounded, size: 19, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// صفحة محادثة: العنوان، والفقاعات، وخانة الكتابة في أسفلها.
class _ChatScaffold extends StatelessWidget {
  const _ChatScaffold({required this.title, this.subtitle = '', required this.body, this.composer});

  final String title;
  final String subtitle;
  final Widget body;
  final Widget? composer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppText.family, color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
              ),
          ],
        ),
      ),
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: AppText.family),
        child: Column(
          children: [
            Expanded(child: body),
            ?composer,
          ],
        ),
      ),
    );
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
              disabledText: latest.replies.length >= replyLimit ? 'وصلت حد الردود على هذه الملاحظة' : '',
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
    Widget arrow(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(icon, size: 18, color: dim),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Corner.card + 2),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppColors.navy, AppColors.navyMid],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -40,
            top: -60,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 14),
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
                        borderRadius: BorderRadius.circular(Corner.field),
                      ),
                      child: const Icon(Icons.campaign_outlined, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إعلان من المدرسة · ${noteTime(a.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: dim, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (shown.length > 1) ...[
                      arrow(Icons.chevron_right_rounded, 'السابق', () => setState(() => index = i == 0 ? shown.length - 1 : i - 1)),
                      Text('${i + 1}/${shown.length}', style: TextStyle(color: dim, fontSize: 11, fontWeight: FontWeight.w700)),
                      arrow(Icons.chevron_left_rounded, 'التالي', () => setState(() => index = (i + 1) % shown.length)),
                    ],
                    IconButton(
                      tooltip: 'إخفاء',
                      onPressed: () => _dismiss(a.id),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded, size: 18, color: dim),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Text(
                    a.body,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.6),
                  ),
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
        if (threads.isEmpty) error = _errText(e, 'تعذّر تحميل الملاحظات');
      });
    }
  }

  Future<void> _remove(String id) async {
    final ok = await confirmSheet(context, title: 'حذف الملاحظة؟', message: 'تختفي عند الأسرة أيضاً', confirmLabel: 'حذف');
    if (!ok || !mounted) return;
    try {
      await widget.service.remove(id);
      await _reload();
    } catch (e) {
      if (mounted) showAppSnack(context, _errText(e, 'تعذّر حذف الملاحظة'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ChatScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      body: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ),
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
        padding: const EdgeInsets.all(14),
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined, size: 20, color: _teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تصل كل أسرة من ${studentIds.length} نسخة خاصة، وردّها يظهر في محادثة ابنها',
                    style: const TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
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
