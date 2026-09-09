import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'kids.dart';

Future<bool> showReportSheet(
  BuildContext context, {
  required ApiClient api,
  required String targetType,
  required int targetId,
}) async {
  final note = TextEditingController();
  String? selected;
  final submit = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Report to LittleNet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose the reason that best describes the problem.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              for (final reason in const [
                'Bullying or harassment',
                'Unsafe or inappropriate content',
                'Sharing personal information',
                'Spam or unwanted contact',
                'Something else',
              ])
                RadioListTile<String>(
                  value: reason,
                  groupValue: selected,
                  title: Text(reason),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setSheetState(() => selected = value),
                ),
              TextField(
                controller: note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Optional note',
                  hintText: 'Tell the safety team what happened.',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Submit report'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (submit != true || selected == null) {
    note.dispose();
    return false;
  }
  try {
    await api.postJson('/api/mobile/v1/kids/reports', {
      'target_type': targetType,
      'target_id': targetId,
      'reason': selected,
      'details': note.text.trim(),
    });
    note.dispose();
    if (context.mounted) toast(context, 'Report submitted for safety review.');
    return true;
  } catch (e) {
    note.dispose();
    if (context.mounted) toast(context, friendlyError(e));
    return false;
  }
}

Future<void> showSharePostSheet(
  BuildContext context, {
  required ApiClient api,
  required int postId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Share with an approved friend',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: api.getJson('/api/mobile/v1/kids/friends'),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(friendlyError(snapshot.error!)));
                }
                final friends = listMaps(snapshot.data?['friends']);
                if (friends.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'No approved friends yet. Both parents must approve a connection before sharing.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: friends.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final friend = friends[index];
                    return ListTile(
                      leading: Avatar(
                        api: api,
                        url: friend['avatar_url']?.toString(),
                        radius: 23,
                      ),
                      title: Text(
                        friend['full_name']?.toString() ?? 'Friend',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('@${friend['username'] ?? ''}'),
                      trailing: const Icon(Icons.send_outlined),
                      onTap: () async {
                        try {
                          await api.postJson(
                            '/api/mobile/v1/kids/chat/${asInt(friend['user_id'])}/share',
                            {'post_id': postId},
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (context.mounted) toast(context, 'Sent safely.');
                        } catch (e) {
                          if (sheetContext.mounted) toast(sheetContext, friendlyError(e));
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.api, required this.postId});

  final ApiClient api;
  final int postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final comment = TextEditingController();
  Future<Map<String, dynamic>>? future;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/posts/${widget.postId}');
      });

  Future<void> _comment() async {
    final text = comment.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final result = await widget.api.postJson(
        '/api/mobile/v1/kids/posts/${widget.postId}/comment',
        {'text': text},
      );
      comment.clear();
      if (mounted && result['status'] == 'REVIEW') {
        toast(context, 'Your comment is waiting for a safety review.');
      }
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _toggle(String action) async {
    try {
      await widget.api.postJson(
        '/api/mobile/v1/kids/posts/${widget.postId}/$action',
        const {},
      );
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: AsyncBody(
        future: future,
        onRetry: _load,
        builder: (data) {
          final post = Map<String, dynamic>.from(data['post'] as Map? ?? const {});
          final comments = listMaps(data['comments']);
          final creatorId = asInt(post['child_id']);
          final media = post['media_url']?.toString();
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView(
                    children: [
                      ListTile(
                        leading: Avatar(
                          api: widget.api,
                          url: post['avatar_url']?.toString(),
                          radius: 22,
                        ),
                        title: Text(
                          post['full_name']?.toString() ?? 'LittleNet student',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('@${post['username'] ?? ''}'),
                        onTap: creatorId <= 0
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => OtherUserProfileScreen(
                                      api: widget.api,
                                      userId: creatorId,
                                    ),
                                  ),
                                ),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_horiz_rounded),
                          onPressed: () => showReportSheet(
                            context,
                            api: widget.api,
                            targetType: post['is_reel'] == true ? 'REEL' : 'POST',
                            targetId: widget.postId,
                          ),
                        ),
                      ),
                      if (media != null && media.isNotEmpty)
                        AspectRatio(
                          aspectRatio: post['is_reel'] == true ? 9 / 16 : 1,
                          child: NativeMedia(
                            api: widget.api,
                            url: media,
                            mediaType: post['media_type']?.toString(),
                            autoPlay: post['is_reel'] == true,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Like',
                              onPressed: () => _toggle('like'),
                              icon: Icon(
                                post['viewer_liked'] == true
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                              ),
                            ),
                            Text('${post['likes'] ?? 0}'),
                            IconButton(
                              tooltip: 'Comments',
                              onPressed: () => FocusScope.of(context).requestFocus(FocusNode()),
                              icon: const Icon(Icons.chat_bubble_outline_rounded),
                            ),
                            Text('${post['comments_count'] ?? comments.length}'),
                            IconButton(
                              tooltip: 'Share',
                              onPressed: () => showSharePostSheet(
                                context,
                                api: widget.api,
                                postId: widget.postId,
                              ),
                              icon: const Icon(Icons.send_outlined),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: post['viewer_saved'] == true ? 'Unsave' : 'Save',
                              onPressed: () => _toggle('save'),
                              icon: Icon(
                                post['viewer_saved'] == true
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((post['caption']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                          child: Text(post['caption'].toString()),
                        ),
                      const Divider(height: 1),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Comments',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (comments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No comments yet.')),
                        ),
                      for (final item in comments)
                        ListTile(
                          leading: Avatar(
                            api: widget.api,
                            url: item['avatar_url']?.toString(),
                            radius: 18,
                          ),
                          title: Text(
                            item['full_name']?.toString() ?? 'Student',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(item['comment_text']?.toString() ?? ''),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => OtherUserProfileScreen(
                                api: widget.api,
                                userId: asInt(item['child_id']),
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Report comment',
                            onPressed: () => showReportSheet(
                              context,
                              api: widget.api,
                              targetType: 'COMMENT',
                              targetId: asInt(item['comment_id']),
                            ),
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: comment,
                          maxLength: 800,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'Add a kind comment…',
                          ),
                          onSubmitted: (_) => _comment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: sending ? null : _comment,
                        icon: sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OtherUserProfileScreen extends StatefulWidget {
  const OtherUserProfileScreen({super.key, required this.api, required this.userId});

  final ApiClient api;
  final int userId;

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  Future<Map<String, dynamic>>? future;
  bool changing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/profiles/${widget.userId}');
      });

  Future<void> _follow() async {
    if (changing) return;
    setState(() => changing = true);
    try {
      await widget.api.postJson('/api/mobile/v1/kids/follow/${widget.userId}', const {});
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> _action(String action) async {
    try {
      await widget.api.postJson(
        '/api/mobile/v1/kids/profiles/${widget.userId}/actions',
        {'action': action},
      );
      if (!mounted) return;
      toast(context, action == 'BLOCK' ? 'User blocked.' : 'User muted.');
      if (action == 'BLOCK') Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'REPORT') {
                showReportSheet(
                  context,
                  api: widget.api,
                  targetType: 'USER',
                  targetId: widget.userId,
                );
              } else {
                _action(value);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'REPORT', child: Text('Report')),
              PopupMenuItem(value: 'MUTE', child: Text('Mute')),
              PopupMenuItem(value: 'BLOCK', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: AsyncBody(
        future: future,
        onRetry: _load,
        builder: (data) {
          final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
          final counts = Map<String, dynamic>.from(data['counts'] as Map? ?? const {});
          final relation = Map<String, dynamic>.from(data['relationship'] as Map? ?? const {});
          final interests = (data['interests'] as List? ?? const []).map((e) => e.toString()).toList();
          final posts = listMaps(data['posts']);
          final connected = relation['connected'] == true;
          final pending = relation['pending'] == true;
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                Row(
                  children: [
                    Avatar(
                      api: widget.api,
                      url: profile['avatar_url']?.toString(),
                      radius: 42,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile['full_name']?.toString() ?? 'LittleNet student',
                            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
                          ),
                          Text('@${profile['username'] ?? ''}'),
                          if ((profile['bio']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Text(profile['bio'].toString()),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ProfileCount(label: 'Posts', value: counts['posts']),
                    _ProfileCount(label: 'Friends', value: counts['followers']),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: changing ? null : _follow,
                        child: Text(connected ? 'Friends' : pending ? 'Requested' : 'Add friend'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: relation['can_message'] == true
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatPage(
                                      api: widget.api,
                                      peerId: widget.userId,
                                      peerName: profile['full_name']?.toString() ?? 'Friend',
                                    ),
                                  ),
                                )
                            : null,
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Message'),
                      ),
                    ),
                  ],
                ),
                if (interests.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: interests.map((item) => Chip(label: Text(item))).toList(),
                  ),
                ],
                const Divider(height: 30),
                const Text('Posts & Reels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No visible posts yet.')),
                  ),
                for (final post in posts)
                  _SavedItem(api: widget.api, post: post, onChanged: _load),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SavedContentScreen extends StatefulWidget {
  const SavedContentScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SavedContentScreen> createState() => _SavedContentScreenState();
}

class _SavedContentScreenState extends State<SavedContentScreen> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/saved'));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          bottom: const TabBar(tabs: [Text('Posts'), Text('Reels'), Text('Learning')]),
        ),
        body: AsyncBody(
          future: future,
          onRetry: _load,
          builder: (data) {
            final posts = listMaps(data['posts']);
            final reels = listMaps(data['reels']);
            final learning = listMaps(data['learning']);
            return TabBarView(
              children: [
                _SavedList(api: widget.api, items: posts, onChanged: _load, empty: 'No saved posts.'),
                _SavedList(api: widget.api, items: reels, onChanged: _load, empty: 'No saved Reels.'),
                learning.isEmpty
                    ? const Center(child: Text('No saved learning items yet.'))
                    : ListView(
                        children: learning
                            .map((item) => ListTile(title: Text(item['title']?.toString() ?? 'Learning item')))
                            .toList(),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SavedList extends StatelessWidget {
  const _SavedList({
    required this.api,
    required this.items,
    required this.onChanged,
    required this.empty,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> items;
  final VoidCallback onChanged;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Center(child: Text(empty));
    return RefreshIndicator(
      onRefresh: () async => onChanged(),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (_, index) => _SavedItem(
          api: api,
          post: items[index],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SavedItem extends StatelessWidget {
  const _SavedItem({required this.api, required this.post, required this.onChanged});

  final ApiClient api;
  final Map<String, dynamic> post;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final media = post['media_url']?.toString();
    final id = asInt(post['post_id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PostDetailScreen(api: api, postId: id)),
          );
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              if (media != null && media.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 82,
                    height: 82,
                    child: NativeMedia(
                      api: api,
                      url: media,
                      mediaType: post['media_type']?.toString(),
                      autoPlay: false,
                    ),
                  ),
                )
              else
                const SizedBox(width: 82, height: 82, child: Icon(Icons.notes_rounded, size: 36)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post['full_name']?.toString() ?? 'LittleNet',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      post['caption']?.toString() ?? (post['is_reel'] == true ? 'Reel' : 'Post'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from saved',
                onPressed: () async {
                  try {
                    await api.postJson('/api/mobile/v1/kids/posts/$id/save', const {});
                    onChanged();
                  } catch (e) {
                    if (context.mounted) toast(context, friendlyError(e));
                  }
                },
                icon: const Icon(Icons.bookmark_remove_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SafetyCentreScreen extends StatefulWidget {
  const SafetyCentreScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<SafetyCentreScreen> createState() => _SafetyCentreScreenState();
}

class _SafetyCentreScreenState extends State<SafetyCentreScreen> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/safety'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Centre')),
      body: AsyncBody(
        future: future,
        onRetry: _load,
        builder: (data) {
          final events = listMaps(data['events']);
          final reports = listMaps(data['reports']);
          final tips = (data['tips'] as List? ?? const []).map((e) => e.toString()).toList();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, size: 42),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('LittleNet Sentinel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                              Text('${events.length} recent safety events • ${reports.length} reports'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ReportHistoryScreen(api: widget.api)),
                  ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('My Reports'),
                ),
                const SizedBox(height: 18),
                const Text('Safety tips', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                for (final tip in tips)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline_rounded),
                    title: Text(tip),
                  ),
                const Divider(height: 30),
                const Text('Recent safety events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: Text('No recent safety events.')),
                  ),
                for (final event in events)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      event['decision'] == 'BLOCK'
                          ? Icons.block_rounded
                          : event['decision'] == 'REVIEW'
                              ? Icons.visibility_outlined
                              : Icons.verified_user_outlined,
                    ),
                    title: Text('${event['decision'] ?? 'SAFE'} • ${event['content_type'] ?? 'Content'}'),
                    subtitle: Text(event['reason']?.toString() ?? 'LittleNet safety check'),
                    trailing: Text(event['status']?.toString() ?? ''),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/reports'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: AsyncBody(
        future: future,
        onRetry: _load,
        builder: (data) {
          final rows = listMaps(data['reports']);
          if (rows.isEmpty) return const Center(child: Text('You have not submitted any reports.'));
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final report = rows[index];
                return ExpansionTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(report['reason']?.toString() ?? 'Safety report'),
                  subtitle: Text('${report['target_type'] ?? 'CONTENT'} • ${report['status'] ?? 'OPEN'}'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(report['details']?.toString() ?? 'No additional note.'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ProfileCount extends StatelessWidget {
  const _ProfileCount({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('${value ?? 0}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.black54)),
        ],
      );
}
