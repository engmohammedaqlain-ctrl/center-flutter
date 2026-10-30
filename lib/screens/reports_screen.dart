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

/// الفهرس مجموعاً ومرتباً بكثرة الاستعمال، بالصلاحيات نفسها في الويب.
List<({String title, List<ReportItem> items})> reportGroups(AppStore store) {
  final out = <({String title, List<ReportItem> items})>[];
  if (store.isFeatureOn('attendance') && store.can('attendance')) {
    out.add((title: 'الحضور', items: const [
      ReportItem('absence', 'الغياب', 'حضور الشعب والطلاب في شهر أو فترة'),
      ReportItem('alerts', 'إنذارات الغياب', 'من بلغ حد الإنذار، وإرساله للأهل'),
    ]));
  }
  if (store.isFeatureOn('evaluations') && store.can('evaluations')) {
    out.add((title: 'العلامات', items: const [
      ReportItem('results', 'النتائج', 'معدلات الشعب، والطلاب بترتيب وحدود'),
      ReportItem('completion', 'اكتمال الرصد', 'ما رصده كل معلم وما تأخر'),
      ReportItem('decline', 'التراجع', 'من نزلت علامته بين اختبارين'),
      ReportItem('analysis', 'تحليل المواد', 'النجاح والتقديرات لكل مادة'),
      ReportItem('compare', 'مقارنة الشعب', 'الشعب جنباً إلى جنب لكل مادة'),
    ]));
  }
  final people = <ReportItem>[
    if (store.can('students')) const ReportItem('students', 'قوائم الطلاب', 'بصفات وشروط: حالة صحية، غياب...'),
    if (store.can('finance')) const ReportItem('arrears', 'المتأخرات', 'من عليه مستحقات حتى اليوم'),
    if (store.can('students')) const ReportItem('data', 'بيانات ناقصة أو خاطئة', 'هوية أو جوال أو تاريخ ميلاد ناقص أو بصيغة خاطئة'),
  ];
  if (people.isNotEmpty) out.add((title: 'الطلاب والمالية', items: people));
  // نادر ومراجعة لا عمل يومي: آخراً وللمدير وحده
  if (store.isAdminUser) {
    out.add((title: 'الإدارة', items: const [
      ReportItem('usage', 'استخدام النظام', 'من يدخل من الأهالي والطلاب والمعلمين'),
      ReportItem('edits', 'سجل التعديلات', 'من عدّل ماذا ومتى'),
    ]));
  }
  return out;
}

/// يفتح تقريراً بعينه (من الرئيسية أو من رابط داخل تقرير آخر).
Future<void> openReport(BuildContext context, String id) {
  final store = StoreScope.of(context);
  final item = reportGroups(store).expand((g) => g.items).where((i) => i.id == id).firstOrNull;
  if (item == null) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportPage(item: item)));
}

/// التقارير فهرس بأسئلة لا تبويبات متداخلة — `Reports.tsx`. كل سؤال سطر باسمه، ومجموع
/// بعناوين صغيرة باهتة فلا يُخلط العنوان بسطر يُنقر.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final groups = reportGroups(store);
    if (groups.isEmpty) return const NoonEmpty('لا تقارير متاحة لحسابك');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 12, 6, 6),
            child: Text(g.title, style: NoonText.style(11, weight: FontWeight.w600, color: AdminNoon.faint)),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < g.items.length; i++)
                  InkWell(
                    onTap: () => openReport(context, g.items[i].id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: AdminNoon.line))),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.items[i].label, style: NoonText.style(13.5, weight: FontWeight.w700)),
                              Text(g.items[i].hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: NoonText.style(11, color: AdminNoon.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_left_rounded, color: AdminNoon.faint),
                      ]),
                    ),
                  ),
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
  const ReportPage({super.key, required this.item});

  final ReportItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminNoon.paper,
      appBar: AppBar(titleSpacing: 0, title: Text(item.label)),
      body: Material(color: AdminNoon.paper, child: reportView(item.id)),
    );
  }
}
