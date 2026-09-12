import 'package:flutter/material.dart';
import '../../core/auth/auth_state.dart';
import 'incident_detail_screen.dart';

class ModeratorDashboardScreen extends StatefulWidget {
  const ModeratorDashboardScreen({
    super.key,
    required this.authState,
    this.onNavigateTab,
  });

  final AuthState authState;
  final void Function(int tabIndex)? onNavigateTab;

  @override
  State<ModeratorDashboardScreen> createState() =>
      _ModeratorDashboardScreenState();
}

class _ModeratorDashboardScreenState extends State<ModeratorDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _counts = {};
  List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
  }

  Future<void> _fetchDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dashFuture =
          widget.authState.apiClient.get('/api/mobile/v1/admin/dashboard');
      final reviewsFuture =
          widget.authState.apiClient.get('/api/mobile/v1/admin/reviews');

      final results = await Future.wait([dashFuture, reviewsFuture]);
      final dashRes = results[0];
      final reviewsRes = results[1];

      if (mounted) {
        setState(() {
          if (dashRes['ok'] == true && dashRes['counts'] != null) {
            _counts = Map<String, dynamic>.from(dashRes['counts'] as Map);
          }
          if (reviewsRes['ok'] == true && reviewsRes['events'] != null) {
            final list = reviewsRes['events'] as List? ?? [];
            _recentEvents = list
                .map((e) => Map<String, dynamic>.from(e as Map))
                .take(5)
                .toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load moderation metrics.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFF60A5FA),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LittleNet Operations',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Child Safety & Compliance Console',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Metrics',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFCBD5E1)),
            onPressed: _fetchDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0F172A),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchDashboard,
              color: const Color(0xFF0F172A),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Color(0xFF991B1B), fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: _fetchDashboard,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),

                  // Header status banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'SAFETY ENGINE ACTIVE',
                              style: TextStyle(
                                color: Color(0xFF86EFAC),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Open Reviews: ${_counts['open_reviews'] ?? 0}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Automated AI Pipeline Guarded',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Text, Media, and Voice events are scanned multi-layer before display.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Operational KPI grid
                  const Text(
                    'OPERATIONAL METRICS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _buildKpiCard(
                        title: 'Open Reviews',
                        value: '${_counts['open_reviews'] ?? 0}',
                        subtitle: 'Pending human gate',
                        icon: Icons.pending_actions_rounded,
                        accentColor: const Color(0xFFEAB308),
                        onTap: () => widget.onNavigateTab?.call(1),
                      ),
                      _buildKpiCard(
                        title: 'Enrolled Children',
                        value: '${_counts['children'] ?? 0}',
                        subtitle: 'Monitored accounts',
                        icon: Icons.child_care_rounded,
                        accentColor: const Color(0xFF3B82F6),
                        onTap: () => widget.onNavigateTab?.call(2),
                      ),
                      _buildKpiCard(
                        title: 'Verified Parents',
                        value: '${_counts['parents'] ?? 0}',
                        subtitle: 'Liveness approved',
                        icon: Icons.supervised_user_circle_rounded,
                        accentColor: const Color(0xFF10B981),
                        onTap: () => widget.onNavigateTab?.call(2),
                      ),
                      _buildKpiCard(
                        title: 'Total Directory',
                        value: '${_counts['users'] ?? 0}',
                        subtitle: 'Platform users',
                        icon: Icons.people_outline_rounded,
                        accentColor: const Color(0xFF8B5CF6),
                        onTap: () => widget.onNavigateTab?.call(2),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Shortcuts row
                  const Text(
                    'QUICK SHORTCUTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildShortcutButton(
                          icon: Icons.rule_folder_rounded,
                          label: 'Incident Queue',
                          color: const Color(0xFF0F172A),
                          onTap: () => widget.onNavigateTab?.call(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildShortcutButton(
                          icon: Icons.manage_accounts_rounded,
                          label: 'User Admin',
                          color: const Color(0xFF1E293B),
                          onTap: () => widget.onNavigateTab?.call(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildShortcutButton(
                          icon: Icons.history_edu_rounded,
                          label: 'Audit Log',
                          color: const Color(0xFF334155),
                          onTap: () => widget.onNavigateTab?.call(3),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Recent Incidents Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'RECENT INCIDENTS IN QUEUE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.8,
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onNavigateTab?.call(1),
                        child: const Text(
                          'View All Queue',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (_recentEvents.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF10B981),
                            size: 36,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Moderation Queue Is Clear',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'All incoming items have been processed by server rules.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._recentEvents.map((ev) => _buildIncidentTile(ev)),
                ],
              ),
            ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                Icon(icon, size: 18, color: accentColor),
              ],
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentTile(Map<String, dynamic> ev) {
    final eventId = ev['event_id'] as int? ?? 0;
    final childName =
        ev['full_name'] as String? ?? 'Child #${ev['child_id'] ?? ''}';
    final contentType = ev['content_type'] as String? ?? 'CONTENT';
    final reason = ev['reason'] as String? ?? 'Safety review';
    final riskScore = ev['risk_score'] != null
        ? double.tryParse(ev['risk_score'].toString()) ?? 0.0
        : 0.0;
    final isCritical = riskScore >= 70.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCritical ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          width: isCritical ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isCritical
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFF1F5F9),
          child: Icon(
            contentType == 'IMAGE'
                ? Icons.image_rounded
                : contentType == 'VIDEO'
                    ? Icons.videocam_rounded
                    : Icons.text_snippet_rounded,
            color: isCritical
                ? const Color(0xFFDC2626)
                : const Color(0xFF475569),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                childName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCritical
                    ? const Color(0xFFFEE2E2)
                    : const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isCritical ? 'CRITICAL (${riskScore.toInt()}%)' : 'REVIEW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isCritical
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF854D0E),
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$contentType · ${ev['created_at'] ?? 'Just now'}',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFF94A3B8),
        ),
        onTap: () async {
          final res = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => IncidentDetailScreen(
                authState: widget.authState,
                eventId: eventId,
                initialEvent: ev,
              ),
            ),
          );
          if (res == true) {
            _fetchDashboard();
          }
        },
      ),
    );
  }
}
