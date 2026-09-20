import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/models/models.dart';
import 'package:center_mobile/screens/portal_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// معلّم بشعبة واحدة: طلابها يحملون حقل شعبة، والمجموعة قاعتها «شعبة (أ)».
Student _student(String id, String name, {String section = 'شعبة (أ)'}) => Student(
      id: id,
      fullName: name,
      gradeLevel: 'عاشر',
      section: section,
      phone: '0599000000',
      parentName: 'ولي',
      parentPhone: '0598000000',
      balance: 0,
    );

const _user = PortalUser(
  id: 't1',
  name: 'أ. هدى البنا',
  nationalId: '401000000',
  portalCode: '123456',
  role: 'teacher',
  tenantId: 'tenant-1',
);

TeacherPortalData _data({String studentSection = 'شعبة (أ)', String roomName = 'شعبة (أ)'}) => TeacherPortalData(
      branding: const PortalBranding(name: 'مدرسة الأمل'),
      classes: [
        TeacherClass(
          group: Group(
            id: 'g1',
            name: 'اللغة الإنجليزية',
            subjectId: 'sub1',
            teacherId: 't1',
            gradeLevel: 'عاشر',
            roomId: 'r1',
          ),
          subjectName: 'اللغة الإنجليزية',
          roomName: roomName,
          students: [
            _student('s1', 'ميرا الدحدوح', section: studentSection),
            _student('s2', 'جنى أبو شعبان', section: studentSection),
          ],
        ),
      ],
    );

class _Fake extends PortalService {
  const _Fake(this.data);
  final TeacherPortalData data;

  @override
  Future<TeacherPortalData> teacherData(PortalUser user) async => data;

  @override
  Future<List<StudentEvaluation>> groupEvaluations(String groupId) async => const [];
}

Future<void> _openGradesPage(WidgetTester tester, TeacherPortalData data) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: TeacherPortalScreen(user: _user, onExit: () {}, service: _Fake(data)),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('الدرجات'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('رصد درجات'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('صفحة رصد الدرجات تعرض طلاب الشعبة لا صفراً', (tester) async {
    await _openGradesPage(tester, _data());

    expect(find.text('قائمة الطلاب (2)'), findsOneWidget);
    expect(find.text('ميرا الدحدوح'), findsOneWidget);
  });

  testWidgets('حقل شعبة الطالب مختصر «أ» وقاعة المادة «شعبة (أ)» — يتطابقان', (tester) async {
    await _openGradesPage(tester, _data(studentSection: 'أ'));

    expect(find.text('قائمة الطلاب (2)'), findsOneWidget);
  });
}
