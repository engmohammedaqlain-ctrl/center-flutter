import '../widgets/empty_note.dart';
import 'package:flutter/material.dart';

import '../data/account_statement.dart';
import '../data/doc_export.dart';
import '../data/payment_methods.dart';
import '../data/store.dart';
import '../data/xlsx_styled.dart';
import '../data/teacher_salary.dart';
import '../data/year_closing.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/admin_ui.dart';
import '../widgets/widgets.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// كشف الحسابات — `AccountsStatement`: لكل شخص حساباته، وسطر لكل شهر بداخل وطالع كل حساب
/// ورصيد آخر الشهر. التحويل بين حسابين يظهر طالعاً من الأول وداخلاً في الثاني.
Future<void> showAccountsStatementSheet(BuildContext context, AppStore store, AcademicYear year) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    builder: (_) => _StatementSheet(store: store, year: year),
  );
}

class _StatementSheet extends StatefulWidget {
  const _StatementSheet({required this.store, required this.year});

  final AppStore store;
  final AcademicYear year;

  @override
  State<_StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends State<_StatementSheet> {
  String? picked;
  late final _Data? data = _build();

  _Data? _build() {
    final store = widget.store;
    final year = widget.year;
    final span = yearSpans(store.academicYears).where((s) => s.year.id == year.id).firstOrNull;
    if (span == null || year.startsOn.length < 7) return null;
    final book = store.yearBook[year.id];
    final endsIn = year.endsOn.length >= 7 ? year.endsOn.substring(0, 7) : year.startsOn.substring(0, 7);
    // السنة تمتد حتى بداية التي بعدها (الصيف لها)، والأخيرة حتى نهايتها
    var beforeNext = '';
    if (span.until != '9999-12-31') {
      final until = DateTime.parse(span.until).subtract(const Duration(days: 1));
      beforeNext = isoDate(until).substring(0, 7);
    }
    final months = statementMonthsBetween(
      year.startsOn.substring(0, 7),
      beforeNext.compareTo(endsIn) > 0 ? beforeNext : endsIn,
    );
    final statements = accountStatement(
      payments: store.payments,
      expenses: store.expenses,
      payouts: store.teacherPayouts,
      opening: book?.opening ?? const {},
      from: span.from,
      until: span.until,
      months: months,
      methods: [for (final m in store.paymentMethods) m.id],
    );
    final methods = store.paymentMethods.where((m) => m.enabled || (statements[m.id]?.active ?? false)).toList();
    return _Data(statements: statements, months: months, owners: statementOwners(methods));
  }

  Future<void> _export(String label, List<({String name, AccountStatement statement})> accounts, List<String> months) {
    double balanceAt(int i) => accounts.fold<double>(
          0,
          (n, a) => n + (i < 0 ? a.statement.opening : a.statement.months[i].balance),
        );
    String sum(double Function(AccountStatement) pick) =>
        trimNum(accounts.fold<double>(0, (n, a) => n + pick(a.statement)));
    final rows = <List<String>>[
      ['افتتاحي', for (final _ in accounts) ...['', ''], trimNum(balanceAt(-1))],
      for (var i = 0; i < months.length; i++)
        [
          monthLabel(months[i]),
          for (final a in accounts) ...[trimNum(a.statement.months[i].inflow), trimNum(a.statement.months[i].outflow)],
          trimNum(balanceAt(i)),
        ],
      [
        'المجموع',
        for (final a in accounts) ...[trimNum(a.statement.totalIn), trimNum(a.statement.totalOut)],
        sum((s) => s.closing),
      ],
    ];
    // كشف منسّق كالويب (`accountsSheet`): عنوان وتفاصيل ورأس ملوّن، بالعرض
    final sheet = StyledSheet(
      title: 'كشف حسابات $label',
      details: [widget.year.label],
      headers: ['الشهر', for (final a in accounts) ...['${a.name} داخل', '${a.name} طالع'], 'الرصيد'],
      rows: rows,
      landscape: true,
      nameColumn: -1,
    );
    final bytes = styledXlsx([sheet], school: widget.store.institutionName, logo: widget.store.institutionLogo);
    return DocExport.download(context, bytes, 'حسابات_${label}_${widget.year.label}.xlsx', mime: _xlsxMime);
  }

  Widget _account(String name, AccountStatement s) {
    Widget cell(String text, {bool bold = false, Color? color}) => Expanded(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading)),
        const SizedBox(height: 4),
        Row(children: [cell('الشهر', bold: true), cell('داخل', bold: true), cell('طالع', bold: true), cell('الرصيد', bold: true)]),
        const Divider(height: 8),
        Row(children: [cell('افتتاحي'), cell(''), cell(''), cell(trimNum(s.opening), bold: true)]),
        for (final m in s.months)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                cell(monthLabel(m.month)),
                cell(m.inflow == 0 ? '—' : trimNum(m.inflow), color: AppColors.success),
                cell(m.outflow == 0 ? '—' : trimNum(m.outflow), color: AppColors.danger),
                cell(trimNum(m.balance), bold: true, color: m.balance < 0 ? AppColors.danger : null),
              ],
            ),
          ),
        const Divider(height: 8),
        Row(
          children: [
            cell('المجموع', bold: true),
            cell(trimNum(s.totalIn), bold: true),
            cell(trimNum(s.totalOut), bold: true),
            cell(trimNum(s.closing), bold: true),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final owners = d?.owners ?? const [];
    final group = owners.where((g) => g.owner == picked).firstOrNull ?? owners.firstOrNull;
    final accounts = group == null
        ? const <({String name, AccountStatement statement})>[]
        : [
            for (final a in group.accounts)
              if (d!.statements[a.id] case final s?)
                if (s.active || group.accounts.length == 1) (name: a.name, statement: s),
          ];
    return NoonSheetFrame(
      title: 'كشف الحسابات · ${widget.year.label}',
      footer: [
        if (accounts.isNotEmpty && group != null)
          NoonButton(
            label: 'Excel',
            icon: Icons.table_chart_outlined,
            onPressed: () => _export(group.label, accounts, d!.months),
          ),
      ],
      children: [
        if (d == null || owners.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('لا حسابات', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          )
        else ...[
          DropdownButton<String>(
            isExpanded: true,
            value: group?.owner,
            items: [for (final g in owners) DropdownMenuItem(value: g.owner, child: Text(g.label))],
            onChanged: (v) => setState(() => picked = v),
          ),
          if (accounts.isEmpty)
            EmptyNote('لا حركة في حسابات هذا الصاحب')
          else
            for (final a in accounts) _account(a.name, a.statement),
        ],
      ],
    );
  }
}

class _Data {
  const _Data({required this.statements, required this.months, required this.owners});

  final Map<String, AccountStatement> statements;
  final List<String> months;
  final List<({String owner, String label, List<PaymentMethodItem> accounts})> owners;
}
