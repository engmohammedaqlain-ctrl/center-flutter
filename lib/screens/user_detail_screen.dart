import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pay_terms.dart';
import '../data/permissions.dart';
import '../data/phone.dart';
import '../data/staff.dart';
import '../data/store.dart';
import '../data/teacher_salary.dart';
import '../models/models.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'settings_forms.dart';
import 'settings_screen.dart';

String _dm(String d) => d.length < 10 ? d : '${int.parse(d.substring(8, 10))}/${int.parse(d.substring(5, 7))}';

/// صفحة المستخدم كصفحة المعلم والطالب — `UserDetail.tsx`: الضغط على مستخدم في «المستخدمون»
/// يفتحها. دوره ودخوله وصلاحياته، وراتبه من داخلها (إضافته للرواتب، وأجره، وسنداته)، ودوامه
/// وإجازاته.
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  List<StaffDay> monthDays = const [];
  List<LeaveRequest> leaves = const [];
  String _loadedFor = '';

  /// الدوام والإجازات من السحابة لملف راتبه، مرة لكل ملف
  Future<void> _loadCloud(String recordId) async {
    if (_loadedFor == recordId) return;
    _loadedFor = recordId;
    final month = isoDate(DateTime.now()).substring(0, 7);
    final r = await Future.wait([StaffService.days('$month-01', '$month-31'), StaffService.leaves()]);
    if (!mounted) return;
    setState(() {
      monthDays = [for (final d in (r[0] as List<StaffDay>?) ?? const <StaffDay>[]) if (d.teacherId == recordId) d]..sort((a, b) => b.date.compareTo(a.date));
      leaves = [for (final l in (r[1] as List<LeaveRequest>?) ?? const <LeaveRequest>[]) if (l.teacherId == recordId) l]..sort((a, b) => b.fromDate.compareTo(a.fromDate));
    });
  }

  Widget _row(String label, String? value, {bool ltr = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: NoonText.style(12.5, color: AdminNoon.muted))),
          Text(
            (value ?? '').trim().isEmpty ? '—' : value!,
            textDirection: ltr ? TextDirection.ltr : null,
            style: NoonText.style(12.5, weight: FontWeight.w700),
          ),
        ]),
      );

  /// الجوال يُحفظ في ملف راتبه، فلا يُضاف قبل الإضافة للرواتب.
  Widget _phoneRow(AppStore store, Teacher? record, bool canPay) {
    final phone = (record?.phone ?? '').trim();
    if (phone.isNotEmpty) return _row('الجوال', formatPhoneDisplay(record!.phone), ltr: true);
    if (record == null) return _row('الجوال', canPay ? 'يُسجَّل بعد الإضافة للرواتب' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text('الجوال', style: NoonText.style(12.5, color: AdminNoon.muted))),
        TextButton.icon(
          onPressed: () async {
            final v = await _ask('جوال ${record.name}', '', number: true);
            if (v == null || v.isEmpty) return;
            final full = combinePhoneAndPrefix(digitsOnly(v));
            if (!RegExp(r'^05[69]\d{7}$').hasMatch(full)) {
              if (mounted) showAppSnack(context, 'رقم الجوال غير صحيح', error: true);
              return;
            }
            _run(() => store.saveTeacherPay(record, {'phone': full, 'phone_prefix': parsePhoneAndPrefix(full).prefix}));
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('إضافة جوال'),
        ),
      ]),
    );
  }

  Future<String?> _ask(String title, String initial, {bool number = false}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          textDirection: number ? TextDirection.ltr : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
  }

  void _run(VoidCallback action) {
    try {
      action();
    } on StoreException catch (e) {
      showAppSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final u = store.users.where((x) => x.id == widget.userId).firstOrNull;
    if (u == null) {
      return Scaffold(appBar: AppBar(title: const Text('المستخدم')), body: const Center(child: Text('المستخدم غير موجود')));
    }
    final canPay = store.can('finance.expenses');
    final canManage = store.can('settings.users');
    final record = store.staffPayRecord(u.id);
    if (record != null) unawaited(_loadCloud(record.id));
    final isAdmin = normalizeRole(u.role) == 'admin';
    final login = (u.nationalId ?? '').isNotEmpty ? u.nationalId! : (u.username ?? '');
    final sections = effectiveSections(u.capabilities, u.role);
    final month = isoDate(DateTime.now()).substring(0, 7);
    String money(double v) => '${trimNum(v)} شيكل';

    final payouts = record == null
        ? const <TeacherPayout>[]
        : ([for (final p in store.teacherPayouts) if (p.teacherId == record.id && !p.cancelled) p]..sort((a, b) => b.paymentDate.compareTo(a.paymentDate)));
    final isAdvance = (TeacherPayout p) => p.payoutType == 'advance';
    final paidMonth = payouts.where((p) => p.paymentDate.startsWith(month) && !isAdvance(p)).fold<double>(0, (n, p) => n + p.amount);
    final advances = payouts.where(isAdvance).fold<double>(0, (n, p) => n + p.amount);
    final terms = record == null ? null : currentTerms(record);
    final offDays = monthDays.where((d) => d.status != 'present').toList();
    final present = monthDays.where((d) => d.status == 'present').length;

    Widget sec(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 10), child: child);

    return Scaffold(
      backgroundColor: AdminNoon.paper,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              [roleLabel(u.role), if ((record?.jobTitle ?? '').isNotEmpty) record!.jobTitle].join(' · '),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) async {
                if (v == 'rename') {
                  final name = await _ask('تعديل الاسم', u.name);
                  if (name == null || name.isEmpty || name == u.name) return;
                  _run(() => store.updateUser(AppUser(id: u.id, name: name, role: u.role, email: u.email, isActive: u.isActive, capabilities: u.capabilities)));
                } else if (v == 'unpay') {
                  if (context.mounted) await confirmRemoveFromPayroll(context, u);
                } else if (v == 'delete') {
                  if (!context.mounted) return;
                  if (await confirmDeleteUser(context, u) && context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('تعديل الاسم')),
                if (canPay && record != null) const PopupMenuItem(value: 'unpay', child: Text('إزالة من الرواتب')),
                if (u.id != store.deviceUserId) const PopupMenuItem(value: 'delete', child: Text('حذف المستخدم')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          sec(NoonFoldCard(
            title: 'الحساب',
            initiallyOpen: true,
            children: [
              _row('الدور', roleLabel(u.role)),
              _row('الدخول للنظام', login.isEmpty ? 'بلا دخول' : login, ltr: login.isNotEmpty),
              _phoneRow(store, record, canPay),
              if (!u.isActive) _row('الحالة', 'موقوف'),
              if (canManage) ...[
                const SizedBox(height: 6),
                NoonButton(
                  label: login.isEmpty ? 'إنشاء دخول' : 'الدخول وكلمة المرور',
                  icon: Icons.key_outlined,
                  expand: true,
                  onPressed: () => showStaffLoginSheet(context, u),
                ),
              ],
            ],
          )),

          sec(NoonFoldCard(
            title: 'الصلاحيات',
            headerExtra: Text('${sections.length} صلاحية', style: NoonText.style(11, color: AdminNoon.muted)),
            children: [
              if (isAdmin)
                Text('المدير يرى كل شيء ولا تُقيَّد صلاحياته. لتقييد حساب اختر له دوراً آخر.', style: NoonText.style(12, color: AdminNoon.muted))
              else ...[
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in sections.where((s) => !s.contains('.')))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: AdminNoon.ink.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20)),
                      child: Text(sectionLabel(s), style: NoonText.style(11.5, weight: FontWeight.w600)),
                    ),
                ]),
                if (canManage) ...[
                  const SizedBox(height: 10),
                  NoonButton(
                    label: 'تعديل الصلاحيات',
                    icon: Icons.tune,
                    expand: true,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UserAccessScreen(user: u))),
                  ),
                ],
              ],
            ],
          )),

          if (canPay)
            sec(NoonFoldCard(
              title: 'الراتب',
              initiallyOpen: true,
              headerExtra: record == null
                  ? null
                  : Text(paidMonth > 0 ? money(paidMonth) : 'لم يُصرف هذا الشهر', style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.muted)),
              children: [
                if (record == null) ...[
                  Text('غير مضاف للرواتب: أضفه فيظهر في الرواتب والدوام والإجازات', style: NoonText.style(12, color: AdminNoon.muted)),
                  const SizedBox(height: 8),
                  NoonButton(label: 'إضافة للرواتب', icon: Icons.payments_outlined, tone: NoonTone.ink, expand: true, onPressed: () => showAddToPayrollSheet(context, u)),
                ] else ...[
                  _row('الوظيفة', record.jobTitle),
                  _row('الراتب الأساسي', terms!.fixed > 0 ? money(terms.fixed) : null),
                  if (terms.allowances.isNotEmpty) _row('البدلات', money(terms.allowances.fold<double>(0, (n, a) => n + a.amount))),
                  _row('صُرف له هذا الشهر', money(paidMonth)),
                  _row('سلف هذا العام', advances > 0 ? money(advances) : null),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: NoonButton(
                        label: 'تعديل الراتب',
                        icon: Icons.payments_outlined,
                              expand: true,
                        onPressed: () async {
                          final v = await _ask('الراتب الشهري الأساسي', terms.fixed > 0 ? trimNum(terms.fixed) : '', number: true);
                          if (v == null) return;
                          final salary = double.tryParse(digitsOnly(v)) ?? 0;
                          _run(() => store.saveTeacherPay(record, payUpdate(record, payInputOf(record).copyWith(fixed: salary), month)));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NoonButton(
                        label: 'الوظيفة',
                        icon: Icons.badge_outlined,
                              expand: true,
                        onPressed: () async {
                          final v = await _ask('الوظيفة', record.jobTitle);
                          if (v == null || v.isEmpty) return;
                          _run(() => store.saveTeacherPay(record, {'job_title': v}));
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('البدلات وخصم الغياب والسلف والصرف من المالية ← الرواتب', style: NoonText.style(11.5, color: AdminNoon.muted)),
                  if (payouts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('سجل الصرف', style: NoonText.style(11, weight: FontWeight.w700, color: AdminNoon.muted)),
                    for (final p in payouts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 48, child: Text(_dm(p.paymentDate), style: NoonText.style(12))),
                          Text(payoutTypeNames[p.payoutType] ?? p.payoutType, style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
                          const Spacer(),
                          Text(money(p.amount), style: NoonText.style(12, weight: FontWeight.w700)),
                        ]),
                      ),
                  ],
                ],
              ],
            )),

          if (record != null)
            sec(NoonFoldCard(
              title: 'الدوام هذا الشهر',
              children: [
                if (offDays.isEmpty)
                  Text(present > 0 ? 'حاضر $present يوماً بلا غياب' : 'لم يُرصد بعد', style: NoonText.style(12, color: AdminNoon.muted))
                else
                  for (final d in offDays)
                    Row(children: [
                      Text(_dm(d.date), style: NoonText.style(12)),
                      const Spacer(),
                      Text(d.status == 'absent' ? 'غائب' : 'متأخر', style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
                    ]),
              ],
            )),

          if (record != null)
            sec(NoonFoldCard(
              title: 'الإجازات',
              children: [
                if (leaves.isEmpty)
                  Text('لا إجازات', style: NoonText.style(12, color: AdminNoon.muted))
                else
                  for (final l in leaves)
                    Row(children: [
                      Text(l.fromDate == l.toDate ? _dm(l.fromDate) : '${_dm(l.fromDate)} - ${_dm(l.toDate)}', style: NoonText.style(12)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.reason, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(12, color: AdminNoon.muted))),
                      Text(l.statusLabel, style: NoonText.style(12, weight: FontWeight.w700, color: AdminNoon.muted)),
                    ]),
              ],
            )),
        ],
      ),
    );
  }
}
