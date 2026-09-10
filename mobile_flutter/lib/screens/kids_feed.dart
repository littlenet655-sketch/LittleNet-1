import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'kids_learning.dart';
import 'kids_onboarding.dart';

class KidsHomePage extends StatefulWidget {
  const KidsHomePage({
    super.key,
    required this.api,
    required this.refreshToken,
    required this.onRefreshAll,
  });

  final ApiClient api;
  final int refreshToken;
  final VoidCallback onRefreshAll;

  @override
  State<KidsHomePage> createState() => _KidsHomePageState();
}

class _KidsHomePageState extends State<KidsHomePage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant KidsHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/home');
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
            return GateAwareError(
              api: widget.api,
              error: snapshot.error!,
              onResolved: () {
                _load();
                widget.onRefreshAll();
              },
            );
          }
          final data = snapshot.data ?? const {};
          final profile = Map<String, dynamic>.from(
            data['profile'] as Map? ?? const {},
          );
          final stories = listMaps(data['stories']);
          final posts = listMaps(data['posts']);
          final suggestions = listMaps(data['suggested']);
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
                      Text(
                        'LittleNet',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  actions: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '${data['minutes_today'] ?? 0} min',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Learning',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LearningScreen(api: widget.api),
                        ),
                      ),
                      icon: const Icon(Icons.school_outlined),
                    ),
                    IconButton(
                      tooltip: 'Activity',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NotificationsScreen(api: widget.api),
                        ),
                      ),
                      icon: const Icon(Icons.favorite_border_rounded),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Text(
                      'Hi ${profile['full_name'] ?? 'there'} 👋',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (stories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 118,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: stories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => StoryBubble(
                          api: widget.api,
                          story: stories[i],
                        ),
                      ),
                    ),
                  ),
                if (suggestions.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text(
                        'Safe people to discover',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (suggestions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 104,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final user = suggestions[i];
                          return SizedBox(
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
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (posts.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text('Your safe feed is ready for new posts.'),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: posts.length,
                    itemBuilder: (_, i) => PostCard(
                      api: widget.api,
                      post: posts[i],
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

class StoryBubble extends StatelessWidget {
  const StoryBubble({super.key, required this.api, required this.story});
  final ApiClient api;
  final Map<String, dynamic> story;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryViewer(api: api, story: story)),
      ),
      child: SizedBox(
        width: 74,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: story['viewed'] == true
                      ? [Colors.grey.shade300, Colors.grey.shade400]
                      : [const Color(0xFF38BDF8), const Color(0xFF2563EB)],
                ),
              ),
              child: Avatar(
                api: api,
                url: story['avatar_url']?.toString(),
                radius: 29,
              ),
            ),
            const SizedBox(height: 5),
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
  }
}

class StoryViewer extends StatelessWidget {
  const StoryViewer({super.key, required this.api, required this.story});
  final ApiClient api;
  final Map<String, dynamic> story;

  @override
  Widget build(BuildContext context) {
    final media = story['media_url']?.toString();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(story['full_name']?.toString() ?? 'Story'),
      ),
      body: Center(
        child: media == null
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  story['caption']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 24),
                ),
              )
            : NativeMedia(
                api: api,
                url: media,
                mediaType: story['media_type']?.toString(),
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.api,
    required this.post,
    required this.onChanged,
  });

  final ApiClient api;
  final Map<String, dynamic> post;
  final VoidCallback onChanged;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool liked = widget.post['viewer_liked'] == true;
  late bool saved = widget.post['viewer_saved'] == true;
  late int likes = asInt(widget.post['likes']);
  bool busy = false;
  bool viewRecorded = false;

  Future<void> _toggleLike() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/${widget.post['post_id']}/like',
        const {},
      );
      setState(() {
        liked = data['liked'] == true;
        likes = asInt(data['likes']);
      });
    } catch (_) {
      if (mounted) toast(context, 'Could not update like.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleSave() async {
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/${widget.post['post_id']}/save',
        const {},
      );
      setState(() => saved = data['saved'] == true);
    } catch (_) {
      if (mounted) toast(context, 'Could not save this post.');
    }
  }

  Future<void> _comment() async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: 'Write a kind comment…',
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/${widget.post['post_id']}/comment',
        {'text': text},
      );
      if (mounted) {
        toast(
          context,
          data['status'] == 'REVIEW'
              ? 'Comment sent for safety review.'
              : 'Comment posted.',
        );
      }
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _markViewed() async {
    if (viewRecorded) return;
    viewRecorded = true;
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/feed-view/${widget.post['post_id']}',
        const {},
      );
      if (data['required'] == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QuizGateScreen(api: widget.api)),
        );
        widget.onChanged();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.post['media_url']?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markViewed());
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Avatar(
                    api: widget.api,
                    url: widget.post['avatar_url']?.toString(),
                    radius: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.post['full_name']?.toString() ??
                              'LittleNet Student',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.post['content_category']?.toString() ??
                              'Safe content',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (widget.post['moderation_status'] == 'REVIEW')
                    const Chip(
                      label: Text('In review'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            if (media != null)
              AspectRatio(
                aspectRatio: widget.post['media_type'] == 'VIDEO' ? 9 / 14 : 1,
                child: NativeMedia(
                  api: widget.api,
                  url: media,
                  mediaType: widget.post['media_type']?.toString(),
                ),
              ),
            if ((widget.post['caption']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
                child: Text(widget.post['caption'].toString()),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _toggleLike,
                    icon: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: liked ? Colors.red : null,
                    ),
                  ),
                  Text('$likes'),
                  IconButton(
                    onPressed: _comment,
                    icon: const Icon(Icons.mode_comment_outlined),
                  ),
                  Text('${widget.post['comments_count'] ?? 0}'),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleSave,
                    icon: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
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

class ReelsPage extends StatefulWidget {
  const ReelsPage({
    super.key,
    required this.api,
    required this.refreshToken,
  });

  final ApiClient api;
  final int refreshToken;

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReelsPage oldWidget) {
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
            return GateAwareError(
              api: widget.api,
              error: snapshot.error!,
              onResolved: _load,
            );
          }
          final reels = listMaps(snapshot.data?['reels']);
          if (reels.isEmpty) {
            return const Center(
                child: Text('No safe reels available right now.'));
          }
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            itemBuilder: (_, i) => ReelPane(api: widget.api, reel: reels[i]),
          );
        },
      ),
    );
  }
}

class ReelPane extends StatefulWidget {
  const ReelPane({super.key, required this.api, required this.reel});
  final ApiClient api;
  final Map<String, dynamic> reel;

  @override
  State<ReelPane> createState() => _ReelPaneState();
}

class _ReelPaneState extends State<ReelPane> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      try {
        final result = await widget.api.postJson(
          '/api/mobile/v1/kids/feed-view/${widget.reel['post_id']}',
          const {},
        );
        if (result['required'] == true && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => QuizGateScreen(api: widget.api),
            ),
          );
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.reel['media_url']?.toString();
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            NativeMedia(
              api: widget.api,
              url: url,
              mediaType: widget.reel['media_type']?.toString(),
              fit: BoxFit.contain,
            )
          else
            const Center(
              child: Icon(
                Icons.smart_display_rounded,
                color: Colors.white54,
                size: 80,
              ),
            ),
          Positioned(
            left: 18,
            right: 78,
            bottom: 26,
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
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
