import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import 'edit_profile_screen.dart';
import 'followers_following_screen.dart';

/// LittleNet V2 – Profile screen.
///
/// Visual language:
///  - White background, no gradient scaffold
///  - Avatar + stat row (Instagram layout)
///  - Name, school, bio below avatar row
///  - Edit button (outlined, full-width)
///  - Interest / skill chips in muted style
///  - 3-column square media grid (Instagram style)
///  - Tab bar: My Posts | Reels (future)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _counts;
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _controls;
  bool _isLoading = true;
  String? _error;

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/profile',
      );
      if (res['ok'] == true) {
        setState(() {
          _profile = res['profile'] as Map<String, dynamic>?;
          _counts = res['counts'] as Map<String, dynamic>?;
          _controls = res['controls'] as Map<String, dynamic>?;

          final list = (res['posts'] as List<dynamic>?) ?? [];
          _posts = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load profile.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        // Always-visible app bar so tests and nav can find the title
        appBar: _isLoading || _error != null
            ? AppBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                elevation: 0,
                title: const Text(
                  'My Profile 👤',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF262626),
                  ),
                ),
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(0.5),
                  child: Divider(
                      height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
                ),
              )
            : null,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? LnEmptyState(
                    emoji: '😕',
                    title: 'Could not load profile',
                    subtitle: _error,
                    action: _loadProfile,
                    actionLabel: 'Retry',
                  )
                : _buildProfile(),
      ),
    );
  }


  Widget _buildProfile() {
    final p = _profile ?? {};
    final name = p['full_name'] as String? ?? 'LittleNet Student';
    final bio = p['bio'] as String? ?? 'Excited to learn and create! 🌟';
    final avatarUrl = p['avatar_url'] as String?;
    final school = p['school_name'] as String?;
    final grade = p['current_class'] as String?;

    final postsCount = (_counts?['posts'] ?? _posts.length).toString();
    final followersCount = (_counts?['followers'] ?? 0).toString();
    final followingCount = (_counts?['following'] ?? 0).toString();

    final interests =
        (p['interests'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final skills =
        (p['skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: AppColors.primary,
      child: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          // ── App Bar ──────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            title: Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF262626),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Color(0xFF262626), size: 24),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.menu_rounded,
                    color: Color(0xFF262626), size: 24),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/kids/settings'),
              ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(0.5),
              child: Divider(
                  height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
            ),
          ),

          // ── Profile header ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + Stats row
                  Row(
                    children: [
                      // Avatar
                      LnAvatar(
                        url: avatarUrl,
                        name: name,
                        radius: 42,
                        borderColor: const Color(0xFFDBDBDB),
                        borderWidth: 1,
                      ),
                      const SizedBox(width: 24),
                      // Stats
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            LnStatColumn(value: postsCount, label: 'Posts'),
                            LnStatColumn(
                              value: followersCount,
                              label: 'Friends',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FollowersFollowingScreen(
                                    authState: widget.authState,
                                    initialTab: 0,
                                  ),
                                ),
                              ),
                            ),
                            LnStatColumn(
                              value: followingCount,
                              label: 'Following',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => FollowersFollowingScreen(
                                    authState: widget.authState,
                                    initialTab: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Name + school
                  Text(name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF262626))),

                  if (school != null && school.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.school_outlined,
                            size: 13, color: Color(0xFF8E8E8E)),
                        const SizedBox(width: 4),
                        Text(
                          grade != null && grade.isNotEmpty
                              ? '$school · $grade'
                              : school,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF8E8E8E)),
                        ),
                      ],
                    ),
                  ],

                  if (_controls?['educational_only_feed'] == true) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '📚 Educational Feed Focus',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  Text(bio,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF262626))),

                  const SizedBox(height: 14),

                  // Edit Profile button
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: OutlinedButton(
                      onPressed: () async {
                        final updated = await Navigator.of(context)
                            .push<bool>(MaterialPageRoute(
                          builder: (_) => EditProfileScreen(
                            authState: widget.authState,
                            currentProfile: p,
                          ),
                        ));
                        if (updated == true) _loadProfile();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF262626),
                        side: const BorderSide(color: Color(0xFFDBDBDB)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Edit profile'),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Interest chips
                  if (interests.isNotEmpty || skills.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...interests.map((t) => _chip(t, AppColors.primary)),
                        ...skills.map((t) => _chip(t, AppColors.kidsMint)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),

          // ── Tab Bar ──────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabCtrl,
                indicatorColor: const Color(0xFF262626),
                indicatorWeight: 1.5,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: const Color(0xFF262626),
                unselectedLabelColor: const Color(0xFF8E8E8E),
                tabs: const [
                  Tab(icon: Icon(Icons.grid_on_rounded, size: 20)),
                  Tab(icon: Icon(Icons.play_circle_outline_rounded, size: 20)),
                ],
              ),
            ),
          ),
        ],

        body: TabBarView(
          controller: _tabCtrl,
          children: [
            // Posts grid
            _postsGrid(),
            // Reels placeholder
            LnEmptyState(
              emoji: '🎬',
              title: 'No reels yet',
              subtitle: 'Share your first educational reel!',
            ),
          ],
        ),
      ),
    );
  }

  Widget _postsGrid() {
    if (_posts.isEmpty) {
      return LnEmptyState(
        emoji: '✨',
        title: 'No posts yet',
        subtitle: 'Share your first art, code, or learning moment!',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(1),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _posts.length,
      itemBuilder: (ctx, i) {
        final item = _posts[i];
        final mediaUrl = item['media_url'] as String?;
        final isReel = item['is_reel'] == true;

        return Container(
          color: const Color(0xFFF0F0F0),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mediaUrl != null && mediaUrl.isNotEmpty)
                Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.image_not_supported_outlined,
                        size: 24, color: Color(0xFFBBBBBB)),
                  ),
                )
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      item['caption']?.toString() ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9, color: Color(0xFF8E8E8E)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (isReel)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_circle_fill,
                      size: 16, color: Colors.white),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.9)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Pinned tab bar delegate
// ─────────────────────────────────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height + 1;

  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFDBDBDB)),
          tabBar,
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
