import 'package:flutter/material.dart';

import '../data/dev_health.dart';
import '../data/store.dart';
import '../data/supabase.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';

/// متابعة المدارس — للمطور وحده. المقابل لصفحة «المتابعة» في لوحة الويب.
class DeveloperHealthScreen extends StatefulWidget {
  const DeveloperHealthScreen({super.key, required this.token});

  final String token;

  @override
  State<DeveloperHealthScreen> createState() => _DeveloperHealthScreenState();
}

class _DeveloperHealthScreenState extends State<DeveloperHealthScreen> {
  List<SchoolHealth>? rows;
  List<ErrorRow>? errors;
  bool loading = false, onlyAlerts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final names = {
        for (final t in StoreScope.of(context).tenants)
          if (t.active) t.id: t.name,
      };
      final res = await Future.wait<dynamic>([
        supabaseRpcAs('tenant_usage', const {}, token: widget.token),
        supabaseRpcAs('tenant_activity', const {}, token: widget.token).catchError((Object _) => null),
        loadErrorReports(widget.token),
      ]);
      if (!mounted) return;
      setState(() {
        rows = buildHealth(names, res[0] as List? ?? const [], res[1]);
        errors = res[2] as List<ErrorRow>?;
      });
    } catch (e) {
      debugPrint('dev health: $e');
      if (mounted && rows != null) showAppSnack(context, 'تعذّر التحديث', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = rows;
    final now = DateTime.now();
    final alerts = list?.where((r) => r.alert(now) != null).length ?? 0;
    final shown = list == null
        ? const <SchoolHealth>[]
        : (onlyAlerts ? list.where((r) => r.alert(now) != null).toList() : list);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('المتابعة'),
        titleTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            if (list == null)
              loading
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: AppLoader())
                  : const EmptyState(message: 'تعذّر التحميل', icon: Icons.cloud_off_outlined)
            else ...[
              Tooltip(
                message: healthRule,
                triggerMode: TooltipTriggerMode.tap,
                child: StatRow(children: [
                  StatCard(label: 'المدارس', value: '${list.length}', color: AppColors.heading, compact: true),
                  StatCard(
                    label: 'تنبيه',
                    value: '$alerts',
                    color: alerts > 0 ? AppColors.danger : AppColors.success,
                    compact: true,
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilterChip(
                    label: const Text('الكل'), selected: !onlyAlerts, onSelected: (_) => setState(() => onlyAlerts = false)),
                const SizedBox(width: 6),
                FilterChip(
                    label: Text('تنبيه $alerts'), selected: onlyAlerts, onSelected: (_) => setState(() => onlyAlerts = true)),
              ]),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                EmptyState(message: onlyAlerts ? 'لا تنبيهات' : 'لا مدارس')
              else
                for (final s in shown) Padding(padding: const EdgeInsets.only(bottom: 8), child: _SchoolRow(school: s)),
              if (errors != null) ...[
                const SizedBox(height: 8),
                Text('الأخطاء، 7 أيام', style: AppText.cardTitle),
                const SizedBox(height: 6),
                if (errors!.isEmpty) const EmptyState(message: 'لا أخطاء') else _errors(errors!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _errors(List<ErrorRow> all) {
    final by = <String, List<ErrorRow>>{};
    for (final e in all) {
      (by[e.tenantName.isEmpty ? 'بلا مدرسة' : e.tenantName] ??= []).add(e);
    }
    int count(String k) => by[k]!.fold(0, (n, e) => n + e.count);
    final keys = by.keys.toList()..sort((a, b) => count(b).compareTo(count(a)));
    return Column(children: [
      for (final k in keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$k  ${count(k)}', style: AppText.cardTitle),
              for (final e in by[k]!)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(
                      [e.role, e.platform, e.version, e.route, '${e.count}x'].where((x) => x.isNotEmpty).join('  |  '),
                      style: AppText.muted.copyWith(fontSize: 11),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
    ]);
  }
}

class _SchoolRow extends StatelessWidget {
  const _SchoolRow({required this.school});

  final SchoolHealth school;

  String _ago(DateTime? d) {
    if (d == null) return '—';
    final n = DateTime.now().difference(d).inDays;
    return n <= 0 ? 'اليوم' : (n == 1 ? 'أمس' : 'قبل $n يوم');
  }

  @override
  Widget build(BuildContext context) {
    final s = school;
    final alert = s.alert(DateTime.now());
    return AppCard(
      padding: const EdgeInsets.all(12),
      color: alert != null ? AppColors.dangerSoft : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle)),
          Tooltip(
            message: healthRule,
            triggerMode: TooltipTriggerMode.tap,
            child: alert == null
                ? StatusChip.success('سليم')
                : StatusChip.danger(alert == HealthAlert.silent ? 'متوقف' : 'هبوط'),
          ),
        ]),
        const SizedBox(height: 8),
        StatRow(children: [
          StatCard(label: 'الطلاب', value: '${s.totalStudents}', color: AppColors.heading, compact: true),
          for (final g in healthGroups)
            Tooltip(
              message: 'نشط 30 يوماً من ${s.total(g.$2)}، منهم ${s.d7(g.$2)} آخر 7 أيام',
              triggerMode: TooltipTriggerMode.tap,
              child: StatCard(label: g.$1, value: '${s.d30(g.$2)}', color: AppColors.accent, compact: true),
            ),
        ]),
        const SizedBox(height: 6),
        Text('آخر نشاط: ${_ago(s.lastActivity)}', style: AppText.muted.copyWith(fontSize: 11)),
      ]),
    );
  }
}

void openDeveloperHealth(BuildContext context) {
  final token = SupabaseAuth.developerAccess;
  if (token == null || token.isEmpty) {
    showAppSnack(context, 'سجّل دخول المطور أولاً', error: true);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeveloperHealthScreen(token: token)));
}
