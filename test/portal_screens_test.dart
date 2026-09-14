import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/portal_screens.dart';
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
  Future<List<StudentEvaluation>> groupEvaluations(String groupId) async => const [];

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

  @override
  Future<void> saveAttendance({
    required Group group,
    required String date,
    required Map<String, String> statuses,
    required PortalUser teacher,
  }) async {
    savedAttendance = statuses;
  }

  @override
  Future<void> saveEvaluations(List<StudentEvaluation> batch, String tenantId) async {
    savedEvaluations = batch;
  }
}

const _branding = PortalBranding(name: 'مدرسة أبو عقلين الخاصة');

Student _student(String id, String name, {String nationalId = ''}) => Student(
      id: id,
      fullName: name,
      gradeLevel: 'ثاني عشر أدبي',
      section: 'شعبة (1)',
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

      // الترويسة: اسم المنشأة و«المعلم: …» وزر خروج
      expect(find.text('مدرسة أبو عقلين الخاصة'), findsOneWidget);
      expect(find.text('المعلم: أ. وفاء الأشقر'), findsOneWidget);
      expect(find.text('خروج'), findsOneWidget);

      // التبويبات الثلاثة، ولا إعلانات: جدولها حُذف في النسخة المكتبية
      expect(find.text('رصد الحضور'), findsOneWidget);
      expect(find.text('رصد الدرجات'), findsOneWidget);
      expect(find.text('المودل'), findsOneWidget);
      expect(find.text('نشر إعلان'), findsNothing);

      // تبويب الحضور
      expect(find.text('الصف / المجموعة:'), findsOneWidget);
      expect(find.text('تاريخ الحصة:'), findsOneWidget);
      expect(find.text('الكل حاضر'), findsOneWidget);
      expect(find.text('كشف الطلاب (2):'), findsOneWidget);
      expect(find.text('هوية: 401334845'), findsOneWidget);
      expect(find.text('حفظ كشف الحضور الآن'), findsOneWidget);

      // الدرجات: الحقول ورصد الدرجة الكاملة
      await tester.tap(find.text('رصد الدرجات'));
      await tester.pumpAndSettle();
      expect(find.text('عنوان الاختبار / التقييم:'), findsOneWidget);
      expect(find.text('رصد الدرجة الكاملة للجميع'), findsOneWidget);

      // المودل: فارغ بإطار متقطع ودعوة لإضافة أول وحدة
      await tester.tap(find.text('المودل'));
      await tester.pumpAndSettle();
      expect(find.text('الشعبة الحالية:'), findsOneWidget);
      expect(find.text('إضافة وحدة / قسم'), findsOneWidget);
      expect(find.text('الفصل الأول'), findsOneWidget);
      expect(find.text('لا توجد وحدات أو أقسام مضافة لهذه الشعبة في هذا الفصل'), findsOneWidget);
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

    await tester.tap(find.text('غائب').first);
    await tester.pump();

    await tester.tap(find.text('حفظ كشف الحضور الآن'));
    await tester.pump();
    expect(fake.savedAttendance, {'s1': 'absent', 's2': 'present'}, reason: 'من لم يُلمس يُحفظ حاضراً كما يظهر');

    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('تم حفظ كشف الحضور وتحديث بوابة الطالب بنجاح'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('رصد الدرجات بلا عنوان يُظهر الخطأ تحت الحقل ولا يحفظ', (tester) async {
    final fake = _FakePortal(teacher: _teacherData());
    await _pump(tester, TeacherPortalScreen(user: _teacherUser, onExit: () {}, service: fake));

    await tester.tap(find.text('رصد الدرجات'));
    await tester.pumpAndSettle();
    expect(find.text('رصد درجات اختبار أو تقييم'), findsOneWidget);
    expect(find.text('اترك الدرجة فارغة لمن لم يختبر'), findsOneWidget);

    await tester.tap(find.text('حفظ كشف الدرجات'));
    await tester.pump();
    expect(find.text('يرجى إدخال عنوان الاختبار أو التقييم'), findsOneWidget);
    expect(fake.savedEvaluations, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('بوابة الطالب بتبويبات Center بلا طفح — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData());
      await _pump(tester, StudentPortalScreen(user: _studentUser, onExit: () {}, service: fake), width: width);

      expect(find.text('الطالب: علي أبو حسنين'), findsOneWidget);
      // الشعبة المحفوظة بكلمة «شعبة» لا تتكرر
      expect(find.text('ثاني عشر علمي ذكور - شعبة (1)'), findsOneWidget);
      expect(find.text('401334845'), findsOneWidget);
      for (final t in ['المودل', 'المواد والمعلمون', 'الحضور', 'الدرجات', 'الرسوم']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }

      // المودل: المواد المسجلة وفلتر الفصل
      expect(find.text('1 مواد مسجلة'), findsOneWidget);
      expect(find.text('الكيمياء'), findsOneWidget);
      expect(find.text('لا توجد وحدات أو دروس منشورة لهذه المادة في هذا الفصل'), findsOneWidget);

      await tester.tap(find.text('المواد والمعلمون'));
      await tester.pumpAndSettle();
      expect(find.text('المواد والمعلمون (1):'), findsOneWidget);
      expect(find.text('القاعة: شعبة (1)'), findsOneWidget);

      await tester.tap(find.text('الحضور'));
      await tester.pumpAndSettle();
      expect(find.text('سجل الحضور:'), findsOneWidget);
      expect(find.text('حاضر'), findsOneWidget);
      expect(find.text('غائب'), findsOneWidget);

      await tester.tap(find.text('الدرجات'));
      await tester.pumpAndSettle();
      expect(find.text('لم يتم رصد أي درجات أو تقييمات لك بعد'), findsOneWidget);

      await tester.tap(find.text('الرسوم'));
      await tester.pumpAndSettle();
      expect(find.text('إجمالي المسدد'), findsOneWidget);
      expect(find.text('إجمالي الرسوم'), findsOneWidget);
      expect(find.text('مسدد'), findsOneWidget);
      expect(find.text('قسط قادم'), findsOneWidget, reason: 'القسط الذي لم يحن موعده ليس مطلوباً الآن');
      await tester.scrollUntilVisible(find.text('عرض الوصل'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('سند #2026/1062'), findsOneWidget);
      expect(find.text('محفظة بال بي'), findsOneWidget);
    });

    testWidgets('مودل الطالب: المنشور وحده، بشارة «جديد» وزر عرض الملف — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData(), sections: _sections());
      await _pump(tester, StudentPortalScreen(user: _studentUser, onExit: () {}, service: fake), width: width);

      expect(fake.lastIncludeHidden, isFalse, reason: 'الطالب لا يرى المخفي');
      expect(find.text('الوحدة الأولى - النحو والصرف'), findsOneWidget);
      expect(find.text('الوحدة الثانية - البلاغة'), findsNothing);
      expect(find.text('2 عنصر'), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget, reason: 'أُضيف الآن');
      expect(find.text('عرض الملف'), findsOneWidget);

      // طيّ الوحدة يخفي موادها
      await tester.tap(find.text('الوحدة الأولى - النحو والصرف'));
      await tester.pumpAndSettle();
      expect(find.text('عرض الملف'), findsNothing);
    });

    testWidgets('ولي الأمر يتابع ملف ابنه بلا المودل — عرض ${width.toInt()}', (tester) async {
      final fake = _FakePortal(student: _studentData(), sections: _sections());
      await _pump(tester, StudentPortalScreen(user: _parentUser, onExit: () {}, service: fake), width: width);

      expect(find.text('ولي الأمر: أبو علي'), findsOneWidget);
      expect(find.text('علي أبو حسنين'), findsOneWidget, reason: 'شريط الهوية باسم الابن');
      expect(find.text('المودل'), findsNothing);
      for (final t in ['المواد والمعلمون', 'الحضور', 'الدرجات', 'الرسوم']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(fake.lastIncludeHidden, isNull, reason: 'لا يُطلب محتوى المودل أصلاً');

      // يبدأ من الحضور
      expect(find.text('سجل الحضور:'), findsOneWidget);
    });
  }
}
