import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key, required this.controls});

  final Map<String, dynamic> controls;

  @override
  Widget build(BuildContext context) {
    final allowMessaging = controls['allow_messaging'] != false;
    final allowReels = controls['allow_reels'] != false;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Privacy & Visibility'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.kidsAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: AppColors.kidsAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: AppColors.kidsAccent, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Kids Safe Privacy',
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Your profile is private by default and protected under LittleNet child safety standards.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMutedDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _privacyTile(
            icon: Icons.search_off_rounded,
            title: 'Stranger Search Protection',
            subtitle:
                'Only users who know your username or share school connections can find your public profile.',
            status: 'ENFORCED',
          ),
          const SizedBox(height: AppSpacing.sm),
          _privacyTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Direct Messaging Privacy',
            subtitle: allowMessaging
                ? 'Only parent-approved friends can message you.'
                : 'Direct messaging has been turned off by your parent.',
            status: allowMessaging ? 'APPROVED ONLY' : 'DISABLED',
          ),
          const SizedBox(height: AppSpacing.sm),
          _privacyTile(
            icon: Icons.video_library_outlined,
            title: 'Reels & Video Interaction',
            subtitle: allowReels
                ? 'Reels are filtered by age-appropriateness and safety ratings.'
                : 'Reel browsing is disabled by your parent controls.',
            status: allowReels ? 'FILTERED' : 'DISABLED',
          ),
          const SizedBox(height: AppSpacing.sm),
          _privacyTile(
            icon: Icons.no_photography_outlined,
            title: 'Facial Biometrics Protection',
            subtitle:
                'Your facial data is stored as a one-way mathematical embedding and never shared.',
            status: 'PROTECTED',
          ),
        ],
      ),
    );
  }

  Widget _privacyTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String status,
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
                Text(subtitle,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMutedDark)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              status,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.kidsAccent),
            ),
          ),
        ],
      ),
    );
  }
}
