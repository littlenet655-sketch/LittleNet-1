import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.authState,
    required this.postId,
    this.postCaption,
  });

  final AuthState authState;
  final int postId;
  final String? postCaption;

  static Future<void> show(
    BuildContext context, {
    required AuthState authState,
    required int postId,
    String? postCaption,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CommentsSheet(
        authState: authState,
        postId: postId,
        postCaption: postCaption,
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _commentController = TextEditingController();
  final List<Map<String, dynamic>> _comments = [];

  bool _isLoading = true;
  String? _error;
  bool _isSubmitting = false;
  String? _statusBanner;
  bool _isBannerError = false;

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/posts/${widget.postId}/comment',
      );
      final list = (res['comments'] as List<dynamic>?) ?? [];
      setState(() {
        _comments.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _comments.add(item);
          }
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load comments.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _statusBanner = null;
      _isBannerError = false;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/posts/${widget.postId}/comment',
        body: {'text': text},
      );

      final status = (res['status'] as String? ?? '').toUpperCase();
      if (status == 'ALLOW') {
        _commentController.clear();
        setState(() {
          _statusBanner = 'Comment posted!';
          _isBannerError = false;
        });
        await _fetchComments();
      } else if (status == 'REVIEW') {
        _commentController.clear();
        setState(() {
          _statusBanner =
              'Your comment was sent to your parent for safety review.';
          _isBannerError = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _statusBanner = e.payload?['reason'] as String? ??
            'Comment could not be posted under child safety rules.';
        _isBannerError = true;
      });
    } catch (_) {
      setState(() {
        _statusBanner = 'Network error while checking comment safety.';
        _isBannerError = true;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7 + bottomInset,
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        children: [
          // Drag handle and Title
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Comments 💬', style: AppTypography.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Status Banner (moderation feedback)
          if (_statusBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: _isBannerError
                  ? AppColors.error.withValues(alpha: 0.2)
                  : AppColors.success.withValues(alpha: 0.2),
              child: Text(
                _statusBanner!,
                style: AppTypography.caption.copyWith(
                  color: _isBannerError ? AppColors.error : AppColors.success,
                ),
              ),
            ),

          // Comments List
          Expanded(
            child: _buildCommentsBody(),
          ),

          // Add Comment Input Bar
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a kind, encouraging comment...',
                      hintStyle: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textMutedDark),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded,
                          color: AppColors.kidsAccent),
                  onPressed: _isSubmitting ? null : _submitComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: AppTypography.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _fetchComments,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded,
                size: 40, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No comments yet',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Be the first to share something positive! 🌟',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textMutedDark),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final c = _comments[index];
        final author = c['full_name'] as String? ??
            c['username'] as String? ??
            'LittleNet Student';
        final text = c['comment_text'] as String? ?? '';
        final avatar = c['avatar_url'] as String?;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(
                      author.isNotEmpty ? author[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.kidsAccent, fontSize: 13),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: AppTypography.labelLarge
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(text, style: AppTypography.bodyMedium),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
