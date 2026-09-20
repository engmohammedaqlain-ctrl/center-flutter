import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:center_mobile/widgets/attendance_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// خدمة بوابة بلا شبكة: بيانات ثابتة، وتسجيل ما يُحفظ.
class _FakePortal extends PortalService {
  _FakePortal({this.teacher, this.student, this.sections = const []});

  final TeacherPortalData? teacher;
  final StudentPortalData? student;
  final List<CourseSection> sections;

  Map<String, String>? savedAttendance;
  List<StudentEvaluation>? savedEvaluations;
  bool? lastIncludeHidden;

  @override
  Future<TeacherPortalData> teacherData(PortalUser user) async => teacher!;

  @override
  Future<StudentPortalData?> studentData(PortalUser user) async => student;

  @override
  Future<Map<String, ({String status, String id})>> sessionAttendance(String groupId, String date) async => {};

  @override
  Future<Map<String, Map<String, String>>> weekAttendance(String roomId, List<String> dates) async => {};

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
  }) async {
    lastIncludeHidden = includeHidden;
    return includeHidden ? sections : sections.where((s) => s.isVisible).toList();
  }

  /// الشعبة التي كُتب فيها الكشف — كشف الشعبة اليومي لا كشف الحصة.
  String? savedRoomId;

  @override
  Future<void> saveAttendance({
    required String roomId,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
  }) async {
    savedRoomId = roomId;
    savedAttendance = statuses;
  }

  @override
  Future<void> saveEvaluations(List<StudentEvaluation> batch, String tenantId) async {
    savedEvaluations = batch;
  }
}

const _branding = PortalBranding(name: 'مدرسة أبو عقلين الخاصة');

Student _student(String id, String name, {String nationalId = '', String section = 'شعبة (1)'}) => Student(
      id: id,
      fullName: name,
      gradeLevel: 'ثاني عشر أدبي',
      section: section,
      phone: '0599000000',
      parentName: 'ولي',
      parentPhone: '0598000000',
      balance: 0,
      nationalId: nationalId,
    );

TeacherPortalData _teacherData() => TeacherPortalData(
      branding: _branding,
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
          students: [
            _student('s1', 'علي أبو حسنين', nationalId: '401334845'),
            _student('s2', 'سارة محمود'),
          ],
        ),
      ],
    );

/// وحدتان: منشورة بمادتين، ومخفية عن الطلاب.
List<CourseSection> _sections() => [
      CourseSection(
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
            contentUrl: 'https://x.supabase.co/storage/v1/object/public/course_materials/t/1.pdf',
            description: 'صفحة 12 إلى 18',
            createdAt: DateTime.now().toIso8601String(),
          ),
          const CourseItem(
            id: 'it2',
            sectionId: 'sec1',
            groupId: 'g1',
            title: 'حل تمارين الوحدة',
            type: 'assignment',
            dueDate: '2099-01-01',
          ),
        ],
      ),
      const CourseSection(
        id: 'sec2',
        groupId: 'g1',
        term: 'term_1',
        title: 'الوحدة الثانية - البلاغة',
        isVisible: false,
      ),
    ];

StudentPortalData _studentData() {
  final today = DateTime.now();
  return StudentPortalData(
    student: _student('s1', 'علي أبو حسنين', nationalId: '401334845'),
    branding: _branding,
    subjects: const [
      PortalSubject(
        groupId: 'g1',
        subjectName: 'الكيمياء',
        teacherName: 'أ. محمود الزهار',
        groupName: 'فصل',
        days: [0, 1, 2, 3, 4],
        startTime: '08:00',
        endTime: '13:30',
        roomName: 'شعبة (1)',
      ),
    ],
    attendance: PortalAttendance(
      total: 2,
      present: 1,
      absent: 1,
      records: [
        AttendanceMark(id: 'a1', studentId: 's1', date: '2026-09-11', status: 'present'),
        AttendanceMark(id: 'a2', studentId: 's1', date: '2026-09-09', status: 'absent'),
      ],
    ),
    finance: PortalFinance.compute(
      studentBalance: 0,
      installments: [
        Installment(
          id: 'i1',
          studentId: 's1',
          title: 'القسط الدراسي (1)',
          amount: 230,
          dueDate: today.subtract(const Duration(days: 20)),
          paidAmount: 230,
          status: 'paid',
        ),
        Installment(
          id: 'i2',
          studentId: 's1',
          title: 'القسط الدراسي (2)',
          amount: 230,
          dueDate: today.add(const Duration(days: 10)),
        ),
      ],
      payments: [
        Payment(id: 'p1', receiptNumber: '2026/1062', studentId: 's1', amount: 230, method: 'palpay', date: today),
      ],
    ),
  );
}

const _teacherUser = PortalUser(
  id: 't1',
  name: 'أ. وفاء الأشقر',
  nationalId: '111',
  portalCode: '222222',
  role: 'teacher',
  tenantId: 'tenant',
);

const _studentUser = PortalUser(
  id: 's1',
  name: 'علي أبو حسنين',
  nationalId: '401334845',
  portalCode: '333333',
  role: 'student',
  tenantId: 'tenant',
  gradeLevel: 'ثاني عشر علمي ذكور',
  section: 'شعبة (1)',
);

/// ولي الأمر يدخل برقم هوية ابنه: `id` معرّف الطالب، و`name` اسم ولي الأمر.
const _parentUser = PortalUser(
  id: 's1',
  name: 'أبو علي',
  nationalId: '401334845',
  portalCode: '444444',
  role: 'parent',
  tenantId: 'tenant',
  gradeLevel: 'ثاني عشر علمي ذكور',
  section: 'شعبة (1)',
  studentName: 'علي أبو حسنين',
);

Future<void> _pump(WidgetTester tester, Widget screen, {double width = 360}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: screen)));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('بوابة المعلم بتبويبات Center بلا طفح — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(teacher: _teacherData());
      await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake), width: width);

      // الترويسة: اسم المعلم بجانب الشعار وزر خروج (بلا اسم المدرسة في المساحة الفاضية)
      expect(find.text('أ. وفاء الأشقر'), findsOneWidget);
      expect(find.text('مدرسة أبو عقلين الخاصة'), findsNothing);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

      // التبويبات الثلاثة، ولا إعلانات: جدولها حُذف في النسخة المكتبية
      // التبويبات شريط سفلي كبوابة الطالب
      expect(find.text('الحضور'), findsOneWidget);
      expect(find.text('الدرجات'), findsOneWidget);
      expect(find.text('المودل'), findsOneWidget);
      expect(find.text('نشر إعلان'), findsNothing);

      // تبويب الحضور — زر صف واحد كشاشة الإدارة، بلا قوائم الصف والشعبة والمادة
      expect(find.text('الصف:'), findsNothing);
      expect(find.text('المادة:'), findsNothing, reason: 'الحضور للشعبة لا للمادة');
      expect(find.text('ثاني عشر أدبي  ·  شعبة (1)'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      // كشف الإدارة نفسه: شريط الأيام وملخّص اليوم وصفوف الطلاب
      expect(find.byType(AttendanceDayChip), findsNWidgets(6));
      expect(find.byType(AttendanceDaySummary), findsOneWidget);
      expect(find.byType(AttendanceStudentRow), findsNWidgets(2));
      expect(find.text('علي أبو حسنين'), findsOneWidget);
      expect(find.text('حفظ كشف الحضور'), findsNothing, reason: 'كشف الإدارة يثبّت الرصد عند اللمس');
      expect(find.byTooltip('مزامنة'), findsOneWidget);

      // الدرجات: زر يفتح صفحة الرصد + اختيار النطاق للسجل
      await tester.tap(find.text('الدرجات'));
      await tester.pumpAndSettle();
      expect(find.text('رصد درجات'), findsOneWidget, reason: 'الإجراء في منطقة الإبهام');
      expect(find.text('المادة:'), findsWidgets);

      await tester.tap(find.text('رصد درجات'));
      await tester.pumpAndSettle();
      expect(find.text('الفصل'), findsWidgets);
      expect(find.text('رصد الدرجة الكاملة للجميع'), findsOneWidget);
      expect(find.text('حفظ كشف الدرجات'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // المودل: فارغ بإطار متقطع ودعوة لإضافة أول وحدة
      await tester.tap(find.text('المودل'));
      await tester.pumpAndSettle();
      expect(find.text('الشعبة الحالية:'), findsOneWidget);
      expect(find.text('إضافة وحدة / قسم'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('لا توجد وحدات مضافة لهذه المادة في هذا الفصل'), findsOneWidget);
    });

    testWidgets('مودل المعلم: الوحدات المخفية تظهر له بإجراءاتها بلا طفح — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(teacher: _teacherData(), sections: _sections());
      await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake), width: width);

      await tester.tap(find.text('المودل'));
      await tester.pumpAndSettle();

      expect(fake.lastIncludeHidden, isTrue, reason: 'المعلم يرى المخفي ليُظهره');
      expect(find.text('الوحدة الأولى - النحو والصرف'), findsOneWidget);
      expect(find.text('ورقة عمل / ملخص'), findsOneWidget);
      expect(find.text('واجب منزلي'), findsOneWidget);
      expect(find.text('فتح'), findsOneWidget, reason: 'زر فتح للمادة ذات الرابط وحدها');
      // الوحدة الثانية تحت الطيّة ولا تُبنى قبل التمرير إليها
      expect(find.text('مادة'), findsWidgets, reason: 'زر إضافة مادة في رأس الوحدة');

      await tester.scrollUntilVisible(find.text('مخفي'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('الوحدة الثانية - البلاغة'), findsOneWidget);
    });
  }

  testWidgets('رصد غياب طالب يُحدّث الإحصاء ويُحفظ كما يُعرض', (tester) async {
    final fake = _FakePortal(teacher: _teacherData());
    await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake));

    // الأول في ملخّص اليوم، والثاني مفتاح أول طالب
    await tester.tap(find.text('غائب').at(1));
    await tester.pump();

    // بلا زر: الرفع يتم بعد سكون اللمس
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(fake.savedAttendance, {'s1': 'absent'}, reason: 'من لم يُلمس يبقى غير مرصود كما عند الإدارة');
  });

  testWidgets('رصد الدرجات بلا عنوان يُظهر الخطأ تحت الحقل ولا يحفظ', (tester) async {
    final fake = _FakePortal(teacher: _teacherData());
    await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake));

    await tester.tap(find.text('الدرجات'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('رصد درجات'), findsOneWidget, reason: 'الإجراء في منطقة الإبهام');

    await tester.tap(find.text('رصد درجات'));
    await tester.pumpAndSettle();
    expect(find.text('رصد درجات'), findsWidgets);
    expect(find.text('الفصل'), findsWidgets);
    expect(find.textContaining('قائمة الطلاب'), findsOneWidget);

    await tester.tap(find.text('حفظ كشف الدرجات'));
    await tester.pump();
    expect(find.text('يرجى إدخال عنوان الاختبار أو التقييم'), findsOneWidget);
    expect(fake.savedEvaluations, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('شعبة بصفّين: الرصد يجري صفاً صفاً لا للمجموعة كلها', (tester) async {
    final twoSections = TeacherPortalData(
      branding: _branding,
      classes: [
        TeacherClass(
          group: Group(
            id: 'g1',
            name: 'اللغة العربية',
            subjectId: 'sub1',
            teacherId: 't1',
            gradeLevel: 'ثاني عشر أدبي',
          ),
          subjectName: 'اللغة العربية',
          roomName: 'شعبة (1)، شعبة (2)',
          rooms: const [
            PortalRoom(id: 'r1', name: 'شعبة (1)', gradeLevel: 'ثاني عشر أدبي'),
            PortalRoom(id: 'r2', name: 'شعبة (2)', gradeLevel: 'ثاني عشر أدبي'),
          ],
          students: [
            _student('s1', 'علي أبو حسنين'),
            _student('s2', 'سارة محمود', section: 'شعبة (2)'),
          ],
        ),
      ],
    );
    final fake = _FakePortal(teacher: twoSections);
    await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake));

    // شعبة واحدة تُختار تلقائياً: لا كشف يخلط شعبتين
    expect(find.byType(AttendanceStudentRow), findsOneWidget);
    expect(find.text('علي أبو حسنين'), findsOneWidget);
    expect(find.text('سارة محمود'), findsNothing, reason: 'طالبة الشعبة الثانية ليست في كشف الأولى');

    // ورقة الصف: اختيار الشعبة الثانية
    await tester.tap(find.byIcon(Icons.groups_2_outlined));
    await tester.pumpAndSettle();
    expect(find.text('المرحلة'), findsOneWidget);
    await tester.tap(find.text('شعبة (2)').last);
    await tester.pumpAndSettle();

    expect(find.byType(AttendanceStudentRow), findsOneWidget, reason: 'طلاب الصف المختار وحدهم');
    await tester.scrollUntilVisible(find.text('سارة محمود'), 300);
    expect(find.text('سارة محمود'), findsOneWidget);
    expect(find.text('علي أبو حسنين'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(AttendanceStudentRow),
      matching: find.text('حاضر'),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(fake.savedAttendance, {'s2': 'present'});
    expect(fake.savedRoomId, 'r2', reason: 'يُكتب في كشف الشعبة المختارة لا شعبة أخرى');
  });

  testWidgets('معلم بصفّين: يختار الصف ثم الشعبة ثم المادة', (tester) async {
    final twoGrades = TeacherPortalData(
      branding: _branding,
      classes: [
        TeacherClass(
          group: Group(
            id: 'g1',
            name: 'اللغة العربية',
            subjectId: 'sub1',
            teacherId: 't1',
            gradeLevel: 'ثاني عشر أدبي',
          ),
          subjectName: 'اللغة العربية',
          roomName: 'شعبة (1)',
          students: [_student('s1', 'علي أبو حسنين')],
        ),
        TeacherClass(
          group: Group(
            id: 'g2',
            name: 'اللغة العربية',
            subjectId: 'sub1',
            teacherId: 't1',
            gradeLevel: 'حادي عشر أدبي',
          ),
          subjectName: 'اللغة العربية',
          roomName: 'شعبة (3)',
          students: [_student('s3', 'ريم قاسم', section: 'شعبة (3)')],
        ),
      ],
    );
    final fake = _FakePortal(teacher: twoGrades);
    await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake));

    await tester.tap(find.byIcon(Icons.groups_2_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('حادي عشر أدبي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شعبة (3)').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('ريم قاسم'), 300);
    expect(find.text('ريم قاسم'), findsOneWidget);
    expect(find.text('علي أبو حسنين'), findsNothing);
  });
  for (final width in [320.0, 360.0]) {
    testWidgets('بوابة الطالب بشريط سفلي بلا طفح — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData());
      await _pump(tester, StudentPortalScreen(user: _studentUser, onExit: () {}, service: fake), width: width);

      expect(find.textContaining('علي أبو حسنين'), findsOneWidget, reason: 'الاسم مرة واحدة في الترويسة');
      // سطر واحد تحت الاسم: الصف والشعبة والهوية، والشعبة لا تتكرر فيه
      expect(
        find.textContaining('ثاني عشر علمي ذكور · شعبة (1)'),
        findsOneWidget,
      );
      expect(find.textContaining('401334845'), findsOneWidget);
      for (final t in ['مودل', 'مواد', 'حضور', 'درجات', 'رسوم']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }

      // المودل: شرائح المواد وفلتر الفصل
      expect(find.text('الكيمياء'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('لا توجد وحدات أو دروس منشورة لهذه المادة في هذا الفصل'), findsOneWidget);

      await tester.tap(find.text('مواد'));
      await tester.pumpAndSettle();
      expect(find.text('المواد والمعلمون (1):'), findsOneWidget);
      expect(find.text('القاعة: شعبة (1)'), findsOneWidget);

      await tester.tap(find.text('حضور'));
      await tester.pumpAndSettle();
      expect(find.text('نسبة الحضور'), findsOneWidget);
      expect(find.text('حاضر'), findsWidgets);
      expect(find.text('غائب'), findsWidgets);

      await tester.tap(find.text('درجات'));
      await tester.pumpAndSettle();
      expect(find.text('لم يتم رصد أي درجات أو تقييمات لك بعد'), findsOneWidget);

      await tester.tap(find.text('رسوم'));
      await tester.pumpAndSettle();
      expect(find.text('المقبوض'), findsOneWidget);
      expect(find.text('مسدد'), findsOneWidget);
      expect(find.text('مجدول'), findsOneWidget, reason: 'القسط الذي لم يحن موعده ليس مطلوباً الآن');
      await tester.scrollUntilVisible(find.text('عرض الوصل'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('سند #2026/1062'), findsOneWidget);
      expect(find.text('محفظة بال بي'), findsOneWidget);

      await tester.tap(find.text('عرض الوصل'));
      await tester.pumpAndSettle();
      expect(find.text('سند قبض'), findsOneWidget);
      // السند بشكله المطبوع: رقمه وترويسة المدرسة وتوقيع المستلم
      expect(find.text('2026/1062'), findsWidgets);
      expect(find.text('سند قبض مالي'), findsOneWidget);
      expect(find.textContaining('المستلم:'), findsOneWidget);
    });

    testWidgets('مودل الطالب: المنشور وحده، بشارة «جديد» وزر عرض الملف — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData(), sections: _sections());
      await _pump(tester, StudentPortalScreen(user: _studentUser, onExit: () {}, service: fake), width: width);

      expect(fake.lastIncludeHidden, isFalse, reason: 'الطالب لا يرى المخفي');
      expect(find.text('الوحدة الأولى - النحو والصرف'), findsOneWidget);
      expect(find.text('الوحدة الثانية - البلاغة'), findsNothing);
      expect(find.text('2 عنصر'), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget, reason: 'أُضيف الآن');
      expect(find.byIcon(Icons.download_rounded), findsOneWidget, reason: 'الملف يُفتح بلمس سطره');

      // طيّ الوحدة يخفي موادها
      await tester.tap(find.text('الوحدة الأولى - النحو والصرف'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.download_rounded), findsNothing);
    });

    testWidgets('ولي الأمر يتابع ملف ابنه بلا المودل — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData(), sections: _sections());
      await _pump(tester, StudentPortalScreen(user: _parentUser, onExit: () {}, service: fake), width: width);

      expect(find.textContaining('ولي الأمر: أبو علي'), findsOneWidget);
      expect(find.textContaining('علي أبو حسنين'), findsOneWidget, reason: 'الترويسة باسم الابن');
      expect(find.text('مودل'), findsNothing);
      expect(find.text('المودل'), findsNothing);
      for (final t in ['مواد', 'حضور', 'درجات', 'رسوم']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(fake.lastIncludeHidden, isNull, reason: 'لا يُطلب محتوى المودل أصلاً');

      // يبدأ من الحضور
      expect(find.text('نسبة الحضور'), findsOneWidget);
    });
  }
}
