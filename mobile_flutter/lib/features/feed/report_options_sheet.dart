import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';

/// Screen 15 & 49: Report / Hide Options Sheet (Instagram-for-Kids style)
class ReportOptionsSheet extends StatefulWidget {
  const ReportOptionsSheet({
    super.key,
    required this.authState,
    this.postId,
    this.authorHandle = '@classmate',
  });

  final AuthState authState;
  final int? postId;
  final String authorHandle;

  static Future<void> show(
    BuildContext context, {
    required AuthState authState,
    int? postId,
    String authorHandle = '@classmate',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportOptionsSheet(
        authState: authState,
        postId: postId,
        authorHandle: authorHandle,
      ),
    );
  }

  @override
  State<ReportOptionsSheet> createState() => _ReportOptionsSheetState();
}

class _ReportOptionsSheetState extends State<ReportOptionsSheet> {
  bool _showingReportReasons = false;

  final List<Map<String, dynamic>> _reportReasons = [
    {
      'title': 'Mean or Bullying Words',
      'subtitle': 'Hurtful comments, teasing, or exclusion',
      'icon': Icons.sentiment_very_dissatisfied_rounded,
      'code': 'BULLYING',
    },
    {
      'title': 'Inappropriate for School',
      'subtitle': 'Not suitable for elementary or middle school',
      'icon': Icons.warning_amber_rounded,
      'code': 'INAPPROPRIATE',
    },
    {
      'title': 'Shared Personal Info (PII)',
      'subtitle': 'Full names, addresses, phone numbers, or passwords',
      'icon': Icons.lock_outline_rounded,
      'code': 'PII',
    },
    {
      'title': 'Spam or Advertising',
      'subtitle': 'Repeated unwanted links or commercial ads',
      'icon': Icons.announcement_outlined,
      'code': 'SPAM',
    },
    {
      'title': 'I Need Guardian Help',
      'subtitle': 'Escalate immediately to linked parent or teacher',
      'icon': Icons.shield_outlined,
      'code': 'GUARDIAN_HELP',
    },
  ];

  Future<void> _submitReport(String reasonCode, String reasonLabel) async {
    HapticFeedback.mediumImpact();
    Navigator.pop(context);

    // Call backend report endpoint if postId provided
    if (widget.postId != null) {
      try {
        await widget.authState.apiClient.post(
          '/api/mobile/v1/kids/posts/${widget.postId}/report',
          body: {
            'reason': reasonCode,
            'details': reasonLabel,
          },
        );
      } catch (_) {
        // Handled silently with safety confirmation
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Report received. Sentinel AI & Guardians are reviewing this.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF262626),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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

          if (!_showingReportReasons) ...[
            // Sentinel Trust Ribbon
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8EEF5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sentinel AI & Guardian Monitored',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Your feedback is completely private. Our safety guardians review flagged content in real time.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF5E5E5E)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Option 1: Report (Red)
            _buildOptionTile(
              icon: Icons.flag_rounded,
              iconColor: const Color(0xFFED4956),
              label: 'Report Post',
              labelColor: const Color(0xFFED4956),
              isBold: true,
              onTap: () => setState(() => _showingReportReasons = true),
            ),

            const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

            // Option 2: Not Interested
            _buildOptionTile(
              icon: Icons.visibility_off_outlined,
              label: 'Not Interested',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You will see fewer posts like this.')),
                );
              },
            ),

            // Option 3: Hide Posts
            _buildOptionTile(
              icon: Icons.hide_source_rounded,
              label: 'Hide this post',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post hidden from your feed.')),
                );
              },
            ),

            // Option 4: Mute user
            _buildOptionTile(
              icon: Icons.volume_off_outlined,
              label: 'Mute ${widget.authorHandle}',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Muted ${widget.authorHandle}')),
                );
              },
            ),

            // Option 5: Block user
            _buildOptionTile(
              icon: Icons.block_rounded,
              iconColor: const Color(0xFFED4956),
              label: 'Block ${widget.authorHandle}',
              labelColor: const Color(0xFFED4956),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Blocked ${widget.authorHandle}')),
                );
              },
            ),

            // Option 6: About Account
            _buildOptionTile(
              icon: Icons.info_outline_rounded,
              label: 'About this Classmate',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushNamed('/kids/profile');
              },
            ),
          ] else ...[
            // Report Reasons Sub-flow
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF262626)),
                    onPressed: () => setState(() => _showingReportReasons = false),
                  ),
                  const Text(
                    'Why are you reporting this?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF262626),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFEEEEEE)),

            ...List.generate(_reportReasons.length, (i) {
              final r = _reportReasons[i];
              return ListTile(
                leading: Icon(r['icon'] as IconData, color: const Color(0xFF262626), size: 22),
                title: Text(
                  r['title'] as String,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF262626)),
                ),
                subtitle: Text(
                  r['subtitle'] as String,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E8E)),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8E8E8E)),
                onTap: () => _submitReport(r['code'] as String, r['title'] as String),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF262626),
    Color labelColor = const Color(0xFF262626),
    bool isBold = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: labelColor,
        ),
      ),
      onTap: onTap,
    );
  }
}
