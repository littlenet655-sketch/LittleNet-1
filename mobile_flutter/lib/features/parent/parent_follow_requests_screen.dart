import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentFollowRequestsScreen extends StatefulWidget {
  const ParentFollowRequestsScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ParentFollowRequestsScreen> createState() =>
      _ParentFollowRequestsScreenState();
}

class _ParentFollowRequestsScreenState
    extends State<ParentFollowRequestsScreen> {
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _processingKeys = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/parent/follow-requests',
      );
      if (res['ok'] == true) {
        final list = (res['pending'] as List<dynamic>?) ?? [];
        setState(() {
          _pendingRequests = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load pending follow requests.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAction(
    int childId,
    int targetId,
    String action,
  ) async {
    final key = '$childId-$targetId';
    if (_processingKeys.contains(key)) return;

    setState(() => _processingKeys.add(key));

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/parent/follow-requests/action',
        body: {
          'child_id': childId,
          'target_id': targetId,
          'action': action,
        },
      );

      if (!mounted) return;

      if (res['ok'] == true) {
        setState(() {
          _pendingRequests.removeWhere(
            (r) =>
                (r['child_id'] as num?)?.toInt() == childId &&
                (r['following_child_id'] as num?)?.toInt() == targetId,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'approve'
                  ? 'Connection approved! Safe direct chat is now enabled.'
                  : 'Connection request rejected.',
            ),
            backgroundColor:
                action == 'approve' ? AppColors.success : AppColors.error,
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action failed: ${e.message}'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to process follow request.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingKeys.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Connection Approvals'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ElevatedButton.icon(
                          onPressed: _loadRequests,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRequests,
                  color: AppColors.primary,
                  child: _pendingRequests.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _pendingRequests.length + 1,
                          itemBuilder: (ctx, idx) {
                            if (idx == 0) {
                              return _buildInfoBanner();
                            }
                            return _buildRequestCard(
                              _pendingRequests[idx - 1],
                            );
                          },
                        ),
                ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'LittleNet enforces parental connection approval before direct messaging is permitted. Unapproved contacts can never message your child.',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Icon(
                  Icons.people_outline,
                  size: 64,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No Pending Connection Requests',
                  style: AppTypography.headingLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'When other students request to connect with your child, they will appear here for your review.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final childId = (request['child_id'] as num?)?.toInt() ?? 0;
    final targetId = (request['following_child_id'] as num?)?.toInt() ?? 0;
    final childName = request['child_name'] as String? ?? 'Your Child';
    final peerName = request['peer_name'] as String? ?? 'Peer Student';
    final peerUsername = request['peer_username'] as String? ?? '';
    final peerAge = (request['peer_age'] as num?)?.toInt() ?? 0;
    final requestedAt = request['created_at'] as String? ?? '';

    final key = '$childId-$targetId';
    final isProcessing = _processingKeys.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:
            Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceLight,
                child: Text(
                  peerName.isNotEmpty ? peerName[0].toUpperCase() : 'P',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peerName,
                      style: AppTypography.headingMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@$peerUsername  •  Age $peerAge',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'for $childName',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (requestedAt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Requested: ${requestedAt.length > 10 ? requestedAt.substring(0, 10) : requestedAt}',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () => _handleAction(childId, targetId, 'reject'),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () => _handleAction(childId, targetId, 'approve'),
                  icon: isProcessing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
