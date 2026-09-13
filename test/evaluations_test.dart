import 'package:center_mobile/data/demo_data.dart';
import 'package:center_mobile/data/portal.dart' as portal;
import 'package:center_mobile/data/store.dart';
import 'package:center_mobile/models/models.dart';
// `flutter_test` يصدّر Evaluation خاصاً بفحوص الوصولية — يُخفى ليبقى الاسم
// للنموذج المقابل لـ StudentEvaluation في types/evaluation.ts
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

AppStore seeded() {
  final s = AppStore.forTesting();
  injectDemoData(s);
  return s;
}

/// البيانات التجريبية بنظام مدرسة بلا مجموعات؛ التقييمات تُرصد على شعبة،
/// فتُبنى هنا شعبة بطالبين مسجّلين.
Group seedGroup(AppStore s, {int size = 2}) {
  final group = Group(
    id: 'g-test',
    name: 'شعبة الاختبار',
    subjectId: s.subjects.first.id,
    teacherId: s.teachers.first.id,
    days: const [0, 2],
  );
  s.groups.add(group);
  for (final student in s.students.take(size)) {
    s.enrollments.add(StudentEnrollment(
      id: 'enr-${student.id}',
      studentId: student.id,
      groupId: group.id,
    ));
  }
  return group;
}

void main() {
  group('نموذج التقييم', () {
    test('النسبة والنجاح يُحسبان من الدرجة القصوى', () {
      final e = Evaluation(id: 'e1', studentId: 's1', title: 'اختبار', score: 45, maxScore: 60);
      expect(e.percent, 75);
      expect(e.passed, isTrue);

      final weak = Evaluation(id: 'e2', studentId: 's1', title: 'اختبار', score: 20, maxScore: 60);
      expect(weak.percent, 33);
      expect(weak.passed, isFalse);
    });

    test('عتبة النجاح خمسون بالمئة تماماً', () {
      final e = Evaluation(id: 'e1', studentId: 's1', title: 'ن', score: 50, maxScore: 100);
      expect(e.passed, isTrue);
      final under = Evaluation(id: 'e2', studentId: 's1', title: 'ن', score: 49.5, maxScore: 100);
      expect(under.percent, 50, reason: 'التقريب يرفعها إلى الخمسين');
      expect(under.passed, isTrue);
    });

    test('درجة قصوى صفراً لا تقسم على صفر', () {
      final e = Evaluation(id: 'e1', studentId: 's1', title: 'ن', score: 10, maxScore: 0);
      expect(e.percent, 0);
      expect(e.passed, isFalse);
    });

    test('الصف القديم بلا max_score يُقرأ 100 لا صفراً', () {
      // العمود أُضيف بهجرة لاحقة بافتراضي 100؛ قراءته صفراً تُصفّر كل نسبة
      final e = Evaluation.fromCloud({'id': 'e1', 'student_id': 's1', 'score': 80});
      expect(e.maxScore, 100);
      expect(e.percent, 80);
      expect(e.type, 'quiz', reason: 'النوع الافتراضي كما في الهجرة');
    });

    test('التقييم يمرّ عبر شكل السحابة بلا فقدان', () {
      final e = Evaluation(
        id: 'e1',
        studentId: 's1',
        groupId: 'g1',
        subjectId: 'sub1',
        teacherId: 't1',
        title: 'امتحان الوحدة',
        score: 87.5,
        maxScore: 120,
        evaluationDate: '2026-09-10',
        type: 'monthly',
        notes: 'ممتاز',
      );
      final back = Evaluation.fromCloud(e.toCloud());
      expect(back.title, 'امتحان الوحدة');
      expect(back.score, 87.5);
      expect(back.maxScore, 120);
      expect(back.evaluationDate, '2026-09-10');
      expect(back.type, 'monthly');
      expect(back.groupId, 'g1');
      expect(back.typeLabel, 'اختبار شهري');
    });

    test('الأنواع الخمسة مطابقة للنسخة المكتبية', () {
      expect(
        evaluationTypeNames.keys.toList(),
        ['quiz', 'monthly', 'final', 'activity', 'behavior'],
      );
    });
  });

  group('رصد الدرجات في المتجر', () {
    test('الدفعة تُحفظ وتُدرج في طابور الرفع', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      expect(roster, isNotEmpty, reason: 'البيانات التجريبية تحتاج شعبة بطلاب');
      s.pendingSyncs.clear();

      final saved = s.saveEvaluationBatch(
        groupId: group.id,
        title: '  اختبار الوحدة  ',
        type: 'quiz',
        maxScore: 50,
        evaluationDate: '2026-09-10',
        scores: {roster.first.id: 40},
      );

      expect(saved, 1);
      final stored = s.evaluationsOfGroup(group.id).single;
      expect(stored.title, 'اختبار الوحدة', reason: 'الفراغ الزائد يُقلَّم');
      expect(stored.score, 40);
      expect(stored.maxScore, 50);
      expect(stored.percent, 80);
      expect(stored.subjectId, group.subjectId, reason: 'المادة تُؤخذ من الشعبة');
      expect(stored.teacherId, group.teacherId);
      expect(stored.syncStatus, 'pending');

      final queued = s.pendingSyncs.where((p) => p.tableName == 'student_evaluations');
      expect(queued, hasLength(1));
      expect(queued.single.action, 'INSERT');
    });

    test('الحقل الفارغ لا يُحفظ صفراً', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      // من لم تُرصد له درجة لا يُمرَّر أصلاً، فلا يُنشأ له سجل
      final saved = s.saveEvaluationBatch(
        groupId: group.id,
        title: 'اختبار',
        type: 'quiz',
        maxScore: 100,
        evaluationDate: '2026-09-10',
        scores: {roster.first.id: 90},
      );
      expect(saved, 1);
      expect(s.evaluationsOfGroup(group.id), hasLength(1));
      if (roster.length > 1) {
        expect(s.evaluationsOfGroup(group.id).where((e) => e.studentId == roster[1].id), isEmpty);
      }
    });

    test('العنوان أو الشعبة أو الدرجات الفارغة تُرفض بلا أثر', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      s.pendingSyncs.clear();

      expect(
        () => s.saveEvaluationBatch(
          groupId: group.id,
          title: '   ',
          type: 'quiz',
          maxScore: 100,
          evaluationDate: '2026-09-10',
          scores: {roster.first.id: 10},
        ),
        throwsA(isA<StoreException>()),
      );
      expect(
        () => s.saveEvaluationBatch(
          groupId: '',
          title: 'اختبار',
          type: 'quiz',
          maxScore: 100,
          evaluationDate: '2026-09-10',
          scores: {roster.first.id: 10},
        ),
        throwsA(isA<StoreException>()),
      );
      expect(
        () => s.saveEvaluationBatch(
          groupId: group.id,
          title: 'اختبار',
          type: 'quiz',
          maxScore: 100,
          evaluationDate: '2026-09-10',
          scores: const {},
        ),
        throwsA(isA<StoreException>()),
      );

      expect(s.evaluationsOfGroup(group.id), isEmpty);
      expect(s.pendingSyncs, isEmpty);
    });

    test('الدرجة القصوى غير الموجبة تعود إلى مئة', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      s.saveEvaluationBatch(
        groupId: group.id,
        title: 'اختبار',
        type: 'quiz',
        maxScore: 0,
        evaluationDate: '2026-09-10',
        scores: {roster.first.id: 70},
      );
      expect(s.evaluationsOfGroup(group.id).single.maxScore, 100);
    });

    test('الحذف يُخرج التقييم ويُدرج عملية حذف', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      s.saveEvaluationBatch(
        groupId: group.id,
        title: 'اختبار',
        type: 'quiz',
        maxScore: 100,
        evaluationDate: '2026-09-10',
        scores: {roster.first.id: 70},
      );
      final id = s.evaluationsOfGroup(group.id).single.id;
      s.pendingSyncs.clear();

      s.deleteEvaluation(id);
      expect(s.evaluationsOfGroup(group.id), isEmpty);
      expect(s.pendingSyncs.single.action, 'DELETE');
    });

    test('السجل يرتّب الأحدث تاريخاً أولاً', () {
      final s = seeded();
      final group = seedGroup(s);
      final roster = s.studentsInGroup(group.id);
      s.saveEvaluationBatch(
        groupId: group.id,
        title: 'قديم',
        type: 'quiz',
        maxScore: 100,
        evaluationDate: '2026-01-05',
        scores: {roster.first.id: 60},
      );
      s.saveEvaluationBatch(
        groupId: group.id,
        title: 'حديث',
        type: 'final',
        maxScore: 100,
        evaluationDate: '2026-09-05',
        scores: {roster.first.id: 90},
      );
      expect(s.evaluationsOfGroup(group.id).first.title, 'حديث');
      expect(s.evaluationsOfGroup(group.id), hasLength(2));
    });
  });

  group('تقييم البوابة', () {
    test('الحقول الموسّعة تمرّ عبر شكل السحابة', () {
      const e = portal.StudentEvaluation(
        id: 'e1',
        studentId: 's1',
        groupId: 'g1',
        teacherId: 't1',
        subjectId: 'sub1',
        title: 'اختبار الأسبوع',
        score: 18,
        maxScore: 20,
        evaluationDate: '2026-09-10',
        type: 'activity',
        notes: 'أداء جيد',
      );
      final back = portal.StudentEvaluation.fromCloud(e.toCloud());
      expect(back.title, 'اختبار الأسبوع');
      expect(back.maxScore, 20);
      expect(back.percent, 90);
      expect(back.passed, isTrue);
      expect(back.typeLabel, 'نشاط وواجبات');
      expect(back.groupId, 'g1');
      expect(back.evaluationDate, '2026-09-10');
    });

    test('التقييم بلا درجة لا نسبة له ولا يُعدّ ناجحاً', () {
      const e = portal.StudentEvaluation(id: 'e1', studentId: 's1', title: 'سلوك');
      expect(e.percent, isNull);
      expect(e.passed, isFalse);
    });
  });
}
