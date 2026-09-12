import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class ParentControlsPage extends StatelessWidget {
  const ParentControlsPage({super.key, required this.controls});

  final Map<String, dynamic> controls;

  @override
  Widget build(BuildContext context) {
    final allowReels = controls['allow_reels'] != false;
    final allowStories = controls['allow_stories'] != false;
    final allowMessaging = controls['allow_messaging'] != false;
    final educationalOnly = controls['educational_only_feed'] == true;
    final categories = (controls['categories'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Parent Controls Info'),
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
                const Icon(Icons.family_restroom,
                    color: AppColors.kidsAccent, size: 30),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Supervised by Parent Mode',
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Your parent can update these safety settings anytime through their Parent Dashboard.',
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
          _controlTile('Short Videos & Reels', allowReels),
          const SizedBox(height: AppSpacing.sm),
          _controlTile('Story Viewing & Uploads', allowStories),
          const SizedBox(height: AppSpacing.sm),
          _controlTile(
              'Direct Messaging with Approved Friends', allowMessaging),
          const SizedBox(height: AppSpacing.sm),
          _controlTile('Strict Educational-Only Feed', educationalOnly),
          const SizedBox(height: AppSpacing.md),
          if (categories.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Approved Content Categories',
                      style: AppTypography.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((c) {
                      return Chip(
                        label: Text(c, style: const TextStyle(fontSize: 12)),
                        backgroundColor:
                            AppColors.kidsAccent.withValues(alpha: 0.15),
                        side: const BorderSide(color: AppColors.kidsAccent),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controlTile(String label, bool isEnabled) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: AppTypography.bodyMedium),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isEnabled ? AppColors.success : AppColors.error)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              isEnabled ? 'ALLOWED' : 'RESTRICTED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isEnabled ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
