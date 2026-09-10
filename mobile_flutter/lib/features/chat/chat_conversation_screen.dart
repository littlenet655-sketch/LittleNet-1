import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({
    super.key,
    required this.authState,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
  });

  final AuthState authState;
  final int peerId;
  final String peerName;
  final String? peerAvatarUrl;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = true;
  String? _error;
  bool _isSending = false;
  String? _safetyBanner;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/chat/${widget.peerId}',
      );
      final list = (res['messages'] as List<dynamic>?) ?? [];
      setState(() {
        _messages.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _messages.add(item);
          }
        }
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        setState(() => _error =
            'You can only chat with friends approved by your parent or guardian.');
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error =
          'Unable to load conversation. Please check your internet connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _safetyBanner = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/chat/${widget.peerId}',
        body: {'message_text': text},
      );

      final status = (res['status'] as String? ?? '').toUpperCase();
      _messageController.clear();

      if (status == 'ALLOW') {
        await _loadMessages();
      } else if (status == 'REVIEW') {
        setState(() {
          _safetyBanner =
              'Your message was sent to your parent for a quick safety review.';
        });
        await _loadMessages();
      }
    } on ApiException catch (e) {
      // Child-friendly denial instead of raw safety payload
      setState(() {
        if (e.payload?['blocked'] == true || e.message.contains('blocked')) {
          if (e.message.contains('contact_sharing')) {
            _safetyBanner =
                'For your safety, phone numbers, emails, and addresses cannot be shared in chat.';
          } else {
            _safetyBanner =
                'This message could not be sent. LittleNet keeps conversations kind, safe, and positive! 🌟';
          }
        } else if (e.statusCode == 403) {
          _safetyBanner =
              'You can only message friends approved by your parent.';
        } else {
          _safetyBanner = 'Message could not be sent: ${e.message}';
        }
      });
    } catch (_) {
      setState(() {
        _safetyBanner =
            'Network issue while sending message. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = widget.authState.currentUser?.userId;

    return GradientScaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
              backgroundImage: widget.peerAvatarUrl != null
                  ? NetworkImage(widget.peerAvatarUrl!)
                  : null,
              child: widget.peerAvatarUrl == null
                  ? Text(
                      widget.peerName.isNotEmpty
                          ? widget.peerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.kidsAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName, style: AppTypography.titleMedium),
                  Row(
                    children: [
                      const Icon(Icons.shield,
                          size: 12, color: AppColors.kidsAccent),
                      const SizedBox(width: 4),
                      Text(
                        'Safe & Parent Supervised',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.kidsAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.primary),
            tooltip: 'Chat Details & Safety',
            onPressed: () {
              Navigator.of(context).pushNamed(
                '/kids/chat/details',
                arguments: {
                  'peer_id': widget.peerId,
                  'peer_name': widget.peerName,
                  'peer_avatar_url': widget.peerAvatarUrl,
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Safety Banner if triggered
          if (_safetyBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              color: AppColors.error.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 20, color: AppColors.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _safetyBanner!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _safetyBanner = null),
                  ),
                ],
              ),
            ),

          // Messages Stream
          Expanded(
            child: _buildMessagesList(myUid),
          ),

          // Message Input Field
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded,
                          color: AppColors.kidsAccent),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(int? myUid) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline,
                  size: 40, color: AppColors.kidsAccent),
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: AppTypography.bodyMedium, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.waving_hand_rounded,
                  size: 48, color: AppColors.kidsAccent),
              const SizedBox(height: AppSpacing.md),
              Text('Say hello to ${widget.peerName}!',
                  style: AppTypography.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Remember to be friendly and respectful.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textMutedDark),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isMe = m['sender_child_id'] == myUid;
        final text = m['message_text'] as String? ?? '';
        final status = m['moderation_status'] as String? ?? 'ALLOWED';

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
                if (status == 'REVIEW') ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 12, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        'Under Parent Review',
                        style: AppTypography.caption.copyWith(
                          color: Colors.amber,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
