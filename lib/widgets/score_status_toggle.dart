import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

/// «غائب» و«معفى» بدل العلامة: اللمسة تضع الحالة، والثانية تزيلها — `StatusToggle`.
class ScoreStatusToggle extends StatelessWidget {
  const ScoreStatusToggle({super.key, required this.status, required this.onStatus});

  /// الحالة الحالية؛ الفارغ علامة عادية.
  final String status;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in scoreStatusLabels.entries) ...[
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onStatus(status == entry.key ? '' : entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: status == entry.key
                    ? (entry.key == 'absent' ? AppColors.danger : AppColors.heading)
                    : Colors.white,
                border: Border.all(color: status == entry.key ? Colors.transparent : AppColors.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: status == entry.key ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          ),
          if (entry.key != scoreStatusLabels.keys.last) const SizedBox(width: 4),
        ],
      ],
    );
  }
}
