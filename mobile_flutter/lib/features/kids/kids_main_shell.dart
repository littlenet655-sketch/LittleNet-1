import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../create_post/create_post_screen.dart';
import '../explore/explore_screen.dart';
import '../kids/kids_home_screen.dart';
import '../profile/profile_screen.dart';
import '../reels/reels_screen.dart';
import '../../core/upload/upload_progress_banner.dart';

/// LittleNet V2 – main navigation shell.
///
/// Layout mirrors a social feed app (Instagram-ish):
///   HOME | EXPLORE | [CREATE] | REELS | PROFILE
///
/// The CREATE tab is a modal action sheet, not a full tab page.
class KidsMainShell extends StatefulWidget {
  const KidsMainShell({super.key, required this.authState});

  final AuthState authState;

  @override
  State<KidsMainShell> createState() => _KidsMainShellState();
}

class _KidsMainShellState extends State<KidsMainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      KidsHomeScreen(authState: widget.authState),
      ExploreScreen(authState: widget.authState),
      // index 2 is the create modal – placeholder never shown
      const SizedBox.shrink(),
      ReelsScreen(authState: widget.authState),
      ProfileScreen(authState: widget.authState),
    ];
  }

  void _onTabTapped(int index) {
    if (index == 2) {
      _showCreateSheet();
      return;
    }
    // light haptic on tab switch
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  void _showCreateSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBDBDB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Share something positive',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF262626),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'All posts are reviewed by LittleNet AI before sharing.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E8E)),
              ),
              const SizedBox(height: 20),

              // Photo / Art option
              _CreateOption(
                icon: Icons.photo_library_outlined,
                iconColor: AppColors.kidsMint,
                iconBg: const Color(0xFFE8F5E9),
                title: 'Photo or Art',
                subtitle: 'Share drawings, crafts, or moments',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CreatePostScreen(authState: widget.authState),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Short Video / Reel option
              _CreateOption(
                icon: Icons.videocam_outlined,
                iconColor: AppColors.kidsAccent,
                iconBg: const Color(0xFFFFF0EE),
                title: 'Educational Reel',
                subtitle: 'Explain a concept, recite a poem, show a trick',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreatePostScreen(
                        authState: widget.authState,
                        initialKind: PostKind.reel,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep status bar icons dark on light background
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const UploadProgressBanner(),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex > 2 ? _currentIndex - 1 : _currentIndex,
                  children: [
                    _pages[0], // home
                    _pages[1], // feed / search
                    _pages[3], // reels
                    _pages[4], // profile
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _LnBottomBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  _LnBottomBar
// ─────────────────────────────────────────────────────────────────
class _LnBottomBar extends StatelessWidget {
  const _LnBottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFDBDBDB), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                label: 'Explore',
                icon: Icons.search_rounded,
                selectedIcon: Icons.search_rounded,
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              // Create button – raised pill with label
              GestureDetector(
                onTap: () => onTap(2),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Create',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8E8E8E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _NavItem(
                label: 'Reels',
                icon: Icons.play_circle_outline_rounded,
                selectedIcon: Icons.play_circle_filled_rounded,
                selected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                label: 'Profile',
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                selected: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF262626) : const Color(0xFF8E8E8E);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 22,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  _CreateOption  (helper widget for the bottom sheet)
// ─────────────────────────────────────────────────────────────────
class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF262626))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8E8E8E))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFBBBBBB), size: 22),
          ],
        ),
      ),
    );
  }
}
