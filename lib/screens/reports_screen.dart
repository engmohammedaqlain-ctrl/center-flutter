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
          if (g.items.length > 1)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 12, 6, 6),
              child: Text(g.title, style: NoonText.style(11, weight: FontWeight.w600, color: AdminNoon.faint)),
            )
          else
            const SizedBox(height: 12),
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
                        Expanded(child: Text(g.items[i].label, style: NoonText.style(13.5, weight: FontWeight.w700))),
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
