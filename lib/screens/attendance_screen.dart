import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/list_paging.dart';
import '../widgets/attendance_view.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';
import 'attendance_print.dart';

/// كشف الحضور — مطابق لعرض الهاتف في `Attendance.tsx`:
/// شريط أيام الأسبوع المدرسي، ثم إحصاء اليوم المختار، ثم صفوف الطلاب بزرّي
/// لمس كبيرين. الشبكة الأسبوعية الكاملة تبقى في كشف الطباعة.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.initialGrade, this.initialOwnerId});

  /// المرحلة والصف المختاران سلفاً — حين تُفتح الشاشة من صفحة صف بعينه.
  final String? initialGrade;
  final String? initialOwnerId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// رصد حضور صف من صفحته: الشاشة نفسها والصف مختار، فلا يُعاد اختياره يدوياً.
Future<void> openClassAttendance(BuildContext context, {required Classroom room}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'رصد الحضور',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(height: 2),
              Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        body: AttendanceScreen(initialGrade: room.gradeLevel, initialOwnerId: room.id),
      ),
    ),
  );
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int weekOffset = 0;
  String? grade;
  String? ownerId;
  int visibleCount = kListPageSize;

  /// فُتحت الشاشة من صفحة صف: الصف معروف في العنوان فلا تُعرض قوائم الاختيار.
  bool get _fixedClass => widget.initialOwnerId?.trim().isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    grade = widget.initialGrade?.trim().isEmpty ?? true ? null : widget.initialGrade;
    ownerId = widget.initialOwnerId?.trim().isEmpty ?? true ? null : widget.initialOwnerId;
  }

  /// اليوم المعروض في الشريط. يبدأ من اليوم الحالي.
  String selectedDate = isoDate(DateTime.now());

  void _resetPage() => visibleCount = kListPageSize;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.canOpenSection('attendance')) {
          return NoAccess(section: 'attendance', roleName: store.roleName);
        }

        final week = AppStore.schoolWeek(weekOffset);
        final canEdit = store.can('attendance');

        // المرحلة ثم الشعبة
        final grades = store.roomsInViewedYear.map((r) => r.gradeLevel).where((g) => g.trim().isNotEmpty).toSet().toList();
        final currentGrade =
            grade != null && grades.contains(grade) ? grade : (grades.isNotEmpty ? grades.first : null);
        final owners = store.roomsInViewedYear.where((r) => currentGrade == null || r.gradeLevel == currentGrade).toList();

        final ownerIds = owners.map((r) => r.id).toList();
        final currentOwner =
            (ownerId != null && ownerIds.contains(ownerId)) ? ownerId! : (ownerIds.isNotEmpty ? ownerIds.first : '');
        final room = store.roomById(currentOwner);

        final list = room == null
            ? <Student>[]
            : store.attendanceRosterOf(room, weekDates: week.map((d) => d.dateStr));
        final visible = listPage(list, visibleCount);
        final ownerName = room?.name ?? '';

        // اليوم المختار داخل الأسبوع المعروض، وإلا اليوم الحالي أو أوله
        final day = week.firstWhere(
          (d) => d.dateStr == selectedDate,
          orElse: () => week.where((d) => d.isToday).firstOrNull ?? week.first,
        );

        var present = 0, absent = 0, excused = 0, unmarked = 0;
        for (final s in list) {
          switch (store.attendanceInSession(currentOwner, s.id, day.dateStr)) {
            case 'present':
              present++;
            case 'absent':
              absent++;
            case 'excused':
              excused++;
            default:
              unmarked++;
          }
        }

        // اكتمال رصد كل يوم في الشريط: نقطة خضراء للمكتمل وبلون المأذون للجزئي
        final dayProgress = <String, double>{
          for (final d in week)
            d.dateStr: list.isEmpty
                ? 0
                : list.where((s) => store.attendanceInSession(currentOwner, s.id, d.dateStr) != null).length /
                    list.length,
        };

        return ThumbActionLayer(
          action: canEdit
              ? ThumbAction(
                  label: 'الكل حاضر',
                  icon: Icons.done_all,
                  color: AppColors.success,
                  onPressed: list.isEmpty || currentOwner.isEmpty
                      ? null
                      : () {
                          store.markAllPresent(day.dateStr, list, ownerId: currentOwner);
                          showAppSnack(context, 'تم الحفظ');
                        },
                )
              : null,
          child: Column(
            children: [
              _controls(
                store,
                grades: grades,
                currentGrade: currentGrade,
                owners: owners,
                currentOwner: currentOwner,
                week: week,
                day: day,
                dayProgress: dayProgress,
                onPrint: currentOwner.isEmpty
                    ? null
                    : () => printWeeklyAttendance(
                          context,
                          store: store,
                          title: ownerName,
                          week: week,
                          students: list,
                          ownerId: currentOwner,
                        ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: EmptyState(message: 'لا يوجد طلاب مسجلون في هذه الشعبة'),
                      )
                    // بناء كسول: صفّ واحد لكل ما يظهر على الشاشة فقط.
                    // بناء القائمة كاملةً كان يُنشئ مئات الصفوف عند كل تعديل،
                    // فيتأخر التبديل بين الأيام والصفوف تأخراً محسوساً.
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                            sliver: SliverToBoxAdapter(
                              child: AttendanceDaySummary(
                                day: day,
                                total: list.length,
                                present: present,
                                absent: absent,
                                excused: excused,
                                unmarked: unmarked,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                            // كشف واحد بإطار رفيع، صف لكل طالب — كما في صفحة الصف
                            sliver: DecoratedSliver(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(Corner.card),
                                border: Border.all(color: AppColors.line),
                                boxShadow: cardShadow,
                              ),
                              sliver: SliverList.builder(
                                itemCount: visible.length,
                                itemBuilder: (context, i) {
                                  final student = visible[i];
                                  return AttendanceStudentRow(
                                    // مفتاح يشمل اليوم والحالة: الصف يُعاد بناؤه عند
                                    // تغيّر رصده وحده، لا مع كل إخطار من المخزن
                                    key: ValueKey('${student.id}|${day.dateStr}'),
                                    index: i + 1,
                                    student: student,
                                    status: store.attendanceInSession(currentOwner, student.id, day.dateStr),
                                    canEdit: canEdit,
                                    last: i == visible.length - 1,
                                    onSet: (status) => store.setAttendance(
                                      student.id,
                                      day.dateStr,
                                      status,
                                      ownerId: currentOwner,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, thumbActionClearance),
                              child: LoadMoreButton(
                                shown: visible.length,
                                total: list.length,
                                onMore: () => setState(() => visibleCount += kListPageSize),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ورقة إعدادات الحضور: تنزيل كشف الأسبوع.
  Future<void> _openSettings(VoidCallback? onPrint) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('إعدادات الحضور', style: AppText.cardTitle),
            ),
            const Divider(height: 1, color: AppColors.line),
            ListTile(
              enabled: onPrint != null,
              leading: Icon(Icons.print_outlined, color: AppColors.heading, size: 20),
              title: const Text('تنزيل كشف الأسبوع', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              onTap: () {
                Navigator.pop(ctx);
                onPrint?.call();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// لوحة التحكم العليا — عنصر واحد لكل سؤال: أي صف، أي أسبوع، أي يوم.
  /// اختيار الصف زرّ واحد بدل قائمتين، والأدوات أيقونات بلا إطارات.
  Widget _controls(
    AppStore store, {
    required List<String> grades,
    required String? currentGrade,
    required List<Classroom> owners,
    required String currentOwner,
    required List<SchoolDay> week,
    required SchoolDay day,
    required Map<String, double> dayProgress,
    required VoidCallback? onPrint,
  }) {
    final room = store.roomById(currentOwner);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // الصف حين يُختار من هنا، ومدى الأسبوع حين يكون الصف معروفاً
                child: _fixedClass
                    ? Text(
                        _weekRange(week),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppText.family,
                          color: AppColors.heading,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _ClassButton(
                        label: room == null
                            ? 'اختر الصف'
                            : [if (room.gradeLevel.trim().isNotEmpty) room.gradeLevel.trim(), room.name]
                                .join('  ·  '),
                        onTap: () =>
                            _pickClass(store, grades: grades, currentGrade: currentGrade, currentOwner: currentOwner),
                      ),
              ),
              const SizedBox(width: 6),
              _plainIcon(Icons.settings_outlined, () => _openSettings(onPrint), tooltip: 'إعدادات الحضور'),
            ],
          ),
          const SizedBox(height: 6),
          // الأيام بين سهمي الأسبوع، والسحب عليها ينقل بين الأسابيع أيضاً
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              // في العربية الأسبوع التالي على اليسار: السحب لليمين يُظهره
              setState(() => weekOffset += v > 0 ? 1 : -1);
            },
            child: Directionality(
              // الأسهم باتجاه ثابت (يسار/يمين الشاشة) لا ينعكس مع العربية
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  _plainIcon(Icons.chevron_left, () => setState(() => weekOffset--), tooltip: 'الأسبوع السابق'),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        children: [
                          for (var i = 0; i < week.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: AttendanceDayChip(
                                  day: week[i],
                                  selected: week[i].dateStr == day.dateStr,
                                  progress: dayProgress[week[i].dateStr] ?? 0,
                                  onTap: () => setState(() => selectedDate = week[i].dateStr),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _plainIcon(Icons.chevron_right, () => setState(() => weekOffset++), tooltip: 'الأسبوع التالي'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// مدى الأسبوع: «19 – 24 سبتمبر»، والشهران معاً إن تفرّق الأسبوع بينهما.
  String _weekRange(List<SchoolDay> week) {
    final first = week.first.date, last = week.last.date;
    return first.month == last.month
        ? '${first.day} – ${last.day} ${gregorianMonths[last.month - 1]}'
        : '${first.day} ${gregorianMonths[first.month - 1]} – ${last.day} ${gregorianMonths[last.month - 1]}';
  }

  /// اختيار الصف في ورقة: المراحل شرائح، وشعب المرحلة المختارة تحتها.
  Future<void> _pickClass(
    AppStore store, {
    required List<String> grades,
    required String? currentGrade,
    required String currentOwner,
  }) async {
    final picked = await showModalBottomSheet<(String?, String)>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
      builder: (ctx) {
        var g = currentGrade;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final rooms = store.roomsInViewedYear.where((r) => g == null || r.gradeLevel == g).toList();
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Text('المرحلة', style: AppText.cardTitle),
                    ),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final x in grades)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: _SheetPill(
                                label: x,
                                selected: x == g,
                                onTap: () => setSheet(() => g = x),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Divider(height: 1, color: AppColors.line),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          for (final r in rooms)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                r.id == currentOwner ? Icons.radio_button_checked : Icons.radio_button_off,
                                size: 20,
                                color: r.id == currentOwner ? AppColors.amber : AppColors.faint,
                              ),
                              title: Text(
                                r.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                              trailing: Text(
                                '${store.studentsOf(r).length}',
                                style: const TextStyle(color: AppColors.faint, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              onTap: () => Navigator.pop(ctx, (g, r.id)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      grade = picked.$1;
      ownerId = picked.$2;
      _resetPage();
    });
  }

  Widget _plainIcon(IconData icon, VoidCallback? onTap, {required String tooltip}) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, size: 20, color: onTap == null ? AppColors.faint : AppColors.muted),
    );
  }
}

/// زرّ الصف: المرحلة والشعبة في سطر، وسهم يفتح ورقة الاختيار.
class _ClassButton extends StatelessWidget {
  const _ClassButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
        decoration: BoxDecoration(
          color: AppColors.sunken,
          borderRadius: BorderRadius.circular(Corner.field),
        ),
        child: Row(
          children: [
            Icon(Icons.school_outlined, size: 18, color: AppColors.amberDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppText.family,
                  color: AppColors.heading,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _SheetPill extends StatelessWidget {
  const _SheetPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.amber : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? AppColors.amber : AppColors.lineStrong),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.family,
            color: selected ? Colors.white : AppColors.heading,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
