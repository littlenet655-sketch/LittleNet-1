import 'package:flutter/material.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../create_post/create_post_screen.dart';
import '../feed/feed_screen.dart';
import '../kids/kids_home_screen.dart';
import '../profile/profile_screen.dart';
import '../reels/reels_screen.dart';

class KidsMainShell extends StatefulWidget {
  const KidsMainShell({super.key, required this.authState});

  final AuthState authState;

  @override
  State<KidsMainShell> createState() => _KidsMainShellState();
}

class _KidsMainShellState extends State<KidsMainShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      KidsHomeScreen(authState: widget.authState),
      FeedScreen(authState: widget.authState),
      CreatePostScreen(authState: widget.authState),
      ReelsScreen(authState: widget.authState),
      ProfileScreen(authState: widget.authState),
    ];
  }

  void _onTabTapped(int index) {
    if (index == 2) {
      // Create post sheet / dialog
      _showCreateDialog();
      return;
    }
    setState(() => _currentIndex = index);
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Share Something Positive ✨',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'All posts are checked by LittleNet AI safety models before being shared with classmates.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.photo_library_rounded,
                      color: AppColors.kidsMint),
                ),
                title: const Text('Photo or Art'),
                subtitle:
                    const Text('Share drawings, crafts, or learning moments'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _currentIndex = 2);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child:
                      Icon(Icons.videocam_rounded, color: AppColors.kidsGold),
                ),
                title: const Text('Educational Short Video / Reel'),
                subtitle:
                    const Text('Explain a science trick or recite a poem'),
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon:
                Icon(Icons.dynamic_feed_rounded, color: AppColors.primary),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, size: 28),
            selectedIcon: Icon(Icons.add_circle_rounded,
                size: 28, color: AppColors.kidsAccent),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon:
                Icon(Icons.play_circle_fill, color: AppColors.primary),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
