import 'package:flutter/material.dart';

import '../data/store.dart';
import '../widgets/admin_tokens.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';
import 'report_views.dart';

/// تقرير واحد بسؤال واحد — `ReportItem` في Reports.tsx.
class ReportItem {
  const ReportItem(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

/// الفهرس قصير كالويب: سطر لكل تقرير، وما هو عرض لنفس البيانات (الإنذارات، المقارنة،
/// التراجع، الأوائل) داخل تقريره. مرتب بكثرة الاستعمال، بالصلاحيات نفسها في الويب.
List<({String title, List<ReportItem> items})> reportGroups(AppStore store) {
  final out = <({String title, List<ReportItem> items})>[];
  if (store.isFeatureOn('attendance') && store.can('attendance')) {
    out.add((title: 'الحضور', items: const [
      ReportItem('absence', 'الغياب', 'حضور الشعب والطلاب، والإنذارات'),
    ]));
  }
  if (store.isFeatureOn('evaluations') && store.can('evaluations')) {
    out.add((title: 'العلامات', items: const [
      ReportItem('results', 'النتائج', 'معدلات الشعب، والطلاب والأوائل'),
      ReportItem('analysis', 'التحليل', 'المواد، ومقارنة الشعب، والتراجع'),
      ReportItem('completion', 'الرصد', 'ما رصده كل معلم وما تأخر'),
    ]));
  }
  if (store.can('students')) {
    out.add((title: 'الطلاب', items: const [
      ReportItem('students', 'الاستعلام', 'بصفات وشروط: حالة صحية، غياب...'),
      ReportItem('data', 'البيانات الناقصة', 'هوية أو جوال أو تاريخ ميلاد ناقص أو بصيغة خاطئة'),
    ]));
  }
  if (store.can('finance')) {
    out.add((title: 'المالية', items: const [ReportItem('arrears', 'التحصيل', 'المطلوب والمدفوع والمتأخر لكل شعبة، والمدينون')]));
  }
  // نادر ومراجعة لا عمل يومي: آخراً وللمدير وحده
  if (store.isAdminUser) {
    out.add((title: 'الإدارة', items: const [
      ReportItem('staff', 'دوام الموظفين', 'حضور وغياب وتأخير وإجازات كل موظف في الشهر'),
      ReportItem('usage', 'الاستخدام', 'من يدخل من الأهالي والطلاب والمعلمين'),
      ReportItem('edits', 'السجل', 'من عدّل أو ألغى أو خصم، ومتى'),
    ]));
  }
  return out;
}

/// عروض داخل تقرير: رابط إليها يفتح تقريره عليها.
const _inside = {'alerts': 'absence', 'compare': 'analysis', 'decline': 'analysis'};

/// يفتح تقريراً بعينه (من الرئيسية أو من رابط داخل تقرير آخر).
Future<void> openReport(BuildContext context, String id) {
  final store = StoreScope.of(context);
  final item = reportGroups(store).expand((g) => g.items).where((i) => i.id == (_inside[id] ?? id)).firstOrNull;
  if (item == null) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportPage(item: item, view: id)));
}

const _reportIcons = <String, IconData>{
  'absence': Icons.event_busy_outlined,
  'results': Icons.workspace_premium_outlined,
  'analysis': Icons.insights_outlined,
  'completion': Icons.fact_check_outlined,
  'students': Icons.person_search_outlined,
  'data': Icons.rule_folder_outlined,
  'arrears': Icons.account_balance_wallet_outlined,
  'staff': Icons.badge_outlined,
  'usage': Icons.devices_outlined,
  'edits': Icons.history_rounded,
};

/// التقارير فهرس بأسئلة لا تبويبات متداخلة — `Reports.tsx`. كل مجموعة لوحة بعنوانها، وكل تقرير سطر
/// بأيقونته واسمه وتحته سؤاله الذي يجيب عنه، فيُعرف التقرير من أول نظرة.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final groups = reportGroups(store);
    if (groups.isEmpty) return const NoonEmpty('لا تقارير متاحة لحسابك');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 16, 4, 8),
            child: Text(g.title, style: NoonText.style(12.5, weight: FontWeight.w700, color: AdminNoon.muted)),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: noonPanel(),
            child: Column(
              children: [
                for (var i = 0; i < g.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AdminNoon.line),
                  InkWell(
                    onTap: () => openReport(context, g.items[i].id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: AdminNoon.mist, borderRadius: BorderRadius.circular(12)),
                          child: Icon(_reportIcons[g.items[i].id] ?? Icons.description_outlined, size: 21, color: AdminNoon.ink),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(g.items[i].label, style: NoonText.style(14.5, weight: FontWeight.w700)),
                              if (g.items[i].hint.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(g.items[i].hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: NoonText.style(11.5, color: AdminNoon.muted, height: 1.35)),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: AdminNoon.faint),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// صفحة تقرير: عنوانه، والتقرير نفسه.
class ReportPage extends StatelessWidget {
  const ReportPage({super.key, required this.item, this.view});

  final ReportItem item;

  /// عرض بعينه داخل التقرير («alerts» داخل الغياب مثلاً).
  final String? view;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminNoon.paper,
      appBar: AppBar(titleSpacing: 0, title: Text(item.label)),
      body: Material(color: AdminNoon.paper, child: reportView(view ?? item.id)),
    );
  }
}
