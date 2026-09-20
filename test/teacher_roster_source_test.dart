import 'dart:convert';

import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// معلّم في مدرسة تُسند المواد للشعب — بلا صفّ واحد في `enrollments`.
///
/// الحالة المُبلَّغ عنها: كشف الطلاب يظهر «0» في رصد الدرجات رغم وجود طلاب
/// في شعبة المادة.
const _teacher = PortalUser(
  id: 't1',
  name: 'أ. هدى البنا',
  nationalId: '401000000',
  portalCode: '123456',
  role: 'teacher',
  tenantId: 'tenant-1',
);

http.Response _json(Object data) => http.Response(
      jsonEncode(data),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  tearDown(SupabaseAuth.clear);

  group('حضور المعلم', _attendanceTests);
  group('أعمدة طلاب البوابة', _columnsTests);

  test('مع تسجيلات ناقصة: طلاب الشعبة يُضافون لمن سُجّل', () async {
    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/teachers')) {
          return _json([
            {'id': 't1', 'name': 'أ. هدى البنا', 'tenant_id': 'tenant-1'},
          ]);
        }
        if (path.endsWith('/groups')) {
          return _json([
            {
              'id': 'g1',
              'name': 'اللغة الإنجليزية',
              'subject_id': 'sub1',
              'teacher_id': 't1',
              'room_id': 'r1',
              'grade_level': 'عاشر',
              'status': 'active',
              'tenant_id': 'tenant-1',
            },
          ]);
        }
        if (path.endsWith('/rooms')) {
          return _json([
            {'id': 'r1', 'name': 'شعبة (أ)', 'grade_level': 'عاشر', 'tenant_id': 'tenant-1'},
          ]);
        }
        // طالب واحد فقط مسجَّل في المادة، والشعبة فيها اثنان
        if (path.endsWith('/enrollments')) {
          return _json([
            {'id': 'e1', 'group_id': 'g1', 'student_id': 's1', 'status': 'active'},
          ]);
        }
        if (path.endsWith('/portal_students') || path.endsWith('/students')) {
          return _json([
            {'id': 's1', 'full_name': 'ميرا الدحدوح', 'section': 'شعبة (أ)', 'grade_level': 'عاشر', 'status': 'active'},
            {'id': 's2', 'full_name': 'جنى أبو شعبان', 'section': 'شعبة (أ)', 'grade_level': 'عاشر', 'status': 'active'},
          ]);
        }
        return _json([]);
      }),
    );

    expect(
      data.classes.first.students.map((s) => s.fullName),
      containsAll(['ميرا الدحدوح', 'جنى أبو شعبان']),
    );
  });

  test('بلا تسجيلات: طلاب شعبة المادة يصلون للمعلم', () async {
    final asked = <String>[];

    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      () => MockClient((request) async {
        final path = request.url.path;
        asked.add(path);

        if (path.endsWith('/institution_settings')) return _json([]);
        if (path.endsWith('/teachers')) {
          return _json([
            {'id': 't1', 'name': 'أ. هدى البنا', 'tenant_id': 'tenant-1'},
          ]);
        }
        if (path.endsWith('/groups')) {
          return _json([
            {
              'id': 'g1',
              'name': 'اللغة الإنجليزية',
              'subject_id': 'sub1',
              'teacher_id': 't1',
              'room_id': 'r1',
              'grade_level': 'عاشر',
              'status': 'active',
              'tenant_id': 'tenant-1',
            },
          ]);
        }
        if (path.endsWith('/subjects')) {
          return _json([
            {'id': 'sub1', 'name': 'اللغة الإنجليزية', 'tenant_id': 'tenant-1'},
          ]);
        }
        if (path.endsWith('/rooms')) {
          return _json([
            {'id': 'r1', 'name': 'شعبة (أ)', 'grade_level': 'عاشر', 'tenant_id': 'tenant-1'},
          ]);
        }
        // لا تسجيلات: المدرسة تُسند المواد للشعب
        if (path.endsWith('/enrollments')) return _json([]);
        if (path.endsWith('/portal_students') || path.endsWith('/students')) {
          return _json([
            {
              'id': 's1',
              'full_name': 'ميرا الدحدوح',
              'section': 'شعبة (أ)',
              'grade_level': 'عاشر',
              'status': 'active',
            },
            {
              'id': 's2',
              'full_name': 'طالب من صفّ آخر',
              'section': 'شعبة (ب)',
              'grade_level': 'عاشر',
              'status': 'active',
            },
          ]);
        }
        return _json([]);
      }),
    );

    expect(data.classes, hasLength(1));
    final roster = data.classes.first.students;
    expect(roster.map((s) => s.fullName), ['ميرا الدحدوح'], reason: 'طلاب شعبة المادة وحدهم');
    expect(
      asked.where((p) => p.endsWith('/portal_students') || p.endsWith('/students')),
      isNotEmpty,
      reason: 'يُسأل عن طلاب المرحلة حين لا تسجيلات',
    );
  });
}

/// حضور المعلم يُكتب في كشف الشعبة اليومي نفسه الذي تكتب فيه الإدارة.
void _attendanceTests() {
  test('الكشف كشف شعبة ليومٍ، بمعرّف الإدارة نفسه', () async {
    final upserts = <String, List<dynamic>>{};

    await http.runWithClient(
      () => const PortalService().saveAttendance(
        roomId: 'r1',
        date: '2026-09-20',
        statuses: const {'s1': 'absent'},
        teacher: _teacher,
      ),
      () => MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET') return _json([]);
        final table = path.split('/').last;
        upserts.putIfAbsent(table, () => []).add(jsonDecode(request.body));
        return _json([]);
      }),
    );

    final session = (upserts['sessions']!.first as List).first as Map<String, dynamic>;
    expect(session['id'], 'ses_room_r1_2026-09-20', reason: 'صيغة AppStore.roomSessionIdFor');
    expect(session['room_id'], 'r1');
    expect(session['group_id'], isNull, reason: 'ليست حصة مادة');

    final mark = (upserts['attendance']!.first as List).first as Map<String, dynamic>;
    expect(mark['id'], 'att_ses_room_r1_2026-09-20_s1');
    expect(mark['status'], 'absent');
  });
}

/// أعمدة البوابة: `portal_students` لا تحمل عمود `name`، وتترك `full_name`
/// فارغاً حين يكون الاسم مخزَّناً باسمين. الحالة المُبلَّغ عنها: كشف فارغ.
void _columnsTests() {
  test('لا يُطلب عمود غير موجود، والاسم يُركَّب من الاسمين', () async {
    final asked = <Uri>[];

    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      () => MockClient((request) async {
        final path = request.url.path;
        asked.add(request.url);

        if (path.endsWith('/teachers')) {
          return _json([
            {'id': 't1', 'name': 'أ. هدى البنا', 'tenant_id': 'tenant-1'},
          ]);
        }
        if (path.endsWith('/groups')) {
          return _json([
            {
              'id': 'g1',
              'name': 'اللغة الإنجليزية',
              'subject_id': 'sub1',
              'teacher_id': 't1',
              'room_id': 'r1',
              'grade_level': 'عاشر',
              'status': 'active',
              'tenant_id': 'tenant-1',
            },
          ]);
        }
        if (path.endsWith('/rooms')) {
          return _json([
            {'id': 'r1', 'name': 'شعبة (أ)', 'grade_level': 'عاشر', 'tenant_id': 'tenant-1'},
          ]);
        }
        if (path.endsWith('/enrollments')) {
          return _json([
            {'id': 'e1', 'group_id': 'g1', 'student_id': 's1', 'status': 'active'},
          ]);
        }
        if (path.endsWith('/portal_students')) {
          // العمود غير الموجود يُفشل الاستعلام كما في السحابة
          if ((request.url.queryParameters['select'] ?? '').split(',').contains('name')) {
            return http.Response('{"code":"42703","message":"column does not exist"}', 400);
          }
          return _json([
            {
              'id': 's1',
              'first_name': 'محمد',
              'last_name': 'النجار',
              'full_name': null,
              'section': 'شعبة (أ)',
              'grade_level': 'عاشر',
              'status': 'active',
            },
          ]);
        }
        return _json([]);
      }),
    );

    expect(data.classes.first.students.map((s) => s.fullName), ['محمد النجار']);
    final selects = asked.map((u) => u.queryParameters['select'] ?? '').where((v) => v.contains('full_name'));
    expect(selects, isNotEmpty);
    expect(
      selects.every((v) => !v.split(',').contains('name')),
      isTrue,
      reason: 'لا يُطلب عمود name من عرض البوابة',
    );
  });
}
