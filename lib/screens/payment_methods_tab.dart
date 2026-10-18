import 'package:flutter/material.dart';

import '../data/payment_methods.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_count.dart';
import '../widgets/panels.dart';
import '../widgets/thumb_action.dart';
import '../widgets/widgets.dart';

/// وسائل الدفع — المقابل لـ `features/settings/PaymentMethodsSettings.tsx`.
///
/// الوسيلة الأساسية تُعطَّل ويُعدَّل مسمّاها ولا تُحذف: سنداتٌ قديمة تشير إليها.
/// تفعيل/إيقاف وتسمية وحذف الوسائل المخصصة، ورقم كل وسيلة غير نقدية وظهورها
/// لولي الأمر في البوابة.
class PaymentMethodsTab extends StatelessWidget {
  const PaymentMethodsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final methods = store.paymentMethods;
    final active = methods.where((m) => m.enabled).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, thumbActionClearance),
      children: [
        StatRow(
          children: [
            StatCard(label: 'وسائل الدفع', value: '${methods.length}', color: AppColors.heading),
            StatCard(label: 'المفعّلة', value: '$active', color: AppColors.success),
            StatCard(
              label: 'مخصصة',
              value: '${methods.where((m) => !m.isDefault).length}',
              color: AppColors.heading,
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final m in methods)
          _MethodCard(
            method: m,
            onToggle: () => _save(
              context,
              store,
              [for (final x in methods) x.id == m.id ? x.copyWith(enabled: !x.enabled) : x],
              m.enabled ? 'تم إيقاف «${m.name}»' : 'تم تفعيل «${m.name}»',
            ),
            onTogglePortal: m.type == 'cash'
                ? null
                : () => _save(
                      context,
                      store,
                      [for (final x in methods) x.id == m.id ? x.copyWith(showInPortal: !x.showInPortal) : x],
                      m.showInPortal ? '«${m.name}» مخفية عن ولي الأمر' : '«${m.name}» تظهر لولي الأمر',
                    ),
            onRename: () => _edit(context, store, methods, m),
            onDelete: m.isDefault ? null : () => _delete(context, store, methods, m),
          ),
        const SizedBox(height: 4),
        GhostButton(
          label: 'استعادة الوسائل الافتراضية',
          icon: Icons.restart_alt,
          onPressed: () => _restore(context, store),
        ),
      ],
    );
  }

  static Future<void> _save(
    BuildContext context,
    AppStore store,
    List<PaymentMethodItem> methods,
    String message,
  ) async {
    try {
      await store.savePaymentMethods(methods);
      if (context.mounted) showAppSnack(context, message);
    } on StoreException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, error: true);
    }
  }

  static Future<void> _edit(
    BuildContext context,
    AppStore store,
    List<PaymentMethodItem> methods,
    PaymentMethodItem m,
  ) async {
    final result = await _methodSheet(
      context,
      title: 'تعديل وسيلة الدفع',
      name: m.name,
      number: m.accountNumber,
      type: m.type,
    );
    if (result == null || !context.mounted) return;
    await _save(
      context,
      store,
      [
        for (final x in methods)
          // رقم فارغ يمسح القديم — يُرفع null فلا يبقى في السحابة
          x.id == m.id ? x.copyWith(name: result.name, accountNumber: m.type == 'cash' ? '' : result.number) : x,
      ],
      'تم تحديث وسيلة الدفع',
    );
  }

  static Future<void> _delete(
    BuildContext context,
    AppStore store,
    List<PaymentMethodItem> methods,
    PaymentMethodItem m,
  ) async {
    final ok = await confirmSheet(
      context,
      title: 'حذف وسيلة الدفع',
      message: 'هل تريد حذف وسيلة «${m.name}»؟ السندات المسجَّلة بها تبقى كما هي.',
      confirmLabel: 'حذف',
    );
    if (!ok || !context.mounted) return;
    await _save(context, store, methods.where((x) => x.id != m.id).toList(), 'تم حذف وسيلة الدفع المخصصة');
  }

  static Future<void> _restore(BuildContext context, AppStore store) async {
    final ok = await confirmSheet(
      context,
      title: 'استعادة الوسائل الافتراضية',
      message: 'سيُستبدل ما ضبطته بوسائل الدفع الأساسية في النظام. هل تريد المتابعة؟',
      confirmLabel: 'استعادة',
      confirmColor: AppColors.navy,
    );
    if (!ok || !context.mounted) return;
    await _save(context, store, defaultPaymentMethods, 'تمت استعادة وسائل الدفع الافتراضية');
  }
}

/// إضافة وسيلة دفع جديدة — زر الإبهام في تبويب وسائل الدفع.
Future<void> addPaymentMethod(BuildContext context) async {
  final store = StoreScope.of(context);
  final methods = store.paymentMethods;
  final added = await _methodSheet(context, title: 'وسيلة دفع جديدة', withType: true);
  if (added == null || !context.mounted) return;

  // معرّف بالوقت كما في النسخة المكتبية: لا يتصادم مع معرّفات الوسائل الأساسية
  final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

  await PaymentMethodsTab._save(
    context,
    store,
    [
      ...methods,
      PaymentMethodItem(
        id: id,
        name: added.name,
        type: added.type,
        accountNumber: added.type == 'cash' ? '' : added.number,
      ),
    ],
    'تمت إضافة وسيلة الدفع',
  );
}

/// اسم الوسيلة ورقمها — ومعهما نوعها عند الإضافة.
///
/// كانت تُعيد «الاسم النوع» نصاً واحداً يُقسَم على المسافة، فاسمٌ من كلمتين
/// («بنك القدس») يُقصّ إلى كلمته الأولى ويُقرأ الباقي نوعاً.
Future<({String name, String type, String number})?> _methodSheet(
  BuildContext context, {
  required String title,
  String name = '',
  String number = '',
  String type = 'bank',
  bool withType = false,
}) {
  final nameController = TextEditingController(text: name);
  final numberController = TextEditingController(text: number);
  var selectedType = type;
  String? nameError;

  return showModalBottomSheet<({String name, String type, String number})>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.credit_card, size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title, style: AppText.cardTitle)),
                    SquareIconButton(icon: Icons.close, onTap: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),
                const FieldLabel('اسم وسيلة الدفع', requiredField: true),
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(hintText: 'مثال: بنك القدس', errorText: nameError),
                  onChanged: (_) {
                    if (nameError != null) setSheet(() => nameError = null);
                  },
                ),
                if (withType) ...[
                  const SizedBox(height: 12),
                  const FieldLabel('النوع'),
                  AppDropdown<String>(
                    value: selectedType,
                    items: [
                      for (final e in paymentMethodTypes.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setSheet(() => selectedType = v ?? 'other'),
                  ),
                ],
                // الرقم يظهر لولي الأمر حين يسدّد من البوابة — لا رقم للنقد
                if (selectedType != 'cash') ...[
                  const SizedBox(height: 12),
                  const FieldLabel('الرقم'),
                  TextField(
                    controller: numberController,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(hintText: 'رقم الحساب أو المحفظة'),
                  ),
                ],
                const SizedBox(height: 16),
                ActionButtons(
                  primary: PrimaryButton(
                    label: 'حفظ',
                    icon: Icons.check,
                    height: 40,
                    onPressed: () {
                      final value = nameController.text.trim();
                      if (value.isEmpty) {
                        setSheet(() => nameError = 'يرجى إدخال اسم وسيلة الدفع');
                        showAppSnack(ctx, 'يرجى إدخال اسم وسيلة الدفع', error: true);
                        return;
                      }
                      Navigator.pop(ctx, (name: value, type: selectedType, number: numberController.text.trim()));
                    },
                  ),
                  secondary: GhostButton(label: 'إلغاء', onPressed: () => Navigator.pop(ctx)),
                )
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.onToggle,
    required this.onTogglePortal,
    required this.onRename,
    required this.onDelete,
  });

  final PaymentMethodItem method;
  final VoidCallback onToggle;

  /// إظهارها لولي الأمر في البوابة أو إخفاؤها — لا للنقد.
  final VoidCallback? onTogglePortal;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final on = method.enabled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
        child: Row(
          children: [
            PressableScale(
              onTap: onToggle,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Corner.box),
                  color: on ? const Color(0xFFF0FDF4) : const Color(0xFFF1F5F9),
                  border: Border.all(color: on ? AppColors.successBorder : AppColors.line),
                ),
                child: Icon(
                  Icons.power_settings_new,
                  size: 15,
                  color: on ? AppColors.success : AppColors.faint,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    method.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: on ? AppColors.heading : AppColors.muted,
                      decoration: on ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  if (method.accountNumber.isNotEmpty)
                    Text(
                      method.accountNumber,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontFamily: 'monospace'),
                    )
                  // ولي الأمر يراها في البوابة ولا يعرف إلى أين يحوّل
                  else if (method.type != 'cash' && method.showInPortal)
                    const Text('بلا رقم', style: TextStyle(color: Color(0xFFB45309), fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      method.typeLabel,
                      if (method.isDefault) 'أساسية',
                      if (!on) 'معطّلة',
                      if (method.type != 'cash' && !method.showInPortal) 'مخفية عن البوابة',
                    ].join('  ·  '),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (onTogglePortal != null) ...[
              Tooltip(
                message: method.showInPortal ? 'تظهر لولي الأمر — اضغط للإخفاء' : 'مخفية عن ولي الأمر — اضغط للإظهار',
                child: SquareIconButton(
                  icon: method.showInPortal ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: method.showInPortal ? AppColors.navy : AppColors.faint,
                  onTap: onTogglePortal!,
                ),
              ),
              const SizedBox(width: 4),
            ],
            SquareIconButton(icon: Icons.edit_outlined, onTap: onRename),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              SquareIconButton(icon: Icons.delete_outline, color: AppColors.danger, onTap: onDelete!),
            ],
          ],
        ),
      ),
    );
  }
}
