import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';

/// Screen 14: Share / Direct Send Sheet (Instagram-for-Kids style)
class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.authState,
    this.postId,
    this.postTitle,
  });

  final AuthState authState;
  final int? postId;
  final String? postTitle;

  static Future<void> show(
    BuildContext context, {
    required AuthState authState,
    int? postId,
    String? postTitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(
        authState: authState,
        postId: postId,
        postTitle: postTitle,
      ),
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _sentIds = {};

  final List<Map<String, dynamic>> _mockClassmates = [
    {
      'id': 1,
      'name': 'Maya Patel',
      'handle': '@maya_draws',
      'grade': 'Class 4B',
      'avatar': 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=150',
    },
    {
      'id': 2,
      'name': 'Leo Tanaka',
      'handle': '@leo_robotics',
      'grade': 'STEM Club',
      'avatar': 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
    },
    {
      'id': 3,
      'name': 'Chloe Dupont',
      'handle': '@chloe_space',
      'grade': 'Class 4B',
      'avatar': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
    },
    {
      'id': 4,
      'name': 'Samir Al-Mansoor',
      'handle': '@samir_codes',
      'grade': 'Coding Lab',
      'avatar': 'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=150',
    },
    {
      'id': 5,
      'name': 'Zoe Washington',
      'handle': '@zoe_eco',
      'grade': 'Nature Squad',
      'avatar': 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=150',
    },
  ];

  String _filter = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _filter = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _sendDirect(int classmateId, String classmateName) {
    HapticFeedback.lightImpact();
    setState(() => _sentIds.add(classmateId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shared with $classmateName! 🚀'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _mockClassmates.where((c) {
      if (_filter.isEmpty) return true;
      final name = (c['name'] as String).toLowerCase();
      final handle = (c['handle'] as String).toLowerCase();
      return name.contains(_filter) || handle.contains(_filter);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDBDBDB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Share with Classmates',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF262626),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 13, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Verified Safe',
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

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search verified classmates...',
                  hintStyle: TextStyle(color: Color(0xFF8E8E8E), fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 20, color: Color(0xFF8E8E8E)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Classmates list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                thickness: 0.5,
                color: Color(0xFFEEEEEE),
              ),
              itemBuilder: (context, i) {
                final c = filtered[i];
                final id = c['id'] as int;
                final isSent = _sentIds.contains(id);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      LnAvatar(url: c['avatar'] as String?, name: c['name'] as String, radius: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['name'] as String,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF262626),
                              ),
                            ),
                            Text(
                              '${c['handle']} • ${c['grade']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E8E8E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: isSent ? null : () => _sendDirect(id, c['name'] as String),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSent ? const Color(0xFFF0F0F0) : AppColors.primary,
                          foregroundColor: isSent ? const Color(0xFF8E8E8E) : Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(72, 34),
                        ),
                        child: Text(
                          isSent ? 'Sent' : 'Send',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSent ? const Color(0xFF8E8E8E) : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom quick action row (Copy Link, Story, Guardian)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFDBDBDB), width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickAction(
                  icon: Icons.link_rounded,
                  label: 'Copy Link',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Safe project link copied!')),
                    );
                  },
                ),
                _buildQuickAction(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Add to Story',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).pushNamed(
                      '/kids/create-post',
                      arguments: {'kind': 'story'},
                    );
                  },
                ),
                _buildQuickAction(
                  icon: Icons.supervisor_account_outlined,
                  label: 'Send to Parent',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sent to Guardian for review!')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
            ),
            child: Icon(icon, color: const Color(0xFF262626), size: 22),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF262626), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
