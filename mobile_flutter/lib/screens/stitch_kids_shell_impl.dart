import 'package:flutter/material.dart';

import '../api.dart';
import '../stitch_design.dart';
import '../widgets.dart';
import 'kids.dart';
import 'kids_learning.dart';
import 'kids_onboarding.dart';
import 'stitch_social.dart';

class StitchKidsShellV2 extends StatefulWidget {
  const StitchKidsShellV2({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<StitchKidsShellV2> createState() => _StitchKidsShellV2State();
}

class _StitchKidsShellV2State extends State<StitchKidsShellV2> {
  int index = 0;
  int refreshToken = 0;

  void refreshAll() => setState(() => refreshToken++);

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _StitchHomePage(
        api: widget.api,
        currentUserId: asInt(widget.user['user_id']),
        refreshToken: refreshToken,
        onOpenSearch: () => _push(DiscoverPage(api: widget.api, refreshToken: refreshToken)),
        onOpenNotifications: () => _push(NotificationsScreen(api: widget.api)),
        onOpenMessages: () => _push(MessagesPage(api: widget.api)),
      ),
      _StitchReelsPage(api: widget.api, refreshToken: refreshToken),
      CreatePostPage(
        api: widget.api,
        onCreated: () {
          refreshAll();
          setState(() => index = 0);
        },
      ),
      LearningScreen(api: widget.api),
      ProfilePage(
        api: widget.api,
        user: widget.user,
        onLogout: widget.onLogout,
        refreshToken: refreshToken,
      ),
    ];

    final darkNav = index == 1;
    return Scaffold(
      backgroundColor: darkNav ? Colors.black : Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          if (index == 4)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 2,
              right: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Saved',
                    onPressed: () => _push(SavedContentScreen(api: widget.api)),
                    icon: const Icon(Icons.bookmark_border_rounded),
                  ),
                  IconButton(
                    tooltip: 'Safety Centre',
                    onPressed: () => _push(SafetyCentreScreen(api: widget.api)),
                    icon: const Icon(Icons.shield_outlined),
                  ),
                  IconButton(
                    tooltip: 'Report history',
                    onPressed: () => _push(ReportHistoryScreen(api: widget.api)),
                    icon: const Icon(Icons.history_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: darkNav ? Colors.black : Colors.white,
          border: Border(
            top: BorderSide(
              color: darkNav ? Colors.white24 : StitchTokens.border,
              width: .65,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: index,
          onTap: (value) => setState(() => index = value),
          backgroundColor: darkNav ? Colors.black : Colors.white,
          selectedItemColor: darkNav ? Colors.white : StitchTokens.ink,
          unselectedItemColor: darkNav ? Colors.white : StitchTokens.ink,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search_rounded),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Reels',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.add_box_outlined),
              activeIcon: Icon(Icons.add_box_rounded),
              label: 'Create',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.movie_creation_outlined),
              activeIcon: Icon(Icons.movie_creation_rounded),
              label: 'Learn',
            ),
            BottomNavigationBarItem(
              icon: _BottomAvatar(api: widget.api, url: widget.user['avatar_url']?.toString(), selected: false),
              activeIcon: _BottomAvatar(api: widget.api, url: widget.user['avatar_url']?.toString(), selected: true),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomAvatar extends StatelessWidget {
  const _BottomAvatar({required this.api, required this.url, required this.selected});

  final ApiClient api;
  final String? url;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(selected ? 1.4 : 0),
      decoration: selected
          ? const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: StitchTokens.ink, width: 1.2)),
            )
          : null,
      child: Avatar(api: api, url: url, radius: 11.5),
    );
  }
}

class _StitchHomePage extends StatefulWidget {
  const _StitchHomePage({
    required this.api,
    required this.currentUserId,
    required this.refreshToken,
    required this.onOpenSearch,
    required this.onOpenNotifications,
    required this.onOpenMessages,
  });

  final ApiClient api;
  final int currentUserId;
  final int refreshToken;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenMessages;

  @override
  State<_StitchHomePage> createState() => _StitchHomePageState();
}

class _StitchHomePageState extends State<_StitchHomePage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StitchHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/home');
      });

  Future<void> _openProfile(int userId) async {
    if (userId <= 0 || userId == widget.currentUserId) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OtherUserProfileScreen(api: widget.api, userId: userId)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Column(
              children: [
                _StitchHomeHeader(),
                Divider(height: 1),
                Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              ],
            );
          }
          if (snapshot.hasError) {
            return GateAwareError(api: widget.api, error: snapshot.error!, onResolved: _load);
          }
          final data = snapshot.data ?? const {};
          final stories = listMaps(data['stories']);
          final suggestions = listMaps(data['suggested']);
          final posts = listMaps(data['posts']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _StitchHomeHeader(
                  onSearch: widget.onOpenSearch,
                  onNotifications: widget.onOpenNotifications,
                  onMessages: widget.onOpenMessages,
                ),
                const StitchHairline(),
                _StoryTray(api: widget.api, stories: stories),
                const StitchHairline(),
                if (suggestions.isNotEmpty)
                  _SafePeopleStrip(
                    api: widget.api,
                    people: suggestions,
                    onOpenProfile: _openProfile,
                  ),
                if (posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 72, horizontal: 24),
                    child: Column(
                      children: [
                        Icon(Icons.photo_library_outlined, size: 56, color: StitchTokens.ink),
                        SizedBox(height: 14),
                        Text('Your safe feed is ready', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        SizedBox(height: 6),
                        Text(
                          'Approved posts from your network will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: StitchTokens.muted),
                        ),
                      ],
                    ),
                  )
                else
                  ...posts.map(
                    (post) => _StitchPostCard(
                      api: widget.api,
                      post: post,
                      currentUserId: widget.currentUserId,
                      onChanged: _load,
                    ),
                  ),
                const SizedBox(height: 18),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StitchHomeHeader extends StatelessWidget {
  const _StitchHomeHeader({this.onSearch, this.onNotifications, this.onMessages});

  final VoidCallback? onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback? onMessages;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 14),
          const LittleNetWordmark(fontSize: 25),
          const Spacer(),
          IconButton(tooltip: 'Search', onPressed: onSearch, icon: const Icon(Icons.search_rounded)),
          IconButton(
            tooltip: 'Notifications',
            onPressed: onNotifications,
            icon: const Icon(Icons.favorite_border_rounded),
          ),
          IconButton(tooltip: 'Messages', onPressed: onMessages, icon: const Icon(Icons.send_outlined)),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _StoryTray extends StatelessWidget {
  const _StoryTray({required this.api, required this.stories});

  final ApiClient api;
  final List<Map<String, dynamic>> stories;

  @override
  Widget build(BuildContext context) {
    final visible = stories.take(12).toList();
    return SizedBox(
      height: 103,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        scrollDirection: Axis.horizontal,
        itemCount: visible.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return SizedBox(
              width: 70,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      StitchStoryRing(
                        seen: true,
                        child: Avatar(api: api, url: null, radius: 28),
                      ),
                      const Positioned(
                        right: 1,
                        bottom: 1,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 7.3,
                            backgroundColor: StitchTokens.blue,
                            child: Icon(Icons.add, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Your story', maxLines: 1, style: TextStyle(fontSize: 10.5)),
                ],
              ),
            );
          }
          final story = visible[i - 1];
          return InkWell(
            borderRadius: BorderRadius.circular(42),
            onTap: () {
              final postId = asInt(story['post_id']);
              if (postId <= 0) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PostDetailScreen(api: api, postId: postId)),
              );
            },
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  StitchStoryRing(
                    child: Avatar(api: api, url: story['avatar_url']?.toString(), radius: 28),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    story['username']?.toString() ?? story['full_name']?.toString() ?? 'story',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SafePeopleStrip extends StatelessWidget {
  const _SafePeopleStrip({required this.api, required this.people, required this.onOpenProfile});

  final ApiClient api;
  final List<Map<String, dynamic>> people;
  final Future<void> Function(int userId) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StitchSectionTitle('Suggested for your approved network'),
        SizedBox(
          height: 92,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            scrollDirection: Axis.horizontal,
            itemCount: people.take(10).length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final person = people[i];
              return InkWell(
                onTap: () => onOpenProfile(asInt(person['user_id'])),
                child: Container(
                  width: 168,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    border: Border.all(color: StitchTokens.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Avatar(api: api, url: person['avatar_url']?.toString(), radius: 23),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person['username']?.toString() ??
                                  person['full_name']?.toString() ??
                                  'Friend',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Safe network',
                              style: TextStyle(fontSize: 10.5, color: StitchTokens.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const StitchHairline(),
      ],
    );
  }
}

class _StitchPostCard extends StatefulWidget {
  const _StitchPostCard({
    required this.api,
    required this.post,
    required this.currentUserId,
    required this.onChanged,
  });

  final ApiClient api;
  final Map<String, dynamic> post;
  final int currentUserId;
  final VoidCallback onChanged;

  @override
  State<_StitchPostCard> createState() => _StitchPostCardState();
}

class _StitchPostCardState extends State<_StitchPostCard> {
  late bool liked = widget.post['viewer_liked'] == true;
  late bool saved = widget.post['viewer_saved'] == true;
  late int likes = asInt(widget.post['likes']);
  bool busy = false;

  int get postId => asInt(widget.post['post_id']);
  int get creatorId => asInt(widget.post['child_id']);

  Future<void> _openDetail() async {
    if (postId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(api: widget.api, postId: postId)),
    );
    widget.onChanged();
  }

  Future<void> _openCreator() async {
    if (creatorId <= 0 || creatorId == widget.currentUserId) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OtherUserProfileScreen(api: widget.api, userId: creatorId)),
    );
    widget.onChanged();
  }

  Future<void> _toggleLike() async {
    if (busy || postId <= 0) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.postJson('/api/mobile/v1/kids/posts/$postId/like', const {});
      if (!mounted) return;
      setState(() {
        liked = data['liked'] == true;
        likes = asInt(data['likes']);
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _doubleTapLike() async {
    if (liked || busy) return;
    await _toggleLike();
  }

  Future<void> _toggleSave() async {
    if (postId <= 0) return;
    try {
      final data = await widget.api.postJson('/api/mobile/v1/kids/posts/$postId/save', const {});
      if (mounted) setState(() => saved = data['saved'] == true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.post['media_url']?.toString();
    final username = widget.post['username']?.toString() ??
        widget.post['full_name']?.toString() ??
        'littlenet_student';
    final caption = widget.post['caption']?.toString() ?? '';
    final category = widget.post['content_category']?.toString() ?? 'Classroom Safe';
    final commentCount = asInt(widget.post['comments_count']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: _openCreator,
                  child: StitchStoryRing(
                    size: 36,
                    child: Avatar(api: widget.api, url: widget.post['avatar_url']?.toString(), radius: 16),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    onTap: _openCreator,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.verified_rounded, size: 13.5, color: StitchTokens.blue),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF737373)),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Post options',
                  onPressed: creatorId == widget.currentUserId || postId <= 0
                      ? null
                      : () => showReportSheet(
                            context,
                            api: widget.api,
                            targetType: widget.post['is_reel'] == true ? 'REEL' : 'POST',
                            targetId: postId,
                          ),
                  icon: const Icon(Icons.more_horiz_rounded, size: 22),
                ),
              ],
            ),
          ),
        ),
        if (media != null && media.isNotEmpty)
          DoubleTapLikeOverlay(
            onLike: _doubleTapLike,
            child: InkWell(
              onTap: _openDetail,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NativeMedia(
                      api: widget.api,
                      url: media,
                      mediaType: widget.post['media_type']?.toString(),
                    ),
                    const Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SentinelSafeBadge(label: 'Sentinel Safe • Classroom Approved'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Like',
                  onPressed: _toggleLike,
                  icon: Icon(
                    liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: liked ? StitchTokens.heart : StitchTokens.ink,
                    size: 26,
                  ),
                ),
                IconButton(
                  tooltip: 'Comments',
                  onPressed: _openDetail,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 23),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: postId <= 0
                      ? null
                      : () => showSharePostSheet(context, api: widget.api, postId: postId),
                  icon: const Icon(Icons.send_outlined, size: 24),
                ),
                const Spacer(),
                IconButton(
                  tooltip: saved ? 'Unsave' : 'Save',
                  onPressed: _toggleSave,
                  icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 25),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$likes likes', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(color: StitchTokens.ink, fontSize: 12.8, height: 1.35),
                    children: [
                      TextSpan(text: '$username ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: caption),
                    ],
                  ),
                ),
              ],
              if (commentCount > 0) ...[
                const SizedBox(height: 5),
                InkWell(
                  onTap: _openDetail,
                  child: Text(
                    'View all $commentCount comments',
                    style: const TextStyle(color: Color(0xFF737373), fontSize: 12.5),
                  ),
                ),
              ],
              const SizedBox(height: 5),
              const Text(
                'RECENTLY',
                style: TextStyle(color: StitchTokens.muted, fontSize: 9.5, letterSpacing: .2),
              ),
            ],
          ),
        ),
        const StitchHairline(),
      ],
    );
  }
}

class _StitchReelsPage extends StatefulWidget {
  const _StitchReelsPage({required this.api, required this.refreshToken});

  final ApiClient api;
  final int refreshToken;

  @override
  State<_StitchReelsPage> createState() => _StitchReelsPageState();
}

class _StitchReelsPageState extends State<_StitchReelsPage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StitchReelsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/reels');
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ColoredBox(
              color: Colors.black,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            );
          }
          if (snapshot.hasError) {
            return GateAwareError(api: widget.api, error: snapshot.error!, onResolved: _load);
          }
          final reels = listMaps(snapshot.data?['reels']);
          if (reels.isEmpty) {
            return const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Text('No safe reels available right now.', style: TextStyle(color: Colors.white)),
              ),
            );
          }
          return Stack(
            children: [
              PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: reels.length,
                itemBuilder: (_, i) => _StitchReelPane(api: widget.api, reel: reels[i]),
              ),
              const Positioned(
                left: 14,
                top: 10,
                child: Row(
                  children: [
                    Text('Reels', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
              const Positioned(
                right: 10,
                top: 5,
                child: IconButton(
                  onPressed: null,
                  icon: Icon(Icons.photo_camera_outlined, color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StitchReelPane extends StatefulWidget {
  const _StitchReelPane({required this.api, required this.reel});

  final ApiClient api;
  final Map<String, dynamic> reel;

  @override
  State<_StitchReelPane> createState() => _StitchReelPaneState();
}

class _StitchReelPaneState extends State<_StitchReelPane> {
  late bool liked = widget.reel['viewer_liked'] == true;
  late bool saved = widget.reel['viewer_saved'] == true;
  late int likes = asInt(widget.reel['likes']);
  bool busy = false;

  int get postId => asInt(widget.reel['post_id']);
  int get creatorId => asInt(widget.reel['child_id']);

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      try {
        await widget.api.postJson('/api/mobile/v1/kids/feed-view/$postId', const {});
      } catch (_) {}
    });
  }

  Future<void> _toggleLike() async {
    if (busy || postId <= 0) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.postJson('/api/mobile/v1/kids/posts/$postId/like', const {});
      if (!mounted) return;
      setState(() {
        liked = data['liked'] == true;
        likes = asInt(data['likes']);
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleSave() async {
    if (postId <= 0) return;
    try {
      final data = await widget.api.postJson('/api/mobile/v1/kids/posts/$postId/save', const {});
      if (mounted) setState(() => saved = data['saved'] == true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _detail() async {
    if (postId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(api: widget.api, postId: postId)),
    );
  }

  Future<void> _creator() async {
    if (creatorId <= 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OtherUserProfileScreen(api: widget.api, userId: creatorId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.reel['media_url']?.toString();
    final username = widget.reel['username']?.toString() ??
        widget.reel['full_name']?.toString() ??
        'littlenet_creator';
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            DoubleTapLikeOverlay(
              onLike: liked ? () {} : _toggleLike,
              child: NativeMedia(
                api: widget.api,
                url: url,
                mediaType: widget.reel['media_type']?.toString(),
                fit: BoxFit.cover,
              ),
            )
          else
            const Center(child: Icon(Icons.smart_display_rounded, color: Colors.white54, size: 80)),
          Positioned(
            left: 12,
            right: 76,
            bottom: 15,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SentinelSafeBadge(label: 'AI Approved • Classroom Safe'),
                const SizedBox(height: 11),
                InkWell(
                  onTap: _creator,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(api: widget.api, url: widget.reel['avatar_url']?.toString(), radius: 15),
                      const SizedBox(width: 8),
                      Text(
                        '@$username',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'Follow',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  widget.reel['caption']?.toString() ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
          Positioned(
            right: 6,
            bottom: 12,
            child: Column(
              children: [
                IconButton(
                  tooltip: 'Like',
                  onPressed: _toggleLike,
                  icon: Icon(
                    liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: liked ? StitchTokens.heart : Colors.white,
                    size: 30,
                  ),
                ),
                Text('$likes', style: const TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: 'Comments',
                  onPressed: _detail,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 27),
                ),
                Text('${widget.reel['comments_count'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: 'Share',
                  onPressed: postId <= 0
                      ? null
                      : () => showSharePostSheet(context, api: widget.api, postId: postId),
                  icon: const Icon(Icons.send_outlined, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: saved ? 'Unsave' : 'Save',
                  onPressed: _toggleSave,
                  icon: Icon(
                    saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: 'Report',
                  onPressed: postId <= 0
                      ? null
                      : () => showReportSheet(
                            context,
                            api: widget.api,
                            targetType: 'REEL',
                            targetId: postId,
                          ),
                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 27),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
