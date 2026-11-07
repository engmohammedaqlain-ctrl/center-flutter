import 'package:flutter/material.dart';

import '../data/dev_admin.dart';
import '../data/store.dart';
import '../data/user_message.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/widgets.dart';

String _time(DateTime? d) => d == null ? '' : '${isoDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

BoxDecoration _box() => BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    );

Widget _title(String text, {int? count}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
      child: Text(count == null ? text : '$text ($count)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
    );

Widget _stat(String label, String value, {String? hint}) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(10),
        decoration: _box(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.heading)),
            if (hint != null) Text(hint, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ],
        ),
      ),
    );

/// السجل: كل ما جرى على المدارس من لوحة المطور — `DevLogPanel`.
class DevLogScreen extends StatefulWidget {
  const DevLogScreen({super.key});

  @override
  State<DevLogScreen> createState() => _DevLogScreenState();
}

class _DevLogScreenState extends State<DevLogScreen> {
  List<DevLogEntry>? rows;
  var failed = false;
  var q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DevAdmin.listLog();
    if (mounted) {
      setState(() {
        rows = list;
        failed = list == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final r in rows ?? const <DevLogEntry>[])
        if (q.isEmpty || '${r.tenantName ?? ''} ${r.action} ${r.detail ?? ''}'.contains(q)) r,
    ];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 0, title: const Text('السجل')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              onChanged: (v) => setState(() => q = v.trim()),
              decoration: const InputDecoration(isDense: true, hintText: 'بحث', prefixIcon: Icon(Icons.search, size: 18)),
            ),
          ),
          Expanded(
            child: failed
                ? Center(child: TextButton(onPressed: _load, child: const Text('تعذّر التحميل، إعادة المحاولة')))
                : rows == null
                    ? const Center(child: AppLoader(compact: true))
                    : list.isEmpty
                        ? const Padding(padding: EdgeInsets.all(12), child: EmptyState(message: 'لا شيء'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: list.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final r = list[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: AppColors.sunken, borderRadius: BorderRadius.circular(4)),
                                        child: Text(r.action, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.tenantName ?? 'المنصة', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.heading)),
                                            if ((r.detail ?? '').isNotEmpty)
                                              Text(r.detail!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                          ],
                                        ),
                                      ),
                                      Text(_time(r.createdAt), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

/// إعدادات المنصة: الصيانة، وتحديث الجوال، والإعلانات — `DevSettingsPanel`.
class DevPlatformSettingsScreen extends StatefulWidget {
  const DevPlatformSettingsScreen({super.key});

  @override
  State<DevPlatformSettingsScreen> createState() => _DevPlatformSettingsScreenState();
}

class _DevPlatformSettingsScreenState extends State<DevPlatformSettingsScreen> {
  PlatformSettings? settings;
  List<PlatformAnnouncement> items = const [];
  var failed = false;
  var busy = false;
  final message = TextEditingController();
  final minBuild = TextEditingController();
  final body = TextEditingController();
  String level = 'info';
  String target = '';
  String days = '7';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    message.dispose();
    minBuild.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([DevAdmin.getSettings(), DevAdmin.listAnnouncements()]);
    if (!mounted) return;
    final s = results[0] as PlatformSettings?;
    setState(() {
      settings = s;
      failed = s == null;
      items = results[1] as List<PlatformAnnouncement>;
      message.text = s?.message ?? '';
      minBuild.text = (s?.minBuild ?? 0) > 0 ? '${s!.minBuild}' : '';
    });
  }

  Future<void> _run(Future<void> Function() work, String ok) async {
    setState(() => busy = true);
    try {
      await work();
      await _load();
      if (mounted) showAppSnack(context, ok);
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenants = StoreScope.of(context).tenants;
    final s = settings;
    String nameOf(String? id) => id == null ? 'كل المدارس' : (tenants.where((t) => t.id == id).firstOrNull?.name ?? '—');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 0, title: const Text('إعدادات المنصة')),
      body: failed
          ? Center(child: TextButton(onPressed: _load, child: const Text('تعذّر التحميل، إعادة المحاولة')))
          : s == null
              ? const Center(child: AppLoader(compact: true))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _title('الصيانة'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: _box(),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('إيقاف كل المدارس', style: TextStyle(fontSize: 13)),
                            value: s.maintenance,
                            onChanged: busy
                                ? null
                                : (v) async {
                                    if (v &&
                                        !await confirmSheet(context, title: 'صيانة عامة', message: 'إيقاف كل المدارس؟', confirmLabel: 'إيقاف')) {
                                      return;
                                    }
                                    await _run(() => DevAdmin.saveSettings({'maintenance': v}), v ? 'الصيانة شغالة' : 'انتهت الصيانة');
                                  },
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: message,
                                  maxLength: 300,
                                  decoration: const InputDecoration(isDense: true, hintText: 'رسالة الصيانة', counterText: ''),
                                ),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _run(
                                          () => DevAdmin.saveSettings({'maintenance_message': message.text.trim().isEmpty ? null : message.text.trim()}),
                                          'حُفظت',
                                        ),
                                child: const Text('حفظ'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                    _title('تحديث الجوال'),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: _box(),
                      child: Row(
                        children: [
                          const Tooltip(
                            message: 'الأقدم من هذا الرقم يُجبر على التحديث. 0 = بلا إجبار',
                            child: Text('أقل رقم بناء', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: minBuild,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(isDense: true, hintText: '0'),
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final n = (int.tryParse(minBuild.text.trim()) ?? 0).clamp(0, 1 << 30);
                                    if (n == s.minBuild) return;
                                    if (n > 0 &&
                                        !await confirmSheet(context,
                                            title: 'إجبار التحديث', message: 'إجبار كل جهاز أقدم من البناء $n على التحديث؟', confirmLabel: 'حفظ')) {
                                      return;
                                    }
                                    await _run(() => DevAdmin.saveSettings({'min_build': n}), 'حُفظ');
                                  },
                            child: const Text('حفظ'),
                          ),
                        ],
                      ),
                    ),
                    _title('إعلان جديد'),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: _box(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: body,
                            maxLength: 500,
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(isDense: true, hintText: 'نص الإعلان', counterText: ''),
                          ),
                          const SizedBox(height: 8),
                          AppDropdown<String>(
                            value: target,
                            items: [
                              const DropdownMenuItem(value: '', child: Text('كل المدارس')),
                              for (final t in tenants) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => target = v ?? ''),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppDropdown<String>(
                                  value: level,
                                  items: const [
                                    DropdownMenuItem(value: 'info', child: Text('عادي')),
                                    DropdownMenuItem(value: 'warn', child: Text('مهم')),
                                  ],
                                  onChanged: (v) => setState(() => level = v ?? level),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppDropdown<String>(
                                  value: days,
                                  items: const [
                                    DropdownMenuItem(value: '1', child: Text('يوم')),
                                    DropdownMenuItem(value: '7', child: Text('أسبوع')),
                                    DropdownMenuItem(value: '30', child: Text('شهر')),
                                    DropdownMenuItem(value: '', child: Text('دائماً')),
                                  ],
                                  onChanged: (v) => setState(() => days = v ?? days),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          PrimaryButton(
                            label: 'نشر',
                            expand: true,
                            onPressed: busy || body.text.trim().isEmpty
                                ? null
                                : () => _run(() async {
                                      await DevAdmin.addAnnouncement(
                                        tenantId: target.isEmpty ? null : target,
                                        body: body.text.trim(),
                                        level: level,
                                        endsAt: days.isEmpty ? null : DateTime.now().add(Duration(days: int.parse(days))),
                                      );
                                      body.clear();
                                    }, 'نُشر'),
                          ),
                        ],
                      ),
                    ),
                    _title('الإعلانات', count: items.length),
                    if (items.isEmpty)
                      const EmptyState(message: 'لا إعلانات')
                    else
                      Container(
                        decoration: _box(),
                        child: Column(
                          children: [
                            for (final a in items)
                              Opacity(
                                opacity: a.active ? 1 : 0.5,
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.circle, size: 10, color: a.level == 'warn' ? const Color(0xFFF4AE1A) : const Color(0xFF128A91)),
                                  title: Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    '${nameOf(a.tenantId)} · ${a.active ? (a.endsAt == null ? 'دائم' : 'حتى ${isoDate(a.endsAt!.toLocal())}') : 'منتهي'}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: a.active
                                      ? TextButton(onPressed: busy ? null : () => _run(() => DevAdmin.endAnnouncement(a.id), 'انتهى'), child: const Text('إنهاء'))
                                      : TextButton(
                                          onPressed: busy ? null : () => _run(() => DevAdmin.deleteAnnouncement(a.id), 'حُذف'),
                                          child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// نظرة عامة على المنصة: الإيراد، والدخول، والنمو — `DevOverview`.
class DevOverviewScreen extends StatefulWidget {
  const DevOverviewScreen({super.key});

  @override
  State<DevOverviewScreen> createState() => _DevOverviewScreenState();
}

class _DevOverviewScreenState extends State<DevOverviewScreen> {
  DevStats? stats;
  var failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await DevAdmin.getStats();
    if (mounted) {
      setState(() {
        stats = s;
        failed = s == null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final tenants = StoreScope.of(context).tenants;
    final now = DateTime.now();
    final active = tenants.where((t) => t.active && (t.isLifetime || t.expiresAt.isAfter(now))).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 0, title: const Text('نظرة عامة')),
      body: failed
          ? Center(child: TextButton(onPressed: _load, child: const Text('تعذّر التحميل، إعادة المحاولة')))
          : s == null
              ? const Center(child: AppLoader(compact: true))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(9, 6, 9, 24),
                    children: [
                      Row(children: [
                        _stat('المدارس', '${tenants.length}', hint: '$active فعّالة'),
                        _stat('الإيراد المتوقع شهرياً', money(s.revenue.monthly)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        _stat('هذا الشهر', money(s.revenue.thisMonth)),
                        _stat('الشهر الماضي', money(s.revenue.lastMonth)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        _stat('دخول اليوم', '${s.auth.day}', hint: 'الأسبوع ${s.auth.week}'),
                        _stat('مفاتيح اليوم', '${s.auth.keysDay}'),
                      ]),
                      _title('النمو'),
                      Container(
                        decoration: _box(),
                        child: Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(children: [
                                Expanded(child: Text('الشهر', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                                SizedBox(width: 70, child: Text('المدارس', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                                SizedBox(width: 70, child: Text('الطلاب', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
                              ]),
                            ),
                            for (final g in s.growth.reversed)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                child: Row(children: [
                                  Expanded(child: Text(g.month, style: const TextStyle(fontSize: 12.5))),
                                  SizedBox(width: 70, child: Text('${g.schools}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5))),
                                  SizedBox(width: 70, child: Text('${g.students}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5))),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// صفحة المدرسة للمطور: النشاط، والتحكم، والاشتراك ودفعاته، والملاحظات — `DevSchoolPage`.
class DevSchoolScreen extends StatefulWidget {
  const DevSchoolScreen({super.key, required this.tenant});

  final Tenant tenant;

  @override
  State<DevSchoolScreen> createState() => _DevSchoolScreenState();
}

class _DevSchoolScreenState extends State<DevSchoolScreen> {
  double? price;
  List<TenantPaymentRow>? payments;
  List<TenantNoteRow>? notes;
  Map<String, dynamic>? activity;
  ({bool maintenance, bool updateHold})? controls;
  var busy = false;
  final priceCtl = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  final noteBody = TextEditingController();
  DateTime paidOn = DateTime.now();

  Tenant get t => widget.tenant;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    priceCtl.dispose();
    amount.dispose();
    note.dispose();
    noteBody.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      DevAdmin.getPrices(),
      DevAdmin.listPayments(t.id),
      DevAdmin.listNotes(t.id),
      DevAdmin.getStats(),
      DevAdmin.tenantControls(t.id),
    ]);
    if (!mounted) return;
    setState(() {
      price = (results[0] as Map<String, double>)[t.id];
      priceCtl.text = price == null ? '' : trimNum(price!);
      payments = results[1] as List<TenantPaymentRow>?;
      notes = results[2] as List<TenantNoteRow>?;
      activity = (results[3] as DevStats?)?.activity[t.id];
      controls = results[4] as ({bool maintenance, bool updateHold})?;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
      await _load();
    } catch (e) {
      if (mounted) showAppSnack(context, userMessage(e, 'تعذّر'), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setControl(Map<String, dynamic> fields) async {
    final store = StoreScope.of(context);
    await _run(() async {
      final error = await store.tenantApi.update(t.id, fields);
      if (error != null) throw StoreException(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = payments ?? const <TenantPaymentRow>[];
    final total = list.fold<double>(0, (n, r) => n + r.amount);
    final last = list.firstOrNull;
    final a = activity;
    final c = controls;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 0, title: Text(t.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 24),
          children: [
            if (a != null) ...[
              Row(children: [
                _stat('سندات', '${a['payments'] ?? 0}'),
                _stat('حضور', '${a['attendance'] ?? 0}'),
                _stat('علامات', '${a['evaluations'] ?? 0}'),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _stat('مصروفات', '${a['expenses'] ?? 0}'),
                _stat('إشعارات', '${a['push_sent'] ?? 0}', hint: '${a['push_devices'] ?? 0} جهاز'),
                _stat('آخر مزامنة', '${a['last_sync'] ?? '—'}'.split('T').first),
              ]),
            ],
            _title('التحكم'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: _box(),
              child: c == null
                  ? const Padding(padding: EdgeInsets.all(12), child: AppLoader(compact: true))
                  : Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('صيانة', style: TextStyle(fontSize: 13)),
                          value: c.maintenance,
                          onChanged: busy
                              ? null
                              : (v) async {
                                  if (v && !await confirmSheet(context, title: 'صيانة', message: 'إيقاف ${t.name}؟', confirmLabel: 'إيقاف')) return;
                                  await _setControl({'maintenance': v});
                                },
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('تجميد التحديث', style: TextStyle(fontSize: 13)),
                          value: c.updateHold,
                          onChanged: busy ? null : (v) => _setControl({'update_hold': v}),
                        ),
                      ],
                    ),
            ),
            _title('الاشتراك'),
            Row(children: [
              _stat('الاشتراك الشهري', price == null ? '—' : money(price!)),
              _stat('المدفوع', money(total), hint: '${list.length} دفعة'),
              _stat('آخر دفعة', last == null ? '—' : last.paidOn, hint: last == null ? null : money(last.amount)),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _box(),
              child: Row(
                children: [
                  const Text('السعر الشهري', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: priceCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(isDense: true, hintText: '₪'),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(() {
                              final v = double.tryParse(priceCtl.text.trim());
                              return DevAdmin.setPrice(t.id, priceCtl.text.trim().isEmpty ? null : (v == null || v < 0 ? 0 : v));
                            }),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ),
            _title('دفعة جديدة'),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _box(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true, labelText: 'المبلغ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(context: context, initialDate: paidOn, firstDate: DateTime(2020), lastDate: DateTime(DateTime.now().year + 2));
                          if (picked != null) setState(() => paidOn = picked);
                        },
                        child: Text(isoDate(paidOn)),
                      ),
                    ],
                  ),
                  TextField(controller: note, maxLength: 300, decoration: const InputDecoration(isDense: true, labelText: 'ملاحظة', counterText: '')),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'إضافة',
                    expand: true,
                    onPressed: busy || !((double.tryParse(amount.text.trim()) ?? 0) > 0)
                        ? null
                        : () => _run(() async {
                              await DevAdmin.addPayment(
                                tenantId: t.id,
                                amount: double.parse(amount.text.trim()),
                                paidOn: isoDate(paidOn),
                                note: note.text.trim().isEmpty ? null : note.text.trim(),
                              );
                              amount.clear();
                              note.clear();
                            }),
                  ),
                ],
              ),
            ),
            _title('الدفعات', count: list.length),
            if (payments == null)
              const AppLoader(compact: true)
            else if (list.isEmpty)
              const EmptyState(message: 'لا دفعات')
            else
              Container(
                decoration: _box(),
                child: Column(
                  children: [
                    for (final r in list)
                      ListTile(
                        dense: true,
                        title: Text(money(r.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text([r.paidOn, if ((r.note ?? '').isNotEmpty) r.note!].join(' · ')),
                        trailing: TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!await confirmSheet(context, title: 'حذف الدفعة', message: 'حذف الدفعة؟', confirmLabel: 'حذف')) return;
                                  await _run(() => DevAdmin.deletePayment(r.id));
                                },
                          child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
                        ),
                      ),
                  ],
                ),
              ),
            _title('الملاحظات', count: notes?.length),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _box(),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: noteBody,
                      maxLength: 2000,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(isDense: true, hintText: 'ملاحظة', counterText: ''),
                    ),
                  ),
                  TextButton(
                    onPressed: busy || noteBody.text.trim().isEmpty
                        ? null
                        : () => _run(() async {
                              await DevAdmin.addNote(t.id, noteBody.text.trim());
                              noteBody.clear();
                            }),
                    child: const Text('إضافة'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (notes == null)
              const AppLoader(compact: true)
            else if (notes!.isEmpty)
              const EmptyState(message: 'لا ملاحظات')
            else
              Container(
                decoration: _box(),
                child: Column(
                  children: [
                    for (final n in notes!)
                      ListTile(
                        dense: true,
                        title: Text(n.body, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        subtitle: Text(_time(n.createdAt), textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                        trailing: TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!await confirmSheet(context, title: 'حذف الملاحظة', message: 'حذف الملاحظة؟', confirmLabel: 'حذف')) return;
                                  await _run(() => DevAdmin.deleteNote(n.id));
                                },
                          child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
