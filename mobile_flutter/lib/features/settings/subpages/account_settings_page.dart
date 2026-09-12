import 'package:flutter/material.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({
    super.key,
    required this.authState,
    required this.settingsData,
  });

  final AuthState authState;
  final Map<String, dynamic> settingsData;

  @override
  Widget build(BuildContext context) {
    final user = authState.currentUser;
    final profile = settingsData['profile'] as Map<String, dynamic>? ?? {};
    final hasFace = settingsData['has_face'] == true;

    final username =
        user?.username ?? profile['username']?.toString() ?? 'unknown';
    final fullName =
        user?.fullName ?? profile['full_name']?.toString() ?? 'Student';
    final role = user?.role ?? 'CHILD';
    final age = user?.age?.toString() ?? profile['age']?.toString() ?? '—';

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Account Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _infoCard('Account Overview', [
            _row('Full Name', fullName),
            _row('Username', '@$username'),
            _row('Account Type', role == 'CHILD' ? 'Kids Safe Account' : role),
            _row('Age', '$age years old'),
          ]),
          const SizedBox(height: AppSpacing.md),
          _infoCard('Security & Biometrics', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                hasFace
                    ? Icons.face_rounded
                    : Icons.face_retouching_off_rounded,
                color: hasFace ? AppColors.success : AppColors.textSecondary,
              ),
              title:
                  const Text('Face ID Login', style: AppTypography.titleMedium),
              subtitle: Text(
                hasFace
                    ? 'Enrolled · reference facial template is active for secure sign in.'
                    : 'Not enrolled · Face ID can be enrolled by your parent or on next login.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textMutedDark),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasFace ? AppColors.success : Colors.grey)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  hasFace ? 'ACTIVE' : 'OPTIONAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasFace ? AppColors.success : Colors.grey,
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _infoCard(String title, List<Widget> children) {
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
          const Divider(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textMutedDark)),
          Text(value,
              style: AppTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
