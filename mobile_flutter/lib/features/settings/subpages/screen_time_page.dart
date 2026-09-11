import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class ScreenTimePage extends StatelessWidget {
  const ScreenTimePage({
    super.key,
    required this.minutesToday,
    required this.dailyLimit,
  });

  final int minutesToday;
  final int dailyLimit;

  @override
  Widget build(BuildContext context) {
    final remaining = (dailyLimit - minutesToday).clamp(0, dailyLimit);
    final ratio =
        dailyLimit > 0 ? (minutesToday / dailyLimit).clamp(0.0, 1.0) : 0.0;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Screen Time ⏳'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 12,
                        backgroundColor: Colors.white10,
                        color: ratio >= 0.9
                            ? AppColors.error
                            : ratio >= 0.75
                                ? Colors.amber
                                : AppColors.kidsAccent,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$minutesToday',
                            style: AppTypography.displayLarge
                                .copyWith(fontWeight: FontWeight.bold)),
                        Text('minutes used',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textMutedDark)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricCol('Daily Allowance', '$dailyLimit min'),
                    _metricCol('Time Remaining', '$remaining min'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: AppColors.kidsAccent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Managed by Parent Mode',
                          style: AppTypography.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Your daily time limit is configured by your parent or guardian. When your time limit is reached, LittleNet pauses access until tomorrow so you can rest and enjoy offline activities.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMutedDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCol(String label, String value) {
    return Column(
      children: [
        Text(label,
            style:
                AppTypography.caption.copyWith(color: AppColors.textMutedDark)),
        const SizedBox(height: 4),
        Text(value,
            style: AppTypography.titleMedium
                .copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
