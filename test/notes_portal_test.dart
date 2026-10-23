import 'package:center_mobile/data/notes.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بوابة الأسرة بملاحظات وإعلان، بلا شبكة.
class _Portal extends PortalService {
  @override
  Future<StudentPortalData?> studentData(PortalUser user) async => StudentPortalData(
        student: Student(
          id: 's1',
          fullName: 'علي',
          gradeLevel: 'عاشر',
          section: 'أ',
          phone: '',
          parentName: '',
          parentPhone: '',
          balance: 0,
        ),
        branding: const PortalBranding(name: 'مدرسة'),
        subjects: const [
          PortalSubject(groupId: 'g1', subjectName: 'علوم', teacherName: 'عيسى', groupName: 'علوم'),
          PortalSubject(groupId: 'g2', subjectName: 'رياضيات', teacherName: 'منى', groupName: 'رياضيات'),
        ],
      );

  @override
  Future<List<CourseSection>> groupSections({
    required String tenantId,
    required String groupId,
    String term = 'all',
    bool includeHidden = false,
    String? roomId,
  }) async =>
      const [];
}

class _Notes extends NotesService {
  _Notes(this.rows);

  final List<StudentNote> rows;
  final replies = <String>[];
  final marked = <String>[];

  @override
  Future<List<NoteThread>> family() async => threadNotes(rows);

  @override
  Future<void> reply(String noteId, String body) async => replies.add('$noteId:$body');

  @override
  Future<void> markFamilyRead(List<String> ids) async => marked.addAll(ids);

  @override
  Future<List<SchoolAnnouncement>> announcements() async =>
      const [SchoolAnnouncement(id: 'a1', body: 'الدوام غداً الساعة التاسعة', createdAt: '2026-10-22T08:00:00Z')];
}

final _rows = [
  const StudentNote(
    id: 'n1',
    studentId: 's1',
    body: 'لم يُسلَّم الواجب',
    authorName: 'عيسى',
    subjectName: 'علوم',
    createdAt: '2026-10-22T08:00:00Z',
  ),
  const StudentNote(
    id: 'n2',
    studentId: 's1',
    body: 'اجتماع أولياء الأمور الخميس',
    authorRole: 'school',
    createdAt: '2026-10-21T08:00:00Z',
    readAt: '2026-10-21T09:00:00Z',
  ),
];

PortalUser _user(String role) => PortalUser(
      id: 's1',
      name: 'علي',
      nationalId: '1',
      portalCode: '2',
      role: role,
      tenantId: 't',
      studentName: 'علي',
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: screen)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ولي الأمر: الإعلان وشريط الجديد، و«رسائل» على بطاقة المادة، والإدارة فوقها، والرد', (tester) async {
    final notes = _Notes(_rows);
    await _pump(tester, StudentPortalScreen(user: _user('parent'), onExit: () {}, service: _Portal(), notes: notes));

    expect(find.text('الدوام غداً الساعة التاسعة'), findsOneWidget);
    expect(find.text('ملاحظة من أ. عيسى'), findsOneWidget);

    await tester.tap(find.text('مواد'));
    await tester.pumpAndSettle();
    expect(find.text('رسائل'), findsOneWidget, reason: 'معلم العلوم وحده كتب');
    expect(find.text('الإدارة'), findsOneWidget, reason: 'محادثة بلا بطاقة مادة فوق البطاقات');

    await tester.tap(find.text('رسائل'));
    await tester.pumpAndSettle();
    expect(find.text('لم يُسلَّم الواجب'), findsWidgets);
    expect(notes.marked, ['n1']);

    await tester.enterText(find.byType(TextField), 'تمام، شكراً');
    await tester.pump();
    await tester.tap(find.byTooltip('إرسال'));
    await tester.pumpAndSettle();
    expect(notes.replies, ['n1:تمام، شكراً']);
  });

  testWidgets('الطالب يقرأ ولا يرد، والإعلان يُخفى', (tester) async {
    final notes = _Notes(_rows);
    await _pump(tester, StudentPortalScreen(user: _user('student'), onExit: () {}, service: _Portal(), notes: notes));

    await tester.tap(find.text('ملاحظة من أ. عيسى'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('إخفاء'));
    await tester.pumpAndSettle();
    expect(find.text('الدوام غداً الساعة التاسعة'), findsNothing);
  });
}
