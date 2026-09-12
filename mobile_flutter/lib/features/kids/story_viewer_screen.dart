import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/widgets/ln_components.dart';

/// Screen 16: Story Viewer (Instagram-for-Kids style with synchronized audio)
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.authState,
    this.authorName = 'Maya Patel',
    this.authorHandle = '@maya_draws',
    this.avatarUrl,
    this.mediaUrl,
    this.caption = 'Check out my Mars Rover 3D model! 🚀',
    this.musicTitle,
    this.musicArtist,
    this.musicUrl,
  });

  final AuthState authState;
  final String authorName;
  final String authorHandle;
  final String? avatarUrl;
  final String? mediaUrl;
  final String caption;
  final String? musicTitle;
  final String? musicArtist;
  final String? musicUrl;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();
  AudioPlayer? _audioPlayer;

  final List<String> _quickReactions = ['❤️', '👏', '🚀', '🔬', '🌟'];

  @override
  void initState() {
    super.initState();
    _initAudio();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) Navigator.pop(context);
      }
    });

    _progressController.forward();
  }

  Future<void> _initAudio() async {
    if (widget.musicUrl != null && widget.musicUrl!.isNotEmpty) {
      try {
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.play(UrlSource(widget.musicUrl!));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _pauseStory() {
    _audioPlayer?.pause();
    _progressController.stop();
  }

  void _resumeStory() {
    _audioPlayer?.resume();
    _progressController.forward();
  }

  void _sendReaction(String emoji) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reacted $emoji to ${widget.authorName}\'s story!'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.mediaUrl ??
        'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTapDown: (_) => _pauseStory(),
          onTapUp: (_) => _resumeStory(),
          onTapCancel: () => _resumeStory(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 9:16 Fullscreen Media
              Image.network(
                media,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Center(
                    child: Icon(Icons.broken_image, size: 60, color: Colors.white38),
                  ),
                ),
              ),

              // Gradient Scrim Top & Bottom
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.65),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                      stops: const [0.0, 0.2, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // Top Bar: Segmented Progress + User Meta
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress Bar
                      AnimatedBuilder(
                        animation: _progressController,
                        builder: (ctx, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _progressController.value,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 2.5,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),

                      // User Row
                      Row(
                        children: [
                          LnAvatar(
                            url: widget.avatarUrl,
                            name: widget.authorName,
                            radius: 18,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    widget.authorName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '1h',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                              Text(
                                widget.authorHandle,
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 24),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      if (widget.musicTitle != null && widget.musicTitle!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.music_note, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.musicTitle} · ${widget.musicArtist ?? "LittleNet"}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom Area: Caption + Quick Reactions + Reply Field
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Caption
                        if (widget.caption.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                widget.caption,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),

                        // Quick Reaction Emojis
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _quickReactions.map((emoji) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: GestureDetector(
                                onTap: () => _sendReaction(emoji),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 10),

                        // Reply Field
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white30, width: 0.5),
                                ),
                                child: TextField(
                                  controller: _replyController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: 'Send message to classmate...',
                                    hintStyle: TextStyle(color: Colors.white70, fontSize: 13),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  onSubmitted: (text) {
                                    if (text.trim().isNotEmpty) {
                                      _replyController.clear();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Safe reply sent! 🚀')),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                              onPressed: () {
                                if (_replyController.text.trim().isNotEmpty) {
                                  _replyController.clear();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Safe reply sent! 🚀')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
