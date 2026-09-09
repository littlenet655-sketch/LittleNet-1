import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import 'subpages/account_settings_page.dart';
import 'subpages/blocked_users_page.dart';
import 'subpages/help_about_page.dart';
import 'subpages/muted_users_page.dart';
import 'subpages/notifications_page.dart';
import 'subpages/parent_controls_page.dart';
import 'subpages/privacy_settings_page.dart';
import 'subpages/safety_settings_page.dart';
import 'subpages/screen_time_page.dart';

/// LittleNet V2 – Settings & Safety screen.
///
/// Visual language:
/// - Pure white background, standard iOS/Android settings layout
/// - Grouped sections with muted section labels (small caps, grey)
/// - Tiles are separated by a subtle divider — no card wrapping
/// - Icons in a rounded-rect tinted chip (Instagram settings style)
/// - Screen time progress bar as visual inline callout
/// - Logout at bottom in red, no card
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
      final res =
          await widget.authState.apiClient.get('/api/mobile/v1/kids/settings');
      if (res['ok'] == true) {
        setState(() => _settings = res);
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF262626))),
        content: const Text(
          'Are you sure you want to sign out of LittleNet?',
          style: TextStyle(color: Color(0xFF8E8E8E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF262626))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log Out',
                style: TextStyle(
                    color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F7F7),
          surfaceTintColor: const Color(0xFFF7F7F7),
          elevation: 0,
          title: const Text(
            'Settings',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF262626)),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? LnEmptyState(
                    emoji: '⚙️',
                    title: 'Could not load settings',
                    subtitle: _error,
                    action: _loadSettings,
                    actionLabel: 'Retry',
                  )
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final controls =
        _settings['controls'] as Map<String, dynamic>? ?? {};
    final minutesToday =
        (_settings['minutes_today'] as num?)?.toInt() ?? 0;
    final dailyLimit = (_settings['daily_limit'] as num?)?.toInt() ?? 60;
    final safetyLevel =
        _settings['safety_level']?.toString() ?? 'STRICT';
    final screenTimePct =
        dailyLimit > 0 ? (minutesToday / dailyLimit).clamp(0.0, 1.0) : 0.0;
    final screenTimeColor = screenTimePct >= 0.9
        ? const Color(0xFFE53935)
        : screenTimePct >= 0.7
            ? const Color(0xFFF59F00)
            : const Color(0xFF2E7D32);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ── Screen Time Card ─────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: screenTimeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.timer_outlined,
                          size: 18, color: screenTimeColor),
                    ),
                    const SizedBox(width: 10),
                    const Text('Screen Time Today',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF262626))),
                    const Spacer(),
                    Text(
                      '$minutesToday / $dailyLimit min',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: screenTimeColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: screenTimePct,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEEEEEE),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(screenTimeColor),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ScreenTimePage(
                          minutesToday: minutesToday,
                          dailyLimit: dailyLimit))),
                  child: const Text('View details →',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ),

        // ── Section: Account & Security ───────────────
        _sectionLabel('ACCOUNT & SECURITY'),
        _WhiteGroup(tiles: [
          _Tile(
            icon: Icons.person_outline_rounded,
            iconColor: const Color(0xFF5C6BC0),
            title: 'Account Details',
            subtitle: 'Profile, age, and Face ID',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AccountSettingsPage(
                    authState: widget.authState,
                    settingsData: _settings))),
          ),
          _Tile(
            icon: Icons.notifications_none_rounded,
            iconColor: const Color(0xFFEF6C00),
            title: 'Notifications',
            subtitle: 'Activity, approvals, safety notices',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    NotificationsPage(authState: widget.authState))),
          ),
        ]),

        // ── Section: Safety & Controls ────────────────
        _sectionLabel('SAFETY & CONTROLS'),
        _WhiteGroup(tiles: [
          _Tile(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF00897B),
            title: 'Safety & AI Moderation',
            subtitle: 'Level: $safetyLevel',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    SafetySettingsPage(safetyLevel: safetyLevel))),
          ),
          _Tile(
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFF3949AB),
            title: 'Privacy & Visibility',
            subtitle: 'Messaging, search, DM permissions',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    PrivacySettingsPage(controls: controls))),
          ),
          _Tile(
            icon: Icons.family_restroom_outlined,
            iconColor: const Color(0xFF8E24AA),
            title: 'Parent Controls Info',
            subtitle: 'Active rules from your parent',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ParentControlsPage(controls: controls))),
          ),
        ]),

        // ── Section: Connections ──────────────────────
        _sectionLabel('CONNECTIONS'),
        _WhiteGroup(tiles: [
          _Tile(
            icon: Icons.block_outlined,
            iconColor: const Color(0xFFE53935),
            title: 'Blocked Users',
            subtitle: 'Manage blocked profiles',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    BlockedUsersPage(authState: widget.authState))),
          ),
          _Tile(
            icon: Icons.volume_off_outlined,
            iconColor: const Color(0xFF546E7A),
            title: 'Muted Users',
            subtitle: 'Manage muted profiles',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    MutedUsersPage(authState: widget.authState))),
          ),
        ]),

        // ── Section: About ────────────────────────────
        _sectionLabel('ABOUT'),
        _WhiteGroup(tiles: [
          _Tile(
            icon: Icons.info_outline_rounded,
            iconColor: const Color(0xFF26A69A),
            title: 'Help & About LittleNet',
            subtitle: 'Child safety, mission & app version',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpAboutPage())),
          ),
        ]),

        const SizedBox(height: 16),

        // ── Logout ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout_rounded,
                    size: 18, color: Color(0xFFE53935)),
              ),
              title: const Text(
                'Log Out',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE53935)),
              ),
              onTap: _handleLogout,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 6),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E8E),
              letterSpacing: 0.8),
        ),
      );
}

// ─────────────────────────────────────────────────────────
//  White grouped section container
// ─────────────────────────────────────────────────────────
class _WhiteGroup extends StatelessWidget {
  const _WhiteGroup({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                const Divider(
                    height: 1,
                    thickness: 0.4,
                    indent: 56,
                    endIndent: 0,
                    color: Color(0xFFEEEEEE)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Individual settings tile
// ─────────────────────────────────────────────────────────
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF262626))),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E8E))),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 20, color: Color(0xFFBBBBBB)),
      onTap: onTap,
    );
  }
}
