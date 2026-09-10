import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/upload/upload_manager.dart';

/// LittleNet V2 – Create Post screen.
///
/// Visual language:
/// - Pure white bottom-sheet / full-screen modal (not GradientScaffold)
/// - Type selector: flat segmented row (Post / Reel / Story)
/// - Media zone: white with dashed border → preview once selected
/// - Caption / Category / Audience in clean white card blocks
/// - Submit button: full-width indigo FilledButton
/// - Moderation result: compact coloured info banner below button
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    required this.authState,
    this.initialKind = PostKind.post,
  });

  final AuthState authState;
  final PostKind initialKind;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

enum PostKind { post, reel, story }

enum PostModerationOutcome { none, allowed, review, blocked, error }

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _picker = ImagePicker();
  final _captionController = TextEditingController();
  final _tagInputController = TextEditingController();
  final List<String> _tags = [];

  late PostKind _kind;
  String _selectedCategory = 'Art';
  String _audience = 'ALL';

  File? _selectedFile;
  bool _isVideo = false;
  VideoPlayerController? _videoController;

  PostModerationOutcome _outcome = PostModerationOutcome.none;
  String? _statusMessage;
  String? _rejectionReason;

  static const List<String> _categories = [
    'Art',
    'Science',
    'Coding',
    'Nature',
    'Sports',
    'Music',
    'Reading',
    'Crafts',
    'Other',
  ];

  static const List<({String label, String value})> _audiences = [
    (label: 'All Kids', value: 'ALL'),
    (label: 'Ages 6–8', value: '6-8'),
    (label: 'Ages 9–11', value: '9-11'),
    (label: 'Ages 12–13', value: '12-13'),
    (label: 'Ages 14–18', value: '14-18'),
  ];

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
  }

  @override
  void dispose() {
    _captionController.dispose();
    _tagInputController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // ── Hashtags ──────────────────────────────────────────

  void _addTag(String raw) {
    final clean = raw.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '');
    if (clean.isEmpty) return;

    if (_tags.length >= 10) {
      _showError('Maximum 10 hashtags allowed.');
      return;
    }
    if (clean.length > 30) {
      _showError('Hashtags must be 30 characters or less.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(clean)) {
      _showError('Hashtags can only contain letters, numbers, and underscores.');
      return;
    }
    if (RegExp(r'\d{7,}').hasMatch(clean)) {
      _showError('Phone numbers or sensitive numbers are not allowed.');
      return;
    }
    if (_tags.contains(clean)) {
      _tagInputController.clear();
      return;
    }

    setState(() {
      _tags.add(clean);
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  // ── Media Picking ─────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked != null) _setFile(File(picked.path), isVideo: false);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to access photo: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picked = await _picker.pickVideo(
        source: source,
        maxDuration: _kind == PostKind.reel
            ? const Duration(seconds: 30)
            : const Duration(seconds: 60),
      );
      if (picked != null) _setFile(File(picked.path), isVideo: true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to access video: $e');
    }
  }

  void _setFile(File file, {required bool isVideo}) {
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      _selectedFile = file;
      _isVideo = isVideo;
      _outcome = PostModerationOutcome.none;
      _statusMessage = null;
      _rejectionReason = null;
    });

    if (isVideo) {
      final c = VideoPlayerController.file(file);
      _videoController = c;
      c.initialize().then((_) {
        if (mounted) {
          c.setVolume(0.0);
          c.setLooping(true);
          c.play();
          setState(() {});
        }
      });
    }
  }

  void _clearSelection() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _selectedFile = null;
      _isVideo = false;
      _outcome = PostModerationOutcome.none;
      _statusMessage = null;
      _rejectionReason = null;
    });
  }

  // ── Submit ───────────────────────────────────────────

  Future<void> _submitPost() async {
    final caption = _captionController.text.trim();
    if (_selectedFile == null && caption.isEmpty) {
      _showError('Add a photo/video or write a caption first.');
      return;
    }

    const canonicalAudiences = {'ALL', '6-8', '9-11', '12-13', '14-18'};
    if (!canonicalAudiences.contains(_audience)) {
      setState(() {
        _outcome = PostModerationOutcome.error;
        _statusMessage = 'Unsupported audience age group.';
      });
      return;
    }

    // Auto-commit tag text if child typed in the field without tapping '+'
    if (_tagInputController.text.trim().isNotEmpty) {
      _addTag(_tagInputController.text.trim());
    }

    final kindStr = switch (_kind) {
      PostKind.reel => 'reel',
      PostKind.story => 'story',
      PostKind.post => 'post',
    };

    // Dispatch background upload with zero wait time for child
    UploadManager.instance.startUpload(UploadParams(
      file: _selectedFile,
      kind: kindStr,
      caption: caption,
      category: _selectedCategory,
      audience: _audience,
      tags: List.unmodifiable(_tags),
      authState: widget.authState,
    ));

    HapticFeedback.mediumImpact();

    // Immediately pop screen back to feed/reels tray!
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _outcome = PostModerationOutcome.allowed;
        _statusMessage = 'Upload started! Moderation running in background.';
      });
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFFE53935),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final kindLabel = switch (_kind) {
      PostKind.reel => 'Create Reel 🎬',
      PostKind.story => 'Add Story 📖',
      PostKind.post => 'New Post ✨',
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Color(0xFF262626), size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            kindLabel,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF262626),
            ),
          ),
          actions: [
            if (_selectedFile != null)
              TextButton(
                onPressed: _clearSelection,
                child: const Text('Clear',
                    style: TextStyle(
                        color: Color(0xFF8E8E8E), fontWeight: FontWeight.w500)),
              ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(0.5),
            child: Divider(height: 0.5, thickness: 0.5, color: Color(0xFFDBDBDB)),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Post type selector ───────────────────
              _KindSelector(
                selected: _kind,
                onChanged: (k) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _kind = k;
                    _clearSelection();
                  });
                },
              ),
              const SizedBox(height: 20),

              // ── Media zone ───────────────────────────
              _selectedFile == null
                  ? _MediaPicker(
                      kind: _kind,
                      onPickImage: _pickImage,
                      onPickVideo: _pickVideo,
                    )
                  : _MediaPreview(
                      file: _selectedFile!,
                      isVideo: _isVideo,
                      videoController: _videoController,
                      onClear: _clearSelection,
                    ),

              const SizedBox(height: 20),

              // ── Caption ──────────────────────────────
              _FormCard(
                label: 'Caption / Story',
                child: TextField(
                  controller: _captionController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText:
                        'Write about your project, idea, or discovery…',
                    hintStyle:
                        TextStyle(fontSize: 14, color: Color(0xFF8E8E8E)),
                    border: InputBorder.none,
                    counterStyle:
                        TextStyle(fontSize: 11, color: Color(0xFF8E8E8E)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Hashtags section ─────────────────────
              _FormCard(
                label: 'Hashtags (${_tags.length}/10)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tags.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '#$tag',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => _removeTag(tag),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagInputController,
                            decoration: const InputDecoration(
                              hintText: 'Add a tag (e.g. science, art)',
                              hintStyle: TextStyle(
                                  fontSize: 13, color: Color(0xFF8E8E8E)),
                              prefixText: '#',
                              prefixStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D4ED8),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 4),
                            ),
                            style: const TextStyle(fontSize: 14),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (val) => _addTag(val),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: AppColors.primary, size: 22),
                          onPressed: () => _addTag(_tagInputController.text),
                          tooltip: 'Add hashtag',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Category & Audience row ───────────────
              Row(
                children: [
                  Expanded(
                    child: _FormCard(
                      label: 'Category',
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF262626),
                            fontWeight: FontWeight.w500),
                        dropdownColor: Colors.white,
                        items: _categories
                            .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCategory = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FormCard(
                      label: 'Audience',
                      child: DropdownButtonFormField<String>(
                        initialValue: _audience,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF262626),
                            fontWeight: FontWeight.w500),
                        dropdownColor: Colors.white,
                        items: _audiences
                            .map((a) => DropdownMenuItem(
                                value: a.value,
                                child: Text(a.label,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _audience = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Safety note ──────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 16, color: Color(0xFF2E7D32)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI safety moderation is always active. Posts go to Parent Review if flagged.',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Outcome banner ───────────────────────
              if (_outcome != PostModerationOutcome.none) ...[
                _OutcomeBanner(
                    outcome: _outcome,
                    message: _statusMessage,
                    reason: _rejectionReason),
                const SizedBox(height: 16),
              ],

              // ── Submit ───────────────────────────────
              FilledButton(
                onPressed: UploadManager.instance.state.isActive ? null : _submitPost,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                child: Text(switch (_kind) {
                  PostKind.reel => 'Share Reel',
                  PostKind.story => 'Share Story',
                  PostKind.post => 'Publish Post',
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onChanged});

  final PostKind selected;
  final void Function(PostKind) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _tab('Post', PostKind.post),
          _tab('Reel', PostKind.reel),
          _tab('Story', PostKind.story),
        ],
      ),
    );
  }

  Widget _tab(String label, PostKind kind) {
    final isSelected = selected == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected
                    ? const Color(0xFF262626)
                    : const Color(0xFF8E8E8E),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child, this.label});

  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, label != null ? 8 : 12, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label!,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E8E),
                    letterSpacing: 0.3)),
            const SizedBox(height: 2),
          ],
          child,
        ],
      ),
    );
  }
}

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.kind,
    required this.onPickImage,
    required this.onPickVideo,
  });

  final PostKind kind;
  final Future<void> Function(ImageSource) onPickImage;
  final Future<void> Function(ImageSource) onPickVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFDBDBDB), style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate_outlined,
              size: 40, color: Color(0xFFBBBBBB)),
          const SizedBox(height: 10),
          const Text(
            'Share what you learned or created',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF262626)),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI safety moderation · No audio',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E8E)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PickButton(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                onTap: () => onPickImage(ImageSource.camera),
              ),
              const SizedBox(width: 10),
              _PickButton(
                icon: Icons.photo_library_outlined,
                label: 'Photos',
                onTap: () => onPickImage(ImageSource.gallery),
              ),
              if (kind != PostKind.story) ...[
                const SizedBox(width: 10),
                _PickButton(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: () => onPickVideo(ImageSource.gallery),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDBDBDB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF262626)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF262626))),
          ],
        ),
      ),
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.file,
    required this.isVideo,
    required this.videoController,
    required this.onClear,
  });

  final File file;
  final bool isVideo;
  final VideoPlayerController? videoController;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBDBDB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isVideo) ...[
            if (videoController != null &&
                videoController!.value.isInitialized)
              AspectRatio(
                aspectRatio: videoController!.value.aspectRatio,
                child: VideoPlayer(videoController!),
              )
            else
              const CircularProgressIndicator(color: Colors.white54),
          ] else
            Image.file(file,
                fit: BoxFit.contain, width: double.infinity),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner(
      {required this.outcome, this.message, this.reason});

  final PostModerationOutcome outcome;
  final String? message;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final IconData icon;
    final String title;

    switch (outcome) {
      case PostModerationOutcome.allowed:
        bg = const Color(0xFFE8F5E9);
        border = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        title = 'Published!';
      case PostModerationOutcome.review:
        bg = const Color(0xFFFFF8E1);
        border = const Color(0xFFF59F00);
        icon = Icons.pending_outlined;
        title = 'Sent for Parent Review';
      case PostModerationOutcome.blocked:
        bg = const Color(0xFFFFEBEE);
        border = const Color(0xFFE53935);
        icon = Icons.gpp_bad_outlined;
        title = 'Blocked for Safety';
      default:
        bg = const Color(0xFFF3F3F3);
        border = const Color(0xFF9E9E9E);
        icon = Icons.info_outline;
        title = 'Notice';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: border, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: border)),
          ]),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!,
                style: TextStyle(fontSize: 13, color: border.withValues(alpha: 0.85))),
          ],
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text('Reason: $reason',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF8E8E8E))),
          ],
        ],
      ),
    );
  }
}
