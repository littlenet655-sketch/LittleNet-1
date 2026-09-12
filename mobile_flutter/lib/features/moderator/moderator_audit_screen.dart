import 'package:flutter/material.dart';
import '../../core/auth/auth_state.dart';

class ModeratorAuditScreen extends StatefulWidget {
  const ModeratorAuditScreen({
    super.key,
    required this.authState,
  });

  final AuthState authState;

  @override
  State<ModeratorAuditScreen> createState() => _ModeratorAuditScreenState();
}

class _ModeratorAuditScreenState extends State<ModeratorAuditScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
  }

  Future<void> _fetchAuditLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res =
          await widget.authState.apiClient.get('/api/mobile/v1/admin/audit');
      if (res['ok'] == true && mounted) {
        final list = res['events'] as List? ?? [];
        setState(() {
          _logs = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load audit logs.';
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audit & Compliance Trail',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Immutable Server Activity Records',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFCBD5E1)),
            tooltip: 'Reload Audit Log',
            onPressed: _fetchAuditLogs,
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
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _fetchAuditLogs,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No audit records found.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchAuditLogs,
                      color: const Color(0xFF0F172A),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return _buildAuditLogCard(log);
                        },
                      ),
                    ),
    );
  }

  Widget _buildAuditLogCard(Map<String, dynamic> log) {
    final activityType =
        log['activity_type']?.toString() ?? 'SYSTEM_EVENT';
    final createdAt = log['created_at']?.toString() ?? 'Unknown time';
    final childId = log['child_id'];
    final activityData = log['activity_data'];

    IconData icon = Icons.info_outline_rounded;
    Color iconColor = const Color(0xFF3B82F6);
    Color bgColor = const Color(0xFFEFF6FF);

    if (activityType.contains('BLOCK') || activityType.contains('SUSPEND')) {
      icon = Icons.block_rounded;
      iconColor = const Color(0xFFDC2626);
      bgColor = const Color(0xFFFEE2E2);
    } else if (activityType.contains('APPROVE') ||
        activityType.contains('ACTIVE') ||
        activityType.contains('CREATED')) {
      icon = Icons.check_circle_outline_rounded;
      iconColor = const Color(0xFF16A34A);
      bgColor = const Color(0xFFDCFCE7);
    } else if (activityType.contains('ESCALATE') ||
        activityType.contains('REVIEW')) {
      icon = Icons.warning_amber_rounded;
      iconColor = const Color(0xFFD97706);
      bgColor = const Color(0xFFFEF3C7);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: bgColor,
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        activityType,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    Text(
                      createdAt,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (childId != null)
                  Text(
                    'Target User / Child ID: #$childId',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                  ),
                if (activityData != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      activityData.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
