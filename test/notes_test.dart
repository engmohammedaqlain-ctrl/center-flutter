import 'package:center_mobile/data/notes.dart';
import 'package:flutter_test/flutter_test.dart';

/// منقول من `features/notes/__tests__/notes.test.ts` في الويب.
StudentNote note(
  String id,
  String createdAt, {
  String studentId = 's1',
  String authorRole = 'teacher',
  String replyTo = '',
  String readAt = '',
  String authorName = '',
  String subjectName = '',
  String studentName = '',
}) =>
    StudentNote(
      id: id,
      studentId: studentId,
      body: id,
      authorRole: authorRole,
      replyTo: replyTo,
      readAt: readAt,
      createdAt: createdAt,
      authorName: authorName,
      subjectName: subjectName,
      studentName: studentName,
    );

void main() {
  group('الملاحظات بردودها', () {
    final rows = [
      note('old', '2026-10-20T08:00:00Z', readAt: '2026-10-20T09:00:00Z'),
      note('r2', '2026-10-21T10:00:00Z', authorRole: 'parent', replyTo: 'new'),
      note('new', '2026-10-21T08:00:00Z'),
      note('r1', '2026-10-21T09:00:00Z', authorRole: 'parent', replyTo: 'new', readAt: '2026-10-21T11:00:00Z'),
    ];

    test('الأحدث أولاً، والردود تحت ملاحظتها بترتيب كتابتها', () {
      final threads = threadNotes(rows);
      expect(threads.map((t) => t.id), ['new', 'old']);
      expect(threads[0].replies.map((r) => r.id), ['r1', 'r2']);
      expect(threads[1].replies, isEmpty);
    });

    test('غير المقروء: الملاحظات للأسرة، والردود للكاتب', () {
      final threads = threadNotes(rows);
      expect(unreadNotes(threads), 1);
      expect(unreadReplies(threads), 1);
    });

    test('رد ملاحظته خارج القائمة لا يظهر وحده', () {
      expect(threadNotes([note('x', '2026-10-21T08:00:00Z', replyTo: 'gone')]), isEmpty);
    });

    test('صف الخادم: الحقول الغائبة فارغة', () {
      final n = StudentNote.fromMap({'id': 'a', 'audience': 'student', 'author_role': 'school', 'reply_to': null});
      expect(n.audience, 'student');
      expect(n.replyTo, '');
      expect(n.read, isFalse);
    });
  });

  group('وقت الملاحظة', () {
    final now = DateTime(2026, 10, 22, 18, 0);
    test('اليوم وأمس بالساعة، وما قبلهما بالتاريخ', () {
      expect(noteTime(DateTime(2026, 10, 22, 9, 5).toUtc().toIso8601String(), now: now), 'اليوم 09:05');
      expect(noteTime(DateTime(2026, 10, 21, 23, 30).toUtc().toIso8601String(), now: now), 'أمس 23:30');
      expect(noteTime(DateTime(2026, 10, 3, 8, 0).toUtc().toIso8601String(), now: now), '3/10');
      expect(noteTime(DateTime(2025, 12, 30, 8, 0).toUtc().toIso8601String(), now: now), '30/12/2025');
      expect(noteTime('x', now: now), '');
    });
  });

  group('المحادثات', () {
    test('«أ.» لا تتكرر إن كانت في الاسم', () {
      expect(teacherLabel('عيسى النمس'), 'أ. عيسى النمس');
      expect(teacherLabel('أ. عيسى النمس'), 'أ. عيسى النمس');
      expect(teacherLabel('الأستاذة منى'), 'الأستاذة منى');
      expect(teacherLabel(''), 'المعلم');
    });

    final threads = threadNotes([
      note('a1', '2026-10-21T08:00:00Z',
          studentId: 'A', studentName: 'أنس', authorName: 'عيسى', subjectName: 'علوم', readAt: 'x'),
      note('a1r', '2026-10-21T09:00:00Z', studentId: 'A', authorRole: 'parent', replyTo: 'a1'),
      note('b1', '2026-10-21T08:30:00Z', studentId: 'B', studentName: 'أمير', authorName: 'عيسى', subjectName: 'علوم'),
      note('s1', '2026-10-20T08:00:00Z', studentId: 'A', studentName: 'أنس', authorRole: 'school'),
    ]);

    test('رسائل المحادثة بترتيب الزمن، والرد في جهة الأسرة يشير إلى ملاحظته', () {
      final msgs = chatMessages(threads.where((t) => t.studentId == 'A').toList());
      expect(msgs.map((m) => '${m.id}:${m.fromSchool}'), ['s1:true', 'a1:true', 'a1r:false']);
      expect(msgs[2].noteId, 'a1');
      expect(msgs[1].author, 'أ. عيسى');
    });

    test('المعلم: محادثة لكل طالب، الأحدث نشاطاً أولاً، وعدّاد ردوده الجديدة', () {
      final convs = byStudent(threads);
      expect(convs.map((c) => '${c.key}|${c.title}|${c.unread}'), ['A|أنس|1', 'B|أمير|0']);
      expect(convs[0].last.id, 'a1r');
    });

    test('الأسرة: محادثة لكل معلم ومادته، والإدارة وحدها، وعدّاد ما لم يُقرأ', () {
      final convs = byAuthor(threads);
      expect(convs.map((c) => '${c.title}|${c.subtitle}|${c.unread}'), ['أ. عيسى|علوم|1', 'الإدارة||1']);
      expect(convs[0].key, teacherChatKey(' عيسى', 'علوم '));
    });
  });
}
