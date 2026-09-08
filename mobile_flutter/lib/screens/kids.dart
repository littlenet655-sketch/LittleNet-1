import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../widgets.dart';
import 'kids_feed.dart';
import 'kids_learning.dart';

class KidsShell extends StatefulWidget {
  const KidsShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<KidsShell> createState() => _KidsShellState();
}

class _KidsShellState extends State<KidsShell> {
  int index = 0;
  int refreshToken = 0;

  void refreshAll() => setState(() => refreshToken++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      KidsHomePage(api: widget.api, refreshToken: refreshToken, onRefreshAll: refreshAll),
      DiscoverPage(api: widget.api, refreshToken: refreshToken),
      CreatePostPage(api: widget.api, onCreated: () {
        refreshAll();
        setState(() => index = 0);
      }),
      ReelsPage(api: widget.api, refreshToken: refreshToken),
      ProfilePage(api: widget.api, user: widget.user, onLogout: widget.onLogout, refreshToken: refreshToken),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index == 0
          ? FloatingActionButton.small(
              tooltip: 'Messages',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MessagesPage(api: widget.api)),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), selectedIcon: Icon(Icons.add_box_rounded), label: 'Create'),
          NavigationDestination(icon: Icon(Icons.smart_display_outlined), selectedIcon: Icon(Icons.smart_display_rounded), label: 'Reels'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final search = TextEditingController();
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DiscoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/discover', query: {'q': search.text.trim()});
      });

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search your safe network',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.arrow_forward_rounded)),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(friendlyError(snapshot.error!)));
                }
                final data = snapshot.data ?? const {};
                final kids = listMaps(data['children']);
                final posts = listMaps(data['posts']);
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                    children: [
                      if (data['pii_warning'] == true)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.shield_outlined),
                            title: Text('Search kept private'),
                            subtitle: Text('Phone numbers, addresses and private contact details cannot be searched.'),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 12, 6, 8),
                        child: Text('People', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                      ),
                      if (kids.isEmpty)
                        const Padding(padding: EdgeInsets.all(18), child: Text('No children are available in your approved network.')),
                      ...kids.map((kid) => _PersonCard(api: widget.api, kid: kid, onChanged: _load)),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 18, 6, 8),
                        child: Text('Safe posts', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                      ),
                      ...posts.map((post) => PostCard(api: widget.api, post: post, onChanged: _load)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.api, required this.kid, required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> kid;
  final VoidCallback onChanged;

  Future<void> _toggle(BuildContext context) async {
    try {
      await api.postJson('/api/mobile/v1/kids/follow/${kid['user_id']}', const {});
      onChanged();
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Avatar(api: api, url: kid['avatar_url']?.toString(), radius: 24),
        title: Text(kid['full_name']?.toString() ?? 'LittleNet friend', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(kid['recommendation_reason']?.toString() ?? 'Approved network'),
        trailing: FilledButton.tonal(
          onPressed: _toggle == null ? null : () => _toggle(context),
          child: Text(kid['is_following'] == true ? 'Friends' : kid['is_pending'] == true ? 'Pending' : 'Connect'),
        ),
      ),
    );
  }
}

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key, required this.api, required this.onCreated});
  final ApiClient api;
  final VoidCallback onCreated;

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final caption = TextEditingController();
  final picker = ImagePicker();
  XFile? media;
  String kind = 'post';
  String category = 'Other';
  String audience = 'ALL';
  bool busy = false;

  static const categories = ['Other','Science','Math','Art','Sports','Music','Technology','Education','Nature','Books','Coding','General Knowledge'];

  Future<void> _pick(ImageSource source, {bool video = false}) async {
    final selected = video
        ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 90))
        : await picker.pickImage(source: source, imageQuality: 88, maxWidth: 1800);
    if (selected != null) setState(() => media = selected);
  }

  Future<void> _submit() async {
    if (busy) return;
    if (caption.text.trim().isEmpty && media == null) {
      toast(context, 'Add a caption, photo or video first.');
      return;
    }
    setState(() => busy = true);
    try {
      final result = await widget.api.uploadPost(
        kind: kind,
        caption: caption.text.trim(),
        category: category,
        audience: audience,
        media: media == null ? null : File(media!.path),
      );
      if (!mounted) return;
      final status = result['status']?.toString() ?? 'ALLOW';
      toast(context, status == 'REVIEW' ? 'Uploaded and waiting for safety review.' : 'Published safely!');
      caption.clear();
      setState(() => media = null);
      widget.onCreated();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          const Text('Create', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'post', label: Text('Post'), icon: Icon(Icons.photo_outlined)),
              ButtonSegment(value: 'story', label: Text('Story'), icon: Icon(Icons.history_toggle_off_rounded)),
              ButtonSegment(value: 'reel', label: Text('Reel'), icon: Icon(Icons.smart_display_outlined)),
            ],
            selected: {kind},
            onSelectionChanged: (value) => setState(() => kind = value.first),
          ),
          const SizedBox(height: 16),
          if (media != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.attachment_rounded),
                title: Text(media!.name),
                subtitle: const Text('Selected from this phone'),
                trailing: IconButton(onPressed: () => setState(() => media = null), icon: const Icon(Icons.close_rounded)),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Camera photo')),
              OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery photo')),
              OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera, video: true), icon: const Icon(Icons.videocam_outlined), label: const Text('Camera video')),
              OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery, video: true), icon: const Icon(Icons.video_library_outlined), label: const Text('Gallery video')),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: caption, maxLines: 4, maxLength: 1500, decoration: const InputDecoration(labelText: 'Caption', hintText: 'Share something kind, creative or educational…')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: audience,
            decoration: const InputDecoration(labelText: 'Age audience'),
            items: const ['ALL','6-8','9-11','12-13','14-18'].map((v) => DropdownMenuItem(value: v, child: Text(v == 'ALL' ? 'All allowed ages' : v))).toList(),
            onChanged: (v) => setState(() => audience = v ?? 'ALL'),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : _submit,
            icon: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shield_rounded),
            label: Text(busy ? 'Safety checking…' : 'Safety check & publish'),
          ),
          const SizedBox(height: 8),
          const Text('LittleNet checks text, photos and video before other children can see them.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/messages'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
          final rows = listMaps(snapshot.data?['conversations']);
          if (rows.isEmpty) return const Center(child: Text('Connect with an approved friend to start chatting.'));
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final row = rows[i];
                final last = Map<String, dynamic>.from(row['last_message'] as Map? ?? const {});
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Avatar(api: widget.api, url: row['peer_avatar_url']?.toString(), radius: 25),
                  title: Text(row['peer_name']?.toString() ?? 'Friend', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(last['message_text']?.toString() ?? (last['message_type'] == null ? 'Start a safe chat' : 'Shared media')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatPage(api: widget.api, peerId: asInt(row['peer_id']), peerName: row['peer_name']?.toString() ?? 'Friend')));
                    _load();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.api, required this.peerId, required this.peerName});
  final ApiClient api;
  final int peerId;
  final String peerName;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  Future<Map<String, dynamic>>? future;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/chat/${widget.peerId}'));

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final result = await widget.api.postJson('/api/mobile/v1/kids/chat/${widget.peerId}', {'message_text': text});
      input.clear();
      if (mounted && result['status'] == 'REVIEW') toast(context, 'Message is checking for safety.');
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
                final rows = listMaps(snapshot.data?['messages']);
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: rows.length,
                    itemBuilder: (_, reverseIndex) {
                      final item = rows[rows.length - 1 - reverseIndex];
                      final mine = asInt(item['receiver_child_id']) == widget.peerId;
                      final text = item['message_text']?.toString();
                      final media = item['media_url']?.toString();
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: mine ? const Color(0xFF2563EB) : const Color(0xFFEFF3F8),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (media != null) SizedBox(height: 180, width: 240, child: NativeMedia(api: widget.api, url: media, mediaType: item['message_type']?.toString(), autoPlay: false)),
                              if (text != null && text.isNotEmpty) Text(text, style: TextStyle(color: mine ? Colors.white : Colors.black87)),
                              if (item['moderation_status'] == 'REVIEW') Padding(padding: const EdgeInsets.only(top: 5), child: Text('Checking for safety…', style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : Colors.black54))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: input, maxLength: 1000, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: const InputDecoration(counterText: '', hintText: 'Message safely…'))),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: sending ? null : _send, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.api, required this.user, required this.onLogout, required this.refreshToken});
  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  final int refreshToken;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() => future = widget.api.getJson('/api/mobile/v1/kids/profile'));

  Future<void> _edit(Map<String, dynamic> profile) async {
    final name = TextEditingController(text: profile['full_name']?.toString() ?? '');
    final bio = TextEditingController(text: profile['bio']?.toString() ?? '');
    final school = TextEditingController(text: profile['school_name']?.toString() ?? '');
    final klass = TextEditingController(text: profile['current_class']?.toString() ?? '');
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: bio, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio')),
            const SizedBox(height: 10),
            TextField(controller: school, decoration: const InputDecoration(labelText: 'School')),
            const SizedBox(height: 10),
            TextField(controller: klass, decoration: const InputDecoration(labelText: 'Class')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, {'full_name': name.text.trim(), 'bio': bio.text.trim(), 'school_name': school.text.trim(), 'current_class': klass.text.trim()}), child: const Text('Save')),
        ],
      ),
    );
    for (final c in [name, bio, school, klass]) c.dispose();
    if (data == null) return;
    try {
      await widget.api.putJson('/api/mobile/v1/kids/profile', data);
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
          final data = snapshot.data ?? const {};
          final profile = Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
          final counts = Map<String, dynamic>.from(data['counts'] as Map? ?? const {});
          final posts = listMaps(data['posts']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                Row(children: [
                  Avatar(api: widget.api, url: profile['avatar_url']?.toString(), radius: 42),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile['full_name']?.toString() ?? widget.user['full_name']?.toString() ?? 'Student', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    Text('@${widget.user['username'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text(profile['bio']?.toString() ?? ''),
                  ])),
                ]),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _Count(label: 'Posts', value: counts['posts']),
                  _Count(label: 'Friends', value: counts['followers']),
                  _Count(label: 'Minutes', value: data['minutes_today']),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => _edit(profile), icon: const Icon(Icons.edit_outlined), label: const Text('Edit profile'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearningScreen(api: widget.api))), icon: const Icon(Icons.school_outlined), label: const Text('Learning'))),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: widget.onLogout, icon: const Icon(Icons.logout_rounded), label: const Text('Log out')),
                const Divider(height: 28),
                const Text('My posts', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (posts.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No posts yet.'))),
                ...posts.map((post) => PostCard(api: widget.api, post: post, onChanged: _load)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});
  final String label;
  final dynamic value;
  @override
  Widget build(BuildContext context) => Column(children: [Text('${value ?? 0}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text(label, style: const TextStyle(color: Colors.black54))]);
}
