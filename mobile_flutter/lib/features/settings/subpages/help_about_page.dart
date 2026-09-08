import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class HelpAboutPage extends StatelessWidget {
  const HelpAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Help & About LittleNet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.kidsAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stars_rounded,
                      size: 48, color: AppColors.kidsAccent),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('LittleNet', style: AppTypography.displayMedium),
                const Text('Safe Social Learning for Young Explorers',
                    style: AppTypography.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Version 2.0.0 (Native Release)',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMutedDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _card(
            'Our Mission',
            'LittleNet is an educational, safe social network crafted for children aged 4 to 18. It combines creative expression with real-time AI safety guardrails, parental oversight, and learning challenges.',
          ),
          const SizedBox(height: AppSpacing.md),
          _card(
            'Child Safety Commitments',
            '• Pre-upload AI visual & text inspection\n'
                '• Strict PII (personal info) redaction\n'
                '• Parent verification & approval queue\n'
                '• Curated educational feed & brain quizzes\n'
                '• No stranger messaging & no tracking ads\n'
                '• Daily screen time controls',
          ),
          const SizedBox(height: AppSpacing.md),
          _card(
            'Need Help or Assistance?',
            'If you ever see content that makes you feel uncomfortable or unsafe, report it immediately to your parent or guardian through the Safety Center.',
          ),
        ],
      ),
    );
  }

  Widget _card(String title, String content) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.titleMedium
                  .copyWith(color: AppColors.kidsAccent)),
          const SizedBox(height: 8),
          Text(content,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textMutedDark, height: 1.4)),
        ],
      ),
    );
  }
}
