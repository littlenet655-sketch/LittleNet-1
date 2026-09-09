import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'kids.dart';
import 'stitch_social.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  Future<Map<String, dynamic>>? future;
  String query = '';
  final searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      future = widget.api.getJson('/api/mobile/v1/kids/friends');
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Safe Chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search approved friends…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          searchCtrl.clear();
                          setState(() => query = '');
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => query = val.trim().toLowerCase()),
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
                final allFriends = listMaps(snapshot.data?['friends']);
                final filtered = allFriends.where((f) {
                  if (query.isEmpty) return true;
                  final name = (f['full_name']?.toString() ?? '').toLowerCase();
                  final username = (f['username']?.toString() ?? '').toLowerCase();
                  return name.contains(query) || username.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No approved friends found.',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'You can only chat with classmates and friends approved by your parent.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final friend = filtered[i];
                    final friendId = asInt(friend['user_id']);
                    final friendName = friend['full_name']?.toString() ?? friend['username']?.toString() ?? 'Friend';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Avatar(
                        api: widget.api,
                        url: friend['avatar_url']?.toString(),
                        radius: 22,
                      ),
                      title: Text(
                        friendName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('@${friend['username'] ?? ''}'),
                      trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              api: widget.api,
                              peerId: friendId,
                              peerName: friendName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({
    super.key,
    required this.api,
    required this.peerId,
    required this.peerName,
  });

  final ApiClient api;
  final int peerId;
  final String peerName;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  Future<Map<String, dynamic>>? future;
  bool processing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      future = widget.api.getJson('/api/mobile/v1/kids/chat/${widget.peerId}/info');
    });
  }

  Future<void> _toggleAction(String action) async {
    setState(() => processing = true);
    try {
      await widget.api.postJson(
        '/api/mobile/v1/kids/profiles/${widget.peerId}/actions',
        {'action': action},
      );
      if (mounted) {
        toast(context, 'Updated successfully.');
        _load();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Details'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const {};
          final peer = Map<String, dynamic>.from(data['peer'] as Map? ?? const {});
          final isMuted = data['is_muted'] == true;
          final isBlocked = data['is_blocked'] == true;
          final sharedCount = asInt(data['shared_media_count']);
          final guidelines = (data['guidelines'] as List? ?? const []).cast<String>();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    Avatar(
                      api: widget.api,
                      url: peer['avatar_url']?.toString(),
                      radius: 46,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.peerName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '@${peer['username'] ?? ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    icon: Icon(isMuted ? Icons.notifications_off_rounded : Icons.notifications_rounded),
                    label: Text(isMuted ? 'Unmute' : 'Mute'),
                    onPressed: processing ? null : () => _toggleAction(isMuted ? 'UNMUTE' : 'MUTE'),
                  ),
                  OutlinedButton.icon(
                    icon: Icon(isBlocked ? Icons.lock_open_rounded : Icons.block_rounded, color: Colors.red),
                    label: Text(isBlocked ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.red)),
                    onPressed: processing ? null : () => _toggleAction(isBlocked ? 'UNBLOCK' : 'BLOCK'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.report_problem_outlined, color: Colors.orange),
                    label: const Text('Report', style: const TextStyle(color: Colors.orange)),
                    onPressed: () => showReportSheet(
                      context,
                      api: widget.api,
                      targetType: 'USER',
                      targetId: widget.peerId,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Child Safety Standards',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final rule in guidelines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                              Expanded(child: Text(rule, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.perm_media_outlined),
                title: const Text('Shared Media'),
                trailing: Text('$sharedCount items'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FriendsListScreen extends StatelessWidget {
  const FriendsListScreen({
    super.key,
    required this.api,
    required this.userId,
    this.initialTab = 0,
  });

  final ApiClient api;
  final int userId;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Connections'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Friends / Followers'),
              Tab(text: 'Following'),
            ],
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: api.getJson('/api/mobile/v1/kids/users/$userId/connections'),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(friendlyError(snapshot.error!)));
            }
            final data = snapshot.data ?? const {};
            final followers = listMaps(data['followers']);
            final following = listMaps(data['following']);

            return TabBarView(
              children: [
                _ConnectionListView(api: api, items: followers, emptyMsg: 'No followers yet.'),
                _ConnectionListView(api: api, items: following, emptyMsg: 'Not following anyone yet.'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConnectionListView extends StatelessWidget {
  const _ConnectionListView({required this.api, required this.items, required this.emptyMsg});

  final ApiClient api;
  final List<Map<String, dynamic>> items;
  final String emptyMsg;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyMsg));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        final id = asInt(item['user_id']);
        return ListTile(
          leading: Avatar(api: api, url: item['avatar_url']?.toString(), radius: 20),
          title: Text(item['full_name']?.toString() ?? item['username']?.toString() ?? 'Student', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('@${item['username'] ?? ''}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OtherUserProfileScreen(api: api, userId: id),
            ),
          ),
        );
      },
    );
  }
}

class FollowRequestsScreen extends StatelessWidget {
  const FollowRequestsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friend Requests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Incoming'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: api.getJson('/api/mobile/v1/kids/follow-requests'),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text(friendlyError(snapshot.error!)));
            }
            final data = snapshot.data ?? const {};
            final incoming = listMaps(data['incoming']);
            final outgoing = listMaps(data['outgoing']);

            return TabBarView(
              children: [
                _RequestsList(api: api, items: incoming, isIncoming: true),
                _RequestsList(api: api, items: outgoing, isIncoming: false),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({required this.api, required this.items, required this.isIncoming});

  final ApiClient api;
  final List<Map<String, dynamic>> items;
  final bool isIncoming;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(isIncoming ? 'No pending incoming requests.' : 'No sent requests.'),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        final id = asInt(item['user_id']);
        return ListTile(
          leading: Avatar(api: api, url: item['avatar_url']?.toString(), radius: 20),
          title: Text(
            item['full_name']?.toString() ?? item['username']?.toString() ?? 'Student',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('Pending parent verification', style: TextStyle(color: Colors.orange, fontSize: 12)),
          trailing: OutlinedButton(
            child: const Text('View'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OtherUserProfileScreen(api: api, userId: id)),
            ),
          ),
        );
      },
    );
  }
}

class SettingsLanguageScreen extends StatefulWidget {
  const SettingsLanguageScreen({super.key});

  @override
  State<SettingsLanguageScreen> createState() => _SettingsLanguageScreenState();
}

class _SettingsLanguageScreenState extends State<SettingsLanguageScreen> {
  String selectedLanguage = 'English';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Language'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Language / ಭಾಷೆ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('English (Default)'),
                  value: 'English',
                  groupValue: selectedLanguage,
                  onChanged: (v) => setState(() => selectedLanguage = v ?? 'English'),
                ),
                RadioListTile<String>(
                  title: const Text('ಕನ್ನಡ (Kannada)'),
                  value: 'Kannada',
                  groupValue: selectedLanguage,
                  onChanged: (v) => setState(() => selectedLanguage = v ?? 'Kannada'),
                ),
                RadioListTile<String>(
                  title: const Text('हिंदी (Hindi)'),
                  value: 'Hindi',
                  groupValue: selectedLanguage,
                  onChanged: (v) => setState(() => selectedLanguage = v ?? 'Hindi'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Safety & Well-being', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.timer_outlined),
                  title: Text('Daily Screen Time'),
                  subtitle: Text('Managed by Parent Dashboard'),
                ),
                ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('AI Content Protection'),
                  subtitle: Text('Active (High Security Mode)'),
                ),
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Data Privacy'),
                  subtitle: Text('Compliant with DPDP & COPPA rules'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'LittleNet v2.0.0 (Production Build)\nSafe Social Media for Children',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
