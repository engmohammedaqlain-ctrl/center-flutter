import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

/// سطر مستحق/له/خالص + مجدول — مطابق لـ `DueStatus` في الويب.
enum DueStatusKind { clear, due, credit }

class DueStatus extends StatelessWidget {
  const DueStatus({
    super.key,
    required this.kind,
    this.amount = 0,
    this.scheduled = 0,
    this.clearLabel = 'خالص',
    this.compact = false,
    this.endAligned = true,
  });

  final DueStatusKind kind;
  final double amount;
  final double scheduled;
  final String clearLabel;
  final bool compact;
  final bool endAligned;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      DueStatusKind.due => ('مستحق', AppColors.danger),
      DueStatusKind.credit => ('له', AppColors.heading),
      DueStatusKind.clear => (clearLabel, AppColors.success),
    };
    final showAmount = kind != DueStatusKind.clear || clearLabel != 'لا مستحق';

    return Column(
      crossAxisAlignment: endAligned ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11 : 12,
              color: color,
            ),
            children: [
              TextSpan(text: label),
              if (showAmount) ...[
                const TextSpan(text: ' '),
                TextSpan(text: money(kind == DueStatusKind.clear ? 0 : amount)),
              ],
            ],
          ),
          textDirection: TextDirection.rtl,
        ),
        if (scheduled > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  color: AppColors.muted,
                ),
                children: [
                  const TextSpan(text: 'مجدول '),
                  TextSpan(text: money(scheduled)),
                ],
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
      ],
    );
  }
}
