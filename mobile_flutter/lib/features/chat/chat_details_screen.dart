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
  bool _muteCalls = false;

  final List<String> _sharedMedia = [
    'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=200',
    'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=200',
    'https://images.unsplash.com/photo-1581092160607-ee22621dd758?w=200',
  ];

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
      body: ListView(
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

          // Notifications Switchers
          SwitchListTile(
            title: const Text('Mute Messages', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            value: _muteMessages,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() => _muteMessages = val);
            },
          ),
          SwitchListTile(
            title: const Text('Mute Call Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            value: _muteCalls,
            activeTrackColor: AppColors.primary,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() => _muteCalls = val);
            },
          ),

          const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

          // Shared Media Section
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
                  child: Image.network(_sharedMedia[i], width: 90, height: 90, fit: BoxFit.cover),
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
            onTap: () {
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Conversation reported to Guardian.')),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.block_rounded, color: Color(0xFFED4956), size: 22),
            title: Text(
              'Block ${widget.peerName}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFED4956)),
            ),
            onTap: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Blocked ${widget.peerName}.')),
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
