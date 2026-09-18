/// مزامنة خطة المرحلة الموحّدة — المقابل لـ `gradePlanSync.ts`.
///
/// زر واحد يبني ويكمل ويحدّث الأسعار ويحذف ما سقط من الخطة، مع معاينة قبل الكتابة.
library;

import '../models/models.dart';
import 'academic_matching.dart';
import 'balance.dart';
import 'fee_plan.dart';
import 'store.dart';

double _round2(double n) => (n * 100).round() / 100;

bool _inYear(Installment inst, String yearId) =>
    inst.academicYearId.isEmpty || inst.academicYearId == yearId;

String _seatIdFor(String studentId, String yearId, List<Installment> own) {
  final hasOlderSeat = own.any(
    (i) => i.title == seatTitle && !_inYear(i, yearId),
  );
  return hasOlderSeat
      ? seatInstallmentId(studentId, yearId)
      : seatInstallmentId(studentId);
}

class GradePlanSyncOptions {
  const GradePlanSyncOptions({
    this.apply = false,
    this.studentIds,
    this.includePaid = false,
    this.removePaid = false,
    this.resetUnexplained = false,
    this.repriceOnly = false,
    this.discountChange = false,
    this.discountOverride,
    this.checkPermission = true,
  });

  final bool apply;
  final Set<String>? studentIds;
  final bool includePaid;
  final bool removePaid;
  final bool resetUnexplained;
  final bool repriceOnly;
  final bool discountChange;

  /// خصم مقترح لم يُحفظ بعد، لمعاينة أثره كما في الويب.
  final Map<String, PlanDiscount?>? discountOverride;
  final bool checkPermission;
}

class StudentAmountRow {
  StudentAmountRow({
    required this.studentId,
    required this.name,
    this.count = 0,
    this.amount = 0,
  });

  final String studentId;
  final String name;
  int count;
  double amount;
}

class SyncBucket {
  const SyncBucket({
    this.students = 0,
    this.installments = 0,
    this.difference = 0,
    this.wasDue = 0,
  });

  final int students;
  final int installments;
  final double difference;
  final int wasDue;

  SyncBucket copyWith({
    int? students,
    int? installments,
    double? difference,
    int? wasDue,
  }) => SyncBucket(
    students: students ?? this.students,
    installments: installments ?? this.installments,
    difference: difference ?? this.difference,
    wasDue: wasDue ?? this.wasDue,
  );
}

class SyncPaidRemove {
  const SyncPaidRemove({
    this.students = 0,
    this.installments = 0,
    this.amount = 0,
    this.list = const [],
  });

  final int students;
  final int installments;
  final double amount;
  final List<StudentAmountRow> list;
}

class SyncSkipped {
  const SyncSkipped({this.customPlan = 0, this.manualInstallments = 0});

  final int customPlan;
  final int manualInstallments;

  SyncSkipped copyWith({int? customPlan, int? manualInstallments}) =>
      SyncSkipped(
        customPlan: customPlan ?? this.customPlan,
        manualInstallments: manualInstallments ?? this.manualInstallments,
      );
}

class GradePlanSyncResult {
  GradePlanSyncResult({
    this.considered = 0,
    this.build = const SyncBucket(),
    this.add = const SyncBucket(),
    this.reprice = const SyncBucket(),
    this.repricePaid = const SyncBucket(),
    this.remove = const SyncBucket(),
    this.removePaid = const SyncPaidRemove(),
    this.unexplained = const SyncPaidRemove(),
    this.skipped = const SyncSkipped(),
  });

  int considered;
  SyncBucket build;
  SyncBucket add;
  SyncBucket reprice;
  SyncBucket repricePaid;
  SyncBucket remove;
  SyncPaidRemove removePaid;
  SyncPaidRemove unexplained;
  SyncSkipped skipped;

  bool get isEmpty =>
      build.students == 0 &&
      add.installments == 0 &&
      reprice.installments == 0 &&
      repricePaid.installments == 0 &&
      remove.installments == 0 &&
      removePaid.installments == 0 &&
      unexplained.installments == 0;
}

/// تطبيق خطة المرحلة على طلابها — الزر الواحد.
class GradePlanSync {
  GradePlanSync._();

  static GradePlanSyncResult run(
    AppStore store,
    String gradeName, {
    GradePlanSyncOptions opts = const GradePlanSyncOptions(),
  }) {
    if (opts.checkPermission) store.requireSection('settings');
    final result = GradePlanSyncResult();
    final items = store.planItemsOf(
      store.gradePlans()[gradeName.trim().toLowerCase()],
    );
    if (items.isEmpty) return result;

    final itemById = {for (final i in items) i.id: i};
    final yearId =
        store.operationalAcademicYear?.id ?? store.viewedAcademicYearId;
    final now = store.nowIsoForSync();
    final onlyIds = opts.studentIds;

    final unexplainedList = <String, StudentAmountRow>{};
    final removePaidList = <String, StudentAmountRow>{};

    final targets = store.students.where((s) {
      if (s.status != 'active' || !isSameGrade(s.gradeLevel, gradeName)) {
        return false;
      }
      if (onlyIds != null && !onlyIds.contains(s.id)) return false;
      return true;
    }).toList();

    for (final student in targets) {
      if (student.usesCustomPlan) {
        result.skipped = result.skipped.copyWith(
          customPlan: result.skipped.customPlan + 1,
        );
        continue;
      }
      result.considered++;

      final discount = opts.discountOverride?.containsKey(student.id) == true
          ? opts.discountOverride![student.id]
          : studentDiscountOf(student);
      final own = store.installments
          .where((i) => i.studentId == student.id)
          .toList();
      final yearOwn = own.where((i) => _inYear(i, yearId)).toList();
      final planRows = yearOwn
          .where((i) => planItemIdOf(i.id, student.id) != null)
          .toList();
      final manualRows = yearOwn.where((i) {
        if (planItemIdOf(i.id, student.id) != null) return false;
        if (i.id.startsWith(AppStore.feeIdPrefix)) return false;
        if (isExtraChargeId(i.id)) return false;
        if (i.title == seatTitle) return false;
        return true;
      }).toList();

      final returning = own.any((i) => !_inYear(i, yearId));
      // كـ gradePlanSync.ts: لا يُسقط الحجز بعلم «دفع الحجز» — السند أو وجود القسط يمنع التكرار
      double seatFeeFor(bool hasSeat) =>
          (hasSeat || returning) ? 0.0 : store.seatReservationFee;

      final toDelete = <({Installment inst, bool paid})>[];
      final toUpdate =
          <
            ({Installment inst, double amount, double original, double share})
          >[];
      var toInsert = <Installment>[];

      if (planRows.isEmpty) {
        if (opts.repriceOnly) continue;
        if (manualRows.isNotEmpty) {
          result.skipped = result.skipped.copyWith(
            manualInstallments: result.skipped.manualInstallments + 1,
          );
          continue;
        }
        final hasSeat = yearOwn.any((i) => i.title == seatTitle);
        final source = [
          for (final item in items)
            PlanItem(
              id: item.id,
              title: item.title,
              amount: planInstallmentAmount(
                item.amount,
                item.dueDate,
                discount,
              ),
              dueDate: item.dueDate,
            ),
        ];
        // نمرّر المبالغ بعد الخصم ونحفظ الأصل عبر صفوف وسيطة
        final rows = buildStudentPlan(
          source,
          student.id,
          seatFee: seatFeeFor(hasSeat),
          deductSeat: store.deductsSeatFee,
          enrollmentDate: isoDate(student.enrollmentDate),
          seatId: _seatIdFor(student.id, yearId, own),
        );
        // أعد سعر الخطة الأصلي على بنود المرحلة
        final withOriginal = [
          for (final row in rows)
            () {
              final itemId = planItemIdOf(row.id, student.id);
              if (itemId == null) return row;
              final item = itemById[itemId];
              if (item == null) return row;
              return row.copyWith(originalAmount: item.amount);
            }(),
        ];
        toInsert = toInstallments(
          withOriginal,
          student.id,
          now,
          academicYearId: yearId,
        );
        result.build = result.build.copyWith(
          students: result.build.students + 1,
          installments: result.build.installments + toInsert.length,
        );
      } else {
        if (!opts.repriceOnly) {
          var removedUnpaid = false;
          for (final inst in planRows) {
            final itemId = planItemIdOf(inst.id, student.id)!;
            if (itemById.containsKey(itemId)) continue;
            final paid =
                inst.paidAmount > cent ||
                store.payments.any(
                  (p) => !p.cancelled && p.installmentId == inst.id,
                );
            if (!paid) {
              result.remove = result.remove.copyWith(
                installments: result.remove.installments + 1,
                wasDue: result.remove.wasDue + (isInstallmentDue(inst) ? 1 : 0),
              );
              toDelete.add((inst: inst, paid: false));
              removedUnpaid = true;
            } else {
              final row = removePaidList.putIfAbsent(
                student.id,
                () => StudentAmountRow(
                  studentId: student.id,
                  name: student.fullName,
                ),
              );
              row.count++;
              row.amount = _round2(row.amount + inst.paidAmount);
              if (opts.removePaid) toDelete.add((inst: inst, paid: true));
            }
          }
          if (removedUnpaid) {
            result.remove = result.remove.copyWith(
              students: result.remove.students + 1,
            );
          }
        }

        var repriced = false;
        var repricedPaid = false;
        for (final inst in planRows) {
          final item = itemById[planItemIdOf(inst.id, student.id)!];
          if (item == null || inst.isExempt) continue;
          final hasPaid = inst.paidAmount > cent;
          if (opts.discountChange) {
            if (inst.status == 'paid' && isInstallmentDue(inst)) continue;
          } else if (!hasPaid && isInstallmentDue(inst)) {
            continue;
          }

          final planAmount = item.amount;
          final due = isoDate(inst.dueDate);
          final expected = planInstallmentAmount(
            planAmount,
            due,
            discount,
            seatDeduction: inst.seatDeduction,
            discountAmount: inst.discountAmount,
          );
          if ((expected - inst.amount).abs() < cent) continue;

          var consistent = true;
          if (inst.originalAmount != null) {
            final builtOn = inst.originalAmount!;
            // الصفر قيمة محفوظة صحيحة: يعني أن القسط بُني بلا خصم طالب.
            // اعتباره «مفقوداً» بعد تسجيل خصم جديد يجعل القسط يبدو تعديلاً حراً
            // ويمنع إعادة تسعيره، خلاف حقل الويب nullable.
            final appliedShare = inst.planDiscountShare;
            final rebuilt = _round2(
              builtOn - appliedShare - inst.seatDeduction - inst.discountAmount,
            );
            consistent =
                ((rebuilt < 0 ? 0.0 : rebuilt) - inst.amount).abs() < cent;
          }

          if (!consistent) {
            final row = unexplainedList.putIfAbsent(
              student.id,
              () => StudentAmountRow(
                studentId: student.id,
                name: student.fullName,
              ),
            );
            row.count++;
            row.amount = _round2(row.amount + expected - inst.amount);
            if (!opts.resetUnexplained || (hasPaid && !opts.includePaid)) {
              continue;
            }
          }

          final diff = expected - inst.amount;
          if (hasPaid) {
            result.repricePaid = result.repricePaid.copyWith(
              installments: result.repricePaid.installments + 1,
              difference: result.repricePaid.difference + diff,
            );
            repricedPaid = true;
            if (!opts.includePaid) continue;
          } else if (consistent) {
            result.reprice = result.reprice.copyWith(
              installments: result.reprice.installments + 1,
              difference: result.reprice.difference + diff,
            );
            repriced = true;
          }

          toUpdate.add((
            inst: inst,
            amount: expected,
            original: planAmount,
            share: studentDiscountShare(planAmount, due, discount),
          ));
        }
        if (repriced) {
          result.reprice = result.reprice.copyWith(
            students: result.reprice.students + 1,
          );
        }
        if (repricedPaid) {
          result.repricePaid = result.repricePaid.copyWith(
            students: result.repricePaid.students + 1,
          );
        }

        if (!opts.repriceOnly) {
          final planStart =
              ([
                for (final i in planRows) isoDate(i.dueDate),
              ]..sort()).firstOrNull ??
              '';
          final present = {
            for (final i in planRows) planItemIdOf(i.id, student.id),
          };
          final missing = items.where((item) {
            if (present.contains(item.id)) return false;
            final due = item.dueDate.length >= 10
                ? item.dueDate.substring(0, 10)
                : item.dueDate;
            return due.compareTo(planStart) >= 0;
          }).toList();
          if (missing.isNotEmpty) {
            final hasSeat = yearOwn.any((i) => i.title == seatTitle);
            final source = [
              for (final item in missing)
                PlanItem(
                  id: item.id,
                  title: item.title,
                  amount: planInstallmentAmount(
                    item.amount,
                    item.dueDate,
                    discount,
                  ),
                  dueDate: item.dueDate,
                ),
            ];
            final rows = buildStudentPlan(
              source,
              student.id,
              seatFee: seatFeeFor(hasSeat),
              deductSeat: store.deductsSeatFee,
              enrollmentDate: isoDate(student.enrollmentDate),
              seatId: _seatIdFor(student.id, yearId, own),
            );
            final withOriginal = [
              for (final row in rows)
                () {
                  final itemId = planItemIdOf(row.id, student.id);
                  if (itemId == null) return row;
                  final item = itemById[itemId];
                  if (item == null) return row;
                  return row.copyWith(originalAmount: item.amount);
                }(),
            ];
            // لا نكرر قسط الحجز إن وُجد هذا العام
            final filtered = hasSeat
                ? withOriginal.where((r) => r.title != seatTitle).toList()
                : withOriginal;
            toInsert = toInstallments(
              filtered,
              student.id,
              now,
              academicYearId: yearId,
            );
            if (toInsert.isNotEmpty) {
              result.add = result.add.copyWith(
                students: result.add.students + 1,
                installments: result.add.installments + toInsert.length,
              );
            }
          }
        }
      }

      if (!opts.apply) continue;
      if (toDelete.isEmpty && toUpdate.isEmpty && toInsert.isEmpty) continue;

      for (final d in toDelete) {
        store.unlinkAndDeleteInstallment(d.inst, now);
      }
      for (final u in toUpdate) {
        final inst = u.inst;
        inst.amount = u.amount;
        inst.originalAmount = u.original;
        inst.planDiscountShare = u.share;
        inst.updatedAt = now;
        inst.syncStatus = 'pending';
        inst.status = installmentStatusFor(
          chargeableAmount(inst),
          inst.paidAmount,
        );
        store.queueInstallmentUpdate(inst);
      }
      for (final inst in toInsert) {
        store.installments.add(inst);
        store.queueInstallmentInsert(inst);
      }
      store.persistStudentLedgerPublic(student);
    }

    result.removePaid = SyncPaidRemove(
      students: removePaidList.length,
      installments: removePaidList.values.fold(0, (a, r) => a + r.count),
      amount: _round2(removePaidList.values.fold(0.0, (a, r) => a + r.amount)),
      list: removePaidList.values.toList(),
    );
    result.unexplained = SyncPaidRemove(
      students: unexplainedList.length,
      installments: unexplainedList.values.fold(0, (a, r) => a + r.count),
      amount: _round2(unexplainedList.values.fold(0.0, (a, r) => a + r.amount)),
      list: unexplainedList.values.toList(),
    );
    result.reprice = result.reprice.copyWith(
      difference: _round2(result.reprice.difference),
    );
    result.repricePaid = result.repricePaid.copyWith(
      difference: _round2(result.repricePaid.difference),
    );

    if (opts.apply && !result.isEmpty) {
      store.markDirty('installments');
      store.notifyListeners();
    }

    return result;
  }
}
