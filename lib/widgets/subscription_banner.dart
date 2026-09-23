import 'package:flutter/material.dart';

import '../data/store.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';

/// شريط تنبيه الاشتراك — المقابل لـ `SubscriptionStatusBanner`.
///
/// يظهر عند إيقاف المنشأة أو انتهاء مدة الاشتراك دون طرد المستخدم من الشاشة.
/// زر الإعدادات كالويب (`#/settings`).
class SubscriptionStatusBanner extends StatelessWidget {
  const SubscriptionStatusBanner({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    if (store.isMasterAdmin) return const SizedBox.shrink();
    final tenant = store.currentTenant;
    if (tenant == null) return const SizedBox.shrink();
    final problem = store.subscriptionProblem(tenant);
    if (problem == null) return const SizedBox.shrink();

    final label = 'تنبيه الاشتراك (${tenant.name}): $problem';
    return Material(
      color: const Color(0xFFB45309),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => Material(
                        color: AppColors.bg,
                        child: const SettingsScreen(),
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                child: const Text('الإعدادات'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
