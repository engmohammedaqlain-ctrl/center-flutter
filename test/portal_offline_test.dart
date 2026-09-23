import 'package:center_mobile/data/grading.dart';
import 'package:center_mobile/data/institution.dart';
import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/portal_offline.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:center_mobile/widgets/attendance_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// بوابة المعلم بلا إنترنت — تعمل من نسخة الجهاز كما تعمل واجهة الإدارة.

const _user = PortalUser(
  id: 't1',
  name: 'أ. وفاء الأشقر',
  nationalId: '111',
  portalCode: '222222',
  role: 'teacher',
  tenantId: 'tenant',
);

/// خدمة تنجح، وتسجّل ما وصلها.
class _OnlinePortal extends PortalService {
  _OnlinePortal({this.teacher, this.sections = const []});

  final TeacherPortalData? teacher;
  final List<CourseSection> sections;

  final List<({String roomId, String date, Map<String, String> statuses, String teacherId})> attendanceCalls = [];
  final List<List<StudentEvaluation>> evaluationCalls = [];
  final List<({String id, double score})> scoreCalls = [];
  final List<String> deletedEvaluations = [];
  final List<CourseSection> savedSections = [];

  @override
  Future<void> updateEvaluationScore(String id, double score) async => scoreCalls.add((id: id, score: score));

  @override
  Future<void> deleteEvaluation(String id) async => deletedEvaluations.add(id);

  @override
  Future<void> saveSection(CourseSection section) async => savedSections.add(section);

  @override
  Future<TeacherPortalData> teacherData(PortalUser user) async => teacher!;

  @override
  Future<Map<String, ({String status, String id})>> sessionAttendance(String roomId, String date) async => {};

  @override
  Future<Map<String, Map<String, String>>> weekAttendance(String roomId, List<String> dates) async => {};

  @override
  Future<Map<String, Map<String, String>>> weekTeacherAttendance({
    required String groupId,
    required List<String> dates,
    required Map<String, String> roomOf,
  }) async =>
      {};

  @override
  Future<List<StudentEvaluation>> groupEvaluations(String groupId) async => const [];

  @override
  Future<Map<String, String>> studentNamesByIds(Set<String> ids, String tenantId) async => const {};

  @override
  Future<List<CourseSection>> groupSections({
    required String tenantId,
    required String groupId,
    String term = 'all',
    bool includeHidden = false,
    String? roomId,
  }) async =>
      sections;

  @override
  Future<void> saveAttendance({
    required String roomId,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
    Set<String>? changedStudentIds,
  }) async {
    attendanceCalls.add((roomId: roomId, date: date, statuses: statuses, teacherId: teacher.id));
  }

  @override
  Future<void> saveEvaluations(List<StudentEvaluation> batch, String tenantId) async {
    evaluationCalls.add(batch);
  }
}

/// خدمة بلا شبكة: كل نداء يفشل.
class _DeadPortal extends PortalService {
  @override
  Future<TeacherPortalData> teacherData(PortalUser user) async => throw Exception('offline');

  @override
  Future<Map<String, ({String status, String id})>> sessionAttendance(String roomId, String date) async =>
      throw Exception('offline');

  @override
  Future<Map<String, Map<String, String>>> weekAttendance(String roomId, List<String> dates) async =>
      throw Exception('offline');

  @override
  Future<List<StudentEvaluation>> groupEvaluations(String groupId) async => throw Exception('offline');

  @override
  Future<Map<String, String>> studentNamesByIds(Set<String> ids, String tenantId) async => throw Exception('offline');

  @override
  Future<List<CourseSection>> groupSections({
    required String tenantId,
    required String groupId,
    String term = 'all',
    bool includeHidden = false,
    String? roomId,
  }) async =>
      throw Exception('offline');

  @override
  Future<void> saveAttendance({
    required String roomId,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
    Set<String>? changedStudentIds,
  }) async =>
      throw Exception('offline');

  @override
  Future<void> saveEvaluations(List<StudentEvaluation> batch, String tenantId) async => throw Exception('offline');

  @override
  Future<void> updateEvaluationScore(String id, double score) async => throw Exception('offline');

  @override
  Future<void> deleteEvaluation(String id) async => throw Exception('offline');

  @override
  Future<void> saveSection(CourseSection section) async => throw Exception('offline');
}

Student _student(String id, String name) => Student(
      id: id,
      fullName: name,
      gradeLevel: 'ثاني عشر أدبي',
      section: 'شعبة (1)',
      phone: '0599000000',
      parentName: 'ولي',
      parentPhone: '0598000000',
      balance: 0,
    );

TeacherPortalData _data() => TeacherPortalData(
      branding: PortalBranding(
        name: 'مدرسة أبو عقلين الخاصة',
        colors: const InstitutionColors(sidebarBg: '#101828', activeItem: '#E8A33D'),
        gradingScheme: const GradingScheme(
          term1: [GradingComponent(id: 'c1', name: 'شهري أول', weight: 20)],
        ),
      ),
      classes: [
        TeacherClass(
          group: Group(
            id: 'g1',
            name: 'اللغة العربية - شعبة (1)',
            subjectId: 'sub1',
            teacherId: 't1',
            roomId: 'r1',
            gradeLevel: 'ثاني عشر أدبي',
          ),
          subjectName: 'اللغة العربية',
          roomName: 'شعبة (1)',
          rooms: const [PortalRoom(id: 'r1', name: 'شعبة (1)', gradeLevel: 'ثاني عشر أدبي')],
          students: [_student('s1', 'علي أبو حسنين'), _student('s2', 'سارة محمود')],
        ),
      ],
    );

List<CourseSection> _sections() => [
      const CourseSection(
        id: 'sec1',
        groupId: 'g1',
        term: 'term_1',
        title: 'الوحدة الأولى - النحو والصرف',
        items: [
          CourseItem(
            id: 'it1',
            sectionId: 'sec1',
            groupId: 'g1',
            title: 'ملخص درس المبتدأ والخبر',
            type: 'file',
          ),
        ],
      ),
    ];

Future<void> _pump(WidgetTester tester, Widget screen, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // شجرة فارغة أولاً: إعادة البناء على شاشة من نوعها تُبقي حالتها ولا تعيد التحميل
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('مخزن البوابة على الجهاز', () {
    test('صفوف المعلم وطلابه وهوية المدرسة تعود كما حُفظت', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.saveTeacherData(_data());

      final back = offline.loadTeacherData()!;
      expect(back.classes, hasLength(1));
      expect(back.classes.first.students.map((s) => s.fullName), ['علي أبو حسنين', 'سارة محمود']);
      expect(back.classes.first.rooms.single.id, 'r1');
      expect(back.classes.first.subjectName, 'اللغة العربية');
      // الهوية تُحفظ معها فلا تفتح البوابة بلا شبكة بألوان غريبة
      expect(back.branding.colors.activeItem, '#E8A33D');
      expect(back.branding.gradingScheme.of('term_1').single.name, 'شهري أول');
    });

    test('وحدات المودل تعود بمحتواها لا بعناوينها وحدها', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.saveSections('g1', 'term_1', _sections());

      final back = offline.loadSections('g1', 'term_1')!;
      expect(back.single.title, 'الوحدة الأولى - النحو والصرف');
      expect(back.single.items.single.title, 'ملخص درس المبتدأ والخبر');
      // فصل آخر لم يُحفظ: لا شيء بدل بيانات فصل غيره
      expect(offline.loadSections('g1', 'term_2'), isNull);
    });

    test('رصد اليوم نفسه مرتين يبقى صفاً واحداً في الطابور', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueAttendance(
        roomId: 'r1',
        date: '2026-09-20',
        statuses: {'s1': 'present'},
        userId: 't1',
      );
      await offline.queueAttendance(
        roomId: 'r1',
        date: '2026-09-20',
        statuses: {'s1': 'absent'},
        userId: 't1',
      );

      expect(offline.pendingCountOf('t1'), 1);
      expect(offline.pending.single['statuses'], {'s1': 'absent'}, reason: 'الأحدث يحلّ محل الأقدم');
    });

    test('الرفع يُخرج رصد صاحبه وحده ويترك رصد زميله', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueAttendance(roomId: 'r1', date: '2026-09-20', statuses: {'s1': 'absent'}, userId: 't1');
      await offline.queueAttendance(roomId: 'r9', date: '2026-09-20', statuses: {'s9': 'absent'}, userId: 't2');

      final service = _OnlinePortal();
      expect(await offline.flush(service, _user), 1);

      expect(service.attendanceCalls.single.roomId, 'r1');
      expect(service.attendanceCalls.single.teacherId, 't1');
      expect(offline.pendingCountOf('t1'), 0);
      expect(offline.pendingCountOf('t2'), 1, reason: 'رصد الزميل ينتظر دخوله لا يُرفع باسم غيره');
    });

    test('ما تعذّر رفعه يبقى في الطابور', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueAttendance(roomId: 'r1', date: '2026-09-20', statuses: {'s1': 'absent'}, userId: 't1');

      expect(await offline.flush(_DeadPortal(), _user), 0);
      expect(offline.pendingCountOf('t1'), 1);
    });

    test('الخروج يمسح النسخة المعروضة ويُبقي ما لم يُرفع', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.saveTeacherData(_data());
      await offline.queueAttendance(roomId: 'r1', date: '2026-09-20', statuses: {'s1': 'absent'}, userId: 't1');

      await offline.clear();

      expect(offline.loadTeacherData(), isNull);
      expect(offline.pendingCountOf('t1'), 1, reason: 'كشف صفٍّ حقيقي لا يُتلف بخروج');
    });

    test('درجات صُفَّت تظهر في سجل مادتها فوراً', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueEvaluations(
        [
          const StudentEvaluation(
            id: 'e1',
            studentId: 's1',
            groupId: 'g1',
            title: 'اختبار الوحدة الأولى',
            score: 18,
            maxScore: 20,
          ),
        ],
        'tenant',
        't1',
      );

      expect(offline.loadEvaluations('g1')!.single.title, 'اختبار الوحدة الأولى');
    });
  });

  group('بوابة المعلم بلا اتصال', () {
    testWidgets('تفتح من نسخة الجهاز بطلابها بدل رسالة خطأ', (tester) async {
      final db = NoPersistence();
      await PortalOffline(db).saveTeacherData(_data());

      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _DeadPortal(),
          offline: PortalOffline(db),
        ),
      );

      expect(find.text('تعذّر الاتصال بالسحابة.'), findsNothing);
      expect(find.byTooltip('لا يوجد اتصال'), findsOneWidget);
      expect(find.text('علي أبو حسنين'), findsOneWidget);
      expect(find.text('سارة محمود'), findsOneWidget);
    });

    testWidgets('بلا نسخة محفوظة تبقى رسالة تعذّر الاتصال', (tester) async {
      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _DeadPortal(),
          offline: PortalOffline(NoPersistence()),
        ),
      );

      expect(find.text('تعذّر الاتصال بالسحابة.'), findsOneWidget);
    });

    testWidgets('لمسة الرصد تحفظ بلا زر، وتُرفع حين يعود الاتصال', (tester) async {
      final db = NoPersistence();
      await PortalOffline(db).saveTeacherData(_data());

      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _DeadPortal(),
          offline: PortalOffline(db),
        ),
      );

      await tester.tap(find.descendant(
        of: find.byType(AttendanceStudentRow).first,
        matching: find.text('غائب'),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // اللمسة وحدها تنزل على القرص: إغلاق التطبيق بلا نت لا يضيّع الرصد
      final offline = PortalOffline(db);
      expect(offline.loadMarks('r1', isoDate(DateTime.now())), {'s1': 'absent'});

      // ثم يُصفّ للرفع عند الحفظ، لأن السحابة بعيدة
      await tester.tap(find.text('حفظ الرصد'));
      await tester.pumpAndSettle();
      expect(offline.pendingCountOf('t1'), 1, reason: 'تعذّر الرفع فصُفَّ');

      // عاد الاتصال: يُرفع ما انتظر
      final service = _OnlinePortal(teacher: _data());
      await _pump(
        tester,
        TeacherPortalScreen(user: _user, onExit: () {}, service: service, offline: PortalOffline(db)),
      );

      expect(service.attendanceCalls, isNotEmpty);
      expect(service.attendanceCalls.first.roomId, 'r1');
      expect(service.attendanceCalls.first.statuses, {'s1': 'absent'});
      expect(PortalOffline(db).pendingCountOf('t1'), 0);
    });

    testWidgets('المودل يفتح بوحداته المحفوظة', (tester) async {
      final db = NoPersistence();
      final offline = PortalOffline(db);
      await offline.saveTeacherData(_data());
      await offline.saveSections('g1', 'term_1', _sections());

      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _DeadPortal(),
          offline: PortalOffline(db),
        ),
      );

      await tester.tap(find.text('المودل'));
      await tester.pumpAndSettle();

      expect(find.text('الوحدة الأولى - النحو والصرف'), findsOneWidget);

      // الوحدات تُفتح مطوية: محتواها يظهر بلمسة، وهو المحفوظ على الجهاز
      await tester.tap(find.text('الوحدة الأولى - النحو والصرف'));
      await tester.pumpAndSettle();
      expect(find.text('ملخص درس المبتدأ والخبر'), findsOneWidget);
    });

    testWidgets('الاتصال الناجح يحفظ نسخة تُفتح بعده بلا شبكة', (tester) async {
      final db = NoPersistence();
      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _OnlinePortal(teacher: _data(), sections: _sections()),
          offline: PortalOffline(db),
        ),
      );
      expect(find.text('علي أبو حسنين'), findsOneWidget);
      expect(find.byTooltip('لا يوجد اتصال'), findsNothing);

      await _pump(
        tester,
        TeacherPortalScreen(
          user: _user,
          onExit: () {},
          service: _DeadPortal(),
          offline: PortalOffline(db),
        ),
      );
      expect(find.text('علي أبو حسنين'), findsOneWidget);
      expect(find.byTooltip('لا يوجد اتصال'), findsOneWidget);
    });

    testWidgets('طابور زميل لا يُرفع بدخول معلم آخر', (tester) async {
      final db = NoPersistence();
      final offline = PortalOffline(db);
      await offline.saveTeacherData(_data());
      await offline.queueAttendance(roomId: 'r9', date: '2026-09-20', statuses: {'s9': 'absent'}, userId: 't2');

      final service = _OnlinePortal(teacher: _data());
      await _pump(
        tester,
        TeacherPortalScreen(user: _user, onExit: () {}, service: service, offline: PortalOffline(db)),
      );

      expect(service.attendanceCalls, isEmpty);
      expect(PortalOffline(db).pendingCountOf('t2'), 1);
    });
  });

  group('كل كتابة تعمل بلا نت', () {
    test('تعديل علامة يُصفّ ويُرفع حين يعود الاتصال', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueOp({'kind': 'evaluation_score', 'id': 'e1', 'score': 17.5}, 't1');

      final service = _OnlinePortal();
      expect(await offline.flush(service, _user), 1);
      expect(service.scoreCalls.single.id, 'e1');
      expect(service.scoreCalls.single.score, 17.5);
    });

    test('حذف تقييم يُصفّ', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueOp({'kind': 'evaluation_delete', 'id': 'e9'}, 't1');

      final service = _OnlinePortal();
      expect(await offline.flush(service, _user), 1);
      expect(service.deletedEvaluations, ['e9']);
    });

    test('وحدة مودل أُنشئت بلا نت تُرفع بمعرّفها نفسه', () async {
      final offline = PortalOffline(NoPersistence());
      const draft = CourseSection(id: 'sec-local', groupId: 'g1', term: 'term_1', title: 'وحدة بلا شبكة');
      await offline.queueOp({'kind': 'section_upsert', 'row': draft.toCloud()}, 't1');

      final service = _OnlinePortal();
      expect(await offline.flush(service, _user), 1);
      expect(service.savedSections.single.id, 'sec-local', reason: 'لا تُنشأ مرتين بمعرّفين');
      expect(service.savedSections.single.title, 'وحدة بلا شبكة');
    });

    test('عملية مجهولة تُسقط ولا تعلّق الطابور', () async {
      final offline = PortalOffline(NoPersistence());
      await offline.queueOp({'kind': 'something_else'}, 't1');

      expect(await offline.flush(_OnlinePortal(), _user), 0);
      expect(offline.pendingCountOf('t1'), 0);
    });
  });

  group('الدخول بلا نت', () {
    test('الجلسة تحفظ الحساب فتُفتح البوابة بلا تحقق من السيرفر', () async {
      final store = AppStore.forTesting();
      await store.savePortalSession(
        nationalId: '401234723',
        code: '433333',
        userId: 't1',
        user: _user,
      );

      final saved = store.portalSession!;
      expect(saved.user?.id, 't1');
      expect(saved.user?.name, 'أ. وفاء الأشقر');
      expect(saved.user?.role, 'teacher');
      expect(saved.user?.tenantId, 'tenant');
    });
  });

}
