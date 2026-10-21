/// شاشة الصيانة وشريط الإعلانات — من لوحة المطور (`ClientConfig`).
library;

import 'package:flutter/material.dart';

import '../data/client_config.dart';
import '../theme/app_colors.dart';

const _sunSoft = Color(0xFFFEF1D2);
const _sunText = Color(0xFF7A5A12);

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = ClientConfig.instance;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(color: _sunSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.build_outlined, color: _sunText, size: 28),
                ),
                const SizedBox(height: 16),
                Text('صيانة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.heading)),
                const SizedBox(height: 6),
                Text(
                  config.message.isEmpty ? 'بنرجع بعد شوي' : config.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => config.refresh(force: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  child: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// إعلانات المطور فوق الشاشة، كلٌّ يُغلق وحده ولا يعود.
class AnnouncementsBanner extends StatelessWidget {
  const AnnouncementsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final config = ClientConfig.instance;
    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        final items = config.visible;
        if (items.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in items)
                Material(
                  color: a.warn ? _sunSoft : AppColors.amberSoft,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        Icon(Icons.campaign_outlined, size: 18, color: a.warn ? _sunText : AppColors.navy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.body,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: a.warn ? _sunText : AppColors.navy,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'إغلاق',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close, size: 18, color: a.warn ? _sunText : AppColors.navy),
                          onPressed: () => config.dismiss(a.id),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
