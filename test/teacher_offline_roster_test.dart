import 'dart:convert';

import 'package:center_mobile/data/local_db.dart';
import 'package:center_mobile/data/portal.dart';
import 'package:center_mobile/data/portal_offline.dart';
import 'package:center_mobile/data/supabase.dart';
import 'package:center_mobile/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// كشوف المعلم لا تختفي لأجل انقطاع شبكة.
///
/// `supabaseSelect` يعيد `null` عند انقطاع الشبكة كما يعيد `[]` عند نجاحٍ بلا
/// صفوف. بلا التمييز بينهما كانت البوابة تُفتح بلا نت فتبني نسخةً فارغة
/// وتكتبها فوق كشوف الجهاز، فيصبح المعلم بلا صفوف ولا طلاب ولا شعبة يربّيها.

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

const _group = {
  'id': 'g1',
  'name': 'اللغة الإنجليزية',
  'subject_id': 'sub1',
  'teacher_id': 't1',
  'room_id': 'r1',
  'grade_level': 'حادي عشر علمي',
  'status': 'active',
  'tenant_id': 'tenant-1',
};

const _room = {
  'id': 'r1',
  'name': 'شعبة (1)',
  'grade_level': 'حادي عشر علمي',
  'homeroom_teacher_id': 't1',
  'tenant_id': 'tenant-1',
};

const _students = [
  {
    'id': 's1',
    'full_name': 'ميرا الدحدوح',
    'section': 'شعبة (1)',
    'grade_level': 'حادي عشر علمي',
    'status': 'active',
  },
  {
    'id': 's2',
    'full_name': 'جنى أبو شعبان',
    'section': 'شعبة (1)',
    'grade_level': 'حادي عشر علمي',
    'status': 'active',
  },
];

/// سحابة كاملة الردّ. [emptyView] يحاكي منظر `portal_students` ينجح بلا صفوف
/// لقيد RLS — وهي الحالة التي كانت تُفرِغ الكشف.
MockClient _cloud({bool emptyView = false}) => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/teachers')) return _json([{'id': 't1', 'tenant_id': 'tenant-1'}]);
      if (path.endsWith('/groups')) return _json([_group]);
      if (path.endsWith('/subjects')) {
        return _json([
          {'id': 'sub1', 'name': 'اللغة الإنجليزية', 'tenant_id': 'tenant-1'},
        ]);
      }
      if (path.endsWith('/rooms')) return _json([_room]);
      if (path.endsWith('/enrollments')) return _json([]);
      if (path.endsWith('/portal_students')) return _json(emptyView ? [] : _students);
      if (path.endsWith('/students')) return _json(_students);
      return _json([]);
    });

/// شبكة مقطوعة: كل طلب يفشل، تماماً كفتح التطبيق بلا نت.
MockClient _offlineCloud() => MockClient((_) async => throw http.ClientException('offline'));

TeacherPortalData _saved() => TeacherPortalData(
      classes: [
        TeacherClass(
          group: Group.fromCloud(Map<String, dynamic>.from(_group)),
          subjectName: 'اللغة الإنجليزية',
          roomName: 'شعبة (1)',
          rooms: const [PortalRoom(id: 'r1', name: 'شعبة (1)', gradeLevel: 'حادي عشر علمي')],
          students: [for (final s in _students) Student.fromCloud(Map<String, dynamic>.from(s))],
        ),
      ],
      homerooms: [
        HomeroomClass(
          room: const PortalRoom(id: 'r1', name: 'شعبة (1)', gradeLevel: 'حادي عشر علمي'),
          students: [for (final s in _students) Student.fromCloud(Map<String, dynamic>.from(s))],
        ),
      ],
    );

void main() {
  tearDown(SupabaseAuth.clear);

  test('بلا شبكة: الردّ يُعلَّم ناقصاً بدل أن يبدو صفّاً خالياً', () async {
    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      _offlineCloud,
    );

    expect(data.complete, isFalse);
    expect(data.classes, isEmpty);
    expect(data.homerooms, isEmpty);
  });

  test('بلا شبكة: نسخة الجهاز تبقى ولا تُكتب فوقها نسخة فارغة', () async {
    final db = NoPersistence();
    final offline = PortalOffline(db);
    await offline.saveTeacherData(_saved());

    final fetched = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      _offlineCloud,
    );
    await offline.saveTeacherData(fetched);

    final kept = offline.loadTeacherData();
    expect(kept, isNotNull);
    expect(kept!.classes.single.students, hasLength(2));
    expect(kept.homerooms.single.room.name, 'شعبة (1)');
  });

  test('بشبكة: الردّ كامل ويُحفظ بصفوفه وشعبة المربي', () async {
    final db = NoPersistence();
    final offline = PortalOffline(db);

    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      _cloud,
    );
    expect(data.complete, isTrue);
    expect(data.classes.single.students, hasLength(2));
    expect(data.homerooms.single.students, hasLength(2));

    await offline.saveTeacherData(data);
    final loaded = offline.loadTeacherData()!;
    expect(loaded.classes.single.students.map((s) => s.fullName), contains('ميرا الدحدوح'));
    expect(loaded.homerooms.single.students, hasLength(2));
    expect(loaded.subjects.map((s) => s.name), contains('اللغة الإنجليزية'));
  });

  test('منظر البوابة ينجح بلا صفوف: يُجرَّب جدول الطلاب فلا يفرغ الكشف', () async {
    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      () => _cloud(emptyView: true),
    );

    expect(data.complete, isTrue);
    expect(data.classes.single.students, hasLength(2));
  });

  test('سحابة بلا طلاب فعلاً: الردّ كامل ويُحفظ كشفاً فارغاً', () async {
    final data = await http.runWithClient(
      () => const PortalService().teacherData(_teacher),
      () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/groups')) return _json([_group]);
        if (path.endsWith('/rooms')) return _json([_room]);
        return _json([]);
      }),
    );

    expect(data.complete, isTrue, reason: 'أجابت السحابة — الفراغ حقيقي لا انقطاع');
    expect(data.classes.single.students, isEmpty);
  });
}
