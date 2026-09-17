import '../models/models.dart';
import 'store.dart';

/// حصيلة نسخ هيكل عام منتهٍ إلى العام الجديد.
typedef YearStructureCloneResult = ({
  int subjects,
  int teachers,
  int rooms,
  int gradeFees,
  int groups,
});

String shiftDateOneYear(String value) {
  if (value.trim().isEmpty) return value;
  final date = DateTime.tryParse(value.substring(0, value.length.clamp(0, 10)));
  if (date == null) return value;
  final lastDay = DateTime(date.year + 1, date.month + 1, 0).day;
  final shifted = DateTime(
    date.year + 1,
    date.month,
    date.day.clamp(1, lastDay),
  );
  return '${shifted.year.toString().padLeft(4, '0')}-'
      '${shifted.month.toString().padLeft(2, '0')}-'
      '${shifted.day.toString().padLeft(2, '0')}';
}

/// ينسخ المواد والمعلمين والشعب والخطط والمجموعات فقط؛ سجلات الطلاب تبقى لعامها.
Future<YearStructureCloneResult> cloneYearStructure(
  AppStore store,
  String fromYearId,
  String toYearId,
) async {
  final now = store.nowIsoForSync();
  final subjectMap = <String, String>{};
  final teacherMap = <String, String>{};
  final roomMap = <String, String>{};
  var subjectCount = 0;
  var teacherCount = 0;
  var roomCount = 0;
  var feeCount = 0;
  var groupCount = 0;

  bool inSource(String id) => id == fromYearId || id.isEmpty;

  for (final old
      in store.subjects.where((e) => inSource(e.academicYearId)).toList()) {
    final row = SubjectItem(
      id: store.newId(),
      name: old.name,
      code: old.code,
      gradeLevel: old.gradeLevel,
      description: old.description,
      academicYearId: toYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    subjectMap[old.id] = row.id;
    store.subjects.add(row);
    store.queueYearStructureInsert('subjects', row.id, row.toCloud());
    subjectCount++;
  }

  for (final old
      in store.teachers.where((e) => inSource(e.academicYearId)).toList()) {
    final row = Teacher(
      id: store.newId(),
      name: old.name,
      phone: old.phone,
      subject: old.subject,
      rate: old.rate,
      email: old.email,
      notes: old.notes,
      nationalId: old.nationalId,
      portalCode: old.portalCode,
      subjectIds: [for (final id in old.subjectIds) subjectMap[id] ?? id],
      academicYearId: toYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    teacherMap[old.id] = row.id;
    store.teachers.add(row);
    store.queueYearStructureInsert('teachers', row.id, row.toCloud());
    teacherCount++;
  }

  for (final old
      in store.rooms.where((e) => inSource(e.academicYearId)).toList()) {
    final row = Classroom(
      id: store.newId(),
      name: old.name,
      gradeLevel: old.gradeLevel,
      teacherId: teacherMap[old.teacherId] ?? old.teacherId,
      capacity: old.capacity,
      notes: old.notes,
      tier: old.tier,
      academicYearId: toYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    roomMap[old.id] = row.id;
    store.rooms.add(row);
    store.queueYearStructureInsert('rooms', row.id, row.toCloud());
    roomCount++;
  }

  for (final old
      in store.gradeFees.where((e) => inSource(e.academicYearId)).toList()) {
    final row = GradeFee(
      id: store.newId(),
      gradeName: old.gradeName,
      monthlyFee: old.monthlyFee,
      tier: old.tier,
      orderIndex: old.orderIndex,
      isCustom: old.isCustom,
      term1Start: shiftDateOneYear(old.term1Start),
      term1End: shiftDateOneYear(old.term1End),
      term2Start: shiftDateOneYear(old.term2Start),
      term2End: shiftDateOneYear(old.term2End),
      planItems: [
        for (final item in old.planItems)
          PlanItem(
            id: store.newId(),
            title: item.title,
            amount: item.amount,
            dueDate: shiftDateOneYear(item.dueDate),
          ),
      ],
      academicYearId: toYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    store.gradeFees.add(row);
    store.queueYearStructureInsert('grade_fees', row.id, row.toCloud());
    feeCount++;
  }

  for (final old
      in store.groups.where((e) => inSource(e.academicYearId)).toList()) {
    final roomIds = [
      for (final id in old.allRoomIds)
        if ((roomMap[id] ?? id).isNotEmpty) roomMap[id] ?? id,
    ];
    final row = Group(
      id: store.newId(),
      name: old.name,
      subjectId: subjectMap[old.subjectId] ?? old.subjectId,
      teacherId: teacherMap[old.teacherId] ?? old.teacherId,
      roomId: roomIds.firstOrNull ?? (roomMap[old.roomId] ?? old.roomId),
      roomIds: roomIds,
      gradeLevel: old.gradeLevel,
      pricePerMonth: old.pricePerMonth,
      maxStudents: old.maxStudents,
      days: [...old.days],
      startTime: old.startTime,
      endTime: old.endTime,
      status: old.status,
      academicYearId: toYearId,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    store.groups.add(row);
    store.queueYearStructureInsert('groups', row.id, row.toCloud());
    groupCount++;
  }

  await store.snapshotGradingForYear(fromYearId);
  return (
    subjects: subjectCount,
    teachers: teacherCount,
    rooms: roomCount,
    gradeFees: feeCount,
    groups: groupCount,
  );
}
