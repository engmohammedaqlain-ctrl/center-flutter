import 'package:flutter/material.dart';

import '../data/app_installs.dart';
import '../data/supabase.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/widgets.dart';

/// الأجهزة والإصدارات لكل مدرسة — للمطور وحده (`app_installs_overview`).
///
/// [token] جلسة المطور: جلسته إن دخل من لوحته، أو ما تحقق به في إعدادات المطور.
class AppInstallsScreen extends StatefulWidget {
  const AppInstallsScreen({super.key, required this.token});

  final String token;

  @override
  State<AppInstallsScreen> createState() => _AppInstallsScreenState();
}

const _channelNames = {'school': 'خاصة', 'general': 'عامة', 'play': 'المتجر'};
const _channelTips = {'school': 'نسخة المدرسة من GitHub', 'general': 'النسخة العامة', 'play': 'Google Play'};

class _AppInstallsScreenState extends State<AppInstallsScreen> {
  List<SchoolInstalls>? schools;
  String latest = '';
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await loadInstallsOverview(widget.token);
      if (!mounted) return;
      setState(() {
        schools = data.schools;
        latest = data.latest;
      });
    } catch (e) {
      debugPrint('app installs overview: $e');
      if (mounted && schools != null) showAppSnack(context, 'تعذّر التحديث', error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = schools;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('الأجهزة'),
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
              _summary(list),
              const SizedBox(height: 10),
              if (list.isEmpty)
                const EmptyState(message: 'لا أجهزة بعد', icon: Icons.phone_android_outlined)
              else
                for (final s in list)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: _SchoolCard(school: s)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(List<SchoolInstalls> list) {
    var devices = 0, recent = 0, outdated = 0;
    for (final s in list) {
      devices += s.devices;
      recent += s.recent;
      outdated += s.outdated;
    }
    return StatRow(children: [
      StatCard(label: 'الأجهزة', value: '$devices', color: AppColors.heading, compact: true),
      Tooltip(
        message: 'ظهرت آخر 30 يوماً',
        child: StatCard(label: 'نشطة', value: '$recent', color: AppColors.success, compact: true),
      ),
      StatCard(label: 'قديمة', value: '$outdated', color: outdated > 0 ? AppColors.danger : AppColors.muted, compact: true),
      StatCard(label: 'آخر إصدار', value: latest.isEmpty ? '—' : installLabel(latest, 0), color: AppColors.accent, compact: true),
    ]);
  }
}

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.school});

  final SchoolInstalls school;

  @override
  Widget build(BuildContext context) {
    final s = school;
    final github = s.githubDownloads;
    final downloads = s.pageDownloads + (github ?? 0);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle),
                    if (s.code.isNotEmpty && s.code != s.name) Text(s.code, style: AppText.muted.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              Text('${s.devices}', style: AppText.figure.copyWith(color: AppColors.heading)),
              const SizedBox(width: 4),
              Text('جهاز', style: AppText.muted.copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Fact(icon: Icons.schedule, text: _seen(s.lastSeen), tip: 'آخر ظهور'),
              _Fact(
                icon: Icons.download_outlined,
                text: '$downloads',
                tip: 'صفحة التحميل ${s.pageDownloads}\nGitHub ${github ?? '—'}',
              ),
              if (s.outdated > 0)
                Tooltip(message: 'على إصدار قديم', child: StatusChip.danger('قديم ${s.outdated}')),
            ],
          ),
          if (s.versions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in s.versions.entries)
                  s.oldVersions.contains(v.key)
                      ? StatusChip.danger('${v.key} · ${v.value}')
                      : StatusChip.success('${v.key} · ${v.value}'),
                for (final c in s.channels.entries)
                  Tooltip(
                    message: _channelTips[c.key] ?? c.key,
                    child: StatusChip.muted('${_channelNames[c.key] ?? c.key} ${c.value}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _seen(DateTime? at) {
    if (at == null) return '—';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days <= 0) return 'اليوم';
    if (days == 1) return 'أمس';
    if (days < 30) return 'قبل $days يوم';
    return '${at.year}/${at.month}/${at.day}';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, required this.tip});

  final IconData icon;
  final String text;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.faint),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// يفتح اللوحة بجلسة المطور، أو يقول إنها غير متاحة.
void openAppInstalls(BuildContext context) {
  final token = SupabaseAuth.developerAccess;
  if (token == null || token.isEmpty) {
    showAppSnack(context, 'سجّل دخول المطور أولاً', error: true);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AppInstallsScreen(token: token)));
}
