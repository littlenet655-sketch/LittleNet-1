import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';

/// Screen 34: Chat Details & Safety Controls (Instagram-for-Kids style)
class ChatDetailsScreen extends StatefulWidget {
  const ChatDetailsScreen({
    super.key,
    required this.authState,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
  });

  final AuthState authState;
  final int peerId;
  final String peerName;
  final String? peerAvatarUrl;

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  bool _muteMessages = false;
  bool _isLoading = true;
  final List<String> _sharedMedia = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      // 1. Check mute status
      final mutedRes = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/muted-users',
      );
      final mutedList = (mutedRes['muted_users'] as List<dynamic>?) ?? [];
      final isMuted = mutedList.any(
        (u) => u is Map<String, dynamic> && u['user_id'] == widget.peerId,
      );

      // 2. Fetch shared media from chat
      final chatRes = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/chat/${widget.peerId}?limit=50',
      );
      final messages = (chatRes['messages'] as List<dynamic>?) ?? [];
      final mediaUrls = <String>[];
      for (final m in messages) {
        if (m is Map<String, dynamic>) {
          final url = m['media_url'] as String?;
          if (url != null && url.isNotEmpty) {
            mediaUrls.add(url);
          }
        }
      }

      if (mounted) {
        setState(() {
          _muteMessages = isMuted;
          _sharedMedia.clear();
          _sharedMedia.addAll(mediaUrls);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleMute(bool val) async {
    HapticFeedback.selectionClick();
    setState(() => _muteMessages = val);
    try {
      await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/mute/${widget.peerId}',
        body: {'action': val ? 'mute' : 'unmute'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(val ? 'Notifications muted for ${widget.peerName}' : 'Notifications unmuted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _muteMessages = !val);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update mute settings. Please try again.')),
        );
      }
    }
  }

  Future<void> _reportConversation() async {
    HapticFeedback.mediumImpact();
    final reasons = [
      'Mean or Bullying Words',
      'Asking for Private Information',
      'Uncomfortable Content',
      'Other Safety Concern',
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report Conversation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        children: reasons
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(r, style: const TextStyle(fontSize: 14)),
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected == null || !mounted) return;

    try {
      await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/report',
        body: {
          'target_type': 'USER',
          'target_id': widget.peerId,
          'reason': selected,
          'details': 'Reported via Chat Details',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted to Guardian and Safety team.'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit report. Please check your connection.')),
        );
      }
    }
  }

  Future<void> _blockUser() async {
    HapticFeedback.heavyImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${widget.peerName}?'),
        content: Text(
          'You will no longer be able to message each other, and you will not see each other\'s posts or profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFED4956),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/block/${widget.peerId}',
        body: {'action': 'block'},
      );
      if (mounted) {
        // Pop back to conversations list so the blocked conversation is exited immediately
        Navigator.of(context).popUntil((route) => route.settings.name == '/kids/messages' || route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blocked ${widget.peerName}.'),
            backgroundColor: const Color(0xFFED4956),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not block user. Please check your connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF262626)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF262626),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 24),

                // Profile Center Card
                Center(
                  child: Column(
                    children: [
                      LnAvatar(
                        url: widget.peerAvatarUrl,
                        name: widget.peerName,
                        radius: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.peerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF262626),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 14),
                            SizedBox(width: 5),
                            Text(
                              'Verified Classmate • Sentinel Protected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

                // Notifications Switcher (real backend API wired)
                SwitchListTile(
                  title: const Text('Mute Messages', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  value: _muteMessages,
                  activeTrackColor: AppColors.primary,
                  onChanged: _toggleMute,
                ),

                const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

                // Shared Media Section (real media only, no fake demo links)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Shared Photos & Files',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF262626)),
                      ),
                      Text(
                        '${_sharedMedia.length}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E8E)),
                      ),
                    ],
                  ),
                ),
                if (_sharedMedia.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      'No shared photos or files yet.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8E8E8E), fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _sharedMedia.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _sharedMedia[i],
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 90,
                              height: 90,
                              color: const Color(0xFFEEEEEE),
                              child: const Icon(Icons.broken_image_rounded, color: Color(0xFF8E8E8E)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),
                const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

                // Safety & Moderation Actions
                ListTile(
                  leading: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                  title: const Text(
                    'Safety & Parental Controls',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF262626)),
                  ),
                  subtitle: const Text(
                    'All messages undergo real-time PII & cyberbullying filtering.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8E8E8E)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E8E)),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat is actively supervised by Sentinel AI & Linked Guardians.')),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.flag_rounded, color: Color(0xFFED4956), size: 22),
                  title: const Text(
                    'Report Conversation',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFED4956)),
                  ),
                  subtitle: const Text(
                    'Notify parent or teacher about uncomfortable behavior.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8E8E8E)),
                  ),
                  onTap: _reportConversation,
                ),

                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Color(0xFFED4956), size: 22),
                  title: Text(
                    'Block ${widget.peerName}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFED4956)),
                  ),
                  onTap: _blockUser,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
