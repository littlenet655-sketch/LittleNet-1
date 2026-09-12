import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import 'incident_detail_screen.dart';

class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({
    super.key,
    required this.authState,
  });

  final AuthState authState;

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _selectedEventForSplitPane;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchQueue();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res =
          await widget.authState.apiClient.get('/api/mobile/v1/admin/reviews');
      if (res['ok'] == true && mounted) {
        final list = res['events'] as List? ?? [];
        setState(() {
          _events = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
          if (_selectedEventForSplitPane != null) {
            final stillExists = _events.any((e) =>
                e['event_id'] == _selectedEventForSplitPane!['event_id']);
            if (!stillExists) {
              _selectedEventForSplitPane =
                  _events.isNotEmpty ? _events.first : null;
            }
          } else if (_events.isNotEmpty) {
            _selectedEventForSplitPane = _events.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to fetch moderation queue.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _quickAction(
      int eventId, String action, String reasonText) async {
    try {
      final res = await widget.authState.apiClient.postJson(
        '/api/mobile/v1/admin/reviews/$eventId',
        {
          'action': action,
          'notes': 'Quick action: $action via queue',
        },
      );
      if (res['ok'] == true && mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'APPROVE'
                  ? 'Incident approved.'
                  : action == 'ESCALATE'
                      ? 'Incident escalated.'
                      : 'Incident blocked.',
            ),
            backgroundColor: action == 'APPROVE'
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action failed. Please try again.'),
            backgroundColor: Color(0xFFC62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterEvents(int tabIndex) {
    if (tabIndex == 1) {
      // Critical (risk score >= 70)
      return _events.where((e) {
        final score = double.tryParse(e['risk_score']?.toString() ?? '0') ?? 0;
        return score >= 70.0;
      }).toList();
    } else if (tabIndex == 2) {
      // Review Required (risk < 70)
      return _events.where((e) {
        final score = double.tryParse(e['risk_score']?.toString() ?? '0') ?? 0;
        return score < 70.0;
      }).toList();
    }
    return _events;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWideScreen = constraints.maxWidth >= 720;

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
                'Moderation Queue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                'Server-side Human Review Gate',
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
              tooltip: 'Reload Queue',
              onPressed: _fetchQueue,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF60A5FA),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF94A3B8),
            tabs: [
              Tab(
                text: 'All (${_events.length})',
              ),
              Tab(
                text: 'Critical (${_filterEvents(1).length})',
              ),
              Tab(
                text: 'Review (${_filterEvents(2).length})',
              ),
            ],
            onTap: (_) => setState(() {}),
          ),
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
                            color: Color(0xFF64748B),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _fetchQueue,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : isWideScreen
                    ? _buildSplitPaneView()
                    : _buildMobileListView(),
      );
    });
  }

  Widget _buildMobileListView() {
    final filtered = _filterEvents(_tabController.index);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF10B981),
              size: 56,
            ),
            const SizedBox(height: 14),
            const Text(
              'No Cases in This Category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All items processed according to LittleNet safety rules.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _fetchQueue,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchQueue,
      color: const Color(0xFF0F172A),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final ev = filtered[index];
          return _buildQueueCard(ev, isSelected: false, isWide: false);
        },
      ),
    );
  }

  Widget _buildSplitPaneView() {
    final filtered = _filterEvents(_tabController.index);

    return Row(
      children: [
        // Left pane: List
        SizedBox(
          width: 380,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Queue is clear',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final ev = filtered[index];
                      final isSelected =
                          _selectedEventForSplitPane?['event_id'] ==
                              ev['event_id'];
                      return _buildQueueCard(ev,
                          isSelected: isSelected, isWide: true);
                    },
                  ),
          ),
        ),

        // Right pane: Detail
        Expanded(
          child: _selectedEventForSplitPane == null
              ? const Center(
                  child: Text(
                    'Select an incident from the queue to review.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : IncidentDetailScreen(
                  key: ValueKey(
                      _selectedEventForSplitPane!['event_id'] as int? ?? 0),
                  authState: widget.authState,
                  eventId:
                      _selectedEventForSplitPane!['event_id'] as int? ?? 0,
                  initialEvent: _selectedEventForSplitPane,
                ),
        ),
      ],
    );
  }

  Widget _buildQueueCard(
    Map<String, dynamic> ev, {
    required bool isSelected,
    required bool isWide,
  }) {
    final eventId = ev['event_id'] as int? ?? 0;
    final childName =
        ev['full_name'] as String? ?? 'Child #${ev['child_id'] ?? ''}';
    final username = ev['username'] as String? ?? 'user';
    final contentType = ev['content_type'] as String? ?? 'CONTENT';
    final reason = ev['reason'] as String? ?? 'Pending Safety Review';
    final riskScore = ev['risk_score'] != null
        ? double.tryParse(ev['risk_score'].toString()) ?? 0.0
        : 0.0;
    final isCritical = riskScore >= 70.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF3B82F6)
              : isCritical
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : (isCritical ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (isWide) {
              setState(() => _selectedEventForSplitPane = ev);
            } else {
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
                _fetchQueue();
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
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
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            childName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '@$username · $contentType',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCritical
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFFEF9C3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Risk: ${riskScore.toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCritical
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF854D0E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Event ID #$eventId · ${ev['created_at'] ?? 'Pending'}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _quickAction(eventId, 'BLOCK', 'Quick Block'),
                        child: const Text(
                          'Block',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _quickAction(eventId, 'ESCALATE', 'Quick Escalate'),
                        child: const Text(
                          'Escalate',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _quickAction(eventId, 'APPROVE', 'Quick Approve'),
                        child: const Text(
                          'Approve',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
