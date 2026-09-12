import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';

/// Screen 42: Notifications Centre (Instagram-for-Kids style)
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _selectedFilter = 0;
  final List<String> _filters = ['All', 'Social', 'Comments', 'Safety', 'Learning'];

  final List<Map<String, dynamic>> _mockNotifications = [
    {
      'id': 1,
      'type': 'follow_request',
      'user_name': 'Leo Tanaka',
      'handle': '@leo_robotics',
      'avatar': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
      'text': 'requested to follow you from STEM Robotics Club.',
      'time': '10m',
      'time_group': 'Today',
      'category': 'Social',
      'status': 'pending',
    },
    {
      'id': 2,
      'type': 'like',
      'user_name': 'Maya Patel',
      'handle': '@maya_draws',
      'avatar': 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=150',
      'text': 'liked your Mars Rover Science Project.',
      'time': '42m',
      'time_group': 'Today',
      'category': 'Social',
      'media_thumb': 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=150',
    },
    {
      'id': 3,
      'type': 'comment',
      'user_name': 'Chloe Dupont',
      'handle': '@chloe_space',
      'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'text': 'commented: "Awesome solar panel angles! ✨"',
      'time': '2h',
      'time_group': 'Today',
      'category': 'Comments',
      'media_thumb': 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=150',
    },
    {
      'id': 4,
      'type': 'safety',
      'user_name': 'Sentinel AI Shield',
      'avatar': null,
      'text': 'Approved your new story post for Lincoln Elementary Class 4B.',
      'time': '4h',
      'time_group': 'Today',
      'category': 'Safety',
    },
    {
      'id': 5,
      'type': 'learning',
      'user_name': 'STEM Learning Hub',
      'avatar': null,
      'text': 'You unlocked the "Solar System Pioneer" Quiz Badge! 🚀 (+50 XP)',
      'time': '1d',
      'time_group': 'This Week',
      'category': 'Learning',
    },
    {
      'id': 6,
      'type': 'like',
      'user_name': 'Samir Al-Mansoor',
      'handle': '@samir_codes',
      'avatar': 'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=150',
      'text': 'liked your Python Turtle animation.',
      'time': '2d',
      'time_group': 'This Week',
      'category': 'Social',
      'media_thumb': 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=150',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final activeFilterName = _filters[_selectedFilter];
    final filtered = _mockNotifications.where((n) {
      if (activeFilterName == 'All') return true;
      return n['category'] == activeFilterName;
    }).toList();

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
          'Notifications',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF262626),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF262626), size: 22),
            onPressed: () {},
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips (Pill Bar)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: _filters.length,
              itemBuilder: (ctx, i) {
                final isSelected = _selectedFilter == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedFilter = i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF262626) : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          if (_filters[i] == 'Safety') ...[
                            Icon(
                              Icons.verified_user_rounded,
                              size: 13,
                              color: isSelected ? Colors.white : AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _filters[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF262626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Notifications List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No notifications right now ✨',
                      style: TextStyle(color: Color(0xFF8E8E8E), fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final isToday = item['time_group'] == 'Today';
                      final showHeader = idx == 0 ||
                          filtered[idx - 1]['time_group'] != item['time_group'];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showHeader)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                isToday ? 'Today' : 'This Week',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF262626),
                                ),
                              ),
                            ),
                          _buildNotificationTile(item),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> item) {
    final type = item['type'] as String;
    final userName = item['user_name'] as String;
    final avatar = item['avatar'] as String?;
    final text = item['text'] as String;
    final time = item['time'] as String;
    final mediaThumb = item['media_thumb'] as String?;
    final isFollowRequest = type == 'follow_request';
    final isSafety = type == 'safety';
    final isLearning = type == 'learning';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar or Icon
          Stack(
            clipBehavior: Clip.none,
            children: [
              if (isSafety)
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F3FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 24),
                )
              else if (isLearning)
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF3E0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFF9500), size: 24),
                )
              else
                LnAvatar(url: avatar, name: userName, radius: 22),

              if (isFollowRequest)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_alt_1, size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 12),

          // Message Body
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Color(0xFF262626), height: 1.3),
                children: [
                  TextSpan(
                    text: userName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' $text '),
                  TextSpan(
                    text: time,
                    style: const TextStyle(color: Color(0xFF8E8E8E), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Trailing action or thumbnail
          if (isFollowRequest) ...[
            if (item['status'] == 'accepted')
              const Text(
                'Classmate',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8E8E8E)),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => item['status'] = 'accepted');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(60, 30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Confirm', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _mockNotifications.remove(item));
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(50, 30),
                      side: const BorderSide(color: Color(0xFFDBDBDB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Delete', style: TextStyle(fontSize: 12, color: Color(0xFF262626))),
                  ),
                ],
              ),
          ] else if (mediaThumb != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(mediaThumb, width: 44, height: 44, fit: BoxFit.cover),
            ),
        ],
      ),
    );
  }
}
