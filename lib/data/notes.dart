/// الملاحظات بين المدرسة والأسرة، وإعلانات المدرسة — المقابل لـ
/// `features/notes/notes.service.ts` و`Announcements.tsx` في الويب.
///
/// المعلم أو الإدارة يكتب لولي أمر طالب أو للطالب نفسه، وولي الأمر يرد على
/// الملاحظة (حتى 3 ردود) ولا يبدأ محادثة. نص فقط وعبر دوال الخادم وحدها: لا
/// مزامنة ولا نسخة على الجهاز، فتحتاج اتصالاً.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'supabase.dart';
import 'user_message.dart';

const noteMax = 500;
const replyLimit = 3;

const audienceLabels = {'parent': 'ولي الأمر', 'student': 'الطالب'};

/// عبارات جاهزة بلمسة، تُعدَّل قبل الإرسال.
const quickNotes = [
  'أداء ممتاز اليوم، شكراً لمتابعتكم',
  'لم يُسلَّم الواجب',
  'يحتاج متابعة في البيت',
  'تأخر عن الحصة',
  'نرجو التواصل مع المدرسة',
];

String _s(Object? v) => v == null ? '' : '$v';

/// صف كما يصل من `family_notes` أو `school_notes`. الحقل الغائب نص فارغ.
class StudentNote {
  const StudentNote({
    required this.id,
    this.studentId = '',
    this.audience = 'parent',
    this.body = '',
    this.authorRole = 'teacher',
    this.authorName = '',
    this.subjectName = '',
    this.replyTo = '',
    this.readAt = '',
    this.createdAt = '',
    this.studentName = '',
  });

  final String id;
  final String studentId;

  /// `parent` أو `student`.
  final String audience;
  final String body;

  /// `school` أو `teacher` أو `parent`.
  final String authorRole;
  final String authorName;
  final String subjectName;

  /// معرّف الملاحظة التي هذا الصف ردٌّ عليها.
  final String replyTo;
  final String readAt;
  final String createdAt;

  /// في قائمة المعلم والإدارة وحدها.
  final String studentName;

  bool get read => readAt.isNotEmpty;

  factory StudentNote.fromMap(Map<dynamic, dynamic> m) => StudentNote(
        id: _s(m['id']),
        studentId: _s(m['student_id']),
        audience: m['audience'] == 'student' ? 'student' : 'parent',
        body: _s(m['body']),
        authorRole: _s(m['author_role']).isEmpty ? 'teacher' : _s(m['author_role']),
        authorName: _s(m['author_name']).trim(),
        subjectName: _s(m['subject_name']).trim(),
        replyTo: _s(m['reply_to']),
        readAt: _s(m['read_at']),
        createdAt: _s(m['created_at']),
        studentName: _s(m['student_name']).trim(),
      );

  StudentNote markedRead(String at) => StudentNote(
        id: id,
        studentId: studentId,
        audience: audience,
        body: body,
        authorRole: authorRole,
        authorName: authorName,
        subjectName: subjectName,
        replyTo: replyTo,
        readAt: read ? readAt : at,
        createdAt: createdAt,
        studentName: studentName,
      );
}

/// ملاحظة وردود ولي الأمر عليها.
class NoteThread {
  const NoteThread(this.note, this.replies);

  final StudentNote note;
  final List<StudentNote> replies;

  String get id => note.id;
  String get studentId => note.studentId;
  String get createdAt => note.createdAt;
  bool get read => note.read;
}

/// الصفوف كما تصل من الخادم ← ملاحظات بردودها: الأحدث أولاً، والردود بترتيب كتابتها.
List<NoteThread> threadNotes(List<StudentNote> rows) {
  final replies = <String, List<StudentNote>>{};
  for (final r in rows) {
    if (r.replyTo.isEmpty) continue;
    (replies[r.replyTo] ??= []).add(r);
  }
  final notes = rows.where((r) => r.replyTo.isEmpty).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return [
    for (final n in notes)
      NoteThread(n, (replies[n.id] ?? <StudentNote>[])..sort((a, b) => a.createdAt.compareTo(b.createdAt))),
  ];
}

final _titled = RegExp(r'^(أ\.|أ\s|الأستاذ|الأستاذة|المعلم|المعلمة)');

/// «أ. محمد»، ولا تتكرر «أ.» إن كتبتها المدرسة في الاسم.
String teacherLabel(String? name) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return 'المعلم';
  return _titled.hasMatch(n) ? n : 'أ. $n';
}

/// من كتب الملاحظة كما تراه الأسرة.
String authorLabel(StudentNote n) => switch (n.authorRole) {
      'teacher' => teacherLabel(n.authorName),
      'school' => 'الإدارة',
      _ => n.authorName.isEmpty ? 'ولي الأمر' : n.authorName,
    };

/// رسالة في المحادثة: ملاحظة المدرسة أو رد ولي الأمر، بترتيب الزمن.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.noteId,
    required this.fromSchool,
    required this.body,
    required this.createdAt,
    required this.author,
    required this.audience,
    this.subject = '',
    this.readAt = '',
    this.replies = 0,
  });

  final String id;

  /// ملاحظة الأصل: للرد عليها ولحذفها.
  final String noteId;

  /// ملاحظة المدرسة، وإلا رد الأسرة.
  final bool fromSchool;
  final String body;
  final String createdAt;
  final String author;
  final String audience;
  final String subject;
  final String readAt;
  final int replies;
}

List<ChatMessage> chatMessages(List<NoteThread> threads) {
  final out = <ChatMessage>[];
  for (final t in threads) {
    final n = t.note;
    out.add(ChatMessage(
      id: n.id,
      noteId: n.id,
      fromSchool: true,
      body: n.body,
      createdAt: n.createdAt,
      author: authorLabel(n),
      audience: n.audience,
      subject: n.subjectName,
      readAt: n.readAt,
      replies: t.replies.length,
    ));
    for (final r in t.replies) {
      out.add(ChatMessage(
        id: r.id,
        noteId: n.id,
        fromSchool: false,
        body: r.body,
        createdAt: r.createdAt,
        author: authorLabel(r),
        audience: n.audience,
        readAt: r.readAt,
      ));
    }
  }
  return out..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

/// محادثة في القائمة: طالب عند المعلم، أو كاتب (معلم المادة أو الإدارة) عند الأسرة.
class Conversation {
  const Conversation({
    required this.key,
    required this.title,
    this.subtitle = '',
    required this.threads,
    required this.last,
    required this.unread,
  });

  final String key;
  final String title;
  final String subtitle;

  /// الأحدث أولاً.
  final List<NoteThread> threads;
  final ChatMessage last;

  /// للأسرة: ملاحظات لم تُقرأ، وللمدرسة: ردود لم تُقرأ.
  final int unread;
}

/// ما لم تقرأه الأسرة من ملاحظات المدرسة.
int unreadNotes(List<NoteThread> threads) => threads.where((t) => !t.read).length;

/// ردود الأهل التي لم يقرأها الكاتب.
int unreadReplies(List<NoteThread> threads) =>
    threads.fold(0, (n, t) => n + t.replies.where((r) => !r.read).length);

List<Conversation> _toConversations(
  Map<String, List<NoteThread>> groups,
  ({String title, String subtitle}) Function(NoteThread t) label, {
  required bool family,
}) {
  final out = [
    for (final e in groups.entries)
      () {
        final msgs = chatMessages(e.value);
        final l = label(e.value.first);
        return Conversation(
          key: e.key,
          title: l.title,
          subtitle: l.subtitle,
          threads: e.value,
          last: msgs.last,
          unread: family ? unreadNotes(e.value) : unreadReplies(e.value),
        );
      }(),
  ];
  return out..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
}

/// محادثات المعلم والإدارة: واحدة لكل طالب، الأحدث نشاطاً أولاً.
List<Conversation> byStudent(List<NoteThread> threads) {
  final groups = <String, List<NoteThread>>{};
  for (final t in threads) {
    (groups[t.studentId] ??= []).add(t);
  }
  return _toConversations(
    groups,
    (t) => (title: t.note.studentName.isEmpty ? 'طالب' : t.note.studentName, subtitle: ''),
    family: false,
  );
}

/// مفتاح محادثة الأسرة مع معلم مادة: به تُربط بطاقة المادة بمحادثتها.
String teacherChatKey(String? teacherName, String? subjectName) =>
    '${(teacherName ?? '').trim()}|${(subjectName ?? '').trim()}';

/// محادثات الأسرة: واحدة لكل كاتب (معلم ومادته، أو الإدارة).
List<Conversation> byAuthor(List<NoteThread> threads) {
  final groups = <String, List<NoteThread>>{};
  for (final t in threads) {
    final n = t.note;
    final key = n.authorRole == 'school' ? 'school' : teacherChatKey(n.authorName, n.subjectName);
    (groups[key] ??= []).add(t);
  }
  return _toConversations(
    groups,
    (t) => (title: authorLabel(t.note), subtitle: t.note.authorRole == 'teacher' ? t.note.subjectName : ''),
    family: true,
  );
}

/// «اليوم 10:30» أو «أمس 10:30» أو «12/10».
String noteTime(String iso, {DateTime? now}) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final d = parsed.toLocal();
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(d.hour)}:${two(d.minute)}';
  // ساعات لا أيام: يوم تغيير التوقيت 23 أو 25 ساعة
  final days = (DateTime(n.year, n.month, n.day).difference(DateTime(d.year, d.month, d.day)).inHours / 24).round();
  if (days == 0) return 'اليوم $time';
  if (days == 1) return 'أمس $time';
  return d.year == n.year ? '${d.day}/${d.month}' : '${d.day}/${d.month}/${d.year}';
}

/// إعلان مدرسة في نطاق الطالب.
class SchoolAnnouncement {
  const SchoolAnnouncement({required this.id, required this.body, this.createdAt = ''});

  final String id;
  final String body;
  final String createdAt;

  factory SchoolAnnouncement.fromMap(Map<dynamic, dynamic> m) =>
      SchoolAnnouncement(id: _s(m['id']), body: _s(m['body']), createdAt: _s(m['created_at']));
}

/// دوال الخادم بجلسة المستخدم. قابلة للاستبدال في الاختبارات.
class NotesService {
  const NotesService();

  static const _uuid = Uuid();

  Future<dynamic> _call(String fn, Map<String, dynamic> args, String fallback) async {
    try {
      return await supabaseRpcOrThrow(fn, args);
    } catch (e) {
      throw NotesException(userMessage(e, fallback));
    }
  }

  Future<List<StudentNote>> _rows(String fn, Map<String, dynamic> args) async {
    final data = await _call(fn, args, 'تعذّر تحميل الرسائل');
    return [
      if (data is List)
        for (final r in data)
          if (r is Map) StudentNote.fromMap(r),
    ];
  }

  /// ملاحظات الطالب أو ولي الأمر صاحب الجلسة.
  Future<List<NoteThread>> family() async => threadNotes(await _rows('family_notes', const {}));

  /// ما كتبه المعلم، أو ملاحظات المدرسة كلها للإدارة. [studentId] يحصرها في طالب.
  Future<List<NoteThread>> school({String? studentId}) async =>
      threadNotes(await _rows('school_notes', {'p_student': studentId}));

  /// من المعلم أو الإدارة. المعرّف من الجهاز فإعادة الإرسال بعد انقطاع لا تكررها.
  Future<void> send({
    required String studentId,
    required String body,
    required String audience,
    String subject = '',
  }) =>
      _call(
        'send_student_note',
        {
          'p_id': _uuid.v4(),
          'p_student_id': studentId,
          'p_body': body.trim(),
          'p_audience': audience,
          'p_subject': subject.trim().isEmpty ? null : subject.trim(),
        },
        'تعذّر الإرسال',
      );

  /// رسالة للصف: لكل أسرة نسختها. يعيد عدد من وصلتهم.
  Future<int> sendMany({
    required List<String> studentIds,
    required String body,
    required String audience,
    String subject = '',
  }) async {
    final data = await _call(
      'send_student_notes',
      {
        'p_batch': _uuid.v4(),
        'p_student_ids': studentIds,
        'p_body': body.trim(),
        'p_audience': audience,
        'p_subject': subject.trim().isEmpty ? null : subject.trim(),
      },
      'تعذّر الإرسال',
    );
    return data is num ? data.toInt() : int.tryParse('$data') ?? 0;
  }

  /// رد ولي الأمر على ملاحظة لابنه.
  Future<void> reply(String noteId, String body) => _call(
        'reply_student_note',
        {'p_id': _uuid.v4(), 'p_note_id': noteId, 'p_body': body.trim()},
        'تعذّر إرسال الرد',
      );

  Future<void> remove(String id) => _call('delete_student_note', {'p_id': id}, 'تعذّر الحذف');

  /// «قُرئت» لمحادثة واحدة فتحتها الأسرة. الفشل بلا أثر: تُعلَّم في الفتحة التالية.
  Future<void> markFamilyRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await supabaseRpc('mark_family_notes_read', {'p_ids': ids});
  }

  /// «قُرئت»: للمعلم والإدارة ردود الأهل.
  Future<void> markRead() async {
    await supabaseRpc('mark_notes_read', const {});
  }

  /// إعلانات المدرسة السارية في نطاق الطالب. الفشل قائمة فارغة: الإعلان ليس شرطاً للبوابة.
  Future<List<SchoolAnnouncement>> announcements() async {
    final data = await supabaseRpc('family_announcements', const {});
    return [
      if (data is List)
        for (final a in data)
          if (a is Map) SchoolAnnouncement.fromMap(a),
    ];
  }
}

class NotesException implements Exception {
  const NotesException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// إعلانات أخفاها صاحب الجهاز: تبقى مخفية عليه وحده.
abstract final class DismissedAnnouncements {
  static const _key = 'noon_dismissed_school_announcements';

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> add(List<String> current, String id) async {
    final next = [...current, id];
    final kept = next.length > 50 ? next.sublist(next.length - 50) : next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, kept);
    } catch (_) {
      // التخزين غير متاح: يختفي حتى إعادة الفتح
    }
    return kept;
  }
}
