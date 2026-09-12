import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import '../chat/chat_conversation_screen.dart';

class FollowersFollowingScreen extends StatefulWidget {
  const FollowersFollowingScreen({
    super.key,
    required this.authState,
    this.initialTab = 0,
  });

  final AuthState authState;
  final int initialTab;

  @override
  State<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _suggested = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _loadConnections();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConnections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient
          .get('/api/mobile/v1/kids/connections');
      if (res['ok'] == true && mounted) {
        setState(() {
          _followers = ((res['followers'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          _following = ((res['following'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          _suggested = ((res['suggested'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load connections right now.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleConnect(Map<String, dynamic> person) async {
    final childId = person['user_id'] as int?;
    if (childId == null) return;

    try {
      final res = await widget.authState.apiClient.postJson(
        '/api/mobile/v1/kids/follow/$childId',
        const {},
      );
      if (res['ok'] == true && mounted) {
        final status = res['status'] as String?;
        setState(() {
          if (status == 'pending') {
            person['is_pending'] = true;
            person['is_following'] = false;
          } else if (status == 'removed') {
            person['is_pending'] = false;
            person['is_following'] = false;
            _following.removeWhere((p) => p['user_id'] == childId);
          }
        });
        HapticFeedback.selectionClick();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update connection under safety rules.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((p) {
      final name = (p['full_name'] as String? ?? '').toLowerCase();
      final username = (p['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF262626), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.authState.currentUser?.username ?? 'Connections',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF262626),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF262626),
          unselectedLabelColor: const Color(0xFF8E8E8E),
          indicatorColor: const Color(0xFF262626),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 1.5,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: '${_followers.length} Followers'),
            Tab(text: '${_following.length} Following'),
            const Tab(text: 'Suggested'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchCtrl,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: 'Search connections...',
                  hintStyle: const TextStyle(
                      fontSize: 14, color: Color(0xFF8E8E8E)),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF8E8E8E), size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: Color(0xFF8E8E8E)),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Color(0xFFDBDBDB)),

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LnEmptyState(
                        emoji: '🛡️',
                        title: 'Connections unavailable',
                        subtitle: _error,
                        action: _loadConnections,
                        actionLabel: 'Try Again',
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_filter(_followers), isFollowersTab: true),
                          _buildList(_filter(_following), isFollowingTab: true),
                          _buildList(_filter(_suggested), isSuggestedTab: true),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> people, {
    bool isFollowersTab = false,
    bool isFollowingTab = false,
    bool isSuggestedTab = false,
  }) {
    if (people.isEmpty) {
      return LnEmptyState(
        emoji: isSuggestedTab ? '🌟' : '👥',
        title: isSuggestedTab ? 'No suggestions right now' : 'No connections found',
        subtitle: isSuggestedTab
            ? 'You are connected with all classmates in your grade!'
            : 'Safe classmates you connect with will show up here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: people.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.4,
        indent: 72,
        endIndent: 16,
        color: Color(0xFFEEEEEE),
      ),
      itemBuilder: (context, index) {
        final p = people[index];
        final name = p['full_name'] as String? ?? 'Classmate';
        final username = p['username'] as String? ?? 'student';
        final avatar = p['avatar_url'] as String?;
        final school = p['school_name'] as String?;
        final isPending = p['is_pending'] == true;
        final userId = p['user_id'] as int? ?? 0;

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: LnAvatar(url: avatar, name: name, radius: 24),
          title: Text(
            name,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF262626),
            ),
          ),
          subtitle: Text(
            school != null && school.isNotEmpty
                ? '@$username · $school'
                : '@$username',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E8E)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isFollowingTab
              ? OutlinedButton(
                  onPressed: () => _toggleConnect(p),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF262626),
                    side: const BorderSide(color: Color(0xFFDBDBDB)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: const Size(76, 30),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Following',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                )
              : isSuggestedTab
                  ? isPending
                      ? OutlinedButton(
                          onPressed: () => _toggleConnect(p),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF59F00),
                            side: const BorderSide(color: Color(0xFFFFC107)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: const Size(76, 30),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Requested',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        )
                      : FilledButton(
                          onPressed: () => _toggleConnect(p),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            minimumSize: const Size(76, 30),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Connect',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        )
                  : IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 20, color: Color(0xFF262626)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatConversationScreen(
                              authState: widget.authState,
                              peerId: userId,
                              peerName: name,
                              peerAvatarUrl: avatar,
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
