import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'kids.dart';
import 'kids_learning.dart';
import 'kids_onboarding.dart';
import 'stitch_social.dart';
import 'search_flow.dart';

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

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          if (index == 0)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => _push(
                      SearchScreen(api: widget.api, refreshToken: refreshToken),
                    ),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => _push(NotificationsScreen(api: widget.api)),
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  IconButton(
                    tooltip: 'Messages',
                    onPressed: () => _push(MessagesPage(api: widget.api)),
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
          if (index == 4)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 6,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_display_outlined),
            selectedIcon: Icon(Icons.smart_display_rounded),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box_rounded),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _StitchHomePage extends StatefulWidget {
  const _StitchHomePage({
    required this.api,
    required this.currentUserId,
    required this.refreshToken,
  });

  final ApiClient api;
  final int currentUserId;
  final int refreshToken;

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
      MaterialPageRoute(
        builder: (_) => OtherUserProfileScreen(api: widget.api, userId: userId),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return GateAwareError(api: widget.api, error: snapshot.error!, onResolved: _load);
          }
          final data = snapshot.data ?? const {};
          final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
          final stories = listMaps(data['stories']);
          final suggestions = listMaps(data['suggested']);
          final posts = listMaps(data['posts']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  floating: true,
                  title: const Row(
                    children: [
                      Icon(Icons.shield_rounded, color: Color(0xFF2563EB)),
                      SizedBox(width: 8),
                      Text('LittleNet', style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Text(
                      'Hi ${profile['full_name'] ?? 'there'} 👋',
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                if (stories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 104,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        scrollDirection: Axis.horizontal,
                        itemCount: stories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final story = stories[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(44),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PostDetailScreen(
                                  api: widget.api,
                                  postId: asInt(story['post_id']),
                                ),
                              ),
                            ),
                            child: SizedBox(
                              width: 72,
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2.5),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
                                      ),
                                    ),
                                    child: Avatar(
                                      api: widget.api,
                                      url: story['avatar_url']?.toString(),
                                      radius: 27,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    story['full_name']?.toString() ?? 'Story',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (suggestions.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Safe people to discover',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                if (suggestions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 102,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final user = suggestions[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _openProfile(asInt(user['user_id'])),
                            child: SizedBox(
                              width: 88,
                              child: Column(
                                children: [
                                  Avatar(
                                    api: widget.api,
                                    url: user['avatar_url']?.toString(),
                                    radius: 27,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    user['full_name']?.toString() ?? 'Friend',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (posts.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('Your safe feed is ready for new posts.')),
                  )
                else
                  SliverList.builder(
                    itemCount: posts.length,
                    itemBuilder: (_, i) => _StitchPostCard(
                      api: widget.api,
                      post: posts[i],
                      currentUserId: widget.currentUserId,
                      onChanged: _load,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          );
        },
      ),
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
      MaterialPageRoute(
        builder: (_) => OtherUserProfileScreen(api: widget.api, userId: creatorId),
      ),
    );
    widget.onChanged();
  }

  Future<void> _toggleLike() async {
    if (busy || postId <= 0) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/$postId/like',
        const {},
      );
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
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/$postId/save',
        const {},
      );
      if (mounted) setState(() => saved = data['saved'] == true);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.post['media_url']?.toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Avatar(
                api: widget.api,
                url: widget.post['avatar_url']?.toString(),
                radius: 20,
              ),
              title: Text(
                widget.post['full_name']?.toString() ?? 'LittleNet Student',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(widget.post['content_category']?.toString() ?? 'Safe content'),
              onTap: _openCreator,
              trailing: creatorId == widget.currentUserId
                  ? null
                  : IconButton(
                      tooltip: 'Report',
                      onPressed: () => showReportSheet(
                        context,
                        api: widget.api,
                        targetType: widget.post['is_reel'] == true ? 'REEL' : 'POST',
                        targetId: postId,
                      ),
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
            ),
            if (media != null && media.isNotEmpty)
              InkWell(
                onTap: _openDetail,
                child: AspectRatio(
                  aspectRatio: widget.post['media_type'] == 'VIDEO' ? 9 / 14 : 1,
                  child: NativeMedia(
                    api: widget.api,
                    url: media,
                    mediaType: widget.post['media_type']?.toString(),
                  ),
                ),
              ),
            if ((widget.post['caption']?.toString() ?? '').isNotEmpty)
              InkWell(
                onTap: _openDetail,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Text(widget.post['caption'].toString()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Like',
                    onPressed: _toggleLike,
                    icon: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? Colors.red : null,
                    ),
                  ),
                  Text('$likes'),
                  IconButton(
                    tooltip: 'Comments',
                    onPressed: _openDetail,
                    icon: const Icon(Icons.mode_comment_outlined),
                  ),
                  Text('${widget.post['comments_count'] ?? 0}'),
                  IconButton(
                    tooltip: 'Share',
                    onPressed: postId <= 0
                        ? null
                        : () => showSharePostSheet(context, api: widget.api, postId: postId),
                    icon: const Icon(Icons.send_outlined),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: saved ? 'Unsave' : 'Save',
                    onPressed: _toggleSave,
                    icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return GateAwareError(api: widget.api, error: snapshot.error!, onResolved: _load);
          }
          final reels = listMaps(snapshot.data?['reels']);
          if (reels.isEmpty) {
            return const Center(child: Text('No safe reels available right now.'));
          }
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            itemBuilder: (_, i) => _StitchReelPane(api: widget.api, reel: reels[i]),
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
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/$postId/like',
        const {},
      );
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
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/$postId/save',
        const {},
      );
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
      MaterialPageRoute(
        builder: (_) => OtherUserProfileScreen(api: widget.api, userId: creatorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.reel['media_url']?.toString();
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            NativeMedia(
              api: widget.api,
              url: url,
              mediaType: widget.reel['media_type']?.toString(),
              fit: BoxFit.contain,
            )
          else
            const Center(
              child: Icon(Icons.smart_display_rounded, color: Colors.white54, size: 80),
            ),
          Positioned(
            left: 18,
            right: 88,
            bottom: 26,
            child: InkWell(
              onTap: _creator,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.reel['full_name']?.toString() ?? 'LittleNet',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.reel['caption']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 24,
            child: Column(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Like',
                  onPressed: _toggleLike,
                  icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                ),
                Text('$likes', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Comments',
                  onPressed: _detail,
                  icon: const Icon(Icons.mode_comment_outlined),
                ),
                Text('${widget.reel['comments_count'] ?? 0}', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Share',
                  onPressed: postId <= 0
                      ? null
                      : () => showSharePostSheet(context, api: widget.api, postId: postId),
                  icon: const Icon(Icons.send_outlined),
                ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: saved ? 'Unsave' : 'Save',
                  onPressed: _toggleSave,
                  icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                ),
                const SizedBox(height: 8),
                IconButton.filledTonal(
                  tooltip: 'Report',
                  onPressed: postId <= 0
                      ? null
                      : () => showReportSheet(
                            context,
                            api: widget.api,
                            targetType: 'REEL',
                            targetId: postId,
                          ),
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
