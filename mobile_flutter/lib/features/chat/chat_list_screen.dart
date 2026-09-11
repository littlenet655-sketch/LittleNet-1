import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';
import 'chat_conversation_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/messages',
      );
      final list = (res['conversations'] as List<dynamic>?) ?? [];
      setState(() {
        _conversations.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _conversations.add(item);
          }
        }
      });
    } on ApiException catch (e) {
      if (e.message.contains('messaging')) {
        setState(() => _error =
            'Messaging is currently restricted by your parent safety settings.');
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error =
          'Unable to connect to messaging. Please check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Messages 💬'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_rounded),
            tooltip: 'New Chat',
            onPressed: _openNewChatPicker,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadConversations,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined,
                  size: 48, color: AppColors.kidsAccent),
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: AppTypography.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: _loadConversations,
                child: const Text('Refresh Messages'),
              ),
            ],
          ),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.kidsAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_outline_rounded,
                  size: 56,
                  color: AppColors.kidsAccent,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('No Chats Yet', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Only parent-approved friends and classmates can chat with you on LittleNet.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textMutedDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_clock_outlined,
                        size: 20, color: AppColors.kidsAccent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Stranger messaging is permanently blocked to keep you safe.',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textMutedDark),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Start a Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.kidsAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: _openNewChatPicker,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: _conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final chat = _conversations[index];
          final peerName = chat['peer_name'] as String? ?? 'Friend';
          final peerUsername = chat['peer_username'] as String? ?? '';
          final peerId = chat['peer_id'] as int? ?? 0;
          final avatarUrl = chat['peer_avatar_url'] as String?;
          final lastMsg = chat['last_message'] as Map<String, dynamic>?;
          final lastText =
              lastMsg?['message_text'] as String? ?? 'No messages yet';

          return ListTile(
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text(
                      peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.kidsAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    )
                  : null,
            ),
            title: Text(
              peerUsername.isNotEmpty ? '$peerName (@$peerUsername)' : peerName,
              style: AppTypography.titleMedium,
            ),
            subtitle: Text(
              lastText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textMutedDark),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatConversationScreen(
                    authState: widget.authState,
                    peerId: peerId,
                    peerName: peerName,
                    peerAvatarUrl: avatarUrl,
                  ),
                ),
              );
              _loadConversations();
            },
          );
        },
      ),
    );
  }

  Future<void> _openNewChatPicker() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Start a Chat 💬',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pick an approved friend to message safely.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: widget.authState.apiClient.get('/api/mobile/v1/kids/connections'),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading friends: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final data = snapshot.data ?? {};
                    final following = ((data['following'] as List<dynamic>?) ?? [])
                        .whereType<Map<String, dynamic>>()
                        .toList();
                    final followers = ((data['followers'] as List<dynamic>?) ?? [])
                        .whereType<Map<String, dynamic>>()
                        .toList();

                    final Map<int, Map<String, dynamic>> combined = {};
                    for (final u in [...following, ...followers]) {
                      final uid = u['user_id'] as int?;
                      if (uid != null) combined[uid] = u;
                    }

                    final friends = combined.values.toList();
                    if (friends.isEmpty) {
                      return const Center(
                        child: Text(
                          'No approved friends yet.\nConnect with classmates first!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                      itemBuilder: (context, idx) {
                        final f = friends[idx];
                        final name = f['full_name']?.toString() ?? 'Friend';
                        final username = f['username']?.toString() ?? '';
                        final avatar = f['avatar_url'] as String?;
                        final fid = f['user_id'] as int;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
                            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                            child: avatar == null
                                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: AppColors.kidsAccent, fontWeight: FontWeight.bold))
                                : null,
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: username.isNotEmpty ? Text('@$username', style: const TextStyle(color: Colors.white54, fontSize: 12)) : null,
                          trailing: const Icon(Icons.send_rounded, color: AppColors.kidsAccent, size: 20),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatConversationScreen(
                                  authState: widget.authState,
                                  peerId: fid,
                                  peerName: name,
                                  peerAvatarUrl: avatar,
                                ),
                              ),
                            ).then((_) => _loadConversations());
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
      },
    );
  }
}
