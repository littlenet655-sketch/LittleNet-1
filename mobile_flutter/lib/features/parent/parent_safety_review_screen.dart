import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentSafetyReviewScreen extends StatefulWidget {
  const ParentSafetyReviewScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ParentSafetyReviewScreen> createState() =>
      _ParentSafetyReviewScreenState();
}

class _ParentSafetyReviewScreenState extends State<ParentSafetyReviewScreen> {
  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _error;
  final Set<int> _processingEvents = {};

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/parent/safety',
      );
      if (res['ok'] == true) {
        final list = (res['events'] as List<dynamic>?) ?? [];
        setState(() {
          _events = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load safety review queue.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAction(int eventId, String action) async {
    if (_processingEvents.contains(eventId)) return;

    setState(() => _processingEvents.add(eventId));

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/parent/safety/$eventId',
        body: {'action': action},
      );

      if (!mounted) return;

      if (res['ok'] == true) {
        setState(() {
          _events.removeWhere(
            (e) => (e['event_id'] as num?)?.toInt() == eventId,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'APPROVE'
                  ? 'Content approved and published.'
                  : 'Content blocked and hidden.',
            ),
            backgroundColor:
                action == 'APPROVE' ? AppColors.success : AppColors.error,
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
          content: Text('Failed to perform review action.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingEvents.remove(eventId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Parent Safety Queue'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadQueue,
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
                          onPressed: _loadQueue,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadQueue,
                  color: AppColors.primary,
                  child: _events.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: _events.length + 1,
                          itemBuilder: (ctx, idx) {
                            if (idx == 0) {
                              return _buildPolicyDisclaimer();
                            }
                            return _buildEventCard(_events[idx - 1]);
                          },
                        ),
                ),
    );
  }

  Widget _buildPolicyDisclaimer() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border:
            Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Only flagged content in REVIEW state can be examined. Severe violations blocked by automated AI safety cannot be unblocked to preserve child protection laws.',
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
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppColors.success,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Safety Queue Clear',
                  style: AppTypography.headingLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'No pending posts, comments, or messages require parental review.',
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

  Widget _buildEventCard(Map<String, dynamic> event) {
    final eventId = (event['event_id'] as num?)?.toInt() ?? 0;
    final childName = event['full_name'] as String? ?? 'Child';
    final contentType = event['content_type'] as String? ?? 'CONTENT';
    final reason = event['reason'] as String? ?? 'Safety check triggered';
    final createdAt = event['created_at'] as String? ?? '';
    final preview = event['preview'] as Map<String, dynamic>?;
    final isProcessing = _processingEvents.contains(eventId);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    contentType,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'by $childName',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  createdAt.length > 10
                      ? createdAt.substring(0, 10)
                      : createdAt,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceLight),
          // Content Preview
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reason for Flagging:',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildContentPreview(preview, contentType),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.surfaceLight),
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: isProcessing
                        ? null
                        : () => _handleAction(eventId, 'BLOCK'),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Block Content'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: isProcessing
                        ? null
                        : () => _handleAction(eventId, 'APPROVE'),
                    icon: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Approve & Allow'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentPreview(
    Map<String, dynamic>? preview,
    String contentType,
  ) {
    if (preview == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          'Original item removed or unavailable.',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    final mediaUrl = preview['media_url'] as String?;
    final caption = preview['caption'] as String?;
    final commentText = preview['comment_text'] as String?;
    final messageText = preview['message_text'] as String?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border:
            Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(
                mediaUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) => Container(
                  height: 100,
                  color: AppColors.surfaceLight,
                  child: const Center(
                    child: Icon(Icons.broken_image,
                        color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (caption != null && caption.isNotEmpty)
            Text(
              'Caption: "$caption"',
              style: AppTypography.bodySmall,
            ),
          if (commentText != null && commentText.isNotEmpty)
            Text(
              'Comment: "$commentText"',
              style: AppTypography.bodySmall,
            ),
          if (messageText != null && messageText.isNotEmpty)
            Text(
              'Message: "$messageText"',
              style: AppTypography.bodySmall,
            ),
        ],
      ),
    );
  }
}
