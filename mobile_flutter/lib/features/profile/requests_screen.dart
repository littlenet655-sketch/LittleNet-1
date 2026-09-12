import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient
          .get('/api/mobile/v1/kids/connections/requests');
      if (res['ok'] == true && mounted) {
        setState(() {
          _incoming = ((res['incoming'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          _outgoing = ((res['outgoing'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load connection requests.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAction(int requesterId, bool accept) async {
    try {
      final endpoint = accept
          ? '/child/follow-requests/$requesterId/accept/'
          : '/child/follow-requests/$requesterId/decline/';
      await widget.authState.apiClient.postJson(endpoint, const {});
      HapticFeedback.selectionClick();
      _loadRequests();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accept
                ? 'Could not accept connection request.'
                : 'Could not decline request.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelOutgoing(int targetId) async {
    try {
      await widget.authState.apiClient.postJson(
        '/api/mobile/v1/kids/follow/$targetId',
        const {},
      );
      HapticFeedback.selectionClick();
      _loadRequests();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel connection request.'),
            behavior: SnackBarBehavior.floating,
          ),
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
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF262626), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Connection Requests 🤝',
          style: TextStyle(
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
            Tab(text: 'Received (${_incoming.length})'),
            Tab(text: 'Sent (${_outgoing.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LnEmptyState(
                  emoji: '🛡️',
                  title: 'Requests unavailable',
                  subtitle: _error,
                  action: _loadRequests,
                  actionLabel: 'Try Again',
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildIncomingList(),
                    _buildOutgoingList(),
                  ],
                ),
    );
  }

  Widget _buildIncomingList() {
    if (_incoming.isEmpty) {
      return const LnEmptyState(
        emoji: '📫',
        title: 'No pending requests',
        subtitle:
            'When classmates send you connection requests, you will see them here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _incoming.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.4,
        indent: 72,
        endIndent: 16,
        color: Color(0xFFEEEEEE),
      ),
      itemBuilder: (context, index) {
        final req = _incoming[index];
        final name = req['requester_name'] as String? ?? 'Classmate';
        final username = req['requester_username'] as String? ?? 'student';
        final avatar = req['avatar_url'] as String?;
        final school = req['school_name'] as String?;
        final requesterId = req['requester_id'] as int? ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              LnAvatar(url: avatar, name: name, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF262626),
                      ),
                    ),
                    Text(
                      school != null && school.isNotEmpty
                          ? '@$username · $school'
                          : '@$username',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E8E8E)),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Requires Parent Approval 🛡️',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () => _handleAction(requesterId, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: const Size(60, 30),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Confirm',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () => _handleAction(requesterId, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8E8E8E),
                      side: const BorderSide(color: Color(0xFFDBDBDB)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(54, 30),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoing.isEmpty) {
      return const LnEmptyState(
        emoji: '📤',
        title: 'No outgoing requests',
        subtitle:
            'You haven\'t sent any pending connection requests to classmates.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _outgoing.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.4,
        indent: 72,
        endIndent: 16,
        color: Color(0xFFEEEEEE),
      ),
      itemBuilder: (context, index) {
        final req = _outgoing[index];
        final name = req['target_name'] as String? ?? 'Classmate';
        final username = req['target_username'] as String? ?? 'student';
        final avatar = req['avatar_url'] as String?;
        final school = req['school_name'] as String?;
        final targetId = req['target_id'] as int? ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              LnAvatar(url: avatar, name: name, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF262626),
                      ),
                    ),
                    Text(
                      school != null && school.isNotEmpty
                          ? '@$username · $school'
                          : '@$username',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E8E8E)),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Waiting for Parent Review ⏳',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFF59F00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _cancelOutgoing(targetId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8E8E8E),
                  side: const BorderSide(color: Color(0xFFDBDBDB)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(60, 30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Cancel',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }
}
