import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class SafetySettingsPage extends StatelessWidget {
  const SafetySettingsPage({super.key, required this.safetyLevel});

  final String safetyLevel;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Safety & AI Moderation'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.kidsAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.kidsAccent),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded,
                    color: AppColors.kidsAccent, size: 32),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current Safety Level: $safetyLevel',
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 2),
                      const Text(
                        'Set and managed by your parent to protect your online experience.',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('How Safety Works on LittleNet',
              style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _featureTile(
            icon: Icons.shield_outlined,
            title: 'Automatic Content Filter',
            desc:
                'Every photo, video, and text post is checked by LittleNet AI before being shared. Inappropriate or adult content is blocked instantly.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _featureTile(
            icon: Icons.privacy_tip_outlined,
            title: 'PII (Personal Info) Protection',
            desc:
                'Phone numbers, physical addresses, email addresses, and passwords cannot be shared in captions or comments to prevent accidental disclosure.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _featureTile(
            icon: Icons.family_restroom_outlined,
            title: 'Parent Approval Queue',
            desc:
                'Any content with uncertain safety is routed to your parent for approval before anyone else can see it.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _featureTile(
            icon: Icons.mic_off_outlined,
            title: 'Audio Protection',
            desc:
                'Audio and voice uploads are disabled across the app to prevent background acoustic exposure.',
          ),
        ],
      ),
    );
  }

  Widget _featureTile({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.kidsAccent, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                const SizedBox(height: 4),
                Text(desc,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textMutedDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
