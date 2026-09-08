import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';
import 'subpages/account_settings_page.dart';
import 'subpages/blocked_users_page.dart';
import 'subpages/help_about_page.dart';
import 'subpages/muted_users_page.dart';
import 'subpages/notifications_page.dart';
import 'subpages/parent_controls_page.dart';
import 'subpages/privacy_settings_page.dart';
import 'subpages/safety_settings_page.dart';
import 'subpages/screen_time_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/settings',
      );
      if (res['ok'] == true) {
        setState(() {
          _settings = res;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load settings.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('Are you sure you want to sign out of LittleNet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.authState.logout();
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Settings & Safety ⚙️'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: AppTypography.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
                onPressed: _loadSettings, child: const Text('Retry')),
          ],
        ),
      );
    }

    final controls = _settings['controls'] as Map<String, dynamic>? ?? {};
    final minutesToday = (_settings['minutes_today'] as num?)?.toInt() ?? 0;
    final dailyLimit = (_settings['daily_limit'] as num?)?.toInt() ?? 60;
    final safetyLevel = _settings['safety_level']?.toString() ?? 'STRICT';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // Section: Account & Biometrics
        _sectionLabel('ACCOUNT & SECURITY'),
        _menuTile(
          icon: Icons.person_outline_rounded,
          title: 'Account Details',
          subtitle: 'Profile details, age, and Face ID status',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountSettingsPage(
                authState: widget.authState,
                settingsData: _settings,
              ),
            ),
          ),
        ),
        _menuTile(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications & Alerts',
          subtitle: 'Activity, approvals, and safety notices',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NotificationsPage(authState: widget.authState),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Section: Safety & Controls
        _sectionLabel('SAFETY & CONTROLS'),
        _menuTile(
          icon: Icons.shield_outlined,
          title: 'Safety & AI Moderation',
          subtitle: 'Safety level ($safetyLevel) & content protection',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SafetySettingsPage(safetyLevel: safetyLevel),
            ),
          ),
        ),
        _menuTile(
          icon: Icons.lock_outline_rounded,
          title: 'Privacy & Visibility',
          subtitle: 'Kids safe visibility, messaging, and search',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PrivacySettingsPage(controls: controls),
            ),
          ),
        ),
        _menuTile(
          icon: Icons.family_restroom_outlined,
          title: 'Parent Controls Info',
          subtitle: 'Active rules configured by your parent',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ParentControlsPage(controls: controls),
            ),
          ),
        ),
        _menuTile(
          icon: Icons.timer_outlined,
          title: 'Screen Time',
          subtitle: '$minutesToday of $dailyLimit min used today',
          trailingText: '$dailyLimit min limit',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScreenTimePage(
                minutesToday: minutesToday,
                dailyLimit: dailyLimit,
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Section: Interactions
        _sectionLabel('CONNECTIONS & INTERACTIONS'),
        _menuTile(
          icon: Icons.block_outlined,
          title: 'Blocked Users',
          subtitle: 'Manage blocked profiles',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BlockedUsersPage(authState: widget.authState),
            ),
          ),
        ),
        _menuTile(
          icon: Icons.volume_off_outlined,
          title: 'Muted Users',
          subtitle: 'Manage muted profiles',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MutedUsersPage(authState: widget.authState),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Section: About & Logout
        _sectionLabel('ABOUT'),
        _menuTile(
          icon: Icons.info_outline_rounded,
          title: 'Help & About LittleNet',
          subtitle: 'Child safety standards, mission, and app version',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HelpAboutPage()),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          leading: const Icon(Icons.logout_rounded, color: AppColors.error),
          title: const Text(
            'Log Out',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          onTap: _handleLogout,
        ),
      ],
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.xs,
        top: AppSpacing.xs,
      ),
      child: Text(
        title,
        style: AppTypography.caption.copyWith(
          color: AppColors.kidsAccent,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? trailingText,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppColors.cardDark,
      child: ListTile(
        leading: Icon(icon, color: AppColors.kidsAccent),
        title: Text(title, style: AppTypography.titleSmall),
        subtitle: Text(
          subtitle,
          style: AppTypography.caption.copyWith(color: AppColors.textMutedDark),
        ),
        trailing: trailingText != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.kidsAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  trailingText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.kidsAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        onTap: onTap,
      ),
    );
  }
}
